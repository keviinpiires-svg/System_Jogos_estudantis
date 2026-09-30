// ============================================================================
// CHAVES DO MATA-MATA — quem enfrenta quem, num lugar só.
//
// O FORMATO de cada competição é dado (colunas de `competicoes`: qtd_grupos,
// classificados_por_grupo, melhores_segundos, proxima_fase, turno). O que é
// CÓDIGO é o cruzamento: com quatro classificados, quem pega quem.
//
// As 50 competições caem em cinco formatos, levantados no banco em 30/09/2026:
//
//   A | 1 grupo, 2 classificados      -> FINAL      | 20 competições
//   B | 2 grupos x 1                  -> FINAL      | 11
//   C | 2 grupos x 2                  -> SEMIFINAL   | 10
//   D | 3 grupos x 1 + 1 melhor 2º    -> SEMIFINAL   | 3
//   E | 1 grupo, ida e volta          -> sem mata-mata | 6 (todas com 2 equipes)
//
// Decisões do usuário de 30/09/2026. A de C é o padrão do futebol; as de D e E
// o regulamento não fecha, então são PROVISÓRIAS, como as de
// src/config/regrasProvisorias.js — o chefe ainda vai revisar.
// ============================================================================

const DECIDIDO_EM = '30/09/2026';

const REGRAS_DA_CHAVE = {
  // Formato C — o padrão do futebol: o primeiro de um grupo enfrenta o segundo
  // do outro, e duas equipes do mesmo grupo só se reencontram na final.
  cruzamentoDoisGrupos: {
    provisorio: false,
    decididoEm: DECIDIDO_EM,
    descricao: '1ºA × 2ºB e 1ºB × 2ºA: o primeiro de um grupo pega o segundo do outro.'
  },

  // Formato D — quatro classificados: os três primeiros colocados mais o
  // melhor segundo. Os primeiros são ordenados entre si (mesma comparação do
  // melhor segundo) e o melhor deles pega o melhor segundo. Se os dois forem
  // do mesmo grupo, troca-se o par: ninguém reencontra companheiro de grupo
  // na semifinal.
  cruzamentoTresGruposComMelhorSegundo: {
    provisorio: true,
    decididoEm: DECIDIDO_EM,
    descricao:
      'O melhor primeiro colocado enfrenta o melhor segundo e os outros dois primeiros '
      + 'se enfrentam. Se o melhor segundo for do grupo do melhor primeiro, os pares são '
      + 'trocados para não repetir um confronto da fase de grupos.'
  },

  // Formato E — duas equipes em ida e volta, sem mata-mata. O campeão é quem
  // soma mais nos dois jogos; empatada a soma, decide nas cobranças lançadas
  // na súmula do segundo jogo (pênaltis, 7 metros ou eliminações, conforme a
  // modalidade — a sequência vem de regrasProvisorias.desempateMataMata).
  somaDosDoisJogos: {
    provisorio: true,
    decididoEm: DECIDIDO_EM,
    descricao:
      'Com duas equipes em ida e volta, o campeão é quem soma mais nos dois jogos. '
      + 'Se a soma empatar, decide nas cobranças lançadas na súmula do segundo jogo.'
  },

  // Sem semifinal, o 3º lugar sai da fase classificatória (regulamento). Num
  // grupo único é o 3º da tabela; com dois grupos sobram os dois segundos
  // colocados, e fica com o melhor deles pelos critérios da modalidade.
  terceiroSemSemifinal: {
    provisorio: true,
    decididoEm: DECIDIDO_EM,
    descricao:
      'Sem semifinal, o 3º lugar é o 3º do grupo único ou, com dois grupos, o melhor '
      + 'dos dois segundos colocados pelos critérios de desempate da modalidade.'
  }
};

const rotulo = (equipe) => `${equipe.posicao}º ${equipe.grupo_nome}`;

// Um confronto da chave
const confronto = (nome, equipe_1, equipe_2) => ({
  rotulo: nome,
  equipe_1_id: equipe_1.equipe_id,
  equipe_2_id: equipe_2.equipe_id,
  // Só para a tela explicar a chave antes de o jogo existir
  equipe_1: { equipe_id: equipe_1.equipe_id, escola_nome: equipe_1.escola_nome, origem: rotulo(equipe_1) },
  equipe_2: { equipe_id: equipe_2.equipe_id, escola_nome: equipe_2.escola_nome, origem: rotulo(equipe_2) }
});

