const db = require('../config/db');

const listarClassificacao = async (req, res) => {
  try {
    const [resultado] = await db.query(`
      SELECT c.*, e.nome AS escola_nome
      FROM classificacao c
      INNER JOIN escolas e ON c.escola_id = e.id
      ORDER BY c.pontos DESC, c.vitorias DESC, c.saldo_gols DESC, c.gols_pro DESC
    `);
    res.status(200).json(resultado);
  } catch (erro) {
    console.error("Erro ao buscar classificação:", erro);
    res.status(500).json({ erro: 'Erro ao buscar classificação' });
  }
};

module.exports = { listarClassificacao };