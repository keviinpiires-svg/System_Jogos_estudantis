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
    // Consumido em: src/controllers/classificacaoController.js (compararEntreGrupos,
    // que também alimenta o aviso na tela) e, pela geração da semifinal de três
    // grupos, em src/config/chavesMataMata.js.
    aplicadoEm: 'classificacaoController.compararEntreGrupos e a geração da semifinal (fatia 7)'
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
  },

  // --------------------------------------------------------------------
  // 6. Tabela geral (10/8/6/4/2) — decisões do usuário de 01/10/2026
  // --------------------------------------------------------------------
  // O regulamento dá a pontuação e diz que modalidade com uma só inscrição
  // não pontua, mas não fecha o resto: como dividir os três blocos, de onde
  // saem o 4º e o 5º lugar, o que fazer com empate na soma.
  // A divisão categoria -> bloco mora em src/config/blocosTabelaGeral.js.
  tabelaGeral: {
    provisorio: true,
    decididoEm: '01/10/2026',

    // 4º e 5º lugar seguem sem regra (pendência 5): hoje o sistema só sabe
    // apontar campeão, vice e 3º, então só 10, 8 e 6 são distribuídos.
    posicoesQuePontuam: [1, 2, 3],

    // "Modalidade com uma só inscrição não conta pontos nem premia" vale por
    // COMPETIÇÃO (modalidade × categoria × gênero), não pela modalidade toda.
    minimoDeEquipes: 2,

    // Masculino e feminino pontuam em separado e somam para a mesma escola
    generosSomamJuntos: true,

    // Competição só entra na conta quando tem campeão definido
    soContaEncerrada: true,

    // Empate na soma: mais primeiros lugares, depois segundos, depois terceiros
    desempate: ['primeiros', 'segundos', 'terceiros'],

    // Punição da Comissão Disciplinar: desconta da soma geral da escola (não
    // de um bloco), pode haver mais de uma, e cada uma guarda motivo e data.
    ajuste: { minimo: -10, maximo: -5, naSomaGeral: true },

    // Atletismo fica de fora: não há competição cadastrada nem regra de
    // lançamento do resultado (pendência 3).
    incluiAtletismo: false,

    descricao:
      'Tabela geral por bloco de categoria, somando 10/8/6 por competição encerrada com duas '
      + 'equipes ou mais; punições de 5 a 10 pontos descontam da soma geral da escola.',
    aplicadoEm: 'tabelaGeralController'
  },

  // --------------------------------------------------------------------
  // 7. Atletismo (pendência 3) — NADA DISTO ESTÁ IMPLEMENTADO
  // --------------------------------------------------------------------
  // O regulamento diz quem corre o quê (Sub 8/9: 50 m; Sub 11 a 17: 100 m e
  // salto; 1 atleta por escola, categoria, gênero e prova; salto com 2
  // tentativas, vale a melhor), mas não diz como o resultado é lançado nem
  // se pontua na tabela geral. Hoje não há nenhuma competição de atletismo
  // cadastrada — as 50 da tabela de grupos são todas coletivas.
  //
  // Padrões escolhidos em 01/10/2026 para a fatia do atletismo poder começar
  // sem travar à espera do chefe. Mudar aqui é o bastante.
  atletismo: {
    provisorio: true,
    decididoEm: '01/10/2026',

    // Uma competição por categoria × gênero, com as provas DENTRO dela — e não
    // uma competição por prova, que multiplicaria por três a lista do menu.
    competicaoPor: 'CATEGORIA_E_GENERO',

    // O ADMIN digita a marca de cada atleta (segundos na corrida, metros no
    // salto) e o sistema ordena: tempo, menor vence; distância, maior vence.
    lancamento: 'ADMIN_DIGITA_A_MARCA',

    // As duas tentativas do salto ficam guardadas (o schema já tem as colunas);
    // a que vale é a melhor.
    guardaAsDuasTentativas: true,

    // Fora da tabela geral enquanto o chefe não disser como pontua.
    // Espelha tabelaGeral.incluiAtletismo.
    pontuaNaTabelaGeral: false,

    descricao:
      'Atletismo: uma competição por categoria e gênero, com as provas dentro; o ADMIN digita '
      + 'a marca e o sistema ordena; as duas tentativas do salto ficam guardadas, valendo a '
      + 'melhor; e o atletismo ainda não pontua na tabela geral.',
    aplicadoEm: 'ainda não implementado — é a parte que falta da fatia 8'
  },

  // --------------------------------------------------------------------
  // 8. Modalidades fora e técnicos (pendências 3 e 14)
  // --------------------------------------------------------------------
  modalidadesForaDoSistema: {
    provisorio: true,
    decididoEm: '01/10/2026',
    // O regulamento cita Xadrez, Dama e Dominó; a tabela de grupos não traz
    // nenhuma competição delas.
    fora: ['Xadrez', 'Dama', 'Dominó'],
    descricao:
      'Xadrez, Dama e Dominó ficam fora do sistema enquanto o chefe não confirmar que entram.',
    aplicadoEm: 'nada a implementar: não há competição dessas modalidades cadastrada'
  },

  tecnicos: {
    provisorio: true,
    decididoEm: '01/10/2026',
    // Continua como está: um nome digitado na equipe (equipes.tecnico_nome) e
    // outro na súmula do jogo (sumula_equipes.tecnico_nome). Sem cadastro, sem
    // tabela de dirigentes, sem o limite de 10 por escola do regulamento e sem
    // a checagem de "professor/monitor não pode ser atleta".
    cadastro: false,
    descricao:
      'Técnico segue como nome digitado na equipe e na súmula, sem cadastro próprio. '
      + 'Dirigentes não entram no sistema por enquanto.',
    aplicadoEm: 'equipes.tecnico_nome e sumula_equipes.tecnico_nome'
  },

  // --------------------------------------------------------------------
  // 9. Dois jogos no mesmo local — decisão do usuário de 05/10/2026
  // --------------------------------------------------------------------
  // O sistema deixava agendar dois jogos no mesmo local e no mesmo horário.
  // A duração das partidas fica EM ABERTO por decisão do chefe: varia muito,
  // e o vôlei nem tem tempo, é por sets. Então o sistema NÃO estima duração
  // (nada derivado de competicoes.minutos_por_tempo): compara só os horários
  // de INÍCIO no mesmo local, valendo entre competições diferentes.
  // Conflitam se |inicio_a - inicio_b| < intervaloMinutos. Jogo sem local ou
  // sem horário fica fora da conta, e o W.O. libera o local.
  conflitoDeLocal: {
    provisorio: true,
    decididoEm: '05/10/2026',
    intervaloMinutos: 10,
    statusQueOcupam: ['AGENDADO', 'EM_ANDAMENTO', 'FINALIZADO'],
    get descricao() {
      return `Dois jogos no mesmo local precisam de pelo menos ${this.intervaloMinutos} minutos `
        + 'entre os horários de início, mesmo sendo de competições diferentes; a duração das '
        + 'partidas não é estimada, e jogo com W.O. não ocupa o local.';
    },
    // A trava é só no código, sem índice único: um UNIQUE (local_id, data_hora)
    // não pegaria a sobreposição e impediria o W.O. de liberar o horário.
    aplicadoEm: 'jogoController.agendarJogo e jogoController.atualizarJogo'
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
