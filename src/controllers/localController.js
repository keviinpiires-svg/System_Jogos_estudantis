const db = require('../config/db');

// Locais de disputa, usados no dropdown de agendamento de jogos
const listarLocais = async (req, res) => {
  try {
    const [linhas] = await db.query('SELECT id, nome, endereco FROM locais_disputa ORDER BY nome');
    res.json(linhas);
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao buscar os locais de disputa.' });
  }
};

module.exports = {
  listarLocais
};
