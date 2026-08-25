const db = require('../config/db');

const cadastrarEscola = async (req, res) => {
    // Agora usando as colunas certas que vi na sua imagem!
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

module.exports = {
    cadastrarEscola
};