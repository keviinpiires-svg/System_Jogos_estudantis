const db = require('../config/db');
const { REGRAS } = require('../config/regrasProvisorias');

// ============================================================================
// ATLETISMO POR COLOCAÇÃO (db/37, 12/11/2026).
//
// Chega a folha do juiz ("1º, atleta X, escola Y; 2º...") e o ADMIN lança o
// 1º, o 2º e o 3º de cada prova + categoria + gênero. A prova é texto (as do
// regulamento são sugestão) e o atleta é um nome digitado: os atletas do
// atletismo não estão cadastrados. Ler é público; escrever é só do ADMIN.
//
// Na Tabela Geral cada colocação vale a pontuação das coletivas e conta
// medalha (tabelaGeralController). As regras (pódio de 3, categorias,
// gêneros, sugestões de prova, sem empate, 1 atleta por escola) estão em
// src/config/regrasProvisorias.js, chave `atletismoColocacoes`.
// ============================================================================

const REGRA = REGRAS.atletismoColocacoes;

const PROVA_MAXIMO = 80;
const ATLETA_MAXIMO = 150;
const ROTULO_GENERO = { MASCULINO: 'Masculino', FEMININO: 'Feminino' };

// Erro de validação ou de conflito, com o status que a rota devolve
class ErroDoLancamento extends Error {
  constructor(status, mensagem) {
    super(mensagem);
    this.status = status;
  }
}

const umEspaco = (texto) => String(texto ?? '').trim().replace(/\s+/g, ' ');

const SELECAO = `
  SELECT a.id, a.prova, a.categoria_id, cat.nome AS categoria_nome, a.genero, a.colocacao,
         a.escola_id, esc.nome AS escola_nome, a.atleta_nome, a.criado_em, a.alterado_em
    FROM atletismo_colocacoes a
    INNER JOIN categorias cat ON cat.id = a.categoria_id
    INNER JOIN escolas esc ON esc.id = a.escola_id`;

const ORDEM = ' ORDER BY cat.ordem, a.prova, a.genero DESC, a.colocacao';

const carregarCategorias = async (conexao) => {
  const [categorias] = await conexao.query(
    'SELECT id, nome FROM categorias WHERE nome IN (?) ORDER BY ordem', [REGRA.categorias]
  );
  return categorias;
};

// A prova como já foi digitada antes (ou como a sugestão a escreve): "100 M
// RASOS" e "100 m rasos" são a mesma prova, com uma grafia só
const grafiaDaProva = async (conexao, prova) => {
  const [[existente]] = await conexao.query(
    'SELECT prova FROM atletismo_colocacoes WHERE prova = ? ORDER BY id LIMIT 1', [prova]
  );
  if (existente) return existente.prova;
  const sugestoes = [...new Set(Object.values(REGRA.sugestoes).flat())];
  return sugestoes.find((s) => s.toLocaleLowerCase('pt-BR') === prova.toLocaleLowerCase('pt-BR')) || prova;
};

// Confere prova, categoria e gênero (o "recorte" de um pódio)
const lerRecorte = async (conexao, corpo) => {
  const provaDigitada = umEspaco(corpo.prova);
  if (!provaDigitada) throw new ErroDoLancamento(400, 'Informe a prova.');
  if (provaDigitada.length > PROVA_MAXIMO) {
    throw new ErroDoLancamento(400, `O nome da prova tem no máximo ${PROVA_MAXIMO} letras.`);
  }

  const categoria_id = Number(corpo.categoria_id);
  const categoria = (await carregarCategorias(conexao)).find((c) => c.id === categoria_id);
  if (!categoria) throw new ErroDoLancamento(400, `Categoria inválida: use ${REGRA.categorias.join(', ')}.`);

  const genero = String(corpo.genero || '').toUpperCase();
  if (!REGRA.generos.includes(genero)) {
    throw new ErroDoLancamento(400, 'Gênero inválido: use MASCULINO ou FEMININO.');
  }

  const prova = await grafiaDaProva(conexao, provaDigitada);
  return {
    prova, categoria_id, categoria_nome: categoria.nome, genero,
    rotulo: `${prova} ${categoria.nome} ${ROTULO_GENERO[genero]}`
  };
};

