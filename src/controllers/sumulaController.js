const db = require('../config/db');
const { desempateDaModalidade } = require('../config/regrasProvisorias');
const { folhaDaModalidade } = require('../config/folhasSumula');

// ============================================================================
// SÚMULA: única fonte de verdade do placar.
// Os gols lançados por atleta somam o placar do jogo, que por sua vez alimenta
// a classificação e a artilharia. Nunca divergem, porque saem do mesmo lugar.
//
// Cada modalidade tem o seu papel (14 linhas por equipe, cartões ou faltas,
// teto de faltas acumuladas). Esse desenho está em src/config/folhasSumula.js
// — aqui só o consultamos, para validar e para mandar à tela.
// ============================================================================

const inteiroNaoNegativo = (valor) => {
  const numero = Number(valor ?? 0);
  return Number.isInteger(numero) && numero >= 0 ? numero : null;
};

const booleano = (valor) => valor === true || valor === 1 || valor === '1' || valor === 'true';

const textoOuNulo = (valor) => {
  const texto = (valor || '').trim();
  return texto || null;
};

// ---------------------------------------------------------------------------
// Vôlei: o placar do jogo são os SETS, guardados em jogo_sets.
// ---------------------------------------------------------------------------

// Devolve sempre os espaços do papel (3 sets), zerados enquanto não lançados.
const lerSets = async (conexao, jogo_id, folha) => {
  const [linhas] = await conexao.query(
    'SELECT numero_set, pontos_1, pontos_2 FROM jogo_sets WHERE jogo_id = ? ORDER BY numero_set',
    [jogo_id]
  );

  return Array.from({ length: folha.maxSets }, (_, i) => {
    const gravado = linhas.find((l) => Number(l.numero_set) === i + 1);
    return {
      numero_set: i + 1,
      pontos_1: gravado ? Number(gravado.pontos_1) : 0,
      pontos_2: gravado ? Number(gravado.pontos_2) : 0
    };
  });
};

// Um set está fechado quando alguém chega aos 21 com 2 pontos de vantagem
// (regulamento: melhor de 3, set de 21). Abaixo disso o set está em andamento,
// que é o que a mesa salva enquanto o jogo corre.
const setFechado = (set, folha) => {
  const maior = Math.max(set.pontos_1, set.pontos_2);
  const menor = Math.min(set.pontos_1, set.pontos_2);
  return maior >= folha.pontosPorSet && maior - menor >= 2;
};

const setVazio = (set) => set.pontos_1 === 0 && set.pontos_2 === 0;

const ORDINAL_SET = ['1º', '2º', '3º', '4º', '5º'];

