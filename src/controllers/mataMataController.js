const db = require('../config/db');
const {
  montarClassificacao, compararEntreGrupos, avisoJogosDiferentes, ordenarPorCampanha,
  blocosDeSorteio, primeiraSemSorteio, vencedorDoJogo, ErroDeRegra
} = require('./classificacaoController');
const {
  REGRAS_DA_CHAVE, chaveDaSemifinal, chaveDaFinal, temMataMata
} = require('../config/chavesMataMata');
const { desempateDaModalidade } = require('../config/regrasProvisorias');
const { resolverVagas, resolverVagasDeTodas, ErroDeVaga } = require('../services/vagasMataMata');

// ============================================================================
// MATA-MATA — a chave de cada competição, montada a partir da classificação.
//
// Nada aqui é guardado: os classificados e as colocações saem dos jogos, como
// a classificação. O que o ADMIN grava são os JOGOS da semifinal e da final,
// e é só isso que este controller escreve.
//
// O cruzamento (quem pega quem) mora em src/config/chavesMataMata.js.
// O empate dentro do jogo é do sumulaController, que já lê a sequência de
// desempate de cada modalidade em src/config/regrasProvisorias.js.
// ============================================================================

const RESOLVIDO = ['FINALIZADO', 'WO'];

// Os classificados de cada grupo, já cortados no que a competição classifica
const classificadosPorGrupo = (grupos, quantos) => grupos.map((grupo) => ({
  grupo_id: grupo.id,
  grupo_nome: grupo.nome,
  equipes: grupo.equipes.slice(0, quantos)
}));

// Estado dos jogos de uma fase: o que existe, o que já foi decidido
const jogosDaFase = (jogos, fase) => jogos.filter((j) => j.fase === fase);

const decidido = (jogo) => RESOLVIDO.includes(jogo.status) && jogo.vencedor_equipe_id;

// Monta tudo o que a chave precisa saber. Serve ao GET e à geração.
const montarChave = async (id) => {
  const dados = await montarClassificacao(id);
  const { competicao, grupos, jogos } = dados;

  const [todosOsJogos] = await db.query(
    `SELECT j.id, j.numero_jogo, j.numero_tabela, j.fase, j.status, j.data_hora, j.rodada,
            j.equipe_1_id, j.equipe_2_id, j.placar_1, j.placar_2,
            j.penaltis_1, j.penaltis_2, j.vencedor_equipe_id,
            e1.escola_id AS escola_1_id, esc1.nome AS escola_1_nome,
            e2.escola_id AS escola_2_id, esc2.nome AS escola_2_nome,
            v1.rotulo AS origem_1, v2.rotulo AS origem_2,
            j.local_id, l.nome AS local_nome
       FROM jogos j
       LEFT JOIN equipes e1 ON e1.id = j.equipe_1_id
       LEFT JOIN escolas esc1 ON esc1.id = e1.escola_id
       LEFT JOIN equipes e2 ON e2.id = j.equipe_2_id
       LEFT JOIN escolas esc2 ON esc2.id = e2.escola_id
       LEFT JOIN jogo_vagas v1 ON v1.jogo_id = j.id AND v1.lado = 1
       LEFT JOIN jogo_vagas v2 ON v2.jogo_id = j.id AND v2.lado = 2
       LEFT JOIN locais_disputa l ON l.id = j.local_id
      WHERE j.competicao_id = ?
      ORDER BY j.fase, j.numero_jogo`,
    [id]
  );

  // Mata-mata cadastrado de antemão pela tabela do chefe (jogo_vagas, db/28): as vagas se
  // preenchem sozinhas e o gerar/desfazer por classificação não se aplica
  const [[{ comVagas }]] = await db.query(
    `SELECT COUNT(*) AS comVagas FROM jogo_vagas v INNER JOIN jogos j ON j.id = v.jogo_id
      WHERE j.competicao_id = ?`,
    [id]
  );

  const deGrupos = jogosDaFase(todosOsJogos, 'GRUPOS');
  const pendentesDeGrupos = deGrupos.filter((j) => !RESOLVIDO.includes(j.status));

  const faseDeGrupos = {
    total: deGrupos.length,
    pendentes: pendentesDeGrupos.length,
    // Sem jogo nenhum a fase não está completa, está vazia
    completa: deGrupos.length > 0 && pendentesDeGrupos.length === 0
  };

  // A comparação entre grupos só é necessária quando há mais de um grupo
  const entreGrupos = grupos.length > 1;
  const primeiros = entreGrupos ? compararEntreGrupos(1, dados) : null;
  const segundos = entreGrupos ? compararEntreGrupos(2, dados) : null;

  const contexto = {
    grupos,
    classificadosPorGrupo: classificadosPorGrupo(grupos, competicao.classificados_por_grupo),
    melhoresSegundos: segundos ? segundos.ordenadas.slice(0, competicao.melhores_segundos) : []
  };

  // Posições de pódio empatadas até o sorteio que o ADMIN já decidiu (colocacoes_finais, 16/11/2026)
  const [escolhidas] = await db.query(
    'SELECT posicao, equipe_id FROM colocacoes_finais WHERE competicao_id = ?',
    [id]
  );

  return {
    ...dados,
    escolhas: new Map(escolhidas.map((e) => [e.posicao, e.equipe_id])),
    todosOsJogos,
    vagasCadastradas: Number(comVagas) > 0,
    jogosDeGrupos: jogos,
    faseDeGrupos,
    contexto,
    comparacoes: { primeiros, segundos }
  };
};

// Texto do campeão de uma competição sem mata-mata. Com dois jogos fala da
// soma; com um jogo só (2 escolas e 1 jogo, como o Handebol M Sub 9), do jogo.
const comoFoiCampeao = (jogoUnico, porCobranca, slug, placar) => {
  const acrescimo = Boolean(desempateDaModalidade(slug).acrescimo);
  if (jogoUnico) {
    if (!porCobranca) return `venceu o jogo (${placar})`;
    return acrescimo ? 'campeão no acréscimo (baleou primeiro), com o jogo empatado' : 'campeão nas cobranças';
  }
  if (!porCobranca) return `campeão pela soma dos dois jogos (${placar})`;
  return acrescimo
    ? 'campeão no acréscimo do segundo jogo (baleou primeiro), com a soma dos dois jogos empatada'
    : 'campeão nas cobranças, com a soma dos dois jogos empatada';
};

// Quem venceu cada semifinal, na ordem dos jogos
const vencedoresDaSemifinal = (semifinais) => semifinais
  .filter(decidido)
  .map((jogo) => {
    const venceu = jogo.vencedor_equipe_id;
    return {
      equipe_id: venceu,
      escola_nome: venceu === jogo.equipe_1_id ? jogo.escola_1_nome : jogo.escola_2_nome,
      jogo_id: jogo.id
    };
  });

// Qual fase pode ser gerada agora, e por que não
const proximaGeracao = (chave) => {
  const { competicao, faseDeGrupos, todosOsJogos } = chave;

  if (!temMataMata(competicao)) {
    return {
      fase: null,
      motivo: 'Esta competição não tem mata-mata: são duas equipes em ida e volta, '
        + 'e o campeão sai da soma dos dois jogos.'
    };
  }

  if (chave.vagasCadastradas) {
    return {
      fase: null,
      motivo: 'Os jogos do mata-mata já estão cadastrados pela tabela do chefe: as equipes entram sozinhas '
        + 'quando cada grupo ou jogo termina. Use "Recalcular vagas" se precisar conferir.'
    };
  }

  if (!faseDeGrupos.completa) {
    return {
      fase: null,
      motivo: faseDeGrupos.total === 0
        ? 'A fase de grupos ainda não tem jogos.'
        : `Faltam ${faseDeGrupos.pendentes} de ${faseDeGrupos.total} jogos da fase de grupos.`
    };
  }

  const semifinais = jogosDaFase(todosOsJogos, 'SEMIFINAL');
  const finais = jogosDaFase(todosOsJogos, 'FINAL');

  if (finais.length > 0) {
    return { fase: null, motivo: 'A chave está completa: a final já está gerada.' };
  }

  if (competicao.proxima_fase === 'SEMIFINAL') {
    if (semifinais.length === 0) return { fase: 'SEMIFINAL', motivo: null };

    const decididas = semifinais.filter(decidido).length;

    return decididas === semifinais.length
      ? { fase: 'FINAL', motivo: null }
      : {
        fase: null,
        motivo: `A final sai das semifinais: ${semifinais.length - decididas} de `
          + `${semifinais.length} ainda sem resultado.`
      };
  }

  return { fase: 'FINAL', motivo: null };
};

// Os confrontos que a fase teria, pela regra da competição
const confrontosPrevistos = (chave, fase) => {
  const contexto = fase === 'FINAL'
    ? {
      ...chave.contexto,
      vencedoresDaSemifinal: vencedoresDaSemifinal(jogosDaFase(chave.todosOsJogos, 'SEMIFINAL'))
    }
    : chave.contexto;

  return fase === 'SEMIFINAL'
    ? chaveDaSemifinal(chave.competicao, contexto)
    : chaveDaFinal(chave.competicao, contexto);
};

// ---------------------------------------------------------------------------
// 4º e 5º lugar — REGRAS_DA_CHAVE.quartoEQuinto (06/10/2026, confirmado em 07/10)
// ---------------------------------------------------------------------------
// Só existem com semifinal. Não há jogo de 3º lugar (regulamento), então o 4º
// é sempre o semifinalista que perdeu para o vice. O 5º é a melhor equipe que
// não chegou à semifinal, e só sai quando a competição tem mais equipes do que
// o limite da regra.
const quartoEQuinto = (chave, semifinais, vice) => {
  const { competicao, grupos, criterios, jogos } = chave;
  const regra = REGRAS_DA_CHAVE.quartoEQuinto;
  const colocacoes = [];

  const doVice = semifinais.find((j) => decidido(j) && j.vencedor_equipe_id === vice);
  if (doVice) {
    const quarto = vice === doVice.equipe_1_id ? doVice.equipe_2_id : doVice.equipe_1_id;
    colocacoes.push({
      posicao: 4,
      equipe_id: quarto,
      escola_nome: quarto === doVice.equipe_1_id ? doVice.escola_1_nome : doVice.escola_2_nome,
      como: 'perdeu a semifinal para o vice (não há jogo de 3º lugar)',
      provisoria: regra.provisorio
    });
  }

  const todasAsEquipes = grupos.flatMap((grupo) => grupo.equipes);

  if (todasAsEquipes.length > regra.equipesNaCompeticaoParaQuinto) {
    const naSemifinal = new Set(semifinais.flatMap((j) => [j.equipe_1_id, j.equipe_2_id]));
    // Cópias: o desempate marca `sorteio` nas linhas, e estas são as da classificação
    const foraDaSemifinal = todasAsEquipes
      .filter((equipe) => !naSemifinal.has(equipe.equipe_id))
      .map((equipe) => ({ ...equipe }));

    // Quem empata em todos os critérios NÃO vai a sorteio aqui (06/10/2026):
    // divide o 5º lugar, e cada uma leva os pontos. O sorteio do regulamento
    // continua valendo dentro do grupo, na classificação.
    const empatesAteOFim = [];
    const ordenadas = ordenarPorCampanha(foraDaSemifinal, criterios, {
      competicao,
      jogos,
      aoEmpatarAteOFim: (bloco) => empatesAteOFim.push(bloco.map((e) => e.equipe_id))
    });

    const [lider] = ordenadas;
    const empatadas = lider && empatesAteOFim.find((ids) => ids.includes(lider.equipe_id));
    const quintos = empatadas
      ? ordenadas.filter((equipe) => empatadas.includes(equipe.equipe_id))
      : ordenadas.slice(0, 1);

    for (const quinto of quintos) {
      colocacoes.push({
        posicao: 5,
        equipe_id: quinto.equipe_id,
        escola_nome: quinto.escola_nome,
        como: quintos.length > 1
          ? `${regra.textoDoEmpate} (grupo ${quinto.grupo_nome}; empatada em todos os critérios)`
          : `melhor campanha entre quem não chegou à semifinal (grupo ${quinto.grupo_nome})`,
        dividida: quintos.length > 1,
        provisoria: regra.provisorio
      });
    }
  }

  return colocacoes;
};

// ---------------------------------------------------------------------------
// Colocações finais — calculadas, nunca gravadas
// ---------------------------------------------------------------------------
// Regulamento: NÃO existe jogo de 3º lugar. Com semifinal, o 3º é quem perdeu
// a semifinal PARA O CAMPEÃO. Sem semifinal, vale a fase classificatória:
// o 3º do grupo único ou, com dois grupos, o melhor dos dois segundos pela
// campanha (REGRAS_DA_CHAVE.terceiroSemSemifinal, confirmada em 06/10/2026:
// vale 6 pontos na tabela geral, como qualquer 3º).
// O 3º sem semifinal: a melhor equipe que não foi à final. Num grupo único, a ordem do grupo; com
// mais grupos, a melhor de cada grupo (fora da final) comparada pela campanha. Empate até o sorteio
// devolve { empatadas } para o ADMIN escolher — nada é decidido em silêncio (16/11/2026).
const terceiroSemSemifinal = (chave, naFinal) => {
  const { grupos, criterios, competicao, jogos } = chave;
  const unico = grupos.length === 1;
  const candidatas = [];
  const blocoNoGrupo = new Map(); // equipe -> ids empatadas com ela no grupo (fora da final)

  for (const grupo of grupos) {
    const fora = grupo.equipes.filter((e) => !naFinal.has(e.equipe_id));
    if (fora.length === 0) continue;
    const blocos = blocosDeSorteio(grupo.equipes, criterios, {
      competicao, jogos: unico ? jogos : jogos.filter((j) => j.grupo_id === grupo.id)
    });
    const bloco = blocos.find((ids) => ids.includes(fora[0].equipe_id));
    const empatadas = bloco ? fora.filter((e) => bloco.includes(e.equipe_id)) : [fora[0]];
    for (const e of empatadas) blocoNoGrupo.set(e.equipe_id, empatadas.map((x) => x.equipe_id));
    candidatas.push(...empatadas);
  }

  if (candidatas.length === 0) return {};
  if (unico) return candidatas.length > 1 ? { empatadas: candidatas } : { equipe: candidatas[0] };

  const r = primeiraSemSorteio(candidatas, criterios, { competicao, jogos });
  const doGrupo = blocoNoGrupo.get(r.primeira.equipe_id) || [];
  const ids = new Set([...(doGrupo.length > 1 ? doGrupo : []), ...r.empatadas.map((e) => e.equipe_id)]);
  if (ids.size > 1) return { empatadas: candidatas.filter((e) => ids.has(e.equipe_id)) };
  return { equipe: candidatas.find((e) => e.equipe_id === r.primeira.equipe_id) };
};

// As colocações decididas e as posições que esperam o ADMIN (empate até o sorteio)
const apurarColocacoes = (chave) => {
  const { competicao, todosOsJogos, grupos, faseDeGrupos } = chave;
  const colocacoes = [];
  const pendentes = [];
  const pronto = () => ({ colocacoes, pendentes });

  const nomeDaEquipe = (equipe_id) => {
    for (const grupo of grupos) {
      const equipe = grupo.equipes.find((e) => e.equipe_id === equipe_id);
      if (equipe) return equipe.escola_nome;
    }
    return '';
  };

  // Competição sem mata-mata ("melhor de dois jogos"): campeão pela SOMA
  // DIRETA dos placares dos dois jogos, em qualquer modalidade, sem passar
  // pela classificação (20/10/2026). Antes saía do 1º da tabela, e no baleado,
  // cujo desempate não olha saldo, a soma podia não decidir.
  if (!temMataMata(competicao)) {
    if (!faseDeGrupos.completa) return pronto();

    const [grupo] = grupos;
    if (!grupo || grupo.equipes.length < 2) return pronto();

    const [primeiro, segundo] = grupo.equipes;
    const deGrupos = jogosDaFase(todosOsJogos, 'GRUPOS');
    const soma = new Map([[primeiro.equipe_id, 0], [segundo.equipe_id, 0]]);
    for (const jogo of deGrupos) {
      if (soma.has(jogo.equipe_1_id)) soma.set(jogo.equipe_1_id, soma.get(jogo.equipe_1_id) + (jogo.placar_1 ?? 0));
      if (soma.has(jogo.equipe_2_id)) soma.set(jogo.equipe_2_id, soma.get(jogo.equipe_2_id) + (jogo.placar_2 ?? 0));
    }
    const somaEmpatada = soma.get(primeiro.equipe_id) === soma.get(segundo.equipe_id);

    // Empatada a soma, o título sai do vencedor gravado no último jogo: as
    // cobranças no futsal e no handebol, quem baleou primeiro no acréscimo do
    // baleado (sumulaController.registrarSumula)
    const ultimo = deGrupos.slice(-1)[0];
    const porCobranca = somaEmpatada && ultimo?.vencedor_equipe_id
      ? ultimo.vencedor_equipe_id
      : null;

    if (somaEmpatada && !porCobranca) {
      return pronto();
    }

    const lider = soma.get(primeiro.equipe_id) > soma.get(segundo.equipe_id) ? primeiro : segundo;
    const campeao = porCobranca || lider.equipe_id;
    const vice = campeao === primeiro.equipe_id ? segundo.equipe_id : primeiro.equipe_id;

    colocacoes.push(
      {
        posicao: 1,
        equipe_id: campeao,
        escola_nome: nomeDaEquipe(campeao),
        // Competição de 2 escolas com um jogo só (Handebol M Sub 9, tabela do
        // chefe de 20/10/2026): não há soma, há o jogo
        como: comoFoiCampeao(deGrupos.length === 1, porCobranca, competicao.modalidade_slug,
          `${soma.get(campeao)} × ${soma.get(vice)}`)
      },
      { posicao: 2, equipe_id: vice, escola_nome: nomeDaEquipe(vice), como: 'vice' }
    );
    return pronto();
  }

  const finais = jogosDaFase(todosOsJogos, 'FINAL');
  const final = finais.find(decidido);

  if (!final) return pronto();

  const campeao = final.vencedor_equipe_id;
  const vice = campeao === final.equipe_1_id ? final.equipe_2_id : final.equipe_1_id;

  colocacoes.push(
    {
      posicao: 1,
      equipe_id: campeao,
      escola_nome: campeao === final.equipe_1_id ? final.escola_1_nome : final.escola_2_nome,
      como: 'campeão da final'
    },
    {
      posicao: 2,
      equipe_id: vice,
      escola_nome: vice === final.equipe_1_id ? final.escola_1_nome : final.escola_2_nome,
      como: 'vice'
    }
  );

  const semifinais = jogosDaFase(todosOsJogos, 'SEMIFINAL');

  if (semifinais.length > 0) {
    // O 3º é quem perdeu a semifinal para o campeão — não há jogo de 3º lugar
    const doCampeao = semifinais.find(
      (j) => decidido(j) && j.vencedor_equipe_id === campeao
    );

    if (doCampeao) {
      const terceiro = campeao === doCampeao.equipe_1_id
        ? doCampeao.equipe_2_id
        : doCampeao.equipe_1_id;

      colocacoes.push({
        posicao: 3,
        equipe_id: terceiro,
        escola_nome: terceiro === doCampeao.equipe_1_id
          ? doCampeao.escola_1_nome
          : doCampeao.escola_2_nome,
        como: 'perdeu a semifinal para o campeão (não há jogo de 3º lugar)'
      });
    }

    colocacoes.push(...quartoEQuinto(chave, semifinais, vice));
    return pronto();
  }

  // Sem semifinal: o 3º, o 4º e o 5º vêm da fase classificatória, um de cada vez: a melhor
  // equipe que ainda não foi colocada (terceiroSemSemifinal, com a final e as já colocadas de
  // fora). O 5º só existe com mais de `equipesNaCompeticaoParaQuinto` equipes. Empate até o
  // sorteio deixa a posição pendente para o ADMIN escolher, e as seguintes esperam por ela
  // (4º e 5º sem semifinal: pedido do usuário em 21/11/2026, porque também pontuam).
  const provisoria = REGRAS_DA_CHAVE.terceiroSemSemifinal.provisorio;
  const totalDeEquipes = grupos.reduce((n, g) => n + g.equipes.length, 0);
  const ultimaPosicao = totalDeEquipes > REGRAS_DA_CHAVE.quartoEQuinto.equipesNaCompeticaoParaQuinto ? 5 : 4;
  const jaColocadas = new Set([final.equipe_1_id, final.equipe_2_id]);
  const comoSemSemifinal = (posicao, e) => {
    if (grupos.length === 1) return `${posicao}º lugar pela ordem do grupo (sem semifinal, vale a fase classificatória)`;
    if (posicao === 3 && e.posicao === 2) return `melhor 2º colocado (grupo ${e.grupo_nome}), sem semifinal e sem jogo de 3º lugar`;
    return `melhor campanha entre quem ainda não estava no pódio (grupo ${e.grupo_nome}), sem semifinal`;
  };

  for (let posicao = 3; posicao <= ultimaPosicao; posicao += 1) {
    const r = terceiroSemSemifinal(chave, jaColocadas);
    let equipe = r.equipe;

    if (!equipe && r.empatadas) {
      const nomes = r.empatadas.map((e) => e.escola_nome).join(', ');
      const escolhida = chave.escolhas?.get(posicao);
      const valida = r.empatadas.find((e) => e.equipe_id === escolhida);
      if (!valida) {
        pendentes.push({
          posicao,
          motivo: `empate em todos os critérios (sorteio) entre ${nomes}: o administrador escolhe o ${posicao}º lugar`
            + (escolhida ? '. A escolha gravada antes não vale mais (os resultados mudaram).' : ''),
          candidatas: r.empatadas.map((e) => ({
            equipe_id: e.equipe_id, escola_nome: e.escola_nome, grupo_nome: e.grupo_nome
          }))
        });
        break;
      }
      colocacoes.push({
        posicao,
        equipe_id: valida.equipe_id,
        escola_nome: valida.escola_nome,
        como: `escolhido pelo administrador (empate até o sorteio entre ${nomes})`,
        escolhida_pelo_admin: true,
        provisoria
      });
      jaColocadas.add(valida.equipe_id);
      continue;
    }

    if (!equipe) break;
    colocacoes.push({
      posicao,
      equipe_id: equipe.equipe_id,
      escola_nome: equipe.escola_nome,
      como: comoSemSemifinal(posicao, equipe),
      provisoria
    });
    jaColocadas.add(equipe.equipe_id);
  }

  return pronto();
};

const colocacoesFinais = (chave) => apurarColocacoes(chave).colocacoes;

// ---------------------------------------------------------------------------
// GET /api/matamata/competicao/:competicao_id
// ---------------------------------------------------------------------------
const chaveDaCompeticao = async (req, res) => {
  const id = Number(req.params.competicao_id);

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ erro: 'Identificador de competição inválido.' });
  }

  try {
    const chave = await montarChave(id);
    const { competicao, contexto, comparacoes, faseDeGrupos, todosOsJogos } = chave;

    const geracao = proximaGeracao(chave);
    const semifinais = jogosDaFase(todosOsJogos, 'SEMIFINAL');
    const finais = jogosDaFase(todosOsJogos, 'FINAL');

    // O previsto de cada fase, para a tela mostrar a chave antes de gerar
    const previsto = (fase, existentes) => {
      if (!temMataMata(competicao)) return null;
      if (existentes.length > 0) return { gerada: true, jogos: existentes };
      if (!faseDeGrupos.completa) return { gerada: false, jogos: [], pendente: true };

      const resultado = confrontosPrevistos(chave, fase);
      return {
        gerada: false,
        jogos: [],
        confrontos: resultado.confrontos || [],
        erro: resultado.erro || null,
        observacao: resultado.observacao || null,
        regra: resultado.regra || null
      };
    };

    res.status(200).json({
      competicao: {
        id: competicao.id,
        modalidade_nome: competicao.modalidade_nome,
        modalidade_slug: competicao.modalidade_slug,
        categoria_nome: competicao.categoria_nome,
        genero: competicao.genero,
        tipo_placar: competicao.tipo_placar
      },
      formato: {
        qtd_grupos: competicao.qtd_grupos,
        classificados_por_grupo: competicao.classificados_por_grupo,
        melhores_segundos: competicao.melhores_segundos,
        proxima_fase: competicao.proxima_fase,
        turno: competicao.turno,
        tem_mata_mata: temMataMata(competicao)
      },
      fase_de_grupos: faseDeGrupos,
      vagas_cadastradas: chave.vagasCadastradas,
      classificados: contexto.classificadosPorGrupo,
      melhores_segundos: contexto.melhoresSegundos.map((e) => ({
        equipe_id: e.equipe_id,
        escola_nome: e.escola_nome,
        grupo_nome: e.grupo_nome,
        pontos: e.pontos,
        saldo: e.saldo,
        jogos: e.jogos
      })),
      // Como a comparação entre grupos foi feita: critérios normais da
      // modalidade, com todos os jogos (decisão de 06/10/2026). Os segundos só
      // são comparados quando isso decide alguma coisa — o melhor segundo, ou
      // o 3º lugar sem semifinal —, e só então o aviso de jogos diferentes vale.
      comparacao_entre_grupos: comparacoes.segundos
        ? {
          jogos_por_equipe: comparacoes.segundos.jogos_por_equipe,
          aviso_jogos_diferentes:
            comparacoes.segundos.jogos_diferentes
            && (competicao.melhores_segundos > 0 || competicao.proxima_fase === 'FINAL')
              ? avisoJogosDiferentes(comparacoes.segundos.jogos_por_equipe)
              : null,
          ordem_dos_primeiros: (comparacoes.primeiros?.ordenadas || []).map((e) => ({
            equipe_id: e.equipe_id, escola_nome: e.escola_nome, grupo_nome: e.grupo_nome
          })),
          ordem_dos_segundos: (comparacoes.segundos.ordenadas || []).map((e) => ({
            equipe_id: e.equipe_id, escola_nome: e.escola_nome, grupo_nome: e.grupo_nome
          }))
        }
        : null,
      chave: {
        semifinal: competicao.proxima_fase === 'SEMIFINAL' ? previsto('SEMIFINAL', semifinais) : null,
        final: previsto('FINAL', finais)
      },
      ...(() => {
        const { colocacoes, pendentes } = apurarColocacoes(chave);
        return { colocacoes, colocacoes_pendentes: pendentes };
      })(),
      pode_gerar: geracao
    });
  } catch (erro) {
    if (erro instanceof ErroDeRegra) {
      return res.status(erro.status).json({ erro: erro.message });
    }
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao montar a chave do mata-mata.' });
  }
};

