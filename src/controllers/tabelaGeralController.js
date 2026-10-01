const db = require('../config/db');
const { montarChave, colocacoesFinais } = require('./mataMataController');
const { ErroDeRegra } = require('./classificacaoController');
const { REGRAS } = require('../config/regrasProvisorias');
const { BLOCOS, blocoDaCategoria, blocosNaOrdem } = require('../config/blocosTabelaGeral');

// ============================================================================
// TABELA GERAL — a soma das colocações de cada competição, por escola.
//
// Como a classificação e as colocações, nada é guardado: tudo sai dos jogos.
// Corrigir uma súmula corrige a tabela geral no mesmo instante. A tabela
// `colocacoes_finais` do schema segue sem uso — ela só faz sentido se um dia
// o chefe quiser congelar o resultado de uma competição encerrada.
//
// As decisões que o regulamento não fecha estão em config, não aqui:
//   - quais categorias formam cada bloco -> src/config/blocosTabelaGeral.js
//   - o resto (posições que pontuam, mínimo de equipes, desempate, punição)
//     -> src/config/regrasProvisorias.js, chave `tabelaGeral`.
// ============================================================================

const REGRA = REGRAS.tabelaGeral;

const PONTOS_POR_POSICAO = new Map();

const carregarPontuacao = async () => {
  if (PONTOS_POR_POSICAO.size > 0) return PONTOS_POR_POSICAO;

  const [linhas] = await db.query('SELECT posicao, pontos FROM pontuacao_geral');
  for (const linha of linhas) PONTOS_POR_POSICAO.set(linha.posicao, linha.pontos);
  return PONTOS_POR_POSICAO;
};

// Uma linha da tabela, por escola
const linhaDaEscola = (escola_id, escola_nome) => ({
  escola_id,
  escola_nome,
  pontos: 0,
  primeiros: 0,
  segundos: 0,
  terceiros: 0,
  // De onde veio cada ponto: é o que a escola confere
  origens: []
});

const somar = (mapa, escola_id, escola_nome) => {
  if (!mapa.has(escola_id)) mapa.set(escola_id, linhaDaEscola(escola_id, escola_nome));
  return mapa.get(escola_id);
};

// Mais pontos; empatando, mais primeiros, depois segundos, depois terceiros;
// e, no fim, ordem alfabética para a lista não dançar a cada carregamento.
const ordenar = (linhas) => [...linhas].sort((a, b) =>
  b.pontos - a.pontos
  || b.primeiros - a.primeiros
  || b.segundos - a.segundos
  || b.terceiros - a.terceiros
  || a.escola_nome.localeCompare(b.escola_nome, 'pt-BR'));

const posicionar = (linhas) => {
  const ordenadas = ordenar(linhas);

  // Empate de verdade divide a mesma posição
  ordenadas.forEach((linha, indice) => {
    const anterior = ordenadas[indice - 1];
    const empatou = anterior
      && anterior.pontos === linha.pontos
      && anterior.primeiros === linha.primeiros
      && anterior.segundos === linha.segundos
      && anterior.terceiros === linha.terceiros;

    linha.posicao = empatou ? anterior.posicao : indice + 1;
  });

  return ordenadas;
};

