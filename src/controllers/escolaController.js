const db = require('../config/db');

const cadastrarEscola = async (req, res) => {
  const { nome, cnpj, etapa_ensino_id } = req.body;
  
  try {
    const [resultado] = await db.query(
      'INSERT INTO escolas (nome, cnpj, etapa_ensino_id) VALUES (?, ?, ?)',
      [nome, cnpj, etapa_ensino_id]
    );
    
    res.status(201).json({
      mensagem: 'Escola cadastrada com sucesso!',
      id_escola: resultado.insertId
    });
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao cadastrar a escola. Verifique os dados.' });
  }
};

// Nova função adicionada: Busca todas as escolas no banco
const listarEscolas = async (req, res) => {
  try {
    const [escolas] = await db.query('SELECT * FROM escolas');
    res.status(200).json(escolas); // Envia os dados para o React
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao buscar as escolas.' });
  }
};

// Exportando as duas funções para o Router conseguir enxergá-las
module.exports = {
  cadastrarEscola,
  listarEscolas
};