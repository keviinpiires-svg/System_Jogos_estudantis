const db = require('../config/db');
const { REGRAS } = require('../config/regrasProvisorias');

// ============================================================================
// AJUSTES DE PONTOS DA TABELA GERAL — as punições da Comissão Disciplinar.
//
// O regulamento permite tirar de 5 a 10 pontos da soma geral da escola. É a
// única coisa da tabela geral que é GRAVADA: tudo o mais sai dos jogos. Por
// isso cada ajuste guarda motivo, data e quem aplicou — uma punição sem
// motivo escrito não se defende depois.
//
// A faixa e o alcance (soma geral, não um bloco) vivem em
// src/config/regrasProvisorias.js, chave `tabelaGeral.ajuste`.
// ============================================================================

const { minimo: MINIMO, maximo: MAXIMO } = REGRAS.tabelaGeral.ajuste;

const MOTIVO_MAXIMO = 255;

const listarAjustes = async (req, res) => {
  try {
    const [ajustes] = await db.query(
      `SELECT a.id, a.escola_id, a.pontos, a.motivo, a.criado_em,
              esc.nome AS escola_nome, u.nome AS usuario_nome
         FROM ajustes_pontos_geral a
         INNER JOIN escolas esc ON esc.id = a.escola_id
         LEFT JOIN usuarios u ON u.id = a.usuario_id
        ORDER BY a.criado_em DESC, a.id DESC`
    );

    res.status(200).json({
      ajustes,
      regra: {
        minimo: MINIMO,
        maximo: MAXIMO,
        na_soma_geral: REGRAS.tabelaGeral.ajuste.naSomaGeral,
        provisoria: REGRAS.tabelaGeral.provisorio,
        decidido_em: REGRAS.tabelaGeral.decididoEm
      }
    });
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao listar os ajustes de pontos.' });
  }
};

// POST /api/ajustes-pontos — só ADMIN
const aplicarAjuste = async (req, res) => {
  const escola_id = Number(req.body.escola_id);
  const pontos = Number(req.body.pontos);
  const motivo = String(req.body.motivo || '').trim();

  if (!Number.isInteger(escola_id) || escola_id <= 0) {
    return res.status(400).json({ erro: 'Informe a escola punida.' });
  }

  if (!Number.isInteger(pontos) || pontos < MINIMO || pontos > MAXIMO) {
    return res.status(400).json({
      erro: `A punição do regulamento é de ${Math.abs(MAXIMO)} a ${Math.abs(MINIMO)} pontos: `
        + `informe um valor inteiro entre ${MINIMO} e ${MAXIMO}.`
    });
  }

  if (!motivo) {
    return res.status(400).json({ erro: 'A punição precisa de um motivo escrito.' });
  }

  if (motivo.length > MOTIVO_MAXIMO) {
    return res.status(400).json({ erro: `O motivo cabe em ${MOTIVO_MAXIMO} caracteres.` });
  }

  try {
    const [[escola]] = await db.query('SELECT id, nome FROM escolas WHERE id = ?', [escola_id]);

    if (!escola) {
      return res.status(404).json({ erro: 'Escola não encontrada.' });
    }

    const [resultado] = await db.query(
      'INSERT INTO ajustes_pontos_geral (escola_id, pontos, motivo, usuario_id) VALUES (?, ?, ?, ?)',
      [escola_id, pontos, motivo, req.usuario.id]
    );

    // Quantas punições a escola já tem: mais de uma é permitido, mas quem
    // aplica merece ver que não é a primeira.
    const [[{ total, soma }]] = await db.query(
      `SELECT COUNT(*) AS total, COALESCE(SUM(pontos), 0) AS soma
         FROM ajustes_pontos_geral WHERE escola_id = ?`,
      [escola_id]
    );

    res.status(201).json({
      mensagem: `${escola.nome} perdeu ${Math.abs(pontos)} pontos na tabela geral.`,
      id: resultado.insertId,
      escola_id,
      escola_nome: escola.nome,
      pontos,
      motivo,
      total_de_punicoes: total,
      total_descontado: Number(soma)
    });
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao aplicar o ajuste de pontos.' });
  }
};

// DELETE /api/ajustes-pontos/:id — só ADMIN
// Punição aplicada por engano se desfaz apagando: o histórico de quem aplicou
// está no próprio registro, e guardar punição cancelada só confundiria a soma.
const removerAjuste = async (req, res) => {
  const id = Number(req.params.id);

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ erro: 'Identificador de ajuste inválido.' });
  }

  try {
    const [[ajuste]] = await db.query(
      `SELECT a.id, a.pontos, esc.nome AS escola_nome
         FROM ajustes_pontos_geral a
         INNER JOIN escolas esc ON esc.id = a.escola_id
        WHERE a.id = ?`,
      [id]
    );

    if (!ajuste) {
      return res.status(404).json({ erro: 'Ajuste não encontrado.' });
    }

    await db.query('DELETE FROM ajustes_pontos_geral WHERE id = ?', [id]);

    res.status(200).json({
      mensagem: `${ajuste.escola_nome} recuperou ${Math.abs(ajuste.pontos)} pontos.`,
      id
    });
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao remover o ajuste de pontos.' });
  }
};

module.exports = { listarAjustes, aplicarAjuste, removerAjuste };
