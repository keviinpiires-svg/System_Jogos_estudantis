const db = require('../config/db');

const listarClassificacao = async (req, res) => {
  try {
    // A classificação é calculada a partir dos jogos finalizados, não de uma tabela
    // acumulada: assim ela nunca fica dessincronizada se um placar for corrigido.
    const [resultado] = await db.query(`
      SELECT e.id,
             e.id AS escola_id,
             e.nome AS escola_nome,
             (SELECT g.nome
              FROM grupos_escolas ge
              INNER JOIN grupos g ON g.id = ge.grupo_id
              WHERE ge.escola_id = e.id
              LIMIT 1) AS grupo,
             COUNT(p.escola_id) AS jogos,
             CAST(COALESCE(SUM(p.gols_pro > p.gols_contra), 0) AS SIGNED) AS vitorias,
             CAST(COALESCE(SUM(p.gols_pro = p.gols_contra), 0) AS SIGNED) AS empates,
             CAST(COALESCE(SUM(p.gols_pro < p.gols_contra), 0) AS SIGNED) AS derrotas,
             CAST(COALESCE(SUM(p.gols_pro), 0) AS SIGNED) AS gols_pro,
             CAST(COALESCE(SUM(p.gols_contra), 0) AS SIGNED) AS gols_contra,
             CAST(COALESCE(SUM(p.gols_pro - p.gols_contra), 0) AS SIGNED) AS saldo_gols,
             CAST(COALESCE(SUM((p.gols_pro > p.gols_contra) * 3 + (p.gols_pro = p.gols_contra)), 0) AS SIGNED) AS pontos
      FROM escolas e
      LEFT JOIN (
        SELECT escola_1_id AS escola_id, placar_escola_1 AS gols_pro, placar_escola_2 AS gols_contra
        FROM jogos
        WHERE status = 'FINALIZADO' AND UPPER(fase) NOT IN ('SEMIFINAL', 'TERCEIRO_LUGAR', 'FINAL')
        UNION ALL
        SELECT escola_2_id AS escola_id, placar_escola_2 AS gols_pro, placar_escola_1 AS gols_contra
        FROM jogos
        WHERE status = 'FINALIZADO' AND UPPER(fase) NOT IN ('SEMIFINAL', 'TERCEIRO_LUGAR', 'FINAL')
      ) p ON p.escola_id = e.id
      GROUP BY e.id, e.nome
      ORDER BY pontos DESC, vitorias DESC, saldo_gols DESC, gols_pro DESC, e.nome ASC
    `);
    res.status(200).json(resultado);
  } catch (erro) {
    console.error("Erro ao buscar classificação:", erro);
    res.status(500).json({ erro: 'Erro ao buscar classificação' });
  }
};

module.exports = { listarClassificacao };