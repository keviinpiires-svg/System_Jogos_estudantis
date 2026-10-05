const db = require('../config/db');
const {
  montarClassificacao, compararEntreGrupos, vencedorDoJogo, ErroDeRegra
} = require('./classificacaoController');
const {
  REGRAS_DA_CHAVE, chaveDaSemifinal, chaveDaFinal, temMataMata
} = require('../config/chavesMataMata');

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
    `SELECT j.id, j.numero_jogo, j.fase, j.status, j.data_hora, j.rodada,
            j.equipe_1_id, j.equipe_2_id, j.placar_1, j.placar_2,
            j.penaltis_1, j.penaltis_2, j.vencedor_equipe_id,
            e1.escola_id AS escola_1_id, esc1.nome AS escola_1_nome,
            e2.escola_id AS escola_2_id, esc2.nome AS escola_2_nome,
            j.local_id, l.nome AS local_nome
       FROM jogos j
       INNER JOIN equipes e1 ON e1.id = j.equipe_1_id
       INNER JOIN escolas esc1 ON esc1.id = e1.escola_id
       INNER JOIN equipes e2 ON e2.id = j.equipe_2_id
       INNER JOIN escolas esc2 ON esc2.id = e2.escola_id
       LEFT JOIN locais_disputa l ON l.id = j.local_id
      WHERE j.competicao_id = ?
      ORDER BY j.fase, j.numero_jogo`,
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
    melhoresSegundos: segundos ? segundos.ordenadas.slice(0, competicao.melhores_segundos) : [],
    primeirosOrdenados: primeiros ? primeiros.ordenadas : []
  };

  return {
    ...dados,
    todosOsJogos,
    jogosDeGrupos: jogos,
    faseDeGrupos,
    contexto,
    comparacoes: { primeiros, segundos }
  };
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
// Colocações finais — calculadas, nunca gravadas
// ---------------------------------------------------------------------------
// Regulamento: NÃO existe jogo de 3º lugar. Com semifinal, o 3º é quem perdeu
// a semifinal PARA O CAMPEÃO. Sem semifinal, vale a fase classificatória:
// o 3º do grupo único ou, com dois grupos, o melhor dos dois segundos
// (REGRAS_DA_CHAVE.terceiroSemSemifinal, decisão provisória de 30/09/2026).
const colocacoesFinais = (chave) => {
  const { competicao, todosOsJogos, grupos, comparacoes, faseDeGrupos } = chave;
  const colocacoes = [];

  const nomeDaEquipe = (equipe_id) => {
    for (const grupo of grupos) {
      const equipe = grupo.equipes.find((e) => e.equipe_id === equipe_id);
      if (equipe) return equipe.escola_nome;
    }
    return '';
  };

  // Competição sem mata-mata: campeão pela soma dos dois jogos
  if (!temMataMata(competicao)) {
    if (!faseDeGrupos.completa) return [];

    const [grupo] = grupos;
    if (!grupo || grupo.equipes.length < 2) return [];

    const [primeiro, segundo] = grupo.equipes;
    const somaEmpatada = primeiro.pontos === segundo.pontos && primeiro.saldo === segundo.saldo;
    // Empatada a soma, o título sai das cobranças do último jogo
    const ultimo = jogosDaFase(todosOsJogos, 'GRUPOS').slice(-1)[0];
    const porCobranca = somaEmpatada && ultimo?.vencedor_equipe_id
      ? ultimo.vencedor_equipe_id
      : null;

    if (somaEmpatada && !porCobranca) {
      return [];
    }

    const campeao = porCobranca || primeiro.equipe_id;
    const vice = campeao === primeiro.equipe_id ? segundo.equipe_id : primeiro.equipe_id;

    return [
      {
        posicao: 1,
        equipe_id: campeao,
        escola_nome: nomeDaEquipe(campeao),
        como: porCobranca
          ? 'campeão nas cobranças, com a soma dos dois jogos empatada'
          : 'campeão pela soma dos dois jogos'
      },
      { posicao: 2, equipe_id: vice, escola_nome: nomeDaEquipe(vice), como: 'vice' }
    ];
  }

  const finais = jogosDaFase(todosOsJogos, 'FINAL');
  const final = finais.find(decidido);

  if (!final) return [];

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

    return colocacoes;
  }

  // Sem semifinal: o 3º vem da fase classificatória
  if (grupos.length === 1) {
    const terceiro = grupos[0].equipes[2];
    if (terceiro) {
      colocacoes.push({
        posicao: 3,
        equipe_id: terceiro.equipe_id,
        escola_nome: terceiro.escola_nome,
        como: '3º do grupo (sem semifinal, vale a fase classificatória)',
        provisoria: REGRAS_DA_CHAVE.terceiroSemSemifinal.provisorio
      });
    }
    return colocacoes;
  }

  const melhorSegundo = comparacoes.segundos?.ordenadas?.[0];

  if (melhorSegundo) {
    colocacoes.push({
      posicao: 3,
      equipe_id: melhorSegundo.equipe_id,
      escola_nome: melhorSegundo.escola_nome,
      como: `melhor 2º colocado (grupo ${melhorSegundo.grupo_nome}), `
        + 'sem semifinal e sem jogo de 3º lugar',
      provisoria: REGRAS_DA_CHAVE.terceiroSemSemifinal.provisorio
    });
  }

  return colocacoes;
};

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
      classificados: contexto.classificadosPorGrupo,
      melhores_segundos: contexto.melhoresSegundos.map((e) => ({
        equipe_id: e.equipe_id,
        escola_nome: e.escola_nome,
        grupo_nome: e.grupo_nome,
        pontos: e.pontos,
        saldo: e.saldo,
        jogos: e.jogos
      })),
      // Como a comparação entre grupos foi feita — a regra é provisória
      comparacao_entre_grupos: comparacoes.segundos
        ? {
          jogos_descartados: comparacoes.segundos.jogos_descartados,
          equipes_descartadas: comparacoes.segundos.descartadas,
          provisoria: comparacoes.segundos.provisoria,
          decidido_em: comparacoes.segundos.decididoEm,
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
      colocacoes: colocacoesFinais(chave),
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

module.exports = {
  chaveDaCompeticao,
  gerarFase,
  desfazerFase,
  // Reaproveitados pelos testes e pela tela
  montarChave,
  proximaGeracao,
  confrontosPrevistos,
  colocacoesFinais,
  vencedoresDaSemifinal
};
