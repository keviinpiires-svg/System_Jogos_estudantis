const db = require('../config/db');

const listarElenco = async (req, res) => {
    const { escola_id } = req.params;
    try {
        const [alunos] = await db.query(
            'SELECT * FROM alunos WHERE escola_id = ? ORDER BY nome ASC', [escola_id]
        );
        if (alunos.length === 0) return res.status(404).json({ mensagem: 'Nenhum aluno cadastrado.' });
        res.status(200).json(alunos);
    } catch (erro) {
        console.error(erro);
        res.status(500).json({ erro: 'Erro ao buscar o elenco da escola.' });
    }
};

module.exports = { listarElenco };