const db = require('../config/db');

const gerarSemifinais = async (req, res) => {
    // ... (este é o código que você já tem e está funcionando)
};

// --- NOVA FUNÇÃO DA FINAL ---
const gerarFinais = async (req, res) => {
    const { 
        vencedor_semi1_id, perdedor_semi1_id, 
        vencedor_semi2_id, perdedor_semi2_id, 
        local_id, 
        data_hora_terceiro, data_hora_final 
    } = req.body;

    try {
        // Validação preventiva para garantir que todas as 4 escolas existem
        const [escolas] = await db.query(
            'SELECT id FROM escolas WHERE id IN (?, ?, ?, ?)', 
            [vencedor_semi1_id, perdedor_semi1_id, vencedor_semi2_id, perdedor_semi2_id]
        );

        if (escolas.length < 4) {
            return res.status(400).json({ erro: "Uma ou mais escolas informadas não existem." });
        }

        // Jogo da Disputa de 3º Lugar
        const queryTerceiro = `
            INSERT INTO jogos (numero_jogo, fase, escola_1_id, escola_2_id, local_id, data_hora, status) 
            VALUES (?, 'TERCEIRO_LUGAR', ?, ?, ?, ?, 'AGENDADO')
        `;
        await db.query(queryTerceiro, [102, perdedor_semi1_id, perdedor_semi2_id, local_id, data_hora_terceiro]);

        // Jogo da Grande Final
        const queryFinal = `
            INSERT INTO jogos (numero_jogo, fase, escola_1_id, escola_2_id, local_id, data_hora, status) 
            VALUES (?, 'FINAL', ?, ?, ?, ?, 'AGENDADO')
        `;
        await db.query(queryFinal, [103, vencedor_semi1_id, vencedor_semi2_id, local_id, data_hora_final]);

        res.status(201).json({ mensagem: 'Grande Final e Disputa de 3º Lugar agendadas com sucesso!' });

    } catch (erro) {
        console.error(erro);
        res.status(500).json({ erro: 'Erro ao gerar os jogos finais.' });
    }
};

// Não esqueça de exportar a função nova aqui embaixo!
module.exports = { gerarSemifinais, gerarFinais };