const db = require('../config/db');

// Próximo número de jogo livre (evita erro de número duplicado)
const proximoNumeroJogo = async (conexao) => {
    const [[linha]] = await conexao.query('SELECT COALESCE(MAX(numero_jogo), 0) + 1 AS proximo FROM jogos');
    return linha.proximo;
};

// Busca os 2 primeiros de um grupo calculando a classificação a partir dos jogos
// finalizados, com os mesmos critérios de desempate da tabela geral.
// O grupo vem do vínculo escola -> grupo (grupos_escolas), e não de jogos.grupo_id:
// assim um jogo agendado sem grupo_id preenchido continua contando.
const topDoisDoGrupo = async (conexao, grupo) => {
    const [linhas] = await conexao.query(
        `SELECT p.escola_id
         FROM (
           SELECT j.escola_1_id AS escola_id, j.placar_escola_1 AS gols_pro, j.placar_escola_2 AS gols_contra
           FROM jogos j
           WHERE j.status = 'FINALIZADO' AND UPPER(j.fase) NOT IN ('SEMIFINAL', 'TERCEIRO_LUGAR', 'FINAL')
           UNION ALL
           SELECT j.escola_2_id AS escola_id, j.placar_escola_2 AS gols_pro, j.placar_escola_1 AS gols_contra
           FROM jogos j
           WHERE j.status = 'FINALIZADO' AND UPPER(j.fase) NOT IN ('SEMIFINAL', 'TERCEIRO_LUGAR', 'FINAL')
         ) p
         INNER JOIN grupos_escolas ge ON ge.escola_id = p.escola_id
         INNER JOIN grupos g ON g.id = ge.grupo_id
         WHERE g.nome = ?
         GROUP BY p.escola_id
         ORDER BY SUM((p.gols_pro > p.gols_contra) * 3 + (p.gols_pro = p.gols_contra)) DESC,
                  SUM(p.gols_pro > p.gols_contra) DESC,
                  SUM(p.gols_pro - p.gols_contra) DESC,
                  SUM(p.gols_pro) DESC,
                  p.escola_id ASC
         LIMIT 2`,
        [grupo]
    );
    return linhas.map((l) => l.escola_id);
};

// Data padrão quando o administrador gera as chaves sem informar o calendário
const daquiA = (dias, hora) => {
    const data = new Date();
    data.setDate(data.getDate() + dias);
    data.setHours(hora, 0, 0, 0);
    return data.toISOString().slice(0, 19).replace('T', ' ');
};