// ---------------------------------------------------------------------------
// POST /api/matamata/competicao/:competicao_id/gerar — só ADMIN
// ---------------------------------------------------------------------------
// Gera os jogos da próxima fase (semifinal ou final), com os confrontos que a
// chave manda. O que decide quem pega quem é src/config/chavesMataMata.js;
// aqui só se grava o resultado dessa decisão.
const gerarFase = async (req, res) => {
  const id = Number(req.params.competicao_id);

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ erro: 'Identificador de competição inválido.' });
  }

  let conexao;
  try {
    conexao = await db.getConnection();
    await conexao.beginTransaction();

    // Trava a competição: sem isso, dois cliques no botão gerariam a fase duas
    // vezes, cada um lendo o mesmo "ainda não existe".
    const [[existe]] = await conexao.query(
      'SELECT id FROM competicoes WHERE id = ? FOR UPDATE',
      [id]
    );

    if (!existe) {
      await conexao.rollback();
      return res.status(404).json({ erro: 'Competição não encontrada.' });
    }

    const chave = await montarChave(id);
    const geracao = proximaGeracao(chave);

    if (!geracao.fase) {
      await conexao.rollback();
      return res.status(409).json({ erro: geracao.motivo });
    }

    const previsto = confrontosPrevistos(chave, geracao.fase);

    if (previsto.erro) {
      await conexao.rollback();
      return res.status(422).json({ erro: previsto.erro });
    }

    const [[{ proximo }]] = await conexao.query(
      'SELECT COALESCE(MAX(numero_jogo), 0) + 1 AS proximo FROM jogos WHERE competicao_id = ?',
      [id]
    );

    const criados = [];
    let numero = proximo;

    for (const confronto of previsto.confrontos) {
      const [resultado] = await conexao.query(
        `INSERT INTO jogos (competicao_id, numero_jogo, fase, equipe_1_id, equipe_2_id)
         VALUES (?, ?, ?, ?, ?)`,
        [id, numero, geracao.fase, confronto.equipe_1_id, confronto.equipe_2_id]
      );

      criados.push({
        jogo_id: resultado.insertId,
        numero_jogo: numero,
        fase: geracao.fase,
        rotulo: confronto.rotulo,
        equipe_1: confronto.equipe_1,
        equipe_2: confronto.equipe_2
      });

      numero += 1;
    }

    await conexao.commit();

    res.status(201).json({
      mensagem: geracao.fase === 'SEMIFINAL'
        ? 'Semifinais geradas. Agende data e local pela tabela de jogos.'
        : 'Final gerada. Agende data e local pela tabela de jogos.',
      fase: geracao.fase,
      jogos: criados,
      observacao: previsto.observacao || null,
      // A tela avisa quando o cruzamento usado ainda é provisório
      regra: previsto.regra || null
    });
  } catch (erro) {
    if (conexao) await conexao.rollback();

    if (erro instanceof ErroDeRegra) {
      return res.status(erro.status).json({ erro: erro.message });
    }

    console.error(erro);
    res.status(500).json({ erro: 'Erro ao gerar a fase do mata-mata.' });
  } finally {
    if (conexao) conexao.release();
  }
};