// Lê os sets enviados, valida o que o papel permite e diz quantos cada equipe
// venceu. Devolve { erro } em vez de lançar, para o controller responder 400.
const apurarSets = (enviados, folha, finalizar) => {
  const sets = [];

  for (let i = 0; i < folha.maxSets; i += 1) {
    const enviado = (Array.isArray(enviados) ? enviados : [])
      .find((s) => Number(s.numero_set) === i + 1) || {};
    const pontos_1 = inteiroNaoNegativo(enviado.pontos_1);
    const pontos_2 = inteiroNaoNegativo(enviado.pontos_2);

    if (pontos_1 === null || pontos_2 === null) {
      return { erro: `Os pontos do ${ORDINAL_SET[i]} set precisam ser inteiros não negativos.` };
    }

    sets.push({ numero_set: i + 1, pontos_1, pontos_2 });
  }

  // Ninguém pode começar o 2º set sem fechar o 1º
  const ultimoLancado = sets.reduce((ultimo, set, i) => (setVazio(set) ? ultimo : i), -1);

  for (let i = 0; i < ultimoLancado; i += 1) {
    if (setVazio(sets[i])) {
      return { erro: `O ${ORDINAL_SET[ultimoLancado]} set está lançado, mas o ${ORDINAL_SET[i]} está vazio.` };
    }
    if (!setFechado(sets[i], folha)) {
      return {
        erro: `O ${ORDINAL_SET[i]} set está ${sets[i].pontos_1} x ${sets[i].pontos_2}: `
          + `um set termina em ${folha.pontosPorSet} pontos, com 2 de vantagem.`
      };
    }
  }

  const vencidos = sets.reduce((conta, set) => {
    if (!setFechado(set, folha)) return conta;
    if (set.pontos_1 > set.pontos_2) conta.um += 1;
    else conta.dois += 1;
    return conta;
  }, { um: 0, dois: 0 });

  if (!finalizar) return { sets, vencidos };

  // Ao finalizar, o último set também precisa estar fechado
  if (ultimoLancado >= 0 && !setFechado(sets[ultimoLancado], folha)) {
    return {
      erro: `O ${ORDINAL_SET[ultimoLancado]} set está ${sets[ultimoLancado].pontos_1} x `
        + `${sets[ultimoLancado].pontos_2}: um set termina em ${folha.pontosPorSet} pontos, com 2 de vantagem.`
    };
  }

  if (Math.max(vencidos.um, vencidos.dois) < folha.setsParaVencer) {
    return {
      erro: `O jogo termina quando uma equipe vence ${folha.setsParaVencer} sets. `
        + `Está ${vencidos.um} x ${vencidos.dois}.`
    };
  }

  // Decidido em dois sets não se joga o terceiro
  const decidiuEm = sets.findIndex((_, i) => {
    const ate = sets.slice(0, i + 1).reduce((conta, set) => {
      if (!setFechado(set, folha)) return conta;
      if (set.pontos_1 > set.pontos_2) conta.um += 1;
      else conta.dois += 1;
      return conta;
    }, { um: 0, dois: 0 });
    return Math.max(ate.um, ate.dois) >= folha.setsParaVencer;
  });

  if (decidiuEm >= 0 && ultimoLancado > decidiuEm) {
    return {
      erro: `O jogo foi decidido no ${ORDINAL_SET[decidiuEm]} set: o ${ORDINAL_SET[ultimoLancado]} não se joga.`
    };
  }

  return { sets, vencidos };
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
              COALESCE(s.faltas, 0)             AS faltas,
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
          faltas: Number(atleta.faltas),
          vermelho: Boolean(atleta.vermelho),
          desqualificado: Boolean(atleta.desqualificado)
        }))
      };
    };

    const folha = folhaDaModalidade(jogo.modalidade_slug, jogo.modalidade_nome);

    // Vôlei: o placar são os sets. A folha traz sempre os três espaços do
    // papel, mesmo antes de qualquer lançamento.
    const sets = folha.sets ? await lerSets(db, jogo_id, folha) : null;

    res.status(200).json({
      evento,
      jogo,
      // A regra de desempate e o desenho da folha viajam junto para a tela não
      // precisar de cópia deles: a fonte continua sendo src/config/
      desempate: desempateDaModalidade(jogo.modalidade_slug),
      folha,
      sets,
      linhas_sumula: folha.linhas,
      equipes: [montarEquipe(jogo.equipe_1_id), montarEquipe(jogo.equipe_2_id)],
      lancada: linhas.some((l) => Number(l.gols) > 0 || Number(l.amarelos) > 0
        || Number(l.faltas) > 0 || l.vermelho)
    });
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao buscar a súmula do jogo.' });
  }
};

