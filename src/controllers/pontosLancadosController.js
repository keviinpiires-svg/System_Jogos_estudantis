const db = require('../config/db');
const { REGRAS } = require('../config/regrasProvisorias');

// ============================================================================
// PONTOS LANÇADOS — atletismo, xadrez, dama e dominó (chefe, 12/10/2026).
//
// Essas modalidades funcionam fora do sistema: o juiz entrega a folha e a
// mesa digita os pontos de cada escola, por modalidade × categoria × gênero
// (um "lançamento"). Os pontos somam na Tabela Geral.
//
// - Leitura pública: a escola confere de onde veio a própria soma.
// - Lançar e editar: ADMIN e PLACAR (a mesa). Apagar o lançamento inteiro:
//   só o ADMIN. Sem trava por local: essas modalidades não têm jogo.
// - Correção é edição no lugar: a linha guarda quem digitou e quando, e
//   quem alterou por último e quando. Sem histórico das versões.
// - Duas mesas na mesma grade: quem salva manda a "base" (o que abriu). Se o
//   banco mudou desde então, a API recusa com 409 em vez de apagar o
//   trabalho do outro em silêncio.
//
// Limites, categorias, gêneros e combinações ocultas moram em
// src/config/regrasProvisorias.js, chave `pontosLancados`.
// ============================================================================

const REGRA = REGRAS.pontosLancados;

const GENEROS = { MASCULINO: 'Masculino', FEMININO: 'Feminino' };

// Pontos esperados por escola num lançamento. Acima disso é aviso, não erro.
const esperadoDe = (slug, categoriaNome) => {
  const tabela = REGRA.esperado[slug] || {};
  return tabela[categoriaNome] ?? tabela.padrao ?? REGRA.tetoAbsoluto;
};

const oculta = (slug, categoriaNome, genero) => REGRA.ocultas.some(([s, c, g]) =>
  s === slug && c === categoriaNome && (g === null || g === undefined || g === genero));

// Modalidades e categorias da regra, com os ids do banco
const carregarConfiguracao = async (conexao) => {
  const [modalidades] = await conexao.query(
    'SELECT id, nome, slug FROM modalidades WHERE slug IN (?)',
    [REGRA.modalidades]
  );
  const [categorias] = await conexao.query(
    'SELECT id, nome FROM categorias WHERE nome IN (?)',
    [REGRA.categorias]
  );

  return REGRA.modalidades
    .map((slug) => modalidades.find((m) => m.slug === slug))
    .filter(Boolean)
    .map((modalidade) => ({
      ...modalidade,
      combinacoes: REGRA.categorias
        .map((nome) => categorias.find((c) => c.nome === nome))
        .filter(Boolean)
        .flatMap((categoria) => REGRA.generos
          .filter((genero) => !oculta(modalidade.slug, categoria.nome, genero))
          .map((genero) => ({
            categoria_id: categoria.id,
            categoria_nome: categoria.nome,
            genero,
            esperado: esperadoDe(modalidade.slug, categoria.nome)
          })))
    }));
};

const SELECT_LANCAMENTOS = `
  SELECT p.id, m.slug AS modalidade, m.nome AS modalidade_nome,
         p.categoria_id, cat.nome AS categoria_nome, p.genero,
         p.escola_id, esc.nome AS escola_nome, p.pontos, p.colocacao,
         p.criado_em, uc.nome AS criado_por_nome,
         p.alterado_em, ua.nome AS alterado_por_nome
    FROM pontos_lancados p
    INNER JOIN modalidades m ON m.id = p.modalidade_id
    INNER JOIN categorias cat ON cat.id = p.categoria_id
    INNER JOIN escolas esc ON esc.id = p.escola_id
    INNER JOIN usuarios uc ON uc.id = p.criado_por
    LEFT JOIN usuarios ua ON ua.id = p.alterado_por`;

// O que importa para saber se a grade mudou: pontos e colocação por escola
const assinatura = (linhas) => linhas
  .map((l) => `${Number(l.escola_id)}:${l.pontos ?? ''}:${l.colocacao ?? ''}`)
  .sort()
  .join('|');

const inteiroOuNulo = (valor) => {
  if (valor === null || valor === undefined || valor === '') return null;
  const numero = Number(valor);
  return Number.isInteger(numero) ? numero : undefined;
};

const resumoDe = (modalidade, combinacao, linhas) => {
  const total = linhas.reduce((soma, l) => soma + l.pontos, 0);
  return {
    escolas: linhas.length,
    total,
    texto: `${modalidade.nome} ${combinacao.categoria_nome} ${GENEROS[combinacao.genero]}: `
      + `${linhas.length} ${linhas.length === 1 ? 'escola' : 'escolas'}, total ${total} pontos`
  };
};

