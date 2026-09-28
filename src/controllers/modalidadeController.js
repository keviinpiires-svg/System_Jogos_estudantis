const db = require('../config/db');

// Alimenta o primeiro nível do menu lateral. total_competicoes permite à tela
// esconder (ou marcar) a modalidade que ainda não tem competição importada.
const listarModalidades = async (req, res) => {
  try {
    const [modalidades] = await db.query(
      `SELECT m.id, m.nome, m.slug, m.tipo, m.tipo_placar,
              m.min_atletas, m.max_atletas, m.ordem,
              COUNT(c.id) AS total_competicoes
         FROM modalidades m
         LEFT JOIN competicoes c ON c.modalidade_id = m.id
        GROUP BY m.id
        ORDER BY m.ordem, m.nome`
    );

    res.status(200).json(modalidades);
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao buscar as modalidades.' });
  }
};

module.exports = { listarModalidades };
