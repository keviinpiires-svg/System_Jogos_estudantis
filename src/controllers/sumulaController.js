const db = require('../config/db');

// ============================================================================
// SÚMULA: única fonte de verdade do placar.
// Os gols lançados por atleta somam o placar do jogo, que por sua vez alimenta
// a classificação e a artilharia. Nunca divergem, porque saem do mesmo lugar.
//
// O modelo em papel (docs/referencias/sumula_futsal_modelo.png) tem 14 linhas
// por equipe — o mesmo teto de elenco do regulamento.
// ============================================================================

const LINHAS_SUMULA = 14;
const MAX_AMARELOS = 2;

const inteiroNaoNegativo = (valor) => {
  const numero = Number(valor ?? 0);
  return Number.isInteger(numero) && numero >= 0 ? numero : null;
};

const booleano = (valor) => valor === true || valor === 1 || valor === '1' || valor === 'true';

const textoOuNulo = (valor) => {
  const texto = (valor || '').trim();
  return texto || null;
};

// Monta a súmula de um jogo: cabeçalho, as duas equipes e, em cada uma, o
// elenco inscrito já cruzado com o que foi lançado.
// Serve tanto para preencher quanto para imprimir. Antes de qualquer
// lançamento, devolve o elenco com zeros — que é a súmula EM BRANCO.
const buscarSumulaPorJogo = async (req, res) => {
  const jogo_id = Number(req.params.jogo_id);

  if (!Number.isInteger(jogo_id) || jogo_id <= 0) {
    return res.status(400).json({ erro: 'Identificador de jogo inválido.' });
  }

  try {
    const [[jogo]] = await db.query(
      `SELECT j.id, j.competicao_id, j.numero_jogo, j.fase, j.rodada, j.data_hora,
              j.status, j.placar_1, j.placar_2, j.penaltis_1, j.penaltis_2,
              j.arbitro_1, j.arbitro_2, j.anotador, j.observacoes,
              j.equipe_1_id, j.equipe_2_id, j.vencedor_equipe_id,
              g.nome AS grupo_nome, l.nome AS local_nome,
              m.nome AS modalidade_nome, m.slug AS modalidade_slug, m.tipo_placar,
              cat.nome AS categoria_nome, c.genero
         FROM jogos j
         INNER JOIN competicoes c ON c.id = j.competicao_id
         INNER JOIN modalidades m ON m.id = c.modalidade_id
         INNER JOIN categorias cat ON cat.id = c.categoria_id
         LEFT JOIN grupos g ON g.id = j.grupo_id
         LEFT JOIN locais_disputa l ON l.id = j.local_id
        WHERE j.id = ?`,
      [jogo_id]
    );

    if (!jogo) {
      return res.status(404).json({ erro: 'Jogo não encontrado.' });
    }

    const [[evento]] = await db.query(
      'SELECT nome_evento, ano, cidade, estado FROM configuracao_evento WHERE id = 1'
    );

    // LEFT JOIN: quem está inscrito aparece mesmo sem nada lançado ainda.
    // É o que permite imprimir a súmula em branco com o elenco já escrito.
    const [linhas] = await db.query(
      `SELECT i.equipe_id, i.atleta_id,
              COALESCE(s.numero_camisa, i.numero_camisa) AS numero_camisa,
              a.nome,
              COALESCE(s.presente, TRUE)        AS presente,
              COALESCE(s.capitao, FALSE)        AS capitao,
              COALESCE(s.gols, 0)               AS gols,
              COALESCE(s.amarelos, 0)           AS amarelos,
              COALESCE(s.vermelho, FALSE)       AS vermelho,
              COALESCE(s.desqualificado, FALSE) AS desqualificado
         FROM inscricoes_atletas i
         INNER JOIN atletas a ON a.id = i.atleta_id
         LEFT JOIN sumula_atletas s ON s.atleta_id = i.atleta_id AND s.jogo_id = ?
        WHERE i.equipe_id IN (?, ?)
        ORDER BY COALESCE(s.numero_camisa, i.numero_camisa) IS NULL,
                 COALESCE(s.numero_camisa, i.numero_camisa), a.nome`,
      [jogo_id, jogo.equipe_1_id, jogo.equipe_2_id]
    );

    const [rodapes] = await db.query(
      `SELECT se.equipe_id, se.tecnico_nome,
              se.faltas_1t, se.faltas_2t, se.tempo_tecnico_1t, se.tempo_tecnico_2t
         FROM sumula_equipes se
        WHERE se.jogo_id = ?`,
      [jogo_id]
    );

    const [equipes] = await db.query(
      `SELECT e.id, e.tecnico_nome, esc.nome AS escola_nome
         FROM equipes e
         INNER JOIN escolas esc ON esc.id = e.escola_id
        WHERE e.id IN (?, ?)`,
      [jogo.equipe_1_id, jogo.equipe_2_id]
    );

    // A ordem importa: equipe 1 é a de cima na folha, equipe 2 a de baixo.
    const montarEquipe = (equipe_id) => {
      const equipe = equipes.find((e) => e.id === equipe_id);
      const rodape = rodapes.find((r) => r.equipe_id === equipe_id);
      const atletas = linhas.filter((l) => l.equipe_id === equipe_id);

      return {
        equipe_id,
        escola_nome: equipe ? equipe.escola_nome : '',
        // O técnico da súmula vence o da equipe: pode mudar de um jogo a outro
        tecnico_nome: rodape?.tecnico_nome ?? equipe?.tecnico_nome ?? null,
        faltas_1t: rodape?.faltas_1t ?? 0,
        faltas_2t: rodape?.faltas_2t ?? 0,
        tempo_tecnico_1t: Boolean(rodape?.tempo_tecnico_1t),
        tempo_tecnico_2t: Boolean(rodape?.tempo_tecnico_2t),
        gols: atletas.reduce((total, atleta) => total + Number(atleta.gols), 0),
        atletas: atletas.map((atleta) => ({
          atleta_id: atleta.atleta_id,
          nome: atleta.nome,
          numero_camisa: atleta.numero_camisa,
          presente: Boolean(atleta.presente),
          capitao: Boolean(atleta.capitao),
          gols: Number(atleta.gols),
          amarelos: Number(atleta.amarelos),
          vermelho: Boolean(atleta.vermelho),
          desqualificado: Boolean(atleta.desqualificado)
        }))
      };
    };

    res.status(200).json({
      evento,
      jogo,
      linhas_sumula: LINHAS_SUMULA,
      equipes: [montarEquipe(jogo.equipe_1_id), montarEquipe(jogo.equipe_2_id)],
      lancada: linhas.some((l) => Number(l.gols) > 0 || Number(l.amarelos) > 0 || l.vermelho)
    });
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao buscar a súmula do jogo.' });
  }
};

