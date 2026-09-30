const db = require('../config/db');

// ============================================================================
// ARTILHARIA — somada de sumula_atletas, a mesma fonte do placar.
//
// Artilharia é POR COMPETIÇÃO: "o artilheiro do Futsal Sub 11 Masculino" é uma
// pergunta com resposta; "o artilheiro dos Jogos" somaria gols de futsal com
// pontos de basquete.
//
// Gols de W.O. não entram: um W.O. não tem súmula, e o placar dele vive só em
// jogos.placar_1/placar_2. É o combinado com o usuário (fatia 5c).
// ============================================================================

// Em basquete a coluna gols guarda pontos; o tipo_placar diz como rotular.
const ROTULO_PLACAR = {
  GOLS: 'gols',
  PONTOS: 'pontos',
  SETS: 'pontos',
  ELIMINADOS: 'eliminados',
  MARCA: 'marca'
};

const listarPorCompeticao = async (req, res) => {
  const competicao_id = Number(req.params.competicao_id);

  if (!Number.isInteger(competicao_id) || competicao_id <= 0) {
    return res.status(400).json({ erro: 'Identificador de competição inválido.' });
  }

  try {
    const [[competicao]] = await db.query(
      `SELECT c.id, c.genero,
              m.nome AS modalidade_nome, m.slug AS modalidade_slug, m.tipo_placar,
              cat.nome AS categoria_nome
         FROM competicoes c
         INNER JOIN modalidades m ON m.id = c.modalidade_id
         INNER JOIN categorias cat ON cat.id = c.categoria_id
        WHERE c.id = ?`,
      [competicao_id]
    );

    if (!competicao) {
      return res.status(404).json({ erro: 'Competição não encontrada.' });
    }

    // COUNT(DISTINCT) porque um atleta tem uma linha por jogo: sem isso, um
    // atleta que jogou 3 partidas contaria 3 vezes no total de jogos.
    const [artilheiros] = await db.query(
      `SELECT a.id AS atleta_id, a.nome AS atleta_nome,
              esc.id AS escola_id, esc.nome AS escola_nome,
              CAST(SUM(s.gols) AS UNSIGNED) AS gols,
              COUNT(DISTINCT s.jogo_id) AS jogos,
              CAST(SUM(s.amarelos) AS UNSIGNED) AS amarelos,
              CAST(SUM(s.vermelho) AS UNSIGNED) AS vermelhos
         FROM sumula_atletas s
         INNER JOIN jogos j ON j.id = s.jogo_id
         INNER JOIN atletas a ON a.id = s.atleta_id
         INNER JOIN equipes e ON e.id = s.equipe_id
         INNER JOIN escolas esc ON esc.id = e.escola_id
        WHERE j.competicao_id = ?
        GROUP BY a.id, a.nome, esc.id, esc.nome
       HAVING gols > 0
        ORDER BY gols DESC, jogos ASC, a.nome ASC`,
      [competicao_id]
    );

    res.status(200).json({
      competicao,
      rotulo: ROTULO_PLACAR[competicao.tipo_placar] || 'gols',
      artilheiros
    });
  } catch (erro) {
    console.error('Erro ao buscar artilharia:', erro);
    res.status(500).json({ erro: 'Erro ao buscar a artilharia.' });
  }
};

// Artilheiro de cada competição, para o painel geral. Uma linha por
// competição que já teve gol lançado.
const listarLideres = async (req, res) => {
  try {
    // Uma passada agrupa por competição e atleta; a segunda pega o maior total
    // de cada competição. Empate no topo mostra os dois — é informação, não
    // ranking. CTE funciona no MariaDB 10.4 (dev) e no MySQL 8 (produção).
    const [lideres] = await db.query(
      `WITH somas AS (
          SELECT j.competicao_id,
                 a.id AS atleta_id, a.nome AS atleta_nome,
                 esc.nome AS escola_nome,
                 CAST(SUM(s.gols) AS UNSIGNED) AS gols
            FROM sumula_atletas s
            INNER JOIN jogos j ON j.id = s.jogo_id
            INNER JOIN atletas a ON a.id = s.atleta_id
            INNER JOIN equipes e ON e.id = s.equipe_id
            INNER JOIN escolas esc ON esc.id = e.escola_id
           GROUP BY j.competicao_id, a.id, a.nome, esc.nome
          HAVING gols > 0
       )
       SELECT som.competicao_id,
              m.nome AS modalidade_nome, m.slug AS modalidade_slug, m.tipo_placar,
              cat.nome AS categoria_nome, c.genero,
              som.atleta_id, som.atleta_nome, som.escola_nome, som.gols
         FROM somas som
         INNER JOIN (
           SELECT competicao_id, MAX(gols) AS melhor
             FROM somas
            GROUP BY competicao_id
         ) topo ON topo.competicao_id = som.competicao_id AND topo.melhor = som.gols
         INNER JOIN competicoes c ON c.id = som.competicao_id
         INNER JOIN modalidades m ON m.id = c.modalidade_id
         INNER JOIN categorias cat ON cat.id = c.categoria_id
        ORDER BY m.ordem, cat.ordem, c.genero, som.atleta_nome`
    );

    res.status(200).json(lideres.map((l) => ({
      ...l,
      rotulo: ROTULO_PLACAR[l.tipo_placar] || 'gols'
    })));
  } catch (erro) {
    console.error('Erro ao buscar os artilheiros:', erro);
    res.status(500).json({ erro: 'Erro ao buscar os artilheiros.' });
  }
};

module.exports = { listarPorCompeticao, listarLideres };
