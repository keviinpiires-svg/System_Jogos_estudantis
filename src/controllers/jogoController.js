const db = require('../config/db');

// 1. Lógica para Agendar a Partida
const agendarJogo = async (req, res) => {
    const { numero_jogo, fase, grupo_id, local_id, data_hora, escola_1_id, escola_2_id } = req.body;

    try {
        const [resultado] = await db.query(
            `INSERT INTO jogos (numero_jogo, fase, grupo_id, local_id, data_hora, escola_1_id, escola_2_id) 
             VALUES (?, ?, ?, ?, ?, ?, ?)`,
            [numero_jogo, fase, grupo_id, local_id, data_hora, escola_1_id, escola_2_id]
        );
        res.status(201).json({ mensagem: 'Partida agendada com sucesso!', id_jogo: resultado.insertId });
    } catch (erro) {
        console.error(erro);
        if (erro.code === 'ER_DUP_ENTRY') {
            return res.status(400).json({ erro: 'Já existe uma partida com este número.' });
        }
        res.status(500).json({ erro: 'Erro ao agendar a partida.' });
    }
};

// 2. Lógica para Finalizar a Partida
const finalizarJogo = async (req, res) => {
    const { id } = req.params; 
    const { placar_escola_1, placar_escola_2 } = req.body;

    try {
        const [resultado] = await db.query(
            `UPDATE jogos SET placar_escola_1 = ?, placar_escola_2 = ?, status = 'FINALIZADO' WHERE id = ?`,
            [placar_escola_1, placar_escola_2, id]
        );

        if (resultado.affectedRows === 0) {
            return res.status(404).json({ erro: 'Jogo não encontrado.' });
        }
        res.status(200).json({ mensagem: 'Partida finalizada e placar atualizado com sucesso!' });
    } catch (erro) {
        console.error(erro);
        res.status(500).json({ erro: 'Erro ao finalizar a partida.' });
    }
};
const listarJogos = async (req, res) => {
    try {
        const query = `
            SELECT 
                j.id AS id_jogo, j.numero_jogo, j.fase, g.nome AS grupo, j.data_hora, j.status,
                e1.nome AS escola_1, j.placar_escola_1, j.placar_escola_2, e2.nome AS escola_2,
                l.nome AS local_jogo
            FROM jogos j
            JOIN escolas e1 ON j.escola_1_id = e1.id
            JOIN escolas e2 ON j.escola_2_id = e2.id
            LEFT JOIN grupos g ON j.grupo_id = g.id
            LEFT JOIN locais_disputa l ON j.local_id = l.id
            ORDER BY j.data_hora ASC, j.numero_jogo ASC
        `;
        
        const [jogos] = await db.query(query);

        if (jogos.length === 0) return res.status(404).json({ mensagem: 'Nenhum jogo encontrado.' });
        res.status(200).json(jogos);
    } catch (erro) {
        console.error(erro);
        res.status(500).json({ erro: 'Erro ao buscar a lista de jogos.' });
    }
};
const buscarPorId = async (req, res) => {
    const { id } = req.params;
    try {
        const query = `
            SELECT j.*, e1.nome AS escola_1_nome, e2.nome AS escola_2_nome
            FROM jogos j
            JOIN escolas e1 ON j.escola_1_id = e1.id
            JOIN escolas e2 ON j.escola_2_id = e2.id
            WHERE j.id = ?
        `;
        const [jogo] = await db.query(query, [id]);

        if (jogo.length === 0) {
            return res.status(404).json({ mensagem: 'Jogo não encontrado.' });
        }

        res.status(200).json(jogo[0]);
    } catch (erro) {
        console.error(erro);
        res.status(500).json({ erro: 'Erro ao buscar o jogo.' });
    }
};




// Exporta as funções para a Recepcionista usar
module.exports = {
    agendarJogo,
    finalizarJogo,
    listarJogos,
    buscarPorId
};