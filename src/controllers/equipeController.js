const db = require('../config/db');

// Equipes filtradas por escola e/ou competição, com o que a tela de inscrição
// precisa para decidir: a competição a que pertencem, o grupo, quantos atletas
// já estão inscritos e qual é o teto da modalidade.
const listarEquipes = async (req, res) => {
  const condicoes = [];
  const valores = [];

  if (req.query.escola_id) {
    const escola_id = Number(req.query.escola_id);
    if (!Number.isInteger(escola_id) || escola_id <= 0) {
      return res.status(400).json({ erro: 'Identificador de escola inválido.' });
    }
    condicoes.push('e.escola_id = ?');
    valores.push(escola_id);
  }

  if (req.query.competicao_id) {
    const competicao_id = Number(req.query.competicao_id);
    if (!Number.isInteger(competicao_id) || competicao_id <= 0) {
      return res.status(400).json({ erro: 'Identificador de competição inválido.' });
    }
    condicoes.push('e.competicao_id = ?');
    valores.push(competicao_id);
  }

  const onde = condicoes.length > 0 ? `WHERE ${condicoes.join(' AND ')}` : '';

  try {
    const [equipes] = await db.query(
      `SELECT e.id, e.escola_id, e.competicao_id, e.tecnico_nome,
              esc.nome AS escola_nome,
              g.id AS grupo_id, g.nome AS grupo_nome,
              m.id AS modalidade_id, m.nome AS modalidade_nome, m.slug AS modalidade_slug,
              m.tipo AS modalidade_tipo, m.min_atletas, m.max_atletas,
              cat.nome AS categoria_nome, cat.idade_maxima, c.genero,
              (SELECT COUNT(*) FROM inscricoes_atletas i WHERE i.equipe_id = e.id) AS total_inscritos
         FROM equipes e
         INNER JOIN escolas esc ON esc.id = e.escola_id
         INNER JOIN competicoes c ON c.id = e.competicao_id
         INNER JOIN modalidades m ON m.id = c.modalidade_id
         INNER JOIN categorias cat ON cat.id = c.categoria_id
         LEFT JOIN grupos g ON g.id = e.grupo_id
         ${onde}
        ORDER BY m.ordem, cat.ordem, c.genero, esc.nome`,
      valores
    );

    res.status(200).json(equipes);
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao buscar as equipes.' });
  }
};

module.exports = { listarEquipes };
