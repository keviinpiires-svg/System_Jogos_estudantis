const db = require('../config/db');
const { REGRAS } = require('../config/regrasProvisorias');

// A classificação é sempre calculada a partir dos jogos, nunca guardada:
// corrigir uma súmula corrige a tabela no mesmo instante.
//
// Critérios de desempate por modalidade (regulamento, seção 5 do contexto).
// Cada critério devolve um número por equipe em que MAIOR É MELHOR, e vale
// só dentro do bloco de equipes ainda empatadas — é assim que "confronto
// direto" e "saldo entre as empatadas" funcionam.

// Pontos do jogo para cada lado, conforme a pontuação da competição
const resultado = (jogo, competicao) => {
  const p1 = jogo.placar_1 ?? 0;
  const p2 = jogo.placar_2 ?? 0;

  // No W.O. quem vence está em vencedor_equipe_id, mesmo com placar 0 a 0
  if (jogo.status === 'WO' && jogo.vencedor_equipe_id) {
    return jogo.vencedor_equipe_id === jogo.equipe_1_id
      ? [competicao.pontos_vitoria, competicao.pontos_derrota]
      : [competicao.pontos_derrota, competicao.pontos_vitoria];
  }

  if (p1 > p2) return [competicao.pontos_vitoria, competicao.pontos_derrota];
  if (p1 < p2) return [competicao.pontos_derrota, competicao.pontos_vitoria];
  return [competicao.pontos_empate, competicao.pontos_empate];
};

// Pontos que cada equipe do bloco fez jogando contra as outras do bloco
const pontosEntre = (bloco, ctx) => {
  const ids = new Set(bloco.map((e) => e.equipe_id));
  const pontos = new Map(bloco.map((e) => [e.equipe_id, 0]));

  for (const jogo of ctx.jogos) {
    if (!ids.has(jogo.equipe_1_id) || !ids.has(jogo.equipe_2_id)) continue;

    const [p1, p2] = resultado(jogo, ctx.competicao);
    pontos.set(jogo.equipe_1_id, pontos.get(jogo.equipe_1_id) + p1);
    pontos.set(jogo.equipe_2_id, pontos.get(jogo.equipe_2_id) + p2);
  }

  return pontos;
};

// Saldo (gols, pontos ou sets) só nos jogos entre as equipes do bloco
const saldoEntre = (bloco, ctx) => {
  const ids = new Set(bloco.map((e) => e.equipe_id));
  const saldo = new Map(bloco.map((e) => [e.equipe_id, 0]));

  for (const jogo of ctx.jogos) {
    if (!ids.has(jogo.equipe_1_id) || !ids.has(jogo.equipe_2_id)) continue;

    const diferenca = (jogo.placar_1 ?? 0) - (jogo.placar_2 ?? 0);
    saldo.set(jogo.equipe_1_id, saldo.get(jogo.equipe_1_id) + diferenca);
    saldo.set(jogo.equipe_2_id, saldo.get(jogo.equipe_2_id) - diferenca);
  }

  return saldo;
};

const CRITERIOS = {
  saldo: {
    nome: 'saldo',
    valor: (bloco) => new Map(bloco.map((e) => [e.equipe_id, e.saldo]))
  },
  confronto_direto: {
    nome: 'confronto direto',
    valor: pontosEntre
  },
  saldo_entre_empatadas: {
    nome: 'saldo entre as empatadas',
    valor: saldoEntre
  },
  vitorias: {
    nome: 'mais vitórias',
    valor: (bloco) => new Map(bloco.map((e) => [e.equipe_id, e.vitorias]))
  },
  marcados: {
    nome: 'mais marcados',
    valor: (bloco) => new Map(bloco.map((e) => [e.equipe_id, e.marcados]))
  },
  saldo_pontos_sets: {
    nome: 'saldo de pontos dos sets',
    valor: (bloco) => new Map(bloco.map((e) => [e.equipe_id, e.pontos_set_pro - e.pontos_set_contra]))
  },
  menos_vermelhos: {
    nome: 'menos vermelhos',
    valor: (bloco) => new Map(bloco.map((e) => [e.equipe_id, -e.vermelhos]))
  },
  menos_amarelos: {
    nome: 'menos amarelos',
    valor: (bloco) => new Map(bloco.map((e) => [e.equipe_id, -e.amarelos]))
  },
  menos_desqualificacoes: {
    nome: 'menos desqualificações',
    valor: (bloco) => new Map(bloco.map((e) => [e.equipe_id, -e.desqualificacoes]))
  }
};

