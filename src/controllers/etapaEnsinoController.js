const db = require('../config/db');

// Os três blocos da tabela geral (anos iniciais, anos finais, ensino médio)
const listarEtapas = async (req, res) => {
  try {
    const [linhas] = await db.query('SELECT id, nome, ordem FROM etapas_ensino ORDER BY ordem');
    res.json(linhas);
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao buscar as etapas de ensino.' });
  }
};

module.exports = {
  listarEtapas
};