// ---------------------------------------------------------------------------
// Semifinais
// ---------------------------------------------------------------------------
// `contexto` traz o que o controller já calculou:
//   grupos                -> classificação ordenada, com posicao em cada linha
//   classificadosPorGrupo -> [{ grupo_nome, equipes: [...] }] já cortado
//   melhoresSegundos      -> os melhores segundos, em ordem
//   primeirosOrdenados    -> os primeiros colocados ordenados entre si
const chaveDaSemifinal = (competicao, contexto) => {
  const { classificadosPorGrupo, melhoresSegundos, primeirosOrdenados } = contexto;

  // Formato C: dois grupos, dois classificados de cada
  if (competicao.qtd_grupos === 2 && competicao.classificados_por_grupo === 2) {
    const [a, b] = classificadosPorGrupo;

    if (a.equipes.length < 2 || b.equipes.length < 2) {
      return { erro: 'Cada grupo precisa de duas equipes classificadas para a semifinal.' };
    }

    return {
      regra: REGRAS_DA_CHAVE.cruzamentoDoisGrupos,
      confrontos: [
        confronto('Semifinal 1', a.equipes[0], b.equipes[1]),
        confronto('Semifinal 2', b.equipes[0], a.equipes[1])
      ]
    };
  }

  // Formato D: três grupos, o primeiro de cada mais o melhor segundo
  if (competicao.qtd_grupos === 3
    && competicao.classificados_por_grupo === 1
    && competicao.melhores_segundos === 1) {
    if (primeirosOrdenados.length < 3 || melhoresSegundos.length < 1) {
      return { erro: 'A semifinal precisa dos três primeiros colocados e do melhor segundo.' };
    }

    const [melhor, segundoMelhor, terceiroMelhor] = primeirosOrdenados;
    const segundo = melhoresSegundos[0];
    const mesmoGrupo = segundo.grupo_id === melhor.grupo_id;

    return {
      regra: REGRAS_DA_CHAVE.cruzamentoTresGruposComMelhorSegundo,
      // O melhor primeiro pega o melhor segundo — a não ser que sejam do mesmo
      // grupo, e aí o par é trocado com o pior dos primeiros.
      confrontos: mesmoGrupo
        ? [
          confronto('Semifinal 1', melhor, terceiroMelhor),
          confronto('Semifinal 2', segundoMelhor, segundo)
        ]
        : [
          confronto('Semifinal 1', melhor, segundo),
          confronto('Semifinal 2', segundoMelhor, terceiroMelhor)
        ],
      observacao: mesmoGrupo
        ? `O melhor segundo (${segundo.escola_nome}) é do grupo ${segundo.grupo_nome}, `
          + 'o mesmo do melhor primeiro colocado: os pares foram trocados para não repetir '
          + 'um confronto da fase de grupos.'
        : null
    };
  }

  return {
    erro: `Formato sem cruzamento definido: ${competicao.qtd_grupos} grupo(s), `
      + `${competicao.classificados_por_grupo} classificado(s) por grupo e `
      + `${competicao.melhores_segundos} melhor(es) segundo(s). `
      + 'Defina o cruzamento em src/config/chavesMataMata.js antes de gerar.'
  };
};

// ---------------------------------------------------------------------------
// Final
// ---------------------------------------------------------------------------
// Vem da semifinal, quando existe; sem semifinal, sai direto dos grupos.
const chaveDaFinal = (competicao, contexto) => {
  const { classificadosPorGrupo, vencedoresDaSemifinal } = contexto;

  if (competicao.proxima_fase === 'SEMIFINAL') {
    if (!vencedoresDaSemifinal || vencedoresDaSemifinal.length !== 2) {
      return { erro: 'A final sai das duas semifinais: as duas precisam estar decididas.' };
    }

    const [um, dois] = vencedoresDaSemifinal;
    return {
      confrontos: [{
        rotulo: 'Final',
        equipe_1_id: um.equipe_id,
        equipe_2_id: dois.equipe_id,
        equipe_1: { ...um, origem: 'Vencedor da semifinal 1' },
        equipe_2: { ...dois, origem: 'Vencedor da semifinal 2' }
      }]
    };
  }

  // Formato A: grupo único, os dois primeiros vão à final
  if (competicao.qtd_grupos === 1 && competicao.classificados_por_grupo === 2) {
    const [grupo] = classificadosPorGrupo;

    if (!grupo || grupo.equipes.length < 2) {
      return { erro: 'A final precisa dos dois primeiros do grupo.' };
    }

    return { confrontos: [confronto('Final', grupo.equipes[0], grupo.equipes[1])] };
  }

  // Formato B: dois grupos, o primeiro de cada vai à final
  if (competicao.qtd_grupos === 2 && competicao.classificados_por_grupo === 1) {
    const [a, b] = classificadosPorGrupo;

    if (!a?.equipes.length || !b?.equipes.length) {
      return { erro: 'A final precisa do primeiro colocado de cada grupo.' };
    }

    return { confrontos: [confronto('Final', a.equipes[0], b.equipes[0])] };
  }

  return {
    erro: `Formato sem final definida: ${competicao.qtd_grupos} grupo(s) e `
      + `${competicao.classificados_por_grupo} classificado(s) por grupo. `
      + 'Defina o cruzamento em src/config/chavesMataMata.js antes de gerar.'
  };
};

// Competição que não tem mata-mata: o campeão sai da própria tabela
const temMataMata = (competicao) => competicao.proxima_fase !== 'NENHUMA';

module.exports = {
  REGRAS_DA_CHAVE,
  chaveDaSemifinal,
  chaveDaFinal,
  temMataMata,
  DECIDIDO_EM
};