// Ordem dos critérios por tipo de placar da modalidade. Os pontos vêm antes
// de todos eles e por isso não entram na lista.
const ORDEM_DESEMPATE = {
  // Futsal, Handebol e Futebol Society
  GOLS: ['saldo', 'confronto_direto', 'vitorias', 'marcados', 'menos_vermelhos', 'menos_amarelos'],
  // Basquete
  PONTOS: ['confronto_direto', 'saldo_entre_empatadas', 'marcados', 'menos_desqualificacoes'],
  // Vôlei: o saldo da tabela é de sets; o saldo de pontos vem de jogo_sets
  SETS: ['saldo_entre_empatadas', 'confronto_direto', 'saldo_pontos_sets', 'menos_vermelhos', 'menos_amarelos'],
  // Baleado
  ELIMINADOS: ['confronto_direto', 'vitorias', 'menos_vermelhos', 'menos_amarelos']
};

// Ordena um bloco de equipes empatadas aplicando os critérios em ordem.
// Quem chega ao fim do funil ainda empatado vai para sorteio (regulamento).
const desempatar = (bloco, criterios, indice, ctx) => {
  if (bloco.length === 1) return bloco;

  if (indice >= criterios.length) {
    // Antes da primeira rodada a tabela inteira está zerada: isso não é
    // empate a resolver por sorteio, é só competição que ainda não começou.
    if (bloco.some((equipe) => equipe.jogos > 0)) {
      for (const equipe of bloco) equipe.sorteio = true;
    }
    return [...bloco].sort((a, b) => a.escola_nome.localeCompare(b.escola_nome, 'pt-BR'));
  }

  const criterio = CRITERIOS[criterios[indice]];
  const valores = criterio.valor(bloco, ctx);

  const porValor = new Map();
  for (const equipe of bloco) {
    const valor = valores.get(equipe.equipe_id) ?? 0;
    if (!porValor.has(valor)) porValor.set(valor, []);
    porValor.get(valor).push(equipe);
  }

  const chaves = [...porValor.keys()].sort((a, b) => b - a);

  return chaves.flatMap((chave) => {
    const sub = porValor.get(chave);

    // O critério separou de fato: registra quem decidiu, para a tela mostrar
    if (sub.length < bloco.length) {
      for (const equipe of sub) {
        if (!equipe.criterio_desempate) equipe.criterio_desempate = criterio.nome;
      }
    }

    return desempatar(sub, criterios, indice + 1, ctx);
  });
};

// Regras que o regulamento não fecha e que mudariam esta tabela. Desde
// 30/09/2026 elas têm decisão PROVISÓRIA (src/config/regrasProvisorias.js);
// o aviso continua na tela para lembrar que o chefe ainda vai revisar.
const avisosDeRegra = (competicao, grupos) => {
  const avisos = [];
  const tamanhos = [...new Set(grupos.map((g) => g.equipes.length))];

  if (competicao.melhores_segundos > 0 && tamanhos.length > 1) {
    avisos.push({
      titulo: 'Critério do "melhor segundo" — decisão provisória',
      texto:
        `Os grupos têm tamanhos diferentes (${grupos.map((g) => `${g.nome}: ${g.equipes.length}`).join(', ')}). ` +
        `Decisão de ${REGRAS.melhorSegundo.decididoEm}, ainda a confirmar: ${REGRAS.melhorSegundo.descricao} ` +
        'A tabela abaixo é a classificação dentro de cada grupo; a comparação entre os segundos acontece ' +
        'na geração da semifinal.'
    });
  }

  if (competicao.turno === 'IDA_E_VOLTA' && competicao.total_equipes > 2) {
    avisos.push({
      titulo: 'Formato "melhor de dois jogos" com mais de duas equipes',
      texto:
        `São ${competicao.total_equipes} equipes numa disputa de "melhor de dois jogos", e não está definido ` +
        'se isso é todos contra todos em ida e volta ou dois jogos entre as duas melhores. A tabela soma ' +
        'todos os jogos já lançados, qualquer que seja o formato escolhido.'
    });
  }

  return avisos;
};

