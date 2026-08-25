const db = require('../config/db');

// Função 1: Salva o que o atleta fez no jogo
const registrarSumula = async (req, res) => {
    const { jogo_id, aluno_id, gols, cartoes_amarelos, cartao_vermelho } = req.body;

    try {
        const query = `
            INSERT INTO sumulas (jogo_id, aluno_id, gols, cartoes_amarelos, cartao_vermelho) 
            VALUES (?, ?, ?, ?, ?)
        `;
        await db.query(query, [jogo_id, aluno_id, gols, cartoes_amarelos, cartao_vermelho]);

        res.status(201).json({ mensagem: 'Súmula do atleta registrada com sucesso!' });
    } catch (erro) {
        console.error(erro);
        res.status(500).json({ erro: 'Erro ao registrar a súmula.' });
    }
};

// Função 2: O sistema que checa se o atleta pode jogar
const verificarSuspensao = async (req, res) => {
    const { aluno_id } = req.params;

    try {
        const [resultado] = await db.query(`
            SELECT cartao_vermelho 
            FROM sumulas 
            WHERE aluno_id = ? 
            ORDER BY jogo_id DESC 
            LIMIT 1
        `, [aluno_id]);

        if (resultado.length > 0 && resultado[0].cartao_vermelho === 1) {
            return res.status(200).json({ 
                status: 'SUSPENSO', 
                mensagem: 'Atleta suspenso. Recebeu cartão vermelho na última partida.' 
            });
        }

        res.status(200).json({ 
            status: 'LIBERADO', 
            mensagem: 'Atleta apto para jogar.' 
        });

    } catch (erro) {
        console.error(erro);
        res.status(500).json({ erro: 'Erro ao verificar condição do atleta.' });
    }
};

// Exportando as duas funções exatamente com o mesmo nome
module.exports = { registrarSumula, verificarSuspensao };