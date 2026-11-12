const db = require('../config/db');
const { REGRAS } = require('../config/regrasProvisorias');

// ============================================================================
// TABULEIRO POR COLOCAÇÃO — xadrez, dama e dominó (db/38, 12/11/2026).
//
// Irmão do atletismo por colocação (atletismoColocacoesController, que não
// muda): chega a folha do juiz e o ADMIN lança o 1º, o 2º e o 3º de cada JOGO
// + categoria. Pelo regulamento o tabuleiro é MISTO (não há gênero: a API
// devolve sempre 'MISTO') e todos os jogos são individuais, inclusive o
// dominó: o atleta é um nome só, digitado (os atletas não são cadastrados).
// Ler é público; escrever é só do ADMIN.
//
// Na Tabela Geral cada colocação vale a pontuação das coletivas e conta
// medalha (tabelaGeralController). As regras (jogos, categorias, pódio de 3,
// sem empate, uma escola por jogo + categoria) estão em
// src/config/regrasProvisorias.js, chave `tabuleiroColocacoes`.
// ============================================================================

const REGRA = REGRAS.tabuleiroColocacoes;

const ATLETA_MAXIMO = 150;

// Erro de validação ou de conflito, com o status que a rota devolve
class ErroDoLancamento extends Error {
  constructor(status, mensagem) {
    super(mensagem);
    this.status = status;
  }
}

const umEspaco = (texto) => String(texto ?? '').trim().replace(/\s+/g, ' ');

const SELECAO = `
  SELECT t.id, t.modalidade_id, m.slug AS jogo, m.nome AS jogo_nome,
         t.categoria_id, cat.nome AS categoria_nome, '${REGRA.genero}' AS genero, t.colocacao,
         t.escola_id, esc.nome AS escola_nome, t.atleta_nome, t.criado_em, t.alterado_em
    FROM tabuleiro_colocacoes t
    INNER JOIN modalidades m ON m.id = t.modalidade_id
    INNER JOIN categorias cat ON cat.id = t.categoria_id
    INNER JOIN escolas esc ON esc.id = t.escola_id`;

const ORDEM = ' ORDER BY m.ordem, cat.ordem, t.colocacao';

// Os três jogos (na ordem da regra) e as categorias do tabuleiro
const carregarJogos = async (conexao) => {
  const [jogos] = await conexao.query('SELECT id, slug, nome FROM modalidades WHERE slug IN (?)', [REGRA.jogos]);
  return REGRA.jogos.map((slug) => jogos.find((j) => j.slug === slug)).filter(Boolean);
};

const carregarCategorias = async (conexao) => {
  const [categorias] = await conexao.query(
    'SELECT id, nome FROM categorias WHERE nome IN (?) ORDER BY ordem', [REGRA.categorias]
  );
  return categorias;
};

