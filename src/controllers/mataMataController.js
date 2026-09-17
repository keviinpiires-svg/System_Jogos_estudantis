const db = require('../config/db');

// Próximo número de jogo livre (evita erro de número duplicado)
const proximoNumeroJogo = async (conexao) => {
    const [[linha]] = await conexao.query('SELECT COALESCE(MAX(numero_jogo), 0) + 1 AS proximo FROM jogos');
    return linha.proximo;
};

// Busca os 2 primeiros de um grupo na tabela de classificação
const topDoisDoGrupo = async (conexao, grupo) => {
    const [linhas] = await conexao.query(
        `SELECT escola_id FROM classificacao
         WHERE grupo = ?
         ORDER BY pontos DESC, vitorias DESC, empates DESC, escola_id ASC
         LIMIT 2`,
        [grupo]
    );
    return linhas.map((l) => l.escola_id);
};

// Semifinais: 1º A x 2º B  e  1º B x 2º A
// Body: { local_id, data_hora_semi1, data_hora_semi2 }
const gerarSemifinais = async (req, res) => {
    const { local_id, data_hora_semi1, data_hora_semi2 } = req.body;

    if (!local_id || !data_hora_semi1 || !data_hora_semi2) {
        return res.status(400).json({ erro: 'Informe local_id, data_hora_semi1 e data_hora_semi2.' });
    }

    let conexao;
    try {
        conexao = await db.getConnection();
        await conexao.beginTransaction();

        const grupoA = await topDoisDoGrupo(conexao, 'A');
        const grupoB = await topDoisDoGrupo(conexao, 'B');

        if (grupoA.length < 2 || grupoB.length < 2) {
            await conexao.rollback();
            return res.status(400).json({ erro: 'Cada grupo precisa ter ao menos 2 escolas na classificação.' });
        }

        const [jaExiste] = await conexao.query(`SELECT id FROM jogos WHERE fase = 'SEMIFINAL' LIMIT 1`);
        if (jaExiste.length > 0) {
            await conexao.rollback();
            return res.status(400).json({ erro: 'As semifinais já foram geradas.' });
        }

        const numero = await proximoNumeroJogo(conexao);
        const insert = `
            INSERT INTO jogos (numero_jogo, fase, escola_1_id, escola_2_id, local_id, data_hora, status)
            VALUES (?, 'SEMIFINAL', ?, ?, ?, ?, 'AGENDADO')
        `;
        await conexao.query(insert, [numero, grupoA[0], grupoB[1], local_id, data_hora_semi1]);
        await conexao.query(insert, [numero + 1, grupoB[0], grupoA[1], local_id, data_hora_semi2]);

        await conexao.commit();
        res.status(201).json({
            mensagem: 'Semifinais agendadas com sucesso!',
            semifinal_1: { escola_1_id: grupoA[0], escola_2_id: grupoB[1], numero_jogo: numero },
            semifinal_2: { escola_1_id: grupoB[0], escola_2_id: grupoA[1], numero_jogo: numero + 1 }
        });
    } catch (erro) {
        if (conexao) await conexao.rollback();
        console.error(erro);
        res.status(500).json({ erro: 'Erro ao gerar as semifinais.' });
    } finally {
        if (conexao) conexao.release();
    }
};

// Final e disputa de 3º lugar
const gerarFinais = async (req, res) => {
    const {
        vencedor_semi1_id, perdedor_semi1_id,
        vencedor_semi2_id, perdedor_semi2_id,
        local_id,
        data_hora_terceiro, data_hora_final
    } = req.body;

    let conexao;
    try {
        conexao = await db.getConnection();

        // Garante que as 4 escolas existem
        const [escolas] = await conexao.query(
            'SELECT id FROM escolas WHERE id IN (?, ?, ?, ?)',
            [vencedor_semi1_id, perdedor_semi1_id, vencedor_semi2_id, perdedor_semi2_id]
        );
        if (escolas.length < 4) {
            return res.status(400).json({ erro: 'Uma ou mais escolas informadas não existem.' });
        }

        await conexao.beginTransaction();

        const numero = await proximoNumeroJogo(conexao);
        const insert = `
            INSERT INTO jogos (numero_jogo, fase, escola_1_id, escola_2_id, local_id, data_hora, status)
            VALUES (?, ?, ?, ?, ?, ?, 'AGENDADO')
        `;
        await conexao.query(insert, [numero, 'TERCEIRO_LUGAR', perdedor_semi1_id, perdedor_semi2_id, local_id, data_hora_terceiro]);
        await conexao.query(insert, [numero + 1, 'FINAL', vencedor_semi1_id, vencedor_semi2_id, local_id, data_hora_final]);

        await conexao.commit();
        res.status(201).json({ mensagem: 'Grande Final e Disputa de 3º Lugar agendadas com sucesso!' });
    } catch (erro) {
        if (conexao) await conexao.rollback();
        console.error(erro);
        res.status(500).json({ erro: 'Erro ao gerar os jogos finais.' });
    } finally {
        if (conexao) conexao.release();
    }
};

module.exports = { gerarSemifinais, gerarFinais };