// ---------------------------------------------------------------------------
// DELETE /api/matamata/competicao/:competicao_id/:fase — só ADMIN
// ---------------------------------------------------------------------------
// Desfaz uma geração — e só enquanto ela não valeu nada ainda. Qualquer jogo
// finalizado, por W.O. ou com súmula lançada tranca o desfazer: apagar aí
// levaria junto o resultado, pelo CASCADE, sem ninguém perceber.
const desfazerFase = async (req, res) => {
  const id = Number(req.params.competicao_id);
  const fase = String(req.params.fase || '').toUpperCase();

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ erro: 'Identificador de competição inválido.' });
  }

  if (!['SEMIFINAL', 'FINAL'].includes(fase)) {
    return res.status(400).json({ erro: 'A fase a desfazer é SEMIFINAL ou FINAL.' });
  }

  const [[{ comVagas }]] = await db.query(
    `SELECT COUNT(*) AS comVagas FROM jogo_vagas v INNER JOIN jogos j ON j.id = v.jogo_id
      WHERE j.competicao_id = ?`,
    [id]
  );
  if (Number(comVagas) > 0) {
    return res.status(409).json({
      erro: 'Os jogos do mata-mata desta competição vêm da tabela do chefe e não se desfazem por aqui. '
        + 'Para trocar uma equipe, use a troca de vaga do jogo.'
    });
  }

  let conexao;
  try {
    conexao = await db.getConnection();
    await conexao.beginTransaction();

    const [jogos] = await conexao.query(
      `SELECT id, numero_jogo, status FROM jogos
        WHERE competicao_id = ? AND fase = ?
        FOR UPDATE`,
      [id, fase]
    );

    if (jogos.length === 0) {
      await conexao.rollback();
      return res.status(404).json({
        erro: fase === 'SEMIFINAL'
          ? 'Esta competição não tem semifinais geradas.'
          : 'Esta competição não tem final gerada.'
      });
    }

    const encerrados = jogos.filter((j) => ['FINALIZADO', 'WO'].includes(j.status));

    if (encerrados.length > 0) {
      await conexao.rollback();
      return res.status(409).json({
        erro: `Não dá para desfazer: ${encerrados.length === 1 ? 'o jogo' : 'os jogos'} `
          + `${encerrados.map((j) => '#' + j.numero_jogo).join(', ')} já `
          + `${encerrados.length === 1 ? 'tem resultado' : 'têm resultado'}. `
          + 'Reabra e limpe a súmula antes, se for mesmo para refazer a chave.'
      });
    }

    // A final nasce das semifinais: apagar as semifinais deixaria a final órfã
    if (fase === 'SEMIFINAL') {
      const [[{ finais }]] = await conexao.query(
        "SELECT COUNT(*) AS finais FROM jogos WHERE competicao_id = ? AND fase = 'FINAL'",
        [id]
      );

      if (finais > 0) {
        await conexao.rollback();
        return res.status(409).json({
          erro: 'A final já foi gerada a partir destas semifinais. Desfaça a final primeiro.'
        });
      }
    }

    const ids = jogos.map((j) => j.id);

    const [[{ lancamentos }]] = await conexao.query(
      'SELECT COUNT(*) AS lancamentos FROM sumula_atletas WHERE jogo_id IN (?)',
      [ids]
    );

    if (lancamentos > 0) {
      await conexao.rollback();
      return res.status(409).json({
        erro: 'Há súmula lançada nestes jogos. Limpe os lançamentos antes de desfazer a chave.'
      });
    }

    await conexao.query('DELETE FROM sumula_equipes WHERE jogo_id IN (?)', [ids]);
    await conexao.query('DELETE FROM jogo_sets WHERE jogo_id IN (?)', [ids]);
    await conexao.query('DELETE FROM jogos WHERE id IN (?)', [ids]);

    // Mesma renumeração do excluirJogo: a numeração é por competição e não
    // pode ficar com buracos. Ordem ascendente para não colidir com o índice.
    const menor = Math.min(...jogos.map((j) => j.numero_jogo));
    const [renumerados] = await conexao.query(
      `UPDATE jogos SET numero_jogo = numero_jogo - ?
        WHERE competicao_id = ? AND numero_jogo > ?
        ORDER BY numero_jogo ASC`,
      [jogos.length, id, menor]
    );

    await conexao.commit();

    res.status(200).json({
      mensagem: fase === 'SEMIFINAL' ? 'Semifinais desfeitas.' : 'Final desfeita.',
      fase,
      jogos_removidos: jogos.length,
      jogos_renumerados: renumerados.affectedRows
    });
  } catch (erro) {
    if (conexao) await conexao.rollback();
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao desfazer a fase do mata-mata.' });
  } finally {
    if (conexao) conexao.release();
  }
};

