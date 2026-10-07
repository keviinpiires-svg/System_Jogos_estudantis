const db = require('../config/db');
const { montarChave, colocacoesFinais } = require('./mataMataController');
const { ErroDeRegra } = require('./classificacaoController');
const { REGRAS } = require('../config/regrasProvisorias');
const { REGRAS_DA_CHAVE } = require('../config/chavesMataMata');

// ============================================================================
// TABELA GERAL — a soma das colocações de cada competição, por escola.
//
// Como a classificação e as colocações, nada é guardado: tudo sai dos jogos.
// Corrigir uma súmula corrige a tabela geral no mesmo instante. A tabela
// `colocacoes_finais` do schema segue sem uso — ela só faz sentido se um dia
// o chefe quiser congelar o resultado de uma competição encerrada.
//
// Desde 06/10/2026 há só a soma geral: a divisão em três blocos (anos
// iniciais, anos finais e ensino médio) saiu por decisão do chefe.
//
// As decisões que o regulamento não fecha (posições que pontuam, mínimo de
// equipes, empate na soma, punição) estão em src/config/regrasProvisorias.js,
// chave `tabelaGeral`, e não aqui.
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

// Mais pontos; empatando, mais 1º lugares, depois 2º e 3º (chefe, 07/10/2026).
// A ordem alfabética entre empatadas em tudo só serve para a lista não dançar a
// cada carregamento, e não muda a posição de ninguém.
const ordenar = (linhas) => [...linhas].sort((a, b) =>
  b.pontos - a.pontos
  || REGRA.desempate.criterios.reduce((r, c) => r || (b[c] || 0) - (a[c] || 0), 0)
  || a.escola_nome.localeCompare(b.escola_nome, 'pt-BR'));

const empatadasEmTudo = (a, b) => a.pontos === b.pontos
  && REGRA.desempate.criterios.every((c) => (a[c] || 0) === (b[c] || 0));

// Mesma soma: desempata por mais 1ºs, 2ºs e 3ºs (REGRA.desempate). Empatadas
// em tudo dividem a posição, com numeração de competição: 1, 1, 3.
const posicionar = (linhas) => {
  const ordenadas = ordenar(linhas);

  ordenadas.forEach((linha, indice) => {
    const anterior = ordenadas[indice - 1];
    linha.posicao = anterior && empatadasEmTudo(anterior, linha) ? anterior.posicao : indice + 1;
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

    // escola -> linha da soma geral
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

      // Escola de cada equipe colocada
      const equipesDaCompeticao = new Map();
      for (const grupo of chave.grupos) {
        for (const equipe of grupo.equipes) {
          equipesDaCompeticao.set(equipe.equipe_id, equipe);
        }
      }

      const premiadas = [];

      for (const colocacao of colocacoes) {
        // Posição fora da pontuação não entra (hoje pontuam do 1º ao 5º)
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
          pontos,
          // 4º e 5º saem de uma regra provisória: a tela marca esses pontos
          provisoria: Boolean(colocacao.provisoria)
        };

        const linha = somar(geral, equipe.escola_id, equipe.escola_nome);
        linha.pontos += pontos;
        linha.origens.push(origem);
        // As medalhas desempatam a soma (REGRA.desempate)
        if (colocacao.posicao === 1) linha.primeiros += 1;
        if (colocacao.posicao === 2) linha.segundos += 1;
        if (colocacao.posicao === 3) linha.terceiros += 1;

        premiadas.push({ posicao: colocacao.posicao, escola_nome: equipe.escola_nome, pontos });
      }

      encerradas.push({
        competicao_id: competicao.id,
        modalidade_nome: competicao.modalidade_nome,
        categoria_nome: competicao.categoria_nome,
        genero: competicao.genero,
        premiadas
      });
    }

    // Punições da Comissão: descontam da soma geral da escola
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

    res.status(200).json({
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
        // Mesma soma, mesma posição (1, 1, 3): sem critério de desempate
        // Como a mesma soma se desempata: a tela mostra o critério
        desempate: REGRA.desempate,
        // Posições da pontuação que não entram na conta (hoje, nenhuma)
        posicoes_sem_regra: [...pontuacao.keys()]
          .filter((posicao) => !REGRA.posicoesQuePontuam.includes(posicao))
          .sort((a, b) => a - b),
        // 4º e 5º entram, mas pela regra provisória (pendência 5): a tela avisa
        posicoes_provisorias: {
          posicoes: REGRA.posicoesProvisorias,
          descricao: REGRAS_DA_CHAVE.quartoEQuinto.descricao,
          decidido_em: REGRAS_DA_CHAVE.quartoEQuinto.decididoEm
        }
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

// posicionar sai também para o teste de fumaça conferir o empate (1, 1, 3)
module.exports = { tabelaGeral, posicionar };