// Grava a súmula inteira de uma vez. O corpo traz as duas equipes, cada uma
// com o seu rodapé e as suas linhas de atleta. O placar do jogo é a SOMA dos
// gols lançados — nunca é digitado.
const registrarSumula = async (req, res) => {
  const jogo_id = Number(req.body.jogo_id);
  const equipesEnviadas = Array.isArray(req.body.equipes) ? req.body.equipes : [];
  const finalizar = booleano(req.body.finalizar);

  if (!Number.isInteger(jogo_id) || jogo_id <= 0) {
    return res.status(400).json({ erro: 'Informe o jogo da súmula.' });
  }

  if (equipesEnviadas.length !== 2) {
    return res.status(400).json({ erro: 'A súmula precisa das duas equipes do jogo.' });
  }

  let conexao;
  try {
    conexao = await db.getConnection();
    await conexao.beginTransaction();

    const [[jogo]] = await conexao.query(
      `SELECT j.id, j.fase, j.status, j.equipe_1_id, j.equipe_2_id
         FROM jogos j WHERE j.id = ? FOR UPDATE`,
      [jogo_id]
    );

    if (!jogo) {
      await conexao.rollback();
      return res.status(404).json({ erro: 'Jogo não encontrado.' });
    }

    if (jogo.status === 'WO') {
      await conexao.rollback();
      return res.status(409).json({
        erro: 'Este jogo foi decidido por W.O. e não tem súmula.'
      });
    }

    // Decisão da fatia 1: partida encerrada só o administrador reabre.
    if (jogo.status === 'FINALIZADO' && req.usuario.perfil !== 'ADMIN') {
      await conexao.rollback();
      return res.status(403).json({
        erro: 'Esta súmula já foi finalizada. Peça a um administrador para reabri-la.'
      });
    }

    const idsDoJogo = [jogo.equipe_1_id, jogo.equipe_2_id];
    const idsEnviados = equipesEnviadas.map((e) => Number(e.equipe_id));

    if (!idsDoJogo.every((id) => idsEnviados.includes(id))) {
      await conexao.rollback();
      return res.status(400).json({ erro: 'As equipes enviadas não são as deste jogo.' });
    }

    // Quem pode entrar na súmula é quem está inscrito na equipe
    const [inscritos] = await conexao.query(
      'SELECT equipe_id, atleta_id FROM inscricoes_atletas WHERE equipe_id IN (?, ?)',
      idsDoJogo
    );
    const inscricaoValida = new Set(inscritos.map((i) => `${i.equipe_id}:${i.atleta_id}`));

    const golsPorEquipe = new Map();

    for (const equipe of equipesEnviadas) {
      const equipe_id = Number(equipe.equipe_id);
      const atletas = Array.isArray(equipe.atletas) ? equipe.atletas : [];

      if (atletas.length > LINHAS_SUMULA) {
        await conexao.rollback();
        return res.status(400).json({
          erro: `A súmula tem ${LINHAS_SUMULA} linhas por equipe.`
        });
      }

      let golsDaEquipe = 0;
      const capitaes = atletas.filter((a) => booleano(a.capitao)).length;

      if (capitaes > 1) {
        await conexao.rollback();
        return res.status(400).json({ erro: 'Cada equipe tem um capitão só.' });
      }

      for (const atleta of atletas) {
        const atleta_id = Number(atleta.atleta_id);
        const gols = inteiroNaoNegativo(atleta.gols);
        const amarelos = inteiroNaoNegativo(atleta.amarelos);

        if (!Number.isInteger(atleta_id) || atleta_id <= 0) {
          await conexao.rollback();
          return res.status(400).json({ erro: 'Há linha de súmula sem atleta.' });
        }

        if (gols === null || amarelos === null) {
          await conexao.rollback();
          return res.status(400).json({ erro: 'Gols e cartões precisam ser inteiros não negativos.' });
        }

        if (amarelos > MAX_AMARELOS) {
          await conexao.rollback();
          return res.status(400).json({
            erro: `A súmula tem duas caixas de amarelo: o máximo é ${MAX_AMARELOS}.`
          });
        }

        if (!inscricaoValida.has(`${equipe_id}:${atleta_id}`)) {
          await conexao.rollback();
          return res.status(400).json({
            erro: 'Há atleta que não está inscrito na equipe desta súmula.'
          });
        }

        golsDaEquipe += gols;
      }

      golsPorEquipe.set(equipe_id, golsDaEquipe);
    }

    // Regravar inteiro é mais simples e mais seguro que casar linha a linha:
    // o que vale é sempre o último lançamento da mesa.
    await conexao.query('DELETE FROM sumula_atletas WHERE jogo_id = ?', [jogo_id]);
    await conexao.query('DELETE FROM sumula_equipes WHERE jogo_id = ?', [jogo_id]);

    for (const equipe of equipesEnviadas) {
      const equipe_id = Number(equipe.equipe_id);

      await conexao.query(
        `INSERT INTO sumula_equipes
           (jogo_id, equipe_id, tecnico_nome, faltas_1t, faltas_2t, tempo_tecnico_1t, tempo_tecnico_2t)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [
          jogo_id, equipe_id, textoOuNulo(equipe.tecnico_nome),
          inteiroNaoNegativo(equipe.faltas_1t) ?? 0,
          inteiroNaoNegativo(equipe.faltas_2t) ?? 0,
          booleano(equipe.tempo_tecnico_1t), booleano(equipe.tempo_tecnico_2t)
        ]
      );

      for (const atleta of equipe.atletas || []) {
        await conexao.query(
          `INSERT INTO sumula_atletas
             (jogo_id, equipe_id, atleta_id, numero_camisa, presente, capitao,
              gols, amarelos, vermelho, desqualificado)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [
            jogo_id, equipe_id, Number(atleta.atleta_id),
            atleta.numero_camisa ? Number(atleta.numero_camisa) : null,
            booleano(atleta.presente), booleano(atleta.capitao),
            inteiroNaoNegativo(atleta.gols) ?? 0,
            inteiroNaoNegativo(atleta.amarelos) ?? 0,
            booleano(atleta.vermelho), booleano(atleta.desqualificado)
          ]
        );
      }
    }

    const placar_1 = golsPorEquipe.get(jogo.equipe_1_id) ?? 0;
    const placar_2 = golsPorEquipe.get(jogo.equipe_2_id) ?? 0;

    let status = jogo.status === 'AGENDADO' ? 'EM_ANDAMENTO' : jogo.status;
    let vencedor_equipe_id = null;
    let penaltis_1 = null;
    let penaltis_2 = null;

    if (finalizar) {
      if (placar_1 !== placar_2) {
        vencedor_equipe_id = placar_1 > placar_2 ? jogo.equipe_1_id : jogo.equipe_2_id;
      } else if (jogo.fase !== 'GRUPOS') {
        // Empate na fase de grupos é resultado; no mata-mata, não decide nada.
        penaltis_1 = inteiroNaoNegativo(req.body.penaltis_1);
        penaltis_2 = inteiroNaoNegativo(req.body.penaltis_2);

        if (penaltis_1 === null || penaltis_2 === null || penaltis_1 === penaltis_2) {
          await conexao.rollback();
          return res.status(400).json({
            erro: 'Empate no mata-mata: informe os pênaltis, com um vencedor.'
          });
        }

        vencedor_equipe_id = penaltis_1 > penaltis_2 ? jogo.equipe_1_id : jogo.equipe_2_id;
      }

      status = 'FINALIZADO';
    }

    await conexao.query(
      `UPDATE jogos
          SET placar_1 = ?, placar_2 = ?, status = ?,
              vencedor_equipe_id = ?, penaltis_1 = ?, penaltis_2 = ?
        WHERE id = ?`,
      [placar_1, placar_2, status, vencedor_equipe_id, penaltis_1, penaltis_2, jogo_id]
    );

    await conexao.commit();

    res.status(201).json({
      mensagem: finalizar ? 'Súmula finalizada!' : 'Súmula salva.',
      jogo_id,
      placar_1,
      placar_2,
      status,
      vencedor_equipe_id
    });
  } catch (erro) {
    if (conexao) await conexao.rollback();
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao registrar a súmula.' });
  } finally {
    if (conexao) conexao.release();
  }
};

module.exports = {
  buscarSumulaPorJogo,
  registrarSumula
};
