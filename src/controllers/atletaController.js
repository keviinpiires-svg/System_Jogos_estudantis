const db = require('../config/db');

const cadastrarAtleta = async (req, res) => {
  const { nome, rg_ra, data_nascimento, equipe_id } = req.body;
  
  try {
    const [resultado] = await db.query(
      'INSERT INTO atletas (nome, rg_ra, data_nascimento, equipe_id) VALUES (?, ?, ?, ?)',
      [nome, rg_ra, data_nascimento, equipe_id]
    );
    
    res.status(201).json({
      mensagem: 'Atleta cadastrado com sucesso!',
      id_atleta: resultado.insertId
    });
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao cadastrar o atleta. Verifique os dados.' });
  }
};

const listarAtletasPorEquipe = async (req, res) => {
  const { equipe_id } = req.params;

  try {
    const [atletas] = await db.query(
      'SELECT * FROM atletas WHERE equipe_id = ?',
      [equipe_id]
    );
    
    res.status(200).json(atletas);
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao buscar os atletas da equipe.' });
  }
};

module.exports = {
  cadastrarAtleta,
  listarAtletasPorEquipe
};