// ---------------------------------------------------------------------------
// GET /api/pontos-lancados[?modalidade=slug] — público
// ---------------------------------------------------------------------------
const listarPontosLancados = async (req, res) => {
  try {
    const configuracao = await carregarConfiguracao(db);
    const slug = req.query.modalidade ? String(req.query.modalidade) : null;

    const [lancamentos] = await db.query(
      `${SELECT_LANCAMENTOS}
        ${slug ? 'WHERE m.slug = ?' : ''}
        ORDER BY m.ordem, cat.ordem, p.genero, p.pontos DESC, esc.nome`,
      slug ? [slug] : []
    );
    const [escolas] = await db.query('SELECT id, nome FROM escolas ORDER BY nome');

    res.status(200).json({
      configuracao: {
        modalidades: configuracao,
        teto_absoluto: REGRA.tetoAbsoluto,
        conta_no_desempate: REGRA.contaNoDesempate,
        provisoria: REGRA.provisorio,
        decidido_em: REGRA.decididoEm,
        descricao: REGRA.descricao
      },
      escolas,
      lancamentos
    });
  } catch (erro) {
    console.error('Erro ao listar os pontos lançados:', erro);
    res.status(500).json({ erro: 'Erro ao buscar os pontos lançados.' });
  }
};

// Acha a modalidade e a combinação pedidas na configuração, ou diz o erro
const localizarLancamento = (configuracao, slug, categoria_id, genero) => {
  const modalidade = configuracao.find((m) => m.slug === slug);
  if (!modalidade) {
    return { erro: `Modalidade inválida: use ${REGRA.modalidades.join(', ')}.` };
  }
  const combinacao = modalidade.combinacoes
    .find((c) => c.categoria_id === categoria_id && c.genero === genero);
  if (!combinacao) {
    return { erro: `${modalidade.nome} não tem essa categoria e gênero para lançar pontos.` };
  }
  return { modalidade, combinacao };
};

// ---------------------------------------------------------------------------
// PUT /api/pontos-lancados — ADMIN e PLACAR
// Corpo: { modalidade, categoria_id, genero, linhas: [{ escola_id, pontos,
// colocacao }], base: [...as linhas como estavam ao abrir], confirmado }.
// Pontos em branco (null) tiram a escola do lançamento. Escola que não vem
// em `linhas` fica como está.
// ---------------------------------------------------------------------------
const salvarPontosLancados = async (req, res) => {
  const slug = String(req.body.modalidade || '');
  const categoria_id = Number(req.body.categoria_id);
  const genero = String(req.body.genero || '').toUpperCase();
  const enviadas = Array.isArray(req.body.linhas) ? req.body.linhas : null;
  const base = Array.isArray(req.body.base) ? req.body.base : null;
  const confirmado = req.body.confirmado === true;

  if (!enviadas || !base) {
    return res.status(400).json({ erro: 'Envie as linhas da grade e a base que você abriu.' });
  }

  // Validação linha a linha: pontos inteiros de 0 ao teto, colocação opcional
  const linhas = [];
  const vistas = new Set();
  for (const enviada of enviadas) {
    const escola_id = Number(enviada.escola_id);
    const pontos = inteiroOuNulo(enviada.pontos);
    const colocacao = inteiroOuNulo(enviada.colocacao);

    if (!Number.isInteger(escola_id) || escola_id <= 0 || vistas.has(escola_id)) {
      return res.status(400).json({ erro: 'Há escola inválida ou repetida na grade.' });
    }
    vistas.add(escola_id);

    if (pontos === undefined || (pontos !== null && (pontos < 0 || pontos > REGRA.tetoAbsoluto))) {
      return res.status(400).json({
        erro: `Pontos precisam ser um número inteiro de 0 a ${REGRA.tetoAbsoluto}.`,
        escola_id
      });
    }
    if (colocacao === undefined || (colocacao !== null && (colocacao < 1 || colocacao > 99))) {
      return res.status(400).json({ erro: 'A colocação, quando informada, vai de 1 a 99.', escola_id });
    }
    if (pontos === null && colocacao !== null) {
      return res.status(400).json({ erro: 'Escola com colocação precisa ter os pontos.', escola_id });
    }

    linhas.push({ escola_id, pontos, colocacao });
  }

  let conexao;
  try {
    const configuracao = await carregarConfiguracao(db);
    const alvo = localizarLancamento(configuracao, slug, categoria_id, genero);
    if (alvo.erro) return res.status(400).json({ erro: alvo.erro });
    const { modalidade, combinacao } = alvo;

    // Acima do esperado: a mesa precisa confirmar (a tela já pergunta)
    const acima = linhas.filter((l) => l.pontos !== null && l.pontos > combinacao.esperado);
    if (acima.length && !confirmado) {
      return res.status(422).json({
        erro: `${acima.length === 1 ? 'Uma escola passou' : `${acima.length} escolas passaram`} `
          + `dos ${combinacao.esperado} pontos esperados. Confira e confirme para salvar.`,
        acima_do_esperado: acima.map((l) => l.escola_id),
        esperado: combinacao.esperado
      });
    }

    const [escolas] = vistas.size
      ? await db.query('SELECT id FROM escolas WHERE id IN (?)', [[...vistas]])
      : [[]];
    if (escolas.length !== vistas.size) {
      return res.status(400).json({ erro: 'Há escola que não existe no cadastro.' });
    }

    conexao = await db.getConnection();
    await conexao.beginTransaction();

    // Trava a modalidade: quem salva o mesmo lançamento entra na fila, e a
    // leitura abaixo (FOR UPDATE) vê o que o outro acabou de gravar
    await conexao.query('SELECT id FROM modalidades WHERE id = ? FOR UPDATE', [modalidade.id]);

    const [atuais] = await conexao.query(
      `SELECT p.id, p.escola_id, p.pontos, p.colocacao,
              COALESCE(p.alterado_em, p.criado_em) AS mexido_em,
              COALESCE(ua.nome, uc.nome) AS mexido_por
         FROM pontos_lancados p
         INNER JOIN usuarios uc ON uc.id = p.criado_por
         LEFT JOIN usuarios ua ON ua.id = p.alterado_por
        WHERE p.modalidade_id = ? AND p.categoria_id = ? AND p.genero = ?
        FOR UPDATE`,
      [modalidade.id, categoria_id, genero]
    );

    if (assinatura(atuais) !== assinatura(base.filter((l) => l.pontos !== null && l.pontos !== undefined))) {
      await conexao.rollback();
      const ultimo = [...atuais].sort((a, b) => new Date(b.mexido_em) - new Date(a.mexido_em))[0];
      return res.status(409).json({
        erro: 'Outra pessoa salvou este lançamento depois que você abriu a grade'
          + (ultimo ? ` (${ultimo.mexido_por})` : '')
          + '. Recarregue e digite de novo o que faltar.'
      });
    }

    const porEscola = new Map(atuais.map((a) => [a.escola_id, a]));
    let mudancas = 0;

    for (const linha of linhas) {
      const atual = porEscola.get(linha.escola_id);

      if (linha.pontos === null) {
        if (atual) {
          await conexao.query('DELETE FROM pontos_lancados WHERE id = ?', [atual.id]);
          mudancas += 1;
        }
      } else if (!atual) {
        await conexao.query(
          `INSERT INTO pontos_lancados
             (modalidade_id, categoria_id, genero, escola_id, pontos, colocacao, criado_por)
           VALUES (?, ?, ?, ?, ?, ?, ?)`,
          [modalidade.id, categoria_id, genero, linha.escola_id, linha.pontos, linha.colocacao, req.usuario.id]
        );
        mudancas += 1;
      } else if (atual.pontos !== linha.pontos || (atual.colocacao ?? null) !== linha.colocacao) {
        await conexao.query(
          `UPDATE pontos_lancados
              SET pontos = ?, colocacao = ?, alterado_por = ?, alterado_em = CURRENT_TIMESTAMP
            WHERE id = ?`,
          [linha.pontos, linha.colocacao, req.usuario.id, atual.id]
        );
        mudancas += 1;
      }
    }

    await conexao.commit();

    const [lancamento] = await db.query(
      `${SELECT_LANCAMENTOS}
        WHERE p.modalidade_id = ? AND p.categoria_id = ? AND p.genero = ?
        ORDER BY p.pontos DESC, esc.nome`,
      [modalidade.id, categoria_id, genero]
    );
    const resumo = resumoDe(modalidade, combinacao, lancamento);

    res.status(200).json({
      mensagem: mudancas
        ? `Salvo. ${resumo.texto}.`
        : `Nada mudou. ${resumo.texto}.`,
      mudancas,
      resumo,
      lancamento
    });
  } catch (erro) {
    if (conexao) await conexao.rollback();
    console.error('Erro ao salvar os pontos lançados:', erro);
    res.status(500).json({ erro: 'Erro ao salvar os pontos. Nada foi gravado.' });
  } finally {
    if (conexao) conexao.release();
  }
};

