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
// Decisões do usuário de 30/09/2026. A de C é o padrão do futebol; as de D e E,
// e o 3º lugar sem semifinal, o chefe confirmou ou trocou em 06/10/2026; a
// revanche na semifinal de D, em 07/10/2026 (revancheNaSemifinal).
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
  // melhor segundo. Decisão do chefe de 06/10/2026: confrontos FIXOS,
  // 1ºA × melhor 2º e 1ºB × 1ºC. O melhor 2º sai da campanha, pelos critérios
  // da modalidade (regrasProvisorias.melhorSegundo). Se ele for do grupo A,
  // a semifinal repete um jogo da fase de grupos — e funciona assim mesmo
  // (`revancheNaSemifinal`).
  cruzamentoTresGruposComMelhorSegundo: {
    provisorio: false,
    decididoEm: '06/10/2026',
    descricao:
      '1ºA × melhor 2º colocado e 1ºB × 1ºC. O melhor 2º é escolhido pela campanha, '
      + 'pelos critérios de desempate da modalidade.'
  },

  // A revanche da fase de grupos na semifinal (1ºA contra um 2º do grupo A)
  // é aceita: o chefe confirmou em 07/10/2026 que funciona assim mesmo, então
  // a chave sai sem aviso nenhum.
  revancheNaSemifinal: {
    provisorio: false,
    decididoEm: '07/10/2026',
    descricao: 'A revanche da fase de grupos na semifinal é aceita, sem aviso.'
  },

  // Formato E — duas equipes em ida e volta, sem mata-mata. O campeão é quem
  // soma mais nos dois jogos; empatada a soma, decide nas cobranças lançadas
  // na súmula do segundo jogo (pênaltis, 7 metros ou eliminações, conforme a
  // modalidade — a sequência vem de regrasProvisorias.desempateMataMata).
  // Confirmada pelo chefe em 06/10/2026.
  somaDosDoisJogos: {
    provisorio: false,
    decididoEm: '06/10/2026',
    descricao:
      'Com duas equipes em ida e volta, o campeão é quem soma mais nos dois jogos. '
      + 'Se a soma empatar, decide nas cobranças lançadas na súmula do segundo jogo.'
  },

  // Sem semifinal, o 3º lugar sai da fase classificatória (regulamento). Num
  // grupo único é o 3º da tabela; com dois grupos sobram os dois segundos
  // colocados, e fica com o melhor deles pela campanha, nos critérios da
  // modalidade. Confirmado pelo chefe em 06/10/2026: esse 3º vale 6 pontos na
  // tabela geral, como qualquer 3º lugar.
  terceiroSemSemifinal: {
    provisorio: false,
    decididoEm: '06/10/2026',
    descricao:
      'Sem semifinal, o 3º lugar é o 3º do grupo único ou, com dois grupos, o melhor '
      + 'dos dois segundos colocados pela campanha, e vale 6 pontos na tabela geral.'
  },

  // 4º e 5º lugar (4 e 2 pontos na tabela geral) — decididos em 06/10/2026 e
  // confirmados pelo chefe em 07/10/2026.
  //   4º: o perdedor da disputa de 3º lugar, quando houver. O regulamento diz
  //       que NÃO há jogo de 3º lugar (e o schema não tem essa fase), então
  //       hoje vale sempre o outro caminho: o semifinalista que não foi 3º,
  //       isto é, quem perdeu a semifinal para o vice. Sem semifinal, não há 4º.
  //   5º: a melhor equipe que não chegou à semifinal, pela campanha da fase
  //       de grupos, só quando a COMPETIÇÃO tem mais de
  //       `equipesNaCompeticaoParaQuinto` equipes (correção do usuário,
  //       06/10/2026). Com 4 equipes ou menos, não há 5º.
  //       Empate em todos os critérios: as empatadas DIVIDEM o 5º e cada uma
  //       leva os 2 pontos — nada de sorteio aqui (o sorteio do regulamento
  //       fica para o desempate dentro do grupo).
  // Confirmado pelo chefe em 07/10/2026: deixa de ser provisório.
  quartoEQuinto: {
    provisorio: false,
    decididoEm: '07/10/2026',
    equipesNaCompeticaoParaQuinto: 4,
    textoDoEmpate: '5º lugar dividido',
    descricao:
      '4º é o semifinalista que não ficou em 3º (não há jogo de 3º lugar); 5º é a melhor '
      + 'equipe que não chegou à semifinal, pela campanha da fase de grupos, só quando a '
      + 'competição tem mais de 4 equipes; empatadas em tudo dividem o 5º e levam 2 pontos '
      + 'cada uma.'
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
const chaveDaSemifinal = (competicao, contexto) => {
  const { classificadosPorGrupo, melhoresSegundos } = contexto;

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

  // Formato D: três grupos, o primeiro de cada mais o melhor segundo.
  // Confrontos fixos (06/10/2026): 1ºA × melhor 2º e 1ºB × 1ºC.
  if (competicao.qtd_grupos === 3
    && competicao.classificados_por_grupo === 1
    && competicao.melhores_segundos === 1) {
    // Pelo nome do grupo, para "A", "B" e "C" não dependerem da ordem da consulta
    const [a, b, c] = [...classificadosPorGrupo]
      .sort((x, y) => String(x.grupo_nome).localeCompare(String(y.grupo_nome), 'pt-BR'));
    const primeiroA = a?.equipes[0];
    const primeiroB = b?.equipes[0];
    const primeiroC = c?.equipes[0];
    const segundo = melhoresSegundos[0];

    if (!primeiroA || !primeiroB || !primeiroC || !segundo) {
      return { erro: 'A semifinal precisa dos três primeiros colocados e do melhor segundo.' };
    }

    // Se o melhor 2º for do grupo A, é revanche da fase de grupos: aceita
    // (07/10/2026), sem aviso
    return {
      regra: REGRAS_DA_CHAVE.cruzamentoTresGruposComMelhorSegundo,
      confrontos: [
        confronto('Semifinal 1', primeiroA, segundo),
        confronto('Semifinal 2', primeiroB, primeiroC)
      ]
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