// ---------------------------------------------------------------------------
// POST /api/matamata/competicao/:competicao_id/recalcular-vagas — só ADMIN
// POST /api/matamata/recalcular-vagas — só ADMIN, todas as competições
// ---------------------------------------------------------------------------
// Preenche as vagas dos jogos de mata-mata cadastrados pela tabela do chefe
// (jogo_vagas): classificados quando o grupo fecha, vencedor quando o jogo
// termina. É o mesmo cálculo que roda sozinho ao encerrar a súmula. Vaga trocada
// à mão não é tocada, e jogo iniciado ou encerrado só vira aviso.
const recalcularVagas = async (req, res) => {
  const id = Number(req.params.competicao_id);

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ erro: 'Identificador de competição inválido.' });
  }

  try {
    const resultado = await resolverVagas(id);
    res.status(200).json({ mensagem: 'Vagas recalculadas.', ...resultado });
  } catch (erro) {
    if (erro instanceof ErroDeVaga) return res.status(erro.status).json({ erro: erro.message });
    console.error('Erro ao recalcular as vagas:', erro);
    res.status(500).json({ erro: 'Erro ao recalcular as vagas do mata-mata.' });
  }
};

const recalcularVagasDeTodas = async (req, res) => {
  try {
    const resultados = await resolverVagasDeTodas();
    res.status(200).json({
      mensagem: 'Vagas recalculadas em todas as competições.',
      competicoes: resultados.length,
      preenchidas: resultados.reduce((s, r) => s + r.preenchidas, 0),
      limpas: resultados.reduce((s, r) => s + r.limpas, 0),
      avisos: resultados.flatMap((r) => r.avisos.map((x) => ({ competicao_id: r.competicao_id, ...x })))
    });
  } catch (erro) {
    console.error('Erro ao recalcular as vagas:', erro);
    res.status(500).json({ erro: 'Erro ao recalcular as vagas do mata-mata.' });
  }
};

// ---------------------------------------------------------------------------
// PUT /api/matamata/competicao/:competicao_id/colocacao — só ADMIN (16/11/2026)
// ---------------------------------------------------------------------------
// Posição de pódio empatada até o sorteio: o ADMIN grava a equipe sorteada
// ({ posicao, equipe_id }) ou desfaz a escolha ({ posicao, equipe_id: null }).
// Só vale enquanto a posição estiver de fato empatada, e só entre as candidatas.
const definirColocacao = async (req, res) => {
  const id = Number(req.params.competicao_id);
  const posicao = Number(req.body.posicao);
  const equipeId = req.body.equipe_id === null || req.body.equipe_id === undefined ? null : Number(req.body.equipe_id);

  if (!Number.isInteger(id) || id <= 0) return res.status(400).json({ erro: 'Identificador de competição inválido.' });
  if (!Number.isInteger(posicao) || posicao < 1 || posicao > 5) return res.status(400).json({ erro: 'Informe a posição (1 a 5).' });

  try {
    if (equipeId === null) {
      await db.query('DELETE FROM colocacoes_finais WHERE competicao_id = ? AND posicao = ?', [id, posicao]);
      return res.status(200).json({ mensagem: `Escolha do ${posicao}º lugar desfeita.` });
    }

    const chave = await montarChave(id);
    // A conta sem a escolha gravada DESTA posição (o que está empatado de verdade). As escolhas
    // das posições de cima ficam: sem elas o 4º e o 5º sem semifinal nem chegam a ser apurados.
    chave.escolhas = new Map([...(chave.escolhas || new Map())].filter(([p]) => p !== posicao));
    const { pendentes } = apurarColocacoes(chave);
    const pendente = pendentes.find((p) => p.posicao === posicao);
    if (!pendente) {
      return res.status(409).json({ erro: `O ${posicao}º lugar desta competição não está empatado até o sorteio: ele sai dos resultados.` });
    }
    const candidata = pendente.candidatas.find((c) => c.equipe_id === equipeId);
    if (!candidata) {
      return res.status(400).json({ erro: `Escolha uma das equipes empatadas: ${pendente.candidatas.map((c) => c.escola_nome).join(', ')}.` });
    }

    const conexao = await db.getConnection();
    try {
      await conexao.beginTransaction();
      await conexao.query('DELETE FROM colocacoes_finais WHERE competicao_id = ? AND (posicao = ? OR equipe_id = ?)', [id, posicao, equipeId]);
      await conexao.query('INSERT INTO colocacoes_finais (competicao_id, equipe_id, posicao) VALUES (?, ?, ?)', [id, equipeId, posicao]);
      await conexao.commit();
    } catch (erro) {
      await conexao.rollback();
      throw erro;
    } finally {
      conexao.release();
    }

    res.status(200).json({ mensagem: `${posicao}º lugar: ${candidata.escola_nome} (escolha do administrador).` });
  } catch (erro) {
    if (erro instanceof ErroDeRegra) return res.status(erro.status).json({ erro: erro.message });
    console.error('Erro ao definir a colocação:', erro);
    res.status(500).json({ erro: 'Erro ao definir a colocação.' });
  }
};

module.exports = {
  chaveDaCompeticao,
  definirColocacao,
  apurarColocacoes,
  gerarFase,
  desfazerFase,
  recalcularVagas,
  recalcularVagasDeTodas,
  // Reaproveitados pelos testes e pela tela
  montarChave,
  proximaGeracao,
  confrontosPrevistos,
  colocacoesFinais,
  vencedoresDaSemifinal
};