// Grava a súmula inteira de uma vez. O corpo traz as duas equipes, cada uma
// com o seu rodapé e as suas linhas de atleta. O placar do jogo é a SOMA dos
// gols lançados — nunca é digitado.
// Ida e volta de duas equipes (formato E, sem mata-mata): o campeão é quem
// soma mais nos dois jogos e, empatada a soma, decide nas cobranças lançadas
// na súmula do segundo jogo — decisão provisória de 30/09/2026, registrada em
// src/config/chavesMataMata.js (somaDosDoisJogos).
//
// Devolve true só quando ESTE é o último jogo a finalizar e a soma dos dois
// empata: é quando as cobranças passam a ser obrigatórias. Enquanto houver
// outro jogo em aberto, o empate é resultado, como em qualquer fase de grupos.
const somaDosDoisJogosEmpatada = async (conexao, jogo, placar_1, placar_2) => {
  if (jogo.turno !== 'IDA_E_VOLTA' || jogo.proxima_fase !== 'NENHUMA') return false;
  if (jogo.fase !== 'GRUPOS') return false;

  const [outros] = await conexao.query(
    `SELECT id, status, equipe_1_id, equipe_2_id, placar_1, placar_2
       FROM jogos
      WHERE competicao_id = ? AND id <> ?`,
    [jogo.competicao_id, jogo.id]
  );

  // Ainda há jogo por disputar: dá para desempatar em quadra
  if (outros.some((outro) => !['FINALIZADO', 'WO'].includes(outro.status))) return false;

  let soma_1 = placar_1;
  let soma_2 = placar_2;

  for (const outro of outros) {
    // As equipes trocam de lado no jogo de volta
    const mesmaOrdem = outro.equipe_1_id === jogo.equipe_1_id;
    soma_1 += (mesmaOrdem ? outro.placar_1 : outro.placar_2) ?? 0;
    soma_2 += (mesmaOrdem ? outro.placar_2 : outro.placar_1) ?? 0;
  }

  return soma_1 === soma_2;
};

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
      `SELECT j.id, j.competicao_id, j.fase, j.status, j.equipe_1_id, j.equipe_2_id,
              c.turno, c.proxima_fase,
              m.slug AS modalidade_slug, m.nome AS modalidade_nome
         FROM jogos j
         INNER JOIN competicoes c ON c.id = j.competicao_id
         INNER JOIN modalidades m ON m.id = c.modalidade_id
        WHERE j.id = ? FOR UPDATE`,
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

    // O papel da modalidade manda nas validações: quantas linhas, se tem
    // cartão, quantas faltas cabem. Está em src/config/folhasSumula.js.
    const folha = folhaDaModalidade(jogo.modalidade_slug, jogo.modalidade_nome);
    const golsPorEquipe = new Map();

    // Vôlei: o placar são os sets, e eles são validados antes de qualquer
    // escrita — set em andamento passa no parcial, mas não ao finalizar.
    const apuracao = folha.sets ? apurarSets(req.body.sets, folha, finalizar) : null;

    if (apuracao?.erro) {
      await conexao.rollback();
      return res.status(400).json({ erro: apuracao.erro });
    }

    for (const equipe of equipesEnviadas) {
      const equipe_id = Number(equipe.equipe_id);
      const atletas = Array.isArray(equipe.atletas) ? equipe.atletas : [];

      // O teto é o do elenco (14): no handebol e no baleado o papel tem 12
      // linhas, e a folha preenchida ganha as que faltarem
      if (atletas.length > folha.linhasMaximas) {
        await conexao.rollback();
        return res.status(400).json({
          erro: `A súmula tem no máximo ${folha.linhasMaximas} linhas por equipe.`
        });
      }

      // Tempo técnico só onde o papel tem a caixa (o baleado e o vôlei não têm)
      if (!folha.tempoTecnico && (booleano(equipe.tempo_tecnico_1t) || booleano(equipe.tempo_tecnico_2t))) {
        await conexao.rollback();
        return res.status(400).json({
          erro: `A folha de ${jogo.modalidade_nome} não tem tempo técnico.`
        });
      }

      // Faltas acumuladas da equipe: 5 por tempo no futsal e no handebol,
      // 7 no basquete. Quem não tem o campo na folha não pode lançar.
      for (const [campo, rotulo] of [['faltas_1t', '1º tempo'], ['faltas_2t', '2º tempo']]) {
        const faltas = inteiroNaoNegativo(equipe[campo]) ?? 0;

        if (faltas > folha.faltasAcumuladas) {
          await conexao.rollback();
          return res.status(400).json({
            erro: folha.faltasAcumuladas === 0
              ? `A folha de ${jogo.modalidade_nome} não tem faltas acumuladas.`
              : `As faltas acumuladas do ${rotulo} vão até ${folha.faltasAcumuladas} em ${jogo.modalidade_nome}.`
          });
        }
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
        const faltas = inteiroNaoNegativo(atleta.faltas);

        if (!Number.isInteger(atleta_id) || atleta_id <= 0) {
          await conexao.rollback();
          return res.status(400).json({ erro: 'Há linha de súmula sem atleta.' });
        }

        if (gols === null || amarelos === null || faltas === null) {
          await conexao.rollback();
          return res.status(400).json({
            erro: `${folha.rotuloEstatistica || 'Os lançamentos'}, cartões e faltas precisam ser inteiros não negativos.`
          });
        }

        // O basquete não tem cartão no papel; o futsal não tem falta individual.
        if (!folha.cartoes && (amarelos > 0 || booleano(atleta.vermelho))) {
          await conexao.rollback();
          return res.status(400).json({
            erro: `A folha de ${jogo.modalidade_nome} não tem cartões.`
          });
        }

        if (amarelos > folha.maxAmarelos) {
          await conexao.rollback();
          return res.status(400).json({
            erro: folha.maxAmarelos === 1
              ? `A súmula de ${jogo.modalidade_nome} tem uma caixa de amarelo: o máximo é 1.`
              : `A súmula tem ${folha.maxAmarelos} caixas de amarelo: o máximo é ${folha.maxAmarelos}.`
          });
        }

        if (folha.sets && gols > 0) {
          await conexao.rollback();
          return res.status(400).json({
            erro: `Em ${jogo.modalidade_nome} o placar são os sets: não se lança ponto por atleta.`
          });
        }

        if (faltas > folha.faltasIndividuais) {
          await conexao.rollback();
          return res.status(400).json({
            erro: folha.faltasIndividuais === 0
              ? `A folha de ${jogo.modalidade_nome} não tem faltas por atleta.`
              : `As faltas individuais vão de 0 a ${folha.faltasIndividuais}: com ${folha.faltasIndividuais} o atleta está excluído.`
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

    if (apuracao) {
      await conexao.query('DELETE FROM jogo_sets WHERE jogo_id = ?', [jogo_id]);

      // Só os sets jogados vão para a tabela: o papel tem três espaços, o
      // jogo pode ter acabado em dois.
      for (const set of apuracao.sets.filter((s) => !setVazio(s))) {
        await conexao.query(
          'INSERT INTO jogo_sets (jogo_id, numero_set, pontos_1, pontos_2) VALUES (?, ?, ?, ?)',
          [jogo_id, set.numero_set, set.pontos_1, set.pontos_2]
        );
      }
    }

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
              gols, amarelos, faltas, vermelho, desqualificado)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [
            jogo_id, equipe_id, Number(atleta.atleta_id),
            atleta.numero_camisa ? Number(atleta.numero_camisa) : null,
            booleano(atleta.presente), booleano(atleta.capitao),
            inteiroNaoNegativo(atleta.gols) ?? 0,
            inteiroNaoNegativo(atleta.amarelos) ?? 0,
            inteiroNaoNegativo(atleta.faltas) ?? 0,
            booleano(atleta.vermelho), booleano(atleta.desqualificado)
          ]
        );
      }
    }

    // No vôlei o placar do jogo são os sets vencidos; nas outras modalidades,
    // a soma da coluna do atleta (gols, pontos ou eliminações).
    const placar_1 = apuracao ? apuracao.vencidos.um : (golsPorEquipe.get(jogo.equipe_1_id) ?? 0);
    const placar_2 = apuracao ? apuracao.vencidos.dois : (golsPorEquipe.get(jogo.equipe_2_id) ?? 0);

    const prorrogacao = booleano(req.body.prorrogacao);
    let status = jogo.status === 'AGENDADO' ? 'EM_ANDAMENTO' : jogo.status;
    let vencedor_equipe_id = null;
    let penaltis_1 = null;
    let penaltis_2 = null;

    if (finalizar) {
      // Ida e volta sem mata-mata: o título sai da soma dos dois jogos, então
      // o empate no último jogo só decide alguma coisa se a soma também
      // empatar — e aí este jogo precisa das cobranças.
      const somaEmpatada = await somaDosDoisJogosEmpatada(conexao, jogo, placar_1, placar_2);

      // Empate que precisa de dono: no mata-mata, o do próprio jogo; no ida e
      // volta, o da soma dos dois — e aí o placar do jogo não resolve, porque
      // vencer por 2 depois de perder por 2 deixa o confronto empatado.
      const precisaDeDono = somaEmpatada || (placar_1 === placar_2 && jogo.fase !== 'GRUPOS');

      if (precisaDeDono) {
        // Empate na fase de grupos é resultado; no mata-mata, não decide nada.
        // Cada modalidade tem a sua sequência de desempate, e ela mora em
        // src/config/regrasProvisorias.js — não aqui.
        const desempate = desempateDaModalidade(jogo.modalidade_slug);
        const exigeProrrogacao = desempate.sequencia.includes('PRORROGACAO');

        // Em handebol e basquete a prorrogação vem antes das cobranças: só
        // depois de marcada é que faz sentido pedir o placar da cobrança.
        const situacao = somaEmpatada
          ? 'Os dois jogos terminaram com a soma empatada'
          : 'Empate no mata-mata';

        // Modalidade em que o regulamento não diz como desempatar: não há
        // cobrança genérica. A súmula pode ser salva sem finalizar, e o jogo
        // espera a organização decidir.
        if (desempate.pendente) {
          await conexao.rollback();
          return res.status(409).json({
            erro: `${situacao} em ${jogo.modalidade_nome}: ${desempate.motivo}. `
              + 'A regra está pendente com a organização, então o jogo não pode ser finalizado '
              + 'empatado. Salve a súmula sem finalizar e aguarde a decisão.'
          });
        }

        if (exigeProrrogacao && !prorrogacao) {
          await conexao.rollback();
          return res.status(400).json({
            erro: `${situacao}: em ${jogo.modalidade_nome} joga-se prorrogação antes das cobranças. `
              + 'Marque a prorrogação e lance o resultado dela na súmula.'
          });
        }

        penaltis_1 = inteiroNaoNegativo(req.body.penaltis_1);
        penaltis_2 = inteiroNaoNegativo(req.body.penaltis_2);

        if (penaltis_1 === null || penaltis_2 === null || penaltis_1 === penaltis_2) {
          await conexao.rollback();
          return res.status(400).json({
            erro: exigeProrrogacao
              ? `Empate mesmo após a prorrogação: informe ${desempate.nomeCobranca}, com um vencedor.`
              : `${situacao}: informe ${desempate.nomeCobranca}, com um vencedor.`
          });
        }

        vencedor_equipe_id = penaltis_1 > penaltis_2 ? jogo.equipe_1_id : jogo.equipe_2_id;
      } else if (placar_1 !== placar_2) {
        vencedor_equipe_id = placar_1 > placar_2 ? jogo.equipe_1_id : jogo.equipe_2_id;
      }

      status = 'FINALIZADO';
    }

    await conexao.query(
      `UPDATE jogos
          SET placar_1 = ?, placar_2 = ?, status = ?,
              vencedor_equipe_id = ?, penaltis_1 = ?, penaltis_2 = ?, prorrogacao = ?
        WHERE id = ?`,
      [placar_1, placar_2, status, vencedor_equipe_id, penaltis_1, penaltis_2, prorrogacao, jogo_id]
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
