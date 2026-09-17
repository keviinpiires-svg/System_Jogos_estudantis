const db = require('../config/db');

const listarArtilharia = async (req, res) => {
  try {
    const [resultado] = await db.query(`
      SELECT s.atleta_id,
             a.nome AS atleta_nome,
             e.nome AS escola_nome,
             CAST(SUM(s.gols) AS UNSIGNED) AS total_gols
      FROM sumulas s
      INNER JOIN atletas a ON s.atleta_id = a.id
      INNER JOIN escolas e ON a.escola_id = e.id
      GROUP BY s.atleta_id, a.nome, e.nome
      HAVING total_gols > 0
      ORDER BY total_gols DESC, a.nome ASC
      LIMIT 10
    `);
    res.status(200).json(resultado);
  } catch (erro) {
    console.error('Erro ao buscar artilharia:', erro);
    res.status(500).json({ erro: 'Erro ao buscar artilharia' });
  }
};

module.exports = { listarArtilharia };
