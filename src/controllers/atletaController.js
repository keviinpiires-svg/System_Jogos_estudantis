const db = require('../config/db');

const cadastrarAtleta = async (req, res) => {
  const { nome, rg_ou_matricula, data_nascimento, escola_id } = req.body;

  try {
    const [resultado] = await db.query(
      'INSERT INTO atletas (nome, rg_ou_matricula, data_nascimento, escola_id) VALUES (?, ?, ?, ?)',
      [nome, rg_ou_matricula, data_nascimento, escola_id]
    );
    
    res.status(201).json({
      mensagem: 'Atleta cadastrado com sucesso!',
      id_atleta: resultado.insertId
    });
  } catch (erro) {
    console.error(erro);
    if (erro.code === 'ER_DUP_ENTRY') {
      return res.status(400).json({ erro: 'Já existe um atleta com este RG/matrícula.' });
    }
    if (erro.code === 'ER_NO_REFERENCED_ROW_2') {
      return res.status(400).json({ erro: 'Escola informada não existe.' });
    }
    res.status(500).json({ erro: 'Erro ao cadastrar o atleta. Verifique os dados.' });
  }
};

const listarAtletasPorEquipe = async (req, res) => {
  const { escola_id } = req.params;

  try {
    const [atletas] = await db.query(
      'SELECT * FROM atletas WHERE escola_id = ? ORDER BY nome ASC',
      [escola_id]
    );
    
    res.status(200).json(atletas);
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao buscar os atletas da equipe.' });
  }
};

const excluirAtleta = async (req, res) => {
  const { id } = req.params;

  try {
    const [resultado] = await db.query('DELETE FROM atletas WHERE id = ?', [id]);
    
    if (resultado.affectedRows === 0) {
      return res.status(404).json({ erro: 'Atleta não encontrado.' });
    }

    res.status(200).json({ mensagem: 'Atleta excluído com sucesso!' });
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao excluir o atleta.' });
  }
};

const atualizarAtleta = async (req, res) => {
  const { id } = req.params;
  const { nome, rg_ou_matricula, data_nascimento, escola_id } = req.body;

  try {
    const [resultado] = await db.query(
      'UPDATE atletas SET nome = ?, rg_ou_matricula = ?, data_nascimento = ?, escola_id = ? WHERE id = ?',
      [nome, rg_ou_matricula, data_nascimento, escola_id, id]
    );

    if (resultado.affectedRows === 0) {
      return res.status(404).json({ erro: 'Atleta não encontrado.' });
    }

    res.status(200).json({ mensagem: 'Atleta atualizado com sucesso!' });
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao atualizar o atleta.' });
  }
};

module.exports = {
  cadastrarAtleta,
  listarAtletasPorEquipe,
  excluirAtleta,
  atualizarAtleta
};