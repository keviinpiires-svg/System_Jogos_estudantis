const db = require('../config/db');

// Etapas de ensino (anos iniciais, anos finais, ensino médio), usadas no
// cadastro da escola. Desde 06/10/2026 não dividem mais a tabela geral.
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
