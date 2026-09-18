const db = require('../config/db');

const obterEstatisticas = async (req, res) => {
  try {
    const [
      [[escolas]],
      [[atletas]],
      [[gols]],
      [proximosJogos],
      [campeoes]
    ] = await Promise.all([
      db.query('SELECT COUNT(*) AS total FROM escolas'),
      db.query('SELECT COUNT(*) AS total FROM atletas'),
      db.query('SELECT CAST(COALESCE(SUM(gols), 0) AS UNSIGNED) AS total FROM sumulas'),
      db.query(`
        SELECT j.id, j.numero_jogo, UPPER(j.fase) AS fase, j.data_hora, j.status,
               j.escola_1_id, e1.nome AS escola_1_nome,
               j.escola_2_id, e2.nome AS escola_2_nome
        FROM jogos j
        INNER JOIN escolas e1 ON j.escola_1_id = e1.id
        INNER JOIN escolas e2 ON j.escola_2_id = e2.id
        WHERE j.status = 'AGENDADO' AND j.data_hora >= NOW()
        ORDER BY j.data_hora ASC
        LIMIT 1
      `),
      // Campeão: vencedor da final já encerrada. Empate não define campeão.
      db.query(`
        SELECT j.numero_jogo, j.data_hora,
               CASE WHEN j.placar_escola_1 > j.placar_escola_2 THEN e1.nome ELSE e2.nome END AS escola_nome,
               CASE WHEN j.placar_escola_1 > j.placar_escola_2 THEN e2.nome ELSE e1.nome END AS vice_nome,
               GREATEST(j.placar_escola_1, j.placar_escola_2) AS gols_campeao,
               LEAST(j.placar_escola_1, j.placar_escola_2) AS gols_vice
        FROM jogos j
        INNER JOIN escolas e1 ON j.escola_1_id = e1.id
        INNER JOIN escolas e2 ON j.escola_2_id = e2.id
        WHERE UPPER(j.fase) = 'FINAL'
          AND j.status = 'FINALIZADO'
          AND j.placar_escola_1 <> j.placar_escola_2
        ORDER BY j.data_hora DESC
        LIMIT 1
      `)
    ]);

    res.status(200).json({
      total_escolas: escolas.total,
      total_atletas: atletas.total,
      total_gols: gols.total,
      proximo_jogo: proximosJogos[0] || null,
      campeao: campeoes[0] || null
    });
  } catch (erro) {
    console.error('Erro ao buscar estatísticas do dashboard:', erro);
    res.status(500).json({ erro: 'Erro ao buscar estatísticas do dashboard' });
  }
};

module.exports = { obterEstatisticas };