// ---------------------------------------------------------------------------
// GET /api/tabela-geral
// ---------------------------------------------------------------------------
const tabelaGeral = async (req, res) => {
  try {
    const pontuacao = await carregarPontuacao();

    const [competicoes] = await db.query(
      `SELECT c.id, c.genero,
              m.nome AS modalidade_nome, m.slug AS modalidade_slug, m.tipo AS modalidade_tipo,
              cat.nome AS categoria_nome,
              (SELECT COUNT(*) FROM equipes e WHERE e.competicao_id = c.id) AS total_equipes
         FROM competicoes c
         INNER JOIN modalidades m ON m.id = c.modalidade_id
         INNER JOIN categorias cat ON cat.id = c.categoria_id
        ORDER BY m.nome, cat.idade_maxima IS NULL, cat.idade_maxima, c.genero`
    );

    // escola -> linha, por bloco; e a soma de todos os blocos
    const porBloco = new Map();
    const geral = new Map();

    const encerradas = [];
    const semPontuar = [];

    for (const competicao of competicoes) {
      if (competicao.modalidade_tipo !== 'COLETIVO' && !REGRA.incluiAtletismo) {
        semPontuar.push({ ...competicao, motivo: 'modalidade individual, fora desta conta' });
        continue;
      }

      // Regulamento: competição com uma só inscrição não pontua nem premia
      if (competicao.total_equipes < REGRA.minimoDeEquipes) {
        semPontuar.push({ ...competicao, motivo: 'tem menos de duas equipes inscritas' });
        continue;
      }

      const chave = await montarChave(competicao.id);
      const colocacoes = colocacoesFinais(chave);

      if (colocacoes.length === 0) {
        semPontuar.push({ ...competicao, motivo: 'ainda não tem campeão definido' });
        continue;
      }

      const bloco = blocoDaCategoria(competicao.categoria_nome);
      if (!porBloco.has(bloco.etapa)) porBloco.set(bloco.etapa, { ...bloco, escolas: new Map() });
      const doBloco = porBloco.get(bloco.etapa).escolas;

      // Escola de cada equipe colocada
      const equipesDaCompeticao = new Map();
      for (const grupo of chave.grupos) {
        for (const equipe of grupo.equipes) {
          equipesDaCompeticao.set(equipe.equipe_id, equipe);
        }
      }

      const premiadas = [];

      for (const colocacao of colocacoes) {
        // 4º e 5º continuam sem regra: hoje só 1º, 2º e 3º pontuam
        if (!REGRA.posicoesQuePontuam.includes(colocacao.posicao)) continue;

        const equipe = equipesDaCompeticao.get(colocacao.equipe_id);
        if (!equipe) continue;

        const pontos = pontuacao.get(colocacao.posicao) ?? 0;
        const origem = {
          competicao_id: competicao.id,
          modalidade_nome: competicao.modalidade_nome,
          categoria_nome: competicao.categoria_nome,
          genero: competicao.genero,
          posicao: colocacao.posicao,
          pontos
        };

        for (const alvo of [somar(doBloco, equipe.escola_id, equipe.escola_nome),
          somar(geral, equipe.escola_id, equipe.escola_nome)]) {
          alvo.pontos += pontos;
          alvo.origens.push(origem);
          if (colocacao.posicao === 1) alvo.primeiros += 1;
          if (colocacao.posicao === 2) alvo.segundos += 1;
          if (colocacao.posicao === 3) alvo.terceiros += 1;
        }

        premiadas.push({ posicao: colocacao.posicao, escola_nome: equipe.escola_nome, pontos });
      }

      encerradas.push({
        competicao_id: competicao.id,
        modalidade_nome: competicao.modalidade_nome,
        categoria_nome: competicao.categoria_nome,
        genero: competicao.genero,
        bloco: bloco.etapa,
        premiadas
      });
    }

    // Punições da Comissão: descontam da soma geral, não de um bloco
    const [ajustes] = await db.query(
      `SELECT a.id, a.escola_id, a.pontos, a.motivo, a.criado_em,
              esc.nome AS escola_nome, u.nome AS usuario_nome
         FROM ajustes_pontos_geral a
         INNER JOIN escolas esc ON esc.id = a.escola_id
         LEFT JOIN usuarios u ON u.id = a.usuario_id
        ORDER BY a.criado_em DESC`
    );

    for (const ajuste of ajustes) {
      const linha = somar(geral, ajuste.escola_id, ajuste.escola_nome);
      linha.pontos += ajuste.pontos;
      linha.ajustes = (linha.ajustes || 0) + ajuste.pontos;
    }

    const blocos = blocosNaOrdem()
      .filter((bloco) => porBloco.has(bloco.etapa))
      .map((bloco) => ({
        etapa: bloco.etapa,
        ordem: bloco.ordem,
        escolas: posicionar([...porBloco.get(bloco.etapa).escolas.values()])
      }));

    res.status(200).json({
      blocos,
      geral: posicionar([...geral.values()]),
      ajustes,
      competicoes: {
        encerradas,
        sem_pontuar: semPontuar.map((c) => ({
          competicao_id: c.id,
          modalidade_nome: c.modalidade_nome,
          categoria_nome: c.categoria_nome,
          genero: c.genero,
          motivo: c.motivo
        }))
      },
      // O que a tela precisa dizer que ainda não é definitivo
      regras: {
        pontuacao: [...pontuacao.entries()]
          .map(([posicao, pontos]) => ({ posicao, pontos }))
          .sort((a, b) => a.posicao - b.posicao),
        posicoes_que_pontuam: REGRA.posicoesQuePontuam,
        provisoria: REGRA.provisorio,
        decidido_em: REGRA.decididoEm,
        blocos: {
          provisoria: BLOCOS.provisorio,
          decidido_em: BLOCOS.decididoEm,
          descricao: BLOCOS.descricao,
          por_bloco: BLOCOS.porBloco
        },
        // Lembrete de que 4º e 5º não entram: a regra não existe (pendência 5)
        posicoes_sem_regra: [...pontuacao.keys()]
          .filter((posicao) => !REGRA.posicoesQuePontuam.includes(posicao))
          .sort((a, b) => a - b)
      }
    });
  } catch (erro) {
    if (erro instanceof ErroDeRegra) {
      return res.status(erro.status).json({ erro: erro.message });
    }
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao montar a tabela geral.' });
  }
};

module.exports = { tabelaGeral };
