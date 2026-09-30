const db = require('../config/db');

// ============================================================================
// PAINEL GERAL — números do evento inteiro, lidos de jogos, sumula_atletas e
// competicoes. Nada é guardado: tudo sai das mesmas tabelas que a súmula e a
// classificação usam.
// ============================================================================

const obterEstatisticas = async (req, res) => {
  try {
    const [
      [[escolas]],
      [[atletas]],
      [[competicoes]],
      [[equipes]],
      [porSituacao],
      [[gols]],
      [proximos],
      [campeoes]
    ] = await Promise.all([
      db.query('SELECT COUNT(*) AS total FROM escolas'),
      db.query('SELECT COUNT(*) AS total FROM atletas'),
      db.query('SELECT COUNT(*) AS total FROM competicoes'),
      db.query('SELECT COUNT(*) AS total FROM equipes'),

      db.query("SELECT status, COUNT(*) AS total FROM jogos GROUP BY status"),

      // Só competições de gol: somar gols de futsal com pontos de basquete
      // daria um número sem significado. O basquete tem o próprio total na
      // artilharia da competição dele.
      db.query(
        `SELECT CAST(COALESCE(SUM(s.gols), 0) AS UNSIGNED) AS total
           FROM sumula_atletas s
           INNER JOIN jogos j ON j.id = s.jogo_id
           INNER JOIN competicoes c ON c.id = j.competicao_id
           INNER JOIN modalidades m ON m.id = c.modalidade_id
          WHERE m.tipo_placar = 'GOLS'`
      ),

      db.query(
        `SELECT j.id, j.numero_jogo, j.fase, j.data_hora, j.status,
                esc1.nome AS equipe_1_nome, esc2.nome AS equipe_2_nome,
                l.nome AS local_nome,
                c.id AS competicao_id, m.nome AS modalidade_nome,
                m.slug AS modalidade_slug, cat.nome AS categoria_nome, c.genero
           FROM jogos j
           INNER JOIN equipes e1 ON e1.id = j.equipe_1_id
           INNER JOIN escolas esc1 ON esc1.id = e1.escola_id
           INNER JOIN equipes e2 ON e2.id = j.equipe_2_id
           INNER JOIN escolas esc2 ON esc2.id = e2.escola_id
           INNER JOIN competicoes c ON c.id = j.competicao_id
           INNER JOIN modalidades m ON m.id = c.modalidade_id
           INNER JOIN categorias cat ON cat.id = c.categoria_id
           LEFT JOIN locais_disputa l ON l.id = j.local_id
          WHERE j.status = 'AGENDADO' AND j.data_hora IS NOT NULL AND j.data_hora >= NOW()
          ORDER BY j.data_hora ASC
          LIMIT 1`
      ),

      // Campeão de cada competição: a final encerrada com vencedor definido.
      // Com 50 competições não existe "o campeão dos Jogos" — existe um por
      // competição, e o vencedor sai de vencedor_equipe_id, que já cobre
      // pênaltis e W.O.
      db.query(
        `SELECT j.competicao_id, j.numero_jogo, j.data_hora,
                m.nome AS modalidade_nome, m.slug AS modalidade_slug,
                cat.nome AS categoria_nome, c.genero,
                camp.nome AS campeao_nome, vice.nome AS vice_nome,
                GREATEST(j.placar_1, j.placar_2) AS placar_campeao,
                LEAST(j.placar_1, j.placar_2) AS placar_vice,
                j.status
           FROM jogos j
           INNER JOIN competicoes c ON c.id = j.competicao_id
           INNER JOIN modalidades m ON m.id = c.modalidade_id
           INNER JOIN categorias cat ON cat.id = c.categoria_id
           INNER JOIN equipes ec ON ec.id = j.vencedor_equipe_id
           INNER JOIN escolas camp ON camp.id = ec.escola_id
           INNER JOIN equipes ev
                   ON ev.id = CASE WHEN j.vencedor_equipe_id = j.equipe_1_id
                                   THEN j.equipe_2_id ELSE j.equipe_1_id END
           INNER JOIN escolas vice ON vice.id = ev.escola_id
          WHERE j.fase = 'FINAL'
            AND j.status IN ('FINALIZADO', 'WO')
            AND j.vencedor_equipe_id IS NOT NULL
          ORDER BY m.ordem, cat.ordem, c.genero`
      )
    ]);

    // O GROUP BY só devolve as situações que existem; o painel precisa dos
    // quatro contadores mesmo quando um deles é zero.
    const jogos = { AGENDADO: 0, EM_ANDAMENTO: 0, FINALIZADO: 0, WO: 0 };
    for (const linha of porSituacao) jogos[linha.status] = linha.total;
    jogos.total = Object.values(jogos).reduce((soma, n) => soma + n, 0);

    res.status(200).json({
      total_escolas: escolas.total,
      total_atletas: atletas.total,
      total_competicoes: competicoes.total,
      total_equipes: equipes.total,
      total_gols: gols.total,
      jogos,
      proximo_jogo: proximos[0] || null,
      campeoes
    });
  } catch (erro) {
    console.error('Erro ao buscar estatísticas do painel:', erro);
    res.status(500).json({ erro: 'Erro ao buscar as estatísticas do painel.' });
  }
};

module.exports = { obterEstatisticas };
