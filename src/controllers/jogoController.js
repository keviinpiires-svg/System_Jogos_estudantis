const db = require('../config/db');

// 1. Lógica para Agendar a Partida
// Fases eliminatórias só podem nascer do cruzamento automático dos grupos
// (POST /api/matamata/gerar e /finais), nunca de um agendamento manual.
const FASES_BLOQUEADAS = ['SEMIFINAL', 'FINAL', 'TERCEIROLUGAR'];

const agendarJogo = async (req, res) => {
    const { fase, grupo_id, local_id, data_hora, escola_1_id, escola_2_id } = req.body;

    const faseNormalizada = String(fase || '').toUpperCase().replace(/[^A-Z]/g, '');
    if (FASES_BLOQUEADAS.includes(faseNormalizada)) {
        return res.status(403).json({
            erro: 'Jogos de mata-mata não podem ser agendados manualmente. Use o botão "Gerar Semifinais" na tela de Mata-Mata.'
        });
    }

    try {
        // O número do jogo é sequencial e definido aqui, nunca pelo cliente.
        // Calcular dentro do próprio INSERT evita duas partidas pegarem o mesmo número.
        const [resultado] = await db.query(
            `INSERT INTO jogos (numero_jogo, fase, grupo_id, local_id, data_hora, escola_1_id, escola_2_id)
             SELECT COALESCE(MAX(numero_jogo), 0) + 1, ?, ?, ?, ?, ?, ? FROM jogos`,
            [fase, grupo_id, local_id, data_hora, escola_1_id, escola_2_id]
        );

        const [[jogo]] = await db.query('SELECT numero_jogo FROM jogos WHERE id = ?', [resultado.insertId]);

        res.status(201).json({
            mensagem: `Partida agendada com sucesso! Jogo #${jogo.numero_jogo}.`,
            id_jogo: resultado.insertId,
            numero_jogo: jogo.numero_jogo
        });
    } catch (erro) {
        console.error(erro);
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

        // Lista vazia não é erro: devolve [] para a tela mostrar "nenhum jogo"
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


// Exclui um jogo agendado. A súmula do jogo vai junto, dentro da mesma
// transação, para não deixar eventos órfãos apontando para um jogo apagado.
const excluirJogo = async (req, res) => {
    const { id } = req.params;
    const conexao = await db.getConnection();

    try {
        const [jogo] = await conexao.query('SELECT id, numero_jogo, status FROM jogos WHERE id = ?', [id]);

        if (jogo.length === 0) {
            return res.status(404).json({ mensagem: 'Jogo não encontrado.' });
        }

        await conexao.beginTransaction();
        await conexao.query('DELETE FROM sumulas WHERE jogo_id = ?', [id]);
        await conexao.query('DELETE FROM jogos WHERE id = ?', [id]);
        await conexao.commit();

        res.status(200).json({ mensagem: `Jogo #${jogo[0].numero_jogo} excluído com sucesso.` });
    } catch (erro) {
        await conexao.rollback();
        console.error(erro);
        res.status(500).json({ erro: 'Erro ao excluir o jogo.' });
    } finally {
        conexao.release();
    }
};

// Exporta as funções para a Recepcionista usar
module.exports = {
    agendarJogo,
    finalizarJogo,
    listarJogos,
    buscarPorId,
    excluirJogo
};