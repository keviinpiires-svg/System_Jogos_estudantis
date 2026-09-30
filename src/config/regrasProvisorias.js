// ============================================================================
// REGRAS PROVISÓRIAS — decididas em 30/09/2026, sujeitas à revisão do chefe.
//
// ESTE É O ÚNICO LUGAR onde essas regras vivem. Tudo o que o regulamento não
// resolve e foi decidido por nós está aqui, num objeto só. Para mudar uma
// regra, mude este arquivo: nenhum controller tem cópia dela.
//
// Cada entrada diz o que foi decidido, por quê, e ONDE o sistema a consome.
// Ao confirmar (ou trocar) uma regra com o chefe, troque `provisorio` para
// false e atualize a data — e o aviso some das telas.
//
// Registrado também em docs/CONTEXTO_NOVO_ESCOPO.md (seção 12) e em
// docs/CONFERENCIA_COMPETICOES.md, nos dois repositórios.
// ============================================================================

const DECIDIDO_EM = '30/09/2026';

const REGRAS = {
  // --------------------------------------------------------------------
  // 1. "Melhor segundo" quando os grupos têm tamanhos diferentes
  // --------------------------------------------------------------------
  // Um segundo colocado de um grupo de 4 jogou mais partidas que o de um
  // grupo de 3, então somar pontos brutos favorece quem jogou mais.
  // Decisão: comparar só os jogos que todos teriam em comum — ou seja,
  // DESCARTAR os jogos contra o último colocado dos grupos maiores.
  melhorSegundo: {
    provisorio: true,
    decididoEm: DECIDIDO_EM,
    criterio: 'DESCARTAR_JOGOS_CONTRA_ULTIMO',
    descricao:
      'Com grupos de tamanhos diferentes, os segundos colocados são comparados '
      + 'descartando os jogos contra o último colocado dos grupos maiores, '
      + 'para que todos sejam medidos pelo mesmo número de partidas.',
    // Consumido em: src/controllers/classificacaoController.js (aviso na tela)
    // e, quando existir, na geração da semifinal (fatia 7 — mata-mata
    // configurável). Hoje a regra está registrada mas ainda não há semifinal
    // automática que a aplique.
    aplicadoEm: 'fatia 7 — mata-mata configurável (ainda não implementada)'
  },

  // --------------------------------------------------------------------
  // 2. Empate no mata-mata: como cada modalidade decide
  // --------------------------------------------------------------------
  // O regulamento escreve pênaltis 3x1x1 para futsal e society, e
  // "prorrogação" para basquete e handebol — sem dizer o que fazer se a
  // prorrogação também empatar.
  // Decisão: segunda prorrogação e, persistindo, cobranças —
  // 7 metros no handebol, lances livres no basquete.
  desempateMataMata: {
    provisorio: true,
    decididoEm: DECIDIDO_EM,
    // A chave é o slug da modalidade (modalidades.slug)
    porModalidade: {
      futsal: { sequencia: ['PENALTIS'], nomeCobranca: 'pênaltis (3x1x1)' },
      'futebol-society': { sequencia: ['PENALTIS'], nomeCobranca: 'pênaltis (3x1x1)' },
      handebol: {
        sequencia: ['PRORROGACAO', 'PRORROGACAO', 'PENALTIS'],
        nomeCobranca: 'tiros de 7 metros'
      },
      basquete: {
        sequencia: ['PRORROGACAO', 'PRORROGACAO', 'PENALTIS'],
        nomeCobranca: 'lances livres'
      },
      // Vôlei não empata: o jogo acaba quando alguém faz 2 sets.
      volei: { sequencia: [], nomeCobranca: null },
      // Baleado: sem regra escrita para empate no mata-mata [PENDENTE]
      baleado: { sequencia: ['PENALTIS'], nomeCobranca: 'cobranças de desempate' }
    },
    // Consumido em: src/controllers/sumulaController.js, ao finalizar uma
    // súmula empatada fora da fase de grupos.
    aplicadoEm: 'sumulaController.registrarSumula'
  },

  // --------------------------------------------------------------------
  // 3. Placar de um W.O.
  // --------------------------------------------------------------------
  // O regulamento diz que o time ausente perde, mas não diz por quanto.
  // Decisão: 1x0, e o administrador pode editar na hora de declarar.
  wo: {
    provisorio: true,
    decididoEm: DECIDIDO_EM,
    placarVencedor: 1,
    placarPerdedor: 0,
    editavel: true,
    descricao: 'W.O. vale 1x0 por padrão; o ADMIN pode informar outro placar.',
    // Consumido em: src/controllers/jogoController.js (declararWO) e na tela
    // TabelaJogos.jsx, que já abre o painel com o placar sugerido.
    aplicadoEm: 'jogoController.declararWO'
  },

  // --------------------------------------------------------------------
  // 4. Súmula do baleado
  // --------------------------------------------------------------------
  // Não veio folha oficial do baleado entre os modelos.
  // Decisão: usar a folha do futsal, trocando a coluna de gols por
  // ELIMINAÇÕES por atleta. O placar do jogo é a soma das eliminações,
  // que é o que sumula_atletas.gols guarda quando tipo_placar = ELIMINADOS.
  baleado: {
    provisorio: true,
    decididoEm: DECIDIDO_EM,
    folhaBaseadaEm: 'futsal',
    colunaDoAtleta: 'eliminacoes',
    descricao:
      'A folha do baleado segue o desenho da do futsal, com uma coluna de '
      + 'eliminações por atleta no lugar dos gols — 14 caixas, uma por '
      + 'adversário possível — e sem as faltas acumuladas do rodapé, que o '
      + 'baleado não usa.',
    aplicadoEm: 'DetalhesSumula.jsx (impressão) e PreencherSumula.jsx'
  },

  // --------------------------------------------------------------------
  // 5. Formato do Handebol Masculino Aberto
  // --------------------------------------------------------------------
  // A tabela de grupos trazia "melhor de dois jogos" com TRÊS equipes, o que
  // não fecha. Decisão: todos contra todos em turno único; 1º e 2º à final.
  // Isto é DADO, não código: mora na linha da competição.
  handebolMasculinoAberto: {
    provisorio: true,
    decididoEm: DECIDIDO_EM,
    formato: 'todos contra todos em turno único; 1º e 2º vão à final',
    // Aplicado por script versionado, não em tempo de execução
    aplicadoEm: 'db/06_ajustes_regras_provisorios.sql'
  }
};

// Atalho usado pelos controllers: o desempate da modalidade, já com um padrão
// seguro para modalidade que ninguém previu.
const desempateDaModalidade = (slug) =>
  REGRAS.desempateMataMata.porModalidade[slug]
  || { sequencia: ['PENALTIS'], nomeCobranca: 'cobranças de desempate' };

// Lista para as telas mostrarem "isto ainda é provisório"
const regrasProvisoriasAtivas = () =>
  Object.entries(REGRAS)
    .filter(([, regra]) => regra.provisorio)
    .map(([chave, regra]) => ({
      chave,
      decididoEm: regra.decididoEm,
      descricao: regra.descricao || regra.formato || regra.criterio
    }));

module.exports = { REGRAS, desempateDaModalidade, regrasProvisoriasAtivas, DECIDIDO_EM };
