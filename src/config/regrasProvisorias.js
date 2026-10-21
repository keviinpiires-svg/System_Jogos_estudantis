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

// Respostas do chefe às regras provisórias. O que ele confirmou ou trocou
// passou a `provisorio: false` com esta data; o resto segue provisório.
const CONFIRMADO_EM = '06/10/2026';

const REGRAS = {
  // --------------------------------------------------------------------
  // 1. "Melhor segundo" quando os grupos têm tamanhos diferentes
  // --------------------------------------------------------------------
  // A decisão de 30/09 descartava os jogos contra o último colocado dos grupos
  // maiores. O chefe RECUSOU o descarte em 06/10/2026: os segundos são
  // comparados pelos critérios normais da modalidade, com todos os jogos.
  // Quando as equipes comparadas têm números de jogos diferentes, a tela
  // avisa, mas a conta não muda.
  melhorSegundo: {
    provisorio: false,
    decididoEm: CONFIRMADO_EM,
    criterio: 'CRITERIOS_DA_MODALIDADE',
    descricao:
      'Os segundos colocados de grupos diferentes são comparados pelos critérios '
      + 'normais da modalidade, com todos os jogos, sem descartar nenhum.',
    // Consumido em: src/controllers/classificacaoController.js
    // (compararEntreGrupos e o aviso de jogos diferentes).
    aplicadoEm: 'classificacaoController.compararEntreGrupos'
  },

  // --------------------------------------------------------------------
  // 2. Empate no mata-mata: como cada modalidade decide
  // --------------------------------------------------------------------
  // O regulamento escreve pênaltis 3x1x1 para futsal e society, e
  // "prorrogação" para basquete e handebol — sem dizer o que fazer se a
  // prorrogação também empatar.
  // Decisão: segunda prorrogação e, persistindo, cobranças —
  // 7 metros no handebol, lances livres no basquete. Confirmada pelo chefe
  // em 06/10/2026.
  //
  // Não há desempate genérico (decisão de 06/10/2026): cada modalidade segue
  // o regulamento. Onde ele é omisso — hoje o baleado —, a regra fica
  // PENDENTE: a súmula avisa e não deixa finalizar um empate que precisa de
  // vencedor, em vez de inventar uma cobrança.
  desempateMataMata: {
    provisorio: false,
    decididoEm: CONFIRMADO_EM,
    // A chave é o slug da modalidade (modalidades.slug)
    porModalidade: {
      // Regulamento: "tiros livres da marca penal, a saber: 3x1x1"
      futsal: { sequencia: ['PENALTIS'], nomeCobranca: 'pênaltis (3x1x1)' },
      'futebol-society': { sequencia: ['PENALTIS'], nomeCobranca: 'pênaltis (3x1x1)' },
      // Regulamento: prorrogação; a 2ª prorrogação e as cobranças são do chefe
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
      // Baleado: o regulamento diz quem vence (quem balear todos ou, acabado o
      // tempo, quem eliminou mais), mas não o que fazer se as eliminações
      // empatarem. Empate na fase de grupos vale (1 ponto a cada) e não chega
      // aqui. Na FINAL (chefe, 07/10/2026) e na SEMIFINAL (chefe, 12/10/2026)
      // há acréscimo de 4 minutos e vence quem balear primeiro
      // (jogos.baleou_primeiro_equipe_id, db/08). No ida e volta com a soma
      // empatada vale a mesma regra, no SEGUNDO jogo (20/10/2026): a súmula
      // exige quem baleou primeiro e essa equipe é a campeã. Sem caso
      // pendente: não há cobrança, e sim o acréscimo.
      baleado: {
        sequencia: [],
        nomeCobranca: null,
        acrescimo: {
          fases: ['SEMIFINAL', 'FINAL'],
          // Também no 2º jogo do ida e volta com a soma empatada
          somaDosDoisJogos: true,
          minutosDeAcrescimo: 4,
          decididoEm: '12/10/2026',
          somaDecididaEm: '20/10/2026',
          descricao: 'Na semifinal, na final e no segundo jogo do ida e volta com a soma empatada, '
            + 'o empate vai para um acréscimo de 4 minutos: vence quem balear primeiro.'
        }
      }
    },
    // Consumido em: src/controllers/sumulaController.js, ao finalizar uma
    // súmula empatada fora da fase de grupos.
    aplicadoEm: 'sumulaController.registrarSumula'
  },

  // --------------------------------------------------------------------
  // 3. Placar de um W.O.
  // --------------------------------------------------------------------
  // O regulamento diz que o time ausente perde, mas não diz por quanto.
  // Decisão confirmada pelo chefe em 06/10/2026: 1x0, declarado só pela
  // Comissão Organizadora (no sistema, o perfil ADMIN).
  wo: {
    provisorio: false,
    decididoEm: CONFIRMADO_EM,
    placarVencedor: 1,
    placarPerdedor: 0,
    editavel: true,
    descricao: 'W.O. vale 1x0 e é declarado só pela Comissão Organizadora (ADMIN).',
    // Consumido em: src/controllers/jogoController.js (declararWO) e na tela
    // TabelaJogos.jsx, que já abre o painel com o placar sugerido.
    aplicadoEm: 'jogoController.declararWO'
  },

  // --------------------------------------------------------------------
  // 4. Súmula do baleado
  // --------------------------------------------------------------------
  // A decisão provisória de 30/09/2026 (folha do futsal com eliminações por
  // atleta) acabou em 06/10/2026: chegou a folha oficial
  // (docs/referencias/SUMULA_BALEADO.pdf), com um contador de BALEADOS por
  // equipe. O desenho dela está em src/config/folhasSumula.js.
  //
  // O que o contador conta (chefe, 12/10/2026): no bloco de cada equipe, as
  // ADVERSÁRIAS que ela eliminou, e o placar da equipe é o próprio contador.
  // De 06 a 12/10/2026 valeu o contrário (cada bloco marcava as atletas da
  // própria equipe baleadas, e o placar era o contador da adversária).
  baleado: {
    provisorio: false,
    decididoEm: '12/10/2026',
    folhaOficial: 'docs/referencias/SUMULA_BALEADO.pdf',
    descricao:
      'O baleado tem folha oficial: Nº, atletas, capitão e um contador de baleados por '
      + 'equipe, de 1 a 10, com as adversárias que a equipe eliminou. O placar de uma equipe '
      + 'é o próprio contador.',
    aplicadoEm: 'folhasSumula.baleado e sumula_equipes.baleados'
  },

  // --------------------------------------------------------------------
  // 5. Formato do Handebol Masculino Aberto
  // --------------------------------------------------------------------
  // A tabela de grupos trazia "melhor de dois jogos" com TRÊS equipes, o que
  // não fecha. Decisão: todos contra todos em turno único; 1º e 2º à final.
  // Confirmada pelo chefe em 06/10/2026.
  // Isto é DADO, não código: mora na linha da competição.
  handebolMasculinoAberto: {
    provisorio: false,
    decididoEm: CONFIRMADO_EM,
    formato: 'todos contra todos em turno único; 1º e 2º vão à final',
    // Aplicado por script versionado, não em tempo de execução
    aplicadoEm: 'db/06_ajustes_regras_provisorios.sql'
  },

  // --------------------------------------------------------------------
  // 6. Tabela geral (10/8/6/4/2) — decisões de 01/10 e 06/10/2026
  // --------------------------------------------------------------------
  // O regulamento dá a pontuação e diz que modalidade com uma só inscrição
  // não pontua, mas não fecha o resto. Em 06/10/2026 o chefe tirou a divisão
  // em três blocos (fica só a soma geral) e decidiu o empate na soma.
  //
  // O `provisorio` do objeto continua true porque o 4º e o 5º lugar são
  // provisórios e o atletismo segue pendente. O que o chefe confirmou está
  // marcado como DEFINITIVO abaixo.
  tabelaGeral: {
    provisorio: true,
    decididoEm: '01/10/2026',

    // DEFINITIVO (07/10/2026) — do 1º ao 5º pontuam (10/8/6/4/2). Quem é o 4º
    // e o 5º vem de chavesMataMata.quartoEQuinto, confirmado pelo chefe.
    // posicoesProvisorias fica vazio: a tela só avisa se voltar a ter posição.
    posicoesQuePontuam: [1, 2, 3, 4, 5],
    posicoesProvisorias: [],

    // DEFINITIVO (06/10/2026) — "modalidade com uma só inscrição não conta
    // pontos nem premia" vale por COMPETIÇÃO (modalidade × categoria × gênero).
    minimoDeEquipes: 2,

    // Masculino e feminino pontuam em separado e somam para a mesma escola
    generosSomamJuntos: true,

    // Competição só entra na conta quando tem campeão definido
    soContaEncerrada: true,

    // Empate na soma (chefe, 07/10/2026): desempata quem tem mais 1º lugares,
    // depois mais 2º e mais 3º — DEFINITIVO. Se ainda empatar, as escolas
    // dividem a posição, com numeração de competição (1, 1, 3) — essa última
    // parte é EXTENSÃO PROVISÓRIA nossa (o chefe não falou do empate em tudo).
    desempate: {
      criterios: ['primeiros', 'segundos', 'terceiros'],
      decididoEm: '07/10/2026',
      seEmpatarEmTudo: 'DIVIDE_A_POSICAO',
      seEmpatarEmTudoProvisorio: true,
      descricao: 'Mesma soma: desempata quem tem mais 1º lugares, depois mais 2º e mais 3º. '
        + 'Se ainda empatar, as escolas dividem a posição (regra provisória).'
    },

    // DEFINITIVO (06/10/2026) — punição da Comissão Disciplinar: de 5 a 10
    // pontos, desconta da soma geral da escola, pode haver mais de uma, e
    // cada uma guarda motivo e data.
    ajuste: {
      minimo: -10,
      maximo: -5,
      naSomaGeral: true,
      provisorio: false,
      decididoEm: CONFIRMADO_EM
    },

    // Competição de modalidade individual não pontua pela chave: não há
    // nenhuma cadastrada. Atletismo, xadrez, dama e dominó entram na soma
    // pelos pontos lançados pela mesa (pontosLancados, abaixo).
    incluiAtletismo: false,

    descricao:
      'Tabela geral só com a soma geral, somando 10/8/6/4/2 por competição encerrada com '
      + 'duas equipes ou mais; empate na soma divide a posição; punições de 5 a 10 pontos '
      + 'descontam da soma geral da escola. 4º e 5º lugar são provisórios.',
    aplicadoEm: 'tabelaGeralController'
  },

  // --------------------------------------------------------------------
  // 7. Pontos lançados: atletismo, xadrez, dama e dominó (12/10/2026)
  // --------------------------------------------------------------------
  // O chefe definiu (12/10/2026) que essas quatro modalidades funcionam FORA
  // do sistema: sem súmula e sem cálculo de colocação. O juiz entrega a
  // folha, e a mesa (perfil PLACAR) ou o ADMIN digita os pontos de cada
  // escola, por modalidade × categoria × gênero, na tela /pontos-lancados.
  // Os pontos somam na Tabela Geral. (Substitui os padrões de 01/10/2026,
  // em que o ADMIN digitava a marca de cada atleta e xadrez, dama e dominó
  // ficavam de fora.)
  //
  // Os números abaixo são PADRÃO ADOTADO em 12/10/2026, SEM confirmação do
  // chefe: trocar aqui quando chegar a folha do juiz.
  pontosLancados: {
    provisorio: true,
    decididoEm: '12/10/2026',

    // Abas da tela, nesta ordem (modalidades.slug; Xadrez, Dama e Dominó
    // vêm do db/11)
    modalidades: ['atletismo', 'xadrez', 'dama', 'domino'],

    // As mesmas categorias e gêneros nas quatro modalidades (categorias.nome).
    // A mesa usa as que existirem.
    categorias: ['Sub 8', 'Sub 9', 'Sub 11', 'Sub 13', 'Sub 15', 'Sub 17', 'Aberto'],
    generos: ['MASCULINO', 'FEMININO'],

    // Combinação que não existe sai da tela: [slug, categoria, gênero].
    // Gênero null tira os dois. Ex.: ['xadrez', 'Sub 8', null].
    ocultas: [],

    // Atletismo por PROVA (21/10/2026, db/16): cada prova é um lançamento
    // próprio, e a Tabela Geral soma as provas da escola. Regulamento: Sub 8
    // e Sub 9 só correm 50 m; Sub 11 a Sub 17 fazem salto e 100 m. Os nomes
    // são os de provas_atletismo (carga base); `rotulo` é o que a tela mostra.
    provas: {
      atletismo: {
        'Sub 8': ['Corrida 50 metros'],
        'Sub 9': ['Corrida 50 metros'],
        padrao: ['Salto em distância', 'Corrida 100 metros']
      }
    },
    rotulosDasProvas: {
      'Corrida 50 metros': '50 m',
      'Corrida 100 metros': '100 m',
      'Salto em distância': 'Salto'
    },

    // Pontos esperados por escola em cada lançamento (no atletismo, em cada
    // PROVA: 10, ou seja, 20 no total quando a categoria tem duas). Passar
    // disso NÃO bloqueia: a linha fica destacada e a mesa confirma.
    esperado: {
      atletismo: { padrao: 10 },
      xadrez: { padrao: 10 },
      dama: { padrao: 10 },
      domino: { padrao: 10 }
    },

    // Teto absoluto, contra erro de digitação: acima disso a API recusa (o
    // banco também: CHECK em pontos_lancados.pontos)
    tetoAbsoluto: 99,

    // Desempate da soma geral (mais 1ºs, 2ºs e 3ºs): essas modalidades ficam
    // de fora e só somam pontos. A colocação, quando digitada, é só
    // informação.
    contaNoDesempate: false,

    descricao:
      'Atletismo, xadrez, dama e dominó: a mesa digita os pontos de cada escola por categoria '
      + 'e gênero, conforme a folha do juiz. Os pontos somam na tabela geral, mas não entram no '
      + 'desempate por 1º, 2º e 3º lugares. No atletismo cada prova é um lançamento próprio (Sub 8 e '
      + 'Sub 9: 50 m; Sub 11 a Sub 17: salto e 100 m), e as provas somam sozinhas. Pontos esperados '
      + 'por escola: 10 em cada prova do atletismo e 10 no xadrez, na dama e no dominó.',
    aplicadoEm: 'pontosLancadosController e tabelaGeralController'
  },

  // --------------------------------------------------------------------
  // 8. Técnicos (pendência 14)
  // --------------------------------------------------------------------
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

// Atalho usado pelos controllers: o desempate da modalidade. Modalidade que
// ninguém previu fica PENDENTE, como o baleado — nunca com uma cobrança
// genérica que o regulamento não escreve.
const desempateDaModalidade = (slug) =>
  REGRAS.desempateMataMata.porModalidade[slug]
  || {
    sequencia: [],
    nomeCobranca: null,
    pendente: true,
    motivo: 'o regulamento não tem regra de desempate para esta modalidade'
  };

// Lista para as telas mostrarem "isto ainda é provisório"
const regrasProvisoriasAtivas = () =>
  Object.entries(REGRAS)
    .filter(([, regra]) => regra.provisorio)
    .map(([chave, regra]) => ({
      chave,
      decididoEm: regra.decididoEm,
      descricao: regra.descricao || regra.formato || regra.criterio
    }));

module.exports = { REGRAS, desempateDaModalidade, regrasProvisoriasAtivas, DECIDIDO_EM, CONFIRMADO_EM };