// Semifinais: 1º A x 2º B  e  1º B x 2º A
// Body (tudo opcional): { local_id, data_hora_semi1, data_hora_semi2 }
const gerarSemifinais = async (req, res) => {
    const { local_id, data_hora_semi1, data_hora_semi2 } = req.body || {};

    let conexao;
    try {
        conexao = await db.getConnection();
        await conexao.beginTransaction();

        const grupoA = await topDoisDoGrupo(conexao, 'A');
        const grupoB = await topDoisDoGrupo(conexao, 'B');

        if (grupoA.length < 2 || grupoB.length < 2) {
            await conexao.rollback();
            const faltando = [grupoA.length < 2 && 'A', grupoB.length < 2 && 'B'].filter(Boolean).join(' e ');
            return res.status(400).json({
                erro: `O grupo ${faltando} ainda não tem dois times com jogos finalizados. Registre as súmulas da fase de grupos antes de gerar as chaves.`
            });
        }

        const [jaExiste] = await conexao.query(`SELECT id FROM jogos WHERE UPPER(fase) = 'SEMIFINAL' LIMIT 1`);
        if (jaExiste.length > 0) {
            await conexao.rollback();
            return res.status(400).json({ erro: 'As semifinais já foram geradas.' });
        }

        // Sem local informado, usa o primeiro local de disputa cadastrado
        let localEscolhido = Number(local_id);
        if (!localEscolhido) {
            const [[local]] = await conexao.query('SELECT id FROM locais_disputa ORDER BY id LIMIT 1');
            if (!local) {
                await conexao.rollback();
                return res.status(400).json({ erro: 'Cadastre um local de disputa antes de gerar as chaves.' });
            }
            localEscolhido = local.id;
        }

        const dataSemi1 = data_hora_semi1 || daquiA(7, 10);
        const dataSemi2 = data_hora_semi2 || daquiA(7, 13);

        const numero = await proximoNumeroJogo(conexao);
        const insert = `
            INSERT INTO jogos (numero_jogo, fase, escola_1_id, escola_2_id, local_id, data_hora, status)
            VALUES (?, 'SEMIFINAL', ?, ?, ?, ?, 'AGENDADO')
        `;
        await conexao.query(insert, [numero, grupoA[0], grupoB[1], localEscolhido, dataSemi1]);
        await conexao.query(insert, [numero + 1, grupoB[0], grupoA[1], localEscolhido, dataSemi2]);

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

// Grande Final: os finalistas saem dos vencedores das semifinais já finalizadas.
// Quem venceu nunca vem do cliente, para o chaveamento não poder ser burlado.
// Body (tudo opcional): { local_id, data_hora_final }
const gerarFinal = async (req, res) => {
    const { local_id, data_hora_final } = req.body || {};

    let conexao;
    try {
        conexao = await db.getConnection();
        await conexao.beginTransaction();

        const [semifinais] = await conexao.query(`
            SELECT id, escola_1_id, escola_2_id, placar_escola_1, placar_escola_2, status, local_id
            FROM jogos
            WHERE UPPER(fase) = 'SEMIFINAL'
            ORDER BY data_hora, numero_jogo
        `);

        if (semifinais.length < 2) {
            await conexao.rollback();
            return res.status(400).json({ erro: 'As semifinais ainda não foram geradas.' });
        }

        if (semifinais.some((jogo) => jogo.status !== 'FINALIZADO')) {
            await conexao.rollback();
            return res.status(400).json({ erro: 'Registre a súmula das duas semifinais antes de gerar a final.' });
        }

        const empatada = semifinais.find((jogo) => jogo.placar_escola_1 === jogo.placar_escola_2);
        if (empatada) {
            await conexao.rollback();
            return res.status(400).json({
                erro: 'Uma das semifinais terminou empatada e não tem vencedor definido. Ajuste o placar para definir quem avança.'
            });
        }

        const [jaExiste] = await conexao.query(`SELECT id FROM jogos WHERE UPPER(fase) = 'FINAL' LIMIT 1`);
        if (jaExiste.length > 0) {
            await conexao.rollback();
            return res.status(400).json({ erro: 'A Grande Final já foi gerada.' });
        }

        const vencedor = (jogo) =>
            jogo.placar_escola_1 > jogo.placar_escola_2 ? jogo.escola_1_id : jogo.escola_2_id;

        const finalista1 = vencedor(semifinais[0]);
        const finalista2 = vencedor(semifinais[1]);

        // Sem local informado, repete o local da primeira semifinal
        const localEscolhido = Number(local_id) || semifinais[0].local_id;
        const dataFinal = data_hora_final || daquiA(7, 16);

        const numero = await proximoNumeroJogo(conexao);
        await conexao.query(
            `INSERT INTO jogos (numero_jogo, fase, escola_1_id, escola_2_id, local_id, data_hora, status)
             VALUES (?, 'FINAL', ?, ?, ?, ?, 'AGENDADO')`,
            [numero, finalista1, finalista2, localEscolhido, dataFinal]
        );

        await conexao.commit();
        res.status(201).json({
            mensagem: 'Grande Final agendada com sucesso!',
            final: { escola_1_id: finalista1, escola_2_id: finalista2, numero_jogo: numero }
        });
    } catch (erro) {
        if (conexao) await conexao.rollback();
        console.error(erro);
        res.status(500).json({ erro: 'Erro ao gerar a Grande Final.' });
    } finally {
        if (conexao) conexao.release();
    }
};

const listarMataMata = async (req, res) => {
    try {
        const [jogos] = await db.query(`
            SELECT j.id, j.numero_jogo, UPPER(j.fase) AS fase, j.data_hora, j.status, j.local_id,
                   j.escola_1_id, e1.nome AS escola_1_nome, j.placar_escola_1,
                   j.escola_2_id, e2.nome AS escola_2_nome, j.placar_escola_2
            FROM jogos j
            INNER JOIN escolas e1 ON j.escola_1_id = e1.id
            INNER JOIN escolas e2 ON j.escola_2_id = e2.id
            WHERE j.fase IN ('SEMIFINAL', 'TERCEIRO_LUGAR', 'FINAL')
            ORDER BY FIELD(j.fase, 'SEMIFINAL', 'TERCEIRO_LUGAR', 'FINAL'), j.data_hora, j.numero_jogo
        `);
        res.status(200).json(jogos);
    } catch (erro) {
        console.error(erro);
        res.status(500).json({ erro: 'Erro ao buscar os jogos do mata-mata.' });
    }
};

module.exports = { gerarSemifinais, gerarFinal, listarMataMata };