// Confere colocação, escola e nome do atleta de uma linha
const lerLinha = async (conexao, linha) => {
  const colocacao = Number(linha.colocacao);
  if (!REGRA.colocacoes.includes(colocacao)) {
    throw new ErroDoLancamento(400, `Colocação inválida: use ${REGRA.colocacoes.join(', ')}.`);
  }

  const escola_id = Number(linha.escola_id);
  if (!Number.isInteger(escola_id) || escola_id <= 0) {
    throw new ErroDoLancamento(400, `Escolha a escola do ${colocacao}º lugar.`);
  }
  const [[escola]] = await conexao.query('SELECT id, nome FROM escolas WHERE id = ?', [escola_id]);
  if (!escola) throw new ErroDoLancamento(400, `A escola do ${colocacao}º lugar não existe.`);

  const atleta_nome = umEspaco(linha.atleta_nome) || null;
  if (atleta_nome && atleta_nome.length > ATLETA_MAXIMO) {
    throw new ErroDoLancamento(400, `O nome do atleta tem no máximo ${ATLETA_MAXIMO} letras.`);
  }

  return { colocacao, escola_id, escola_nome: escola.nome, atleta_nome };
};

// As duas regras do pódio, contra o que já está gravado (menos a própria
// linha, na edição): sem empate e 1 atleta por escola na prova
const conferirConflitos = async (conexao, recorte, linha, ignorarId = null) => {
  const [gravadas] = await conexao.query(
    `SELECT a.id, a.colocacao, a.escola_id, esc.nome AS escola_nome
       FROM atletismo_colocacoes a
       INNER JOIN escolas esc ON esc.id = a.escola_id
      WHERE a.prova = ? AND a.categoria_id = ? AND a.genero = ? AND a.id <> ?`,
    [recorte.prova, recorte.categoria_id, recorte.genero, ignorarId || 0]
  );

  const mesmaColocacao = gravadas.find((g) => g.colocacao === linha.colocacao);
  if (mesmaColocacao) {
    throw new ErroDoLancamento(409,
      `${recorte.rotulo} já tem o ${linha.colocacao}º lugar (${mesmaColocacao.escola_nome}). `
      + 'Não há empate: edite ou apague esse resultado antes.');
  }

  const mesmaEscola = gravadas.find((g) => g.escola_id === linha.escola_id);
  if (mesmaEscola) {
    throw new ErroDoLancamento(409,
      `${linha.escola_nome} já está em ${recorte.rotulo}, no ${mesmaEscola.colocacao}º lugar. `
      + 'Cada escola tem um atleta só por prova, categoria e gênero.');
  }
};

const responderErro = (res, erro, contexto) => {
  if (erro instanceof ErroDoLancamento) return res.status(erro.status).json({ erro: erro.message });
  // Duas pessoas salvando ao mesmo tempo: o índice único do banco segura
  if (erro.code === 'ER_DUP_ENTRY') {
    return res.status(409).json({
      erro: 'Essa colocação (ou essa escola) acabou de ser lançada nessa prova por outra pessoa. Recarregue a página.'
    });
  }
  console.error(`${contexto}:`, erro);
  return res.status(500).json({ erro: 'Erro ao salvar o resultado do atletismo.' });
};

// ---------------------------------------------------------------------------
// GET /api/atletismo-colocacoes — público
// ---------------------------------------------------------------------------
const listarColocacoes = async (req, res) => {
  try {
    const [resultados] = await db.query(SELECAO + ORDEM);
    const categorias = await carregarCategorias(db);
    const [pontuacao] = await db.query(
      'SELECT posicao, pontos FROM pontuacao_geral WHERE posicao IN (?) ORDER BY posicao', [REGRA.colocacoes]
    );

    // Sugestões do campo "prova": as do regulamento e as já digitadas
    const doRegulamento = [...new Set(Object.values(REGRA.sugestoes).flat())];
    const digitadas = [...new Set(resultados.map((r) => r.prova))];
    const todas = [...doRegulamento];
    for (const prova of digitadas) {
      if (!todas.some((t) => t.toLocaleLowerCase('pt-BR') === prova.toLocaleLowerCase('pt-BR'))) todas.push(prova);
    }

    res.status(200).json({
      resultados,
      configuracao: {
        categorias,
        generos: REGRA.generos,
        colocacoes: REGRA.colocacoes,
        pontuacao,
        provas_sugeridas: todas,
        // As do regulamento para cada categoria (a tela oferece primeiro)
        provas_por_categoria: REGRA.sugestoes,
        descricao: REGRA.descricao
      }
    });
  } catch (erro) {
    console.error('Erro ao listar as colocações do atletismo:', erro);
    res.status(500).json({ erro: 'Erro ao buscar os resultados do atletismo.' });
  }
};