// GET /api/classificacao/competicao/:competicao_id
const classificacaoDaCompeticao = async (req, res) => {
  const id = Number(req.params.competicao_id);

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ erro: 'Identificador de competição inválido.' });
  }

  try {
    const [[competicao]] = await db.query(
      `SELECT c.id, c.genero, c.status, c.qtd_grupos, c.classificados_por_grupo,
              c.melhores_segundos, c.proxima_fase, c.turno,
              c.pontos_vitoria, c.pontos_empate, c.pontos_derrota,
              m.nome AS modalidade_nome, m.slug AS modalidade_slug, m.tipo_placar,
              cat.nome AS categoria_nome
         FROM competicoes c
         INNER JOIN modalidades m ON m.id = c.modalidade_id
         INNER JOIN categorias cat ON cat.id = c.categoria_id
        WHERE c.id = ?`,
      [id]
    );

    if (!competicao) {
      return res.status(404).json({ erro: 'Competição não encontrada.' });
    }

    const criterios = ORDEM_DESEMPATE[competicao.tipo_placar];

    if (!criterios) {
      // Atletismo (MARCA) não tem tabela de grupos: o resultado é por prova
      return res.status(400).json({
        erro: `${competicao.modalidade_nome} não tem classificação por grupos.`
      });
    }

    const [equipes] = await db.query(
      `SELECT e.id AS equipe_id, e.escola_id, esc.nome AS escola_nome,
              g.id AS grupo_id, g.nome AS grupo_nome,
              (SELECT COUNT(*) FROM inscricoes_atletas i WHERE i.equipe_id = e.id) AS total_inscritos
         FROM equipes e
         INNER JOIN escolas esc ON esc.id = e.escola_id
         LEFT JOIN grupos g ON g.id = e.grupo_id
        WHERE e.competicao_id = ?
        ORDER BY g.nome IS NULL, g.nome, esc.nome`,
      [id]
    );

    // Só a fase de grupos entra na classificação: mata-mata não dá pontos
    const [jogos] = await db.query(
      `SELECT id, grupo_id, equipe_1_id, equipe_2_id, placar_1, placar_2, status, vencedor_equipe_id
         FROM jogos
        WHERE competicao_id = ? AND fase = 'GRUPOS' AND status IN ('FINALIZADO', 'WO')`,
      [id]
    );

    const [cartoes] = await db.query(
      `SELECT s.equipe_id,
              COALESCE(SUM(s.amarelos), 0) AS amarelos,
              COALESCE(SUM(s.vermelho), 0) AS vermelhos,
              COALESCE(SUM(s.desqualificado), 0) AS desqualificacoes
         FROM sumula_atletas s
         INNER JOIN jogos j ON j.id = s.jogo_id
        WHERE j.competicao_id = ? AND j.fase = 'GRUPOS'
        GROUP BY s.equipe_id`,
      [id]
    );

    // Vôlei: o saldo de pontos dos sets é critério de desempate
    const [sets] = competicao.tipo_placar === 'SETS'
      ? await db.query(
        `SELECT js.jogo_id, js.pontos_1, js.pontos_2
           FROM jogo_sets js
           INNER JOIN jogos j ON j.id = js.jogo_id
          WHERE j.competicao_id = ? AND j.fase = 'GRUPOS'`,
        [id]
      )
      : [[]];

    const tabela = new Map();
    for (const equipe of equipes) {
      tabela.set(equipe.equipe_id, {
        equipe_id: equipe.equipe_id,
        escola_id: equipe.escola_id,
        escola_nome: equipe.escola_nome,
        grupo_id: equipe.grupo_id,
        grupo_nome: equipe.grupo_nome || 'Sem grupo',
        total_inscritos: equipe.total_inscritos,
        jogos: 0,
        vitorias: 0,
        empates: 0,
        derrotas: 0,
        pontos: 0,
        marcados: 0,
        sofridos: 0,
        saldo: 0,
        pontos_set_pro: 0,
        pontos_set_contra: 0,
        amarelos: 0,
        vermelhos: 0,
        desqualificacoes: 0,
        wo: 0
      });
    }

    for (const jogo of jogos) {
      const casa = tabela.get(jogo.equipe_1_id);
      const fora = tabela.get(jogo.equipe_2_id);
      if (!casa || !fora) continue;

      const [p1, p2] = resultado(jogo, competicao);
      const placar1 = jogo.placar_1 ?? 0;
      const placar2 = jogo.placar_2 ?? 0;

      for (const [equipe, feitos, sofridos, pontos] of [
        [casa, placar1, placar2, p1],
        [fora, placar2, placar1, p2]
      ]) {
        equipe.jogos += 1;
        equipe.marcados += feitos;
        equipe.sofridos += sofridos;
        equipe.saldo += feitos - sofridos;
        equipe.pontos += pontos;
        if (jogo.status === 'WO') equipe.wo += 1;
      }

      const vencedor = jogo.status === 'WO' && jogo.vencedor_equipe_id
        ? jogo.vencedor_equipe_id
        : placar1 === placar2 ? null : placar1 > placar2 ? jogo.equipe_1_id : jogo.equipe_2_id;

      if (vencedor === null) {
        casa.empates += 1;
        fora.empates += 1;
      } else if (vencedor === casa.equipe_id) {
        casa.vitorias += 1;
        fora.derrotas += 1;
      } else {
        fora.vitorias += 1;
        casa.derrotas += 1;
      }
    }

    for (const linha of cartoes) {
      const equipe = tabela.get(linha.equipe_id);
      if (!equipe) continue;
      equipe.amarelos = Number(linha.amarelos);
      equipe.vermelhos = Number(linha.vermelhos);
      equipe.desqualificacoes = Number(linha.desqualificacoes);
    }

    if (sets.length > 0) {
      const porJogo = new Map(jogos.map((j) => [j.id, j]));
      for (const set of sets) {
        const jogo = porJogo.get(set.jogo_id);
        if (!jogo) continue;

        const casa = tabela.get(jogo.equipe_1_id);
        const fora = tabela.get(jogo.equipe_2_id);
        if (!casa || !fora) continue;

        casa.pontos_set_pro += set.pontos_1;
        casa.pontos_set_contra += set.pontos_2;
        fora.pontos_set_pro += set.pontos_2;
        fora.pontos_set_contra += set.pontos_1;
      }
    }

    // Agrupa, ordena por pontos e desempata bloco a bloco
    const grupos = [];
    const porGrupo = new Map();

    for (const equipe of tabela.values()) {
      const chave = equipe.grupo_id ?? 'sem-grupo';
      if (!porGrupo.has(chave)) {
        const grupo = { id: equipe.grupo_id, nome: equipe.grupo_nome, equipes: [] };
        porGrupo.set(chave, grupo);
        grupos.push(grupo);
      }
      porGrupo.get(chave).equipes.push(equipe);
    }

    for (const grupo of grupos) {
      // Jogos do próprio grupo; num grupo único o grupo_id do jogo pode ser nulo
      const ctx = {
        competicao,
        jogos: grupos.length === 1 ? jogos : jogos.filter((j) => j.grupo_id === grupo.id)
      };

      const porPontos = new Map();
      for (const equipe of grupo.equipes) {
        if (!porPontos.has(equipe.pontos)) porPontos.set(equipe.pontos, []);
        porPontos.get(equipe.pontos).push(equipe);
      }

      const chaves = [...porPontos.keys()].sort((a, b) => b - a);
      grupo.equipes = chaves.flatMap((chave) => desempatar(porPontos.get(chave), criterios, 0, ctx));
      grupo.equipes.forEach((equipe, indice) => {
        equipe.posicao = indice + 1;
      });
    }

    res.status(200).json({
      competicao: {
        id: competicao.id,
        modalidade_nome: competicao.modalidade_nome,
        modalidade_slug: competicao.modalidade_slug,
        categoria_nome: competicao.categoria_nome,
        genero: competicao.genero,
        tipo_placar: competicao.tipo_placar,
        classificados_por_grupo: competicao.classificados_por_grupo,
        melhores_segundos: competicao.melhores_segundos,
        proxima_fase: competicao.proxima_fase
      },
      criterios_desempate: criterios.map((c) => CRITERIOS[c].nome),
      total_jogos_computados: jogos.length,
      avisos: avisosDeRegra({ ...competicao, total_equipes: equipes.length }, grupos),
      grupos
    });
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao montar a classificação.' });
  }
};

module.exports = { classificacaoDaCompeticao };