// ---------------------------------------------------------------------------
// DELETE /api/pontos-lancados/:modalidade/:categoria_id/:genero — só ADMIN
// Apaga o lançamento inteiro daquela categoria e gênero.
// ---------------------------------------------------------------------------
const apagarLancamento = async (req, res) => {
  const slug = String(req.params.modalidade || '');
  const categoria_id = Number(req.params.categoria_id);
  const genero = String(req.params.genero || '').toUpperCase();

  try {
    const configuracao = await carregarConfiguracao(db);
    const modalidade = configuracao.find((m) => m.slug === slug);
    if (!modalidade) return res.status(400).json({ erro: 'Modalidade inválida.' });

    const [resultado] = await db.query(
      'DELETE FROM pontos_lancados WHERE modalidade_id = ? AND categoria_id = ? AND genero = ?',
      [modalidade.id, categoria_id, genero]
    );

    if (resultado.affectedRows === 0) {
      return res.status(404).json({ erro: 'Não há pontos lançados nesta categoria e gênero.' });
    }

    res.status(200).json({
      mensagem: `Lançamento apagado: ${resultado.affectedRows} `
        + `${resultado.affectedRows === 1 ? 'escola' : 'escolas'}.`
    });
  } catch (erro) {
    console.error('Erro ao apagar o lançamento de pontos:', erro);
    res.status(500).json({ erro: 'Erro ao apagar o lançamento.' });
  }
};

module.exports = {
  listarPontosLancados,
  salvarPontosLancados,
  apagarLancamento,
  // Exportado para a Tabela Geral e para o teste de fumaça
  esperadoDe
};