// Confere jogo e categoria (o "recorte" de um pódio). O jogo vem pelo slug
// (xadrez, dama, domino) em `jogo`, ou pelo id em `modalidade_id`.
const lerRecorte = async (conexao, corpo) => {
  const jogos = await carregarJogos(conexao);
  const jogo = corpo.jogo !== undefined && corpo.jogo !== null && corpo.jogo !== ''
    ? jogos.find((j) => j.slug === String(corpo.jogo).toLowerCase())
    : jogos.find((j) => j.id === Number(corpo.modalidade_id));
  if (!jogo) throw new ErroDoLancamento(400, `Jogo inválido: use ${jogos.map((j) => j.nome).join(', ')}.`);

  const categoria_id = Number(corpo.categoria_id);
  const categoria = (await carregarCategorias(conexao)).find((c) => c.id === categoria_id);
  if (!categoria) throw new ErroDoLancamento(400, `Categoria inválida: use ${REGRA.categorias.join(', ')}.`);

  return {
    modalidade_id: jogo.id, jogo_nome: jogo.nome, categoria_id, categoria_nome: categoria.nome,
    rotulo: `${jogo.nome} ${categoria.nome}`
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
// linha, na edição): sem empate e uma escola só por jogo + categoria
const conferirConflitos = async (conexao, recorte, linha, ignorarId = null) => {
  const [gravadas] = await conexao.query(
    `SELECT t.id, t.colocacao, t.escola_id, esc.nome AS escola_nome
       FROM tabuleiro_colocacoes t
       INNER JOIN escolas esc ON esc.id = t.escola_id
      WHERE t.modalidade_id = ? AND t.categoria_id = ? AND t.id <> ?`,
    [recorte.modalidade_id, recorte.categoria_id, ignorarId || 0]
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
      + 'Cada escola tem um atleta só por jogo e categoria.');
  }
};

const responderErro = (res, erro, contexto) => {
  if (erro instanceof ErroDoLancamento) return res.status(erro.status).json({ erro: erro.message });
  // Duas pessoas salvando ao mesmo tempo: o índice único do banco segura
  if (erro.code === 'ER_DUP_ENTRY') {
    return res.status(409).json({
      erro: 'Essa colocação (ou essa escola) acabou de ser lançada nesse jogo por outra pessoa. Recarregue a página.'
    });
  }
  console.error(`${contexto}:`, erro);
  return res.status(500).json({ erro: 'Erro ao salvar o resultado do tabuleiro.' });
};

// ---------------------------------------------------------------------------
// GET /api/tabuleiro-colocacoes — público
// ---------------------------------------------------------------------------
const listarColocacoes = async (req, res) => {
  try {
    const [resultados] = await db.query(SELECAO + ORDEM);
    const [pontuacao] = await db.query(
      'SELECT posicao, pontos FROM pontuacao_geral WHERE posicao IN (?) ORDER BY posicao', [REGRA.colocacoes]
    );

    res.status(200).json({
      resultados,
      configuracao: {
        jogos: await carregarJogos(db),
        categorias: await carregarCategorias(db),
        genero: REGRA.genero,
        colocacoes: REGRA.colocacoes,
        pontuacao,
        descricao: REGRA.descricao
      }
    });
  } catch (erro) {
    console.error('Erro ao listar as colocações do tabuleiro:', erro);
    res.status(500).json({ erro: 'Erro ao buscar os resultados do tabuleiro.' });
  }
};

// ---------------------------------------------------------------------------
// POST /api/tabuleiro-colocacoes — só ADMIN. Uma colocação.
// Corpo: { jogo, categoria_id, colocacao, escola_id, atleta_nome }
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
      `INSERT INTO tabuleiro_colocacoes (modalidade_id, categoria_id, colocacao, escola_id, atleta_nome, criado_por)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [recorte.modalidade_id, recorte.categoria_id, linha.colocacao, linha.escola_id, linha.atleta_nome, req.usuario.id]
    );
    await conexao.commit();

    const [[criada]] = await db.query(`${SELECAO} WHERE t.id = ?`, [resultado.insertId]);
    res.status(201).json({ mensagem: `${linha.colocacao}º lugar de ${recorte.rotulo} lançado.`, resultado: criada });
  } catch (erro) {
    if (conexao) await conexao.rollback().catch(() => {});
    responderErro(res, erro, 'Erro ao lançar colocação do tabuleiro');
  } finally {
    if (conexao) conexao.release();
  }
};

// ---------------------------------------------------------------------------
// PUT /api/tabuleiro-colocacoes/:id — só ADMIN. Corrige uma colocação
// (qualquer campo; o que não vier fica como está).
// ---------------------------------------------------------------------------
const atualizarColocacao = async (req, res) => {
  const id = Number(req.params.id);
  let conexao;
  try {
    conexao = await db.getConnection();
    await conexao.beginTransaction();

    const [[atual]] = await conexao.query('SELECT * FROM tabuleiro_colocacoes WHERE id = ? FOR UPDATE', [id]);
    if (!atual) throw new ErroDoLancamento(404, 'Resultado não encontrado.');

    const corpo = { ...atual, ...req.body };
    // Sem `jogo` no corpo, vale o jogo gravado (modalidade_id)
    if (req.body.jogo === undefined) delete corpo.jogo;
    const recorte = await lerRecorte(conexao, corpo);
    const linha = await lerLinha(conexao, corpo);
    await conferirConflitos(conexao, recorte, linha, id);

    await conexao.query(
      `UPDATE tabuleiro_colocacoes
          SET modalidade_id = ?, categoria_id = ?, colocacao = ?, escola_id = ?, atleta_nome = ?,
              alterado_por = ?, alterado_em = CURRENT_TIMESTAMP
        WHERE id = ?`,
      [recorte.modalidade_id, recorte.categoria_id, linha.colocacao, linha.escola_id, linha.atleta_nome, req.usuario.id, id]
    );
    await conexao.commit();

    const [[salva]] = await db.query(`${SELECAO} WHERE t.id = ?`, [id]);
    res.status(200).json({ mensagem: `${linha.colocacao}º lugar de ${recorte.rotulo} atualizado.`, resultado: salva });
  } catch (erro) {
    if (conexao) await conexao.rollback().catch(() => {});
    responderErro(res, erro, 'Erro ao atualizar colocação do tabuleiro');
  } finally {
    if (conexao) conexao.release();
  }
};

// ---------------------------------------------------------------------------
// PUT /api/tabuleiro-colocacoes/podio — só ADMIN. O pódio inteiro de um jogo
// + categoria numa transação (é o que o formulário usa).
// Corpo: { jogo, categoria_id, linhas: [{ colocacao, escola_id, atleta_nome }] }
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

    for (const linha of linhas) {
      if (linhas.filter((l) => l.colocacao === linha.colocacao).length > 1) {
        throw new ErroDoLancamento(409, `O ${linha.colocacao}º lugar aparece duas vezes: não há empate.`);
      }
      const outra = linhas.find((l) => l !== linha && l.escola_id === linha.escola_id);
      if (outra) {
        throw new ErroDoLancamento(409,
          `${linha.escola_nome} aparece no ${Math.min(linha.colocacao, outra.colocacao)}º e no `
          + `${Math.max(linha.colocacao, outra.colocacao)}º lugar de ${recorte.rotulo}. `
          + 'Cada escola tem um atleta só por jogo e categoria.');
      }
    }

    const [gravadas] = await conexao.query(
      `SELECT id, colocacao, escola_id, atleta_nome, criado_por, criado_em
         FROM tabuleiro_colocacoes
        WHERE modalidade_id = ? AND categoria_id = ? FOR UPDATE`,
      [recorte.modalidade_id, recorte.categoria_id]
    );

    // Apaga e regrava (os índices únicos não deixam trocar no lugar), guardando
    // quem lançou cada colocação e marcando quem mexeu no que mudou
    if (gravadas.length > 0) {
      await conexao.query('DELETE FROM tabuleiro_colocacoes WHERE id IN (?)', [gravadas.map((g) => g.id)]);
    }
    for (const linha of linhas) {
      const antes = gravadas.find((g) => g.colocacao === linha.colocacao);
      const mudou = antes && (antes.escola_id !== linha.escola_id || (antes.atleta_nome || null) !== linha.atleta_nome);
      await conexao.query(
        `INSERT INTO tabuleiro_colocacoes
           (modalidade_id, categoria_id, colocacao, escola_id, atleta_nome, criado_por, criado_em, alterado_por, alterado_em)
         VALUES (?, ?, ?, ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP), ?, ${mudou ? 'CURRENT_TIMESTAMP' : 'NULL'})`,
        [recorte.modalidade_id, recorte.categoria_id, linha.colocacao, linha.escola_id, linha.atleta_nome,
          antes ? antes.criado_por : req.usuario.id, antes ? antes.criado_em : null, mudou ? req.usuario.id : null]
      );
    }
    await conexao.commit();

    const [resultados] = await db.query(
      `${SELECAO} WHERE t.modalidade_id = ? AND t.categoria_id = ?${ORDEM}`,
      [recorte.modalidade_id, recorte.categoria_id]
    );
    res.status(200).json({ mensagem: `Pódio de ${recorte.rotulo} salvo.`, resultados });
  } catch (erro) {
    if (conexao) await conexao.rollback().catch(() => {});
    responderErro(res, erro, 'Erro ao salvar o pódio do tabuleiro');
  } finally {
    if (conexao) conexao.release();
  }
};

// ---------------------------------------------------------------------------
// DELETE /api/tabuleiro-colocacoes/:id — só ADMIN
// ---------------------------------------------------------------------------
const apagarColocacao = async (req, res) => {
  try {
    const [resultado] = await db.query('DELETE FROM tabuleiro_colocacoes WHERE id = ?', [Number(req.params.id)]);
    if (resultado.affectedRows === 0) return res.status(404).json({ erro: 'Resultado não encontrado.' });
    res.status(200).json({ mensagem: 'Resultado apagado.' });
  } catch (erro) {
    console.error('Erro ao apagar colocação do tabuleiro:', erro);
    res.status(500).json({ erro: 'Erro ao apagar o resultado do tabuleiro.' });
  }
};

module.exports = { listarColocacoes, criarColocacao, atualizarColocacao, salvarPodio, apagarColocacao };