// ---------------------------------------------------------------------------
// POST /api/atletismo-colocacoes — só ADMIN. Uma colocação.
// Corpo: { prova, categoria_id, genero, colocacao, escola_id, atleta_nome }
// ---------------------------------------------------------------------------
const criarColocacao = async (req, res) => {
  let conexao;
  try {
    conexao = await db.getConnection();
    await conexao.beginTransaction();

    const recorte = await lerRecorte(conexao, req.body);
    const linha = await lerLinha(conexao, req.body);
    await conferirConflitos(conexao, recorte, linha);

    const [resultado] = await conexao.query(
      `INSERT INTO atletismo_colocacoes (prova, categoria_id, genero, colocacao, escola_id, atleta_nome, criado_por)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [recorte.prova, recorte.categoria_id, recorte.genero, linha.colocacao, linha.escola_id, linha.atleta_nome, req.usuario.id]
    );
    await conexao.commit();

    const [[criada]] = await db.query(`${SELECAO} WHERE a.id = ?`, [resultado.insertId]);
    res.status(201).json({ mensagem: `${linha.colocacao}º lugar de ${recorte.rotulo} lançado.`, resultado: criada });
  } catch (erro) {
    if (conexao) await conexao.rollback().catch(() => {});
    responderErro(res, erro, 'Erro ao lançar colocação do atletismo');
  } finally {
    if (conexao) conexao.release();
  }
};

// ---------------------------------------------------------------------------
// PUT /api/atletismo-colocacoes/:id — só ADMIN. Corrige uma colocação
// (qualquer campo; o que não vier fica como está).
// ---------------------------------------------------------------------------
const atualizarColocacao = async (req, res) => {
  const id = Number(req.params.id);
  let conexao;
  try {
    conexao = await db.getConnection();
    await conexao.beginTransaction();

    const [[atual]] = await conexao.query('SELECT * FROM atletismo_colocacoes WHERE id = ? FOR UPDATE', [id]);
    if (!atual) throw new ErroDoLancamento(404, 'Resultado não encontrado.');

    const corpo = { ...atual, ...req.body };
    const recorte = await lerRecorte(conexao, corpo);
    const linha = await lerLinha(conexao, corpo);
    await conferirConflitos(conexao, recorte, linha, id);

    await conexao.query(
      `UPDATE atletismo_colocacoes
          SET prova = ?, categoria_id = ?, genero = ?, colocacao = ?, escola_id = ?, atleta_nome = ?,
              alterado_por = ?, alterado_em = CURRENT_TIMESTAMP
        WHERE id = ?`,
      [recorte.prova, recorte.categoria_id, recorte.genero, linha.colocacao, linha.escola_id, linha.atleta_nome, req.usuario.id, id]
    );
    await conexao.commit();

    const [[salva]] = await db.query(`${SELECAO} WHERE a.id = ?`, [id]);
    res.status(200).json({ mensagem: `${linha.colocacao}º lugar de ${recorte.rotulo} atualizado.`, resultado: salva });
  } catch (erro) {
    if (conexao) await conexao.rollback().catch(() => {});
    responderErro(res, erro, 'Erro ao atualizar colocação do atletismo');
  } finally {
    if (conexao) conexao.release();
  }
};

// ---------------------------------------------------------------------------
// PUT /api/atletismo-colocacoes/podio — só ADMIN. O pódio inteiro de uma
// prova + categoria + gênero numa transação (é o que o formulário usa: dá
// para trocar o 1º com o 2º sem esbarrar no "sem empate").
// Corpo: { prova, categoria_id, genero, linhas: [{ colocacao, escola_id, atleta_nome }] }
// A colocação que não vier em `linhas` é apagada; pelo menos uma precisa vir.
// ---------------------------------------------------------------------------
const salvarPodio = async (req, res) => {
  let conexao;
  try {
    conexao = await db.getConnection();
    await conexao.beginTransaction();

    const recorte = await lerRecorte(conexao, req.body);
    if (!Array.isArray(req.body.linhas) || req.body.linhas.length === 0) {
      throw new ErroDoLancamento(400, 'Informe pelo menos uma colocação (escola do 1º, do 2º ou do 3º lugar).');
    }

    const linhas = [];
    for (const bruta of req.body.linhas) linhas.push(await lerLinha(conexao, bruta));

    // As duas regras, dentro do próprio formulário
    for (const linha of linhas) {
      if (linhas.filter((l) => l.colocacao === linha.colocacao).length > 1) {
        throw new ErroDoLancamento(409, `O ${linha.colocacao}º lugar aparece duas vezes: não há empate.`);
      }
      const outra = linhas.find((l) => l !== linha && l.escola_id === linha.escola_id);
      if (outra) {
        throw new ErroDoLancamento(409,
          `${linha.escola_nome} aparece no ${Math.min(linha.colocacao, outra.colocacao)}º e no `
          + `${Math.max(linha.colocacao, outra.colocacao)}º lugar de ${recorte.rotulo}. `
          + 'Cada escola tem um atleta só por prova, categoria e gênero.');
      }
    }

    const [gravadas] = await conexao.query(
      `SELECT id, colocacao, escola_id, atleta_nome, criado_por, criado_em
         FROM atletismo_colocacoes
        WHERE prova = ? AND categoria_id = ? AND genero = ? FOR UPDATE`,
      [recorte.prova, recorte.categoria_id, recorte.genero]
    );

    // Apaga e regrava (os índices únicos não deixam trocar no lugar), guardando
    // quem lançou cada colocação e marcando quem mexeu no que mudou
    if (gravadas.length > 0) {
      await conexao.query('DELETE FROM atletismo_colocacoes WHERE id IN (?)', [gravadas.map((g) => g.id)]);
    }
    for (const linha of linhas) {
      const antes = gravadas.find((g) => g.colocacao === linha.colocacao);
      const mudou = antes && (antes.escola_id !== linha.escola_id || (antes.atleta_nome || null) !== linha.atleta_nome);
      await conexao.query(
        `INSERT INTO atletismo_colocacoes
           (prova, categoria_id, genero, colocacao, escola_id, atleta_nome, criado_por, criado_em, alterado_por, alterado_em)
         VALUES (?, ?, ?, ?, ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP), ?, ${mudou ? 'CURRENT_TIMESTAMP' : 'NULL'})`,
        [recorte.prova, recorte.categoria_id, recorte.genero, linha.colocacao, linha.escola_id, linha.atleta_nome,
          antes ? antes.criado_por : req.usuario.id, antes ? antes.criado_em : null, mudou ? req.usuario.id : null]
      );
    }
    await conexao.commit();

    const [resultados] = await db.query(
      `${SELECAO} WHERE a.prova = ? AND a.categoria_id = ? AND a.genero = ?${ORDEM}`,
      [recorte.prova, recorte.categoria_id, recorte.genero]
    );
    res.status(200).json({ mensagem: `Pódio de ${recorte.rotulo} salvo.`, resultados });
  } catch (erro) {
    if (conexao) await conexao.rollback().catch(() => {});
    responderErro(res, erro, 'Erro ao salvar o pódio do atletismo');
  } finally {
    if (conexao) conexao.release();
  }
};

// ---------------------------------------------------------------------------
// DELETE /api/atletismo-colocacoes/:id — só ADMIN
// ---------------------------------------------------------------------------
const apagarColocacao = async (req, res) => {
  try {
    const [resultado] = await db.query('DELETE FROM atletismo_colocacoes WHERE id = ?', [Number(req.params.id)]);
    if (resultado.affectedRows === 0) return res.status(404).json({ erro: 'Resultado não encontrado.' });
    res.status(200).json({ mensagem: 'Resultado apagado.' });
  } catch (erro) {
    console.error('Erro ao apagar colocação do atletismo:', erro);
    res.status(500).json({ erro: 'Erro ao apagar o resultado do atletismo.' });
  }
};

module.exports = { listarColocacoes, criarColocacao, atualizarColocacao, salvarPodio, apagarColocacao };
