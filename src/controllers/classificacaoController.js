const db = require('../config/db');

const calcularClassificacao = async (req, res) => {
    const { grupo_id } = req.params;
    try {
        const query = `
            SELECT e.nome AS escola, COUNT(j.id) AS jogos,
                SUM(CASE WHEN (j.escola_1_id = e.id AND j.placar_escola_1 > j.placar_escola_2) OR (j.escola_2_id = e.id AND j.placar_escola_2 > j.placar_escola_1) THEN 1 ELSE 0 END) AS vitorias,
                SUM(CASE WHEN (j.escola_1_id = e.id OR j.escola_2_id = e.id) AND j.placar_escola_1 = j.placar_escola_2 THEN 1 ELSE 0 END) AS empates,
                SUM(CASE WHEN (j.escola_1_id = e.id AND j.placar_escola_1 < j.placar_escola_2) OR (j.escola_2_id = e.id AND j.placar_escola_2 < j.placar_escola_1) THEN 1 ELSE 0 END) AS derrotas,
                SUM(CASE WHEN j.escola_1_id = e.id THEN j.placar_escola_1 WHEN j.escola_2_id = e.id THEN j.placar_escola_2 ELSE 0 END) AS gols_pro,
                SUM(CASE WHEN j.escola_1_id = e.id THEN j.placar_escola_2 WHEN j.escola_2_id = e.id THEN j.placar_escola_1 ELSE 0 END) AS gols_contra
            FROM grupos_escolas ge
            JOIN escolas e ON ge.escola_id = e.id
            LEFT JOIN jogos j ON j.grupo_id = ge.grupo_id AND j.status = 'FINALIZADO' AND (j.escola_1_id = e.id OR j.escola_2_id = e.id)
            WHERE ge.grupo_id = ?
            GROUP BY e.id, e.nome
        `;
        const [tabela] = await db.query(query, [grupo_id]);

        const classificacao = tabela.map(time => {
            const pontos = (Number(time.vitorias) * 3) + (Number(time.empates) * 1);
            const saldo_gols = Number(time.gols_pro) - Number(time.gols_contra);
            return { ...time, pontos, saldo_gols };
        });

        classificacao.sort((a, b) => {
            if (b.pontos !== a.pontos) return b.pontos - a.pontos;
            if (b.saldo_gols !== a.saldo_gols) return b.saldo_gols - a.saldo_gols;
            return b.gols_pro - a.gols_pro;
        });

        res.json(classificacao);
    } catch (erro) {
        console.error(erro);
        res.status(500).json({ erro: 'Erro ao gerar a tabela.' });
    }
};

module.exports = { calcularClassificacao };