// Teste de fumaça do SGE — `npm run fumaca`
//
// Monta uma competição inteira contra o banco de DESENVOLVIMENTO, passando
// pelas rotas da API como a tela passa: cria atletas, inscreve, agenda os jogos
// da fase de grupos, lança as súmulas, confere a classificação, gera o
// mata-mata, lança a final e confere o pódio e a tabela geral. No fim apaga
// tudo o que criou e prova que o banco voltou ao estado anterior.
//
// Não é teste de unidade: é o passeio que se fazia à mão a cada fatia, agora
// num arquivo. Se ele passa, o caminho principal do sistema está de pé.
//
// Uso:
//   1. suba a API:        npm run dev
//   2. noutro terminal:   npm run fumaca
//
// Nunca toca em dados de quem está usando o sistema: escolhe uma competição
// que ainda não tem jogo nenhum, cria tudo com a marca FUMACA e só apaga o que
// tem essa marca ou o id que ele mesmo guardou.
require('dotenv').config({ quiet: true });
const bcrypt = require('bcryptjs');
const db = require('../src/config/db');
const { REGRAS, desempateDaModalidade } = require('../src/config/regrasProvisorias');
const { folhaDaModalidade } = require('../src/config/folhasSumula');
const { compararEntreGrupos } = require('../src/controllers/classificacaoController');
const { posicionar } = require('../src/controllers/tabelaGeralController');
const { colocacoesFinais } = require('../src/controllers/mataMataController');
const { chaveDaSemifinal, REGRAS_DA_CHAVE } = require('../src/config/chavesMataMata');

const API = process.env.FUMACA_API || 'http://localhost:3000/api';
const MARCA = 'FUMACA';
const EMAIL = 'fumaca@local';
const SENHA = 'fumaca-senha-longa';

// Jogos e competição que o dono do projeto usa para testar à mão. Mesmo que a
// escolha automática falhasse, eles ficam de fora.
const COMPETICAO_PROTEGIDA = 41;

const criados = { jogos: [], inscricoes: [], atletas: [], ajustes: [], usuario: null };

let passou = 0;
let falhou = 0;
const problemas = [];

const conferir = (certo, descricao, detalhe) => {
  if (certo) {
    passou++;
    console.log(`  ok    ${descricao}`);
  } else {
    falhou++;
    problemas.push(descricao);
    console.log(`  FALHA ${descricao}${detalhe ? `\n          ${detalhe}` : ''}`);
  }
};

const secao = (titulo) => console.log(`\n${titulo}`);

// ---------------------------------------------------------------------------
// Conversa com a API
// ---------------------------------------------------------------------------
let token = null;

const chamar = async (metodo, caminho, corpo) => {
  const resposta = await fetch(`${API}${caminho}`, {
    method: metodo,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {})
    },
    ...(corpo ? { body: JSON.stringify(corpo) } : {})
  });
  return { status: resposta.status, corpo: await resposta.json().catch(() => ({})) };
};

const exigir = async (metodo, caminho, corpo, oQue) => {
  const { status, corpo: resposta } = await chamar(metodo, caminho, corpo);
  if (status >= 400) {
    throw new Error(`${oQue} falhou (${status}): ${resposta.erro || JSON.stringify(resposta)}`);
  }
  return resposta;
};

// ---------------------------------------------------------------------------
// Trava de segurança: isto não roda em produção
// ---------------------------------------------------------------------------
// Descobre em que banco a conexão REALMENTE vai cair, do mesmo jeito que o
// src/config/db.js decide: a URL única tem prioridade e o DB_NAME é ignorado
// quando ela existe. A trava antiga olhava só o DB_NAME — então um .env com a
// DATABASE_URL da produção e um DB_NAME "..._dev" esquecido ao lado passava na
// conferência, e o teste escrevia e apagava na produção.
const alvoDaConexao = () => {
  const url = process.env.DATABASE_URL || process.env.MYSQL_URL;

  if (!url) {
    return {
      banco: process.env.DB_NAME || '',
      host: process.env.DB_HOST || 'localhost',
      via: 'DB_NAME'
    };
  }

  try {
    const { pathname, hostname } = new URL(url);
    return {
      banco: decodeURIComponent(pathname.replace(/^\//, '')),
      host: hostname,
      via: 'DATABASE_URL'
    };
  } catch {
    throw new Error(
      'DATABASE_URL está definida mas não é uma URL válida. Como não dá para saber em que '
      + 'banco isto cairia, o teste de fumaça não roda.'
    );
  }
};

const conferirQueEhDesenvolvimento = () => {
  const { banco, host, via } = alvoDaConexao();

  if (process.env.NODE_ENV === 'production') {
    throw new Error('O teste de fumaça não roda com NODE_ENV=production.');
  }

  if (!/dev/i.test(banco)) {
    throw new Error(
      'O teste de fumaça escreve e apaga no banco, então só roda num banco de desenvolvimento. '
      + `A conexão (via ${via}) cairia no banco "${banco}" em ${host}; esperava um nome com `
      + '"dev" (ex.: jogos_estudantis_dev).'
    );
  }

  return banco;
};

// ---------------------------------------------------------------------------
// Limpeza — roda no fim e também antes, para o caso de uma execução interrompida
// ---------------------------------------------------------------------------
const limpar = async () => {
  if (criados.jogos.length > 0) {
    await db.query('DELETE FROM sumula_atletas WHERE jogo_id IN (?)', [criados.jogos]);
    await db.query('DELETE FROM sumula_equipes WHERE jogo_id IN (?)', [criados.jogos]);
    await db.query('DELETE FROM jogo_sets WHERE jogo_id IN (?)', [criados.jogos]);
    await db.query('DELETE FROM jogos WHERE id IN (?)', [criados.jogos]);
    criados.jogos = [];
  }

  // Pelo RG marcado: pega também o que sobrou de uma execução anterior
  await db.query(
    `DELETE i FROM inscricoes_atletas i
       INNER JOIN atletas a ON a.id = i.atleta_id
      WHERE a.rg LIKE ?`,
    [`${MARCA}%`]
  );
  await db.query('DELETE FROM atletas WHERE rg LIKE ?', [`${MARCA}%`]);
  await db.query('DELETE FROM ajustes_pontos_geral WHERE motivo LIKE ?', [`${MARCA}%`]);
  await db.query('DELETE FROM usuarios WHERE email = ?', [EMAIL]);

  criados.inscricoes = [];
  criados.atletas = [];
  criados.ajustes = [];
  criados.usuario = null;
};

// ---------------------------------------------------------------------------
// Escolha da competição: duas chaves, dois classificados, semifinal — o formato
// que exercita o caminho mais longo (grupos -> semifinal -> final -> pódio).
// ---------------------------------------------------------------------------
const escolherCompeticao = async () => {
  const [candidatas] = await db.query(
    `SELECT c.id, c.genero, c.qtd_grupos, m.nome AS modalidade, m.tipo_placar,
            cat.nome AS categoria, cat.idade_maxima,
            COUNT(DISTINCT e.id) AS equipes
       FROM competicoes c
       INNER JOIN modalidades m ON m.id = c.modalidade_id
       INNER JOIN categorias cat ON cat.id = c.categoria_id
       INNER JOIN equipes e ON e.id IN (
         SELECT id FROM equipes WHERE competicao_id = c.id AND grupo_id IS NOT NULL
       )
      WHERE c.id <> ?
        AND m.tipo_placar = 'GOLS'
        AND c.qtd_grupos = 2
        AND c.classificados_por_grupo = 2
        AND c.proxima_fase = 'SEMIFINAL'
        AND NOT EXISTS (SELECT 1 FROM jogos j WHERE j.competicao_id = c.id)
      GROUP BY c.id
     HAVING equipes >= 4
      ORDER BY equipes ASC, c.id ASC
      LIMIT 1`,
    [COMPETICAO_PROTEGIDA]
  );

  if (candidatas.length === 0) {
    throw new Error(
      'Nenhuma competição livre no formato esperado (2 grupos, 2 classificados, semifinal '
      + 'e sem jogos). Apague os jogos de alguma antes de rodar o teste de fumaça.'
    );
  }

  const competicao = candidatas[0];

  const [equipes] = await db.query(
    `SELECT e.id, e.escola_id, esc.nome AS escola_nome, g.id AS grupo_id, g.nome AS grupo_nome
       FROM equipes e
       INNER JOIN escolas esc ON esc.id = e.escola_id
       INNER JOIN grupos g ON g.id = e.grupo_id
      WHERE e.competicao_id = ?
      ORDER BY g.nome, esc.nome`,
    [competicao.id]
  );

  // Todas as equipes entram: quem fica de fora acaba classificado por empate em
  // zero ponto e cai na semifinal sem elenco — foi assim que este teste quebrou
  // da primeira vez.
  const grupos = new Set(equipes.map((e) => e.grupo_nome));
  if (grupos.size < 2) {
    throw new Error('A competição escolhida não tem dois grupos com equipes.');
  }

  return { competicao, equipes };
};

// ---------------------------------------------------------------------------
// O passeio
// ---------------------------------------------------------------------------
const rodar = async () => {
  const banco = conferirQueEhDesenvolvimento();
  console.log(`Teste de fumaça — banco ${banco}, API ${API}`);

  await limpar();

  secao('-- antes');
  const [[antes]] = await db.query(
    `SELECT (SELECT COUNT(*) FROM jogos) AS jogos,
            (SELECT COUNT(*) FROM atletas) AS atletas,
            (SELECT COUNT(*) FROM inscricoes_atletas) AS inscricoes,
            (SELECT COUNT(*) FROM sumula_atletas) AS sumulas,
            (SELECT COUNT(*) FROM ajustes_pontos_geral) AS ajustes,
            (SELECT COUNT(*) FROM usuarios) AS usuarios`
  );
  const [jogosAntes] = await db.query('SELECT id FROM jogos ORDER BY id');
  console.log(`  ${JSON.stringify(antes)}`);

  const [[evento]] = await db.query('SELECT ano FROM configuracao_evento WHERE id = 1');

  // Usuário de teste e login
  await db.query(
    'INSERT INTO usuarios (nome, email, senha, perfil) VALUES (?, ?, ?, ?)',
    [`Fumaça (${MARCA})`, EMAIL, bcrypt.hashSync(SENHA, 10), 'ADMIN']
  );
  const login = await exigir('POST', '/login', { email: EMAIL, senha: SENHA }, 'o login');
  token = login.token;
  criados.usuario = login.usuario.id;

  const { competicao, equipes } = await escolherCompeticao();
  console.log(
    `\nCompetição ${competicao.id}: ${competicao.modalidade} ${competicao.categoria} `
    + `${competicao.genero} — ${equipes.map((e) => `${e.grupo_nome}:${e.escola_nome}`).join(', ')}`
  );

  // ---- atletas e inscrições -------------------------------------------------
  secao('-- atletas e inscrições');
  const sexo = competicao.genero === 'FEMININO' ? 'F' : 'M';
  // Sub N aceita quem nasceu em (ano do evento - N) ou depois; Aberto não limita
  const anoNascimento = competicao.idade_maxima
    ? evento.ano - competicao.idade_maxima
    : evento.ano - 20;

  let contador = 0;
  const elenco = new Map();   // equipe_id -> [atleta_id, ...]

  for (const equipe of equipes) {
    const doTime = [];

    for (let i = 1; i <= 3; i++) {
      contador++;
      const atleta = await exigir('POST', '/atletas', {
        nome: `${MARCA} ${equipe.escola_nome} ${i}`,
        rg: `${MARCA}${String(contador).padStart(5, '0')}`,
        data_nascimento: `${anoNascimento}-03-15`,
        sexo,
        escola_id: equipe.escola_id
      }, 'cadastrar atleta');

      criados.atletas.push(atleta.id_atleta);
      doTime.push(atleta.id_atleta);

      const inscricao = await exigir('POST', '/inscricoes', {
        equipe_id: equipe.id,
        atleta_id: atleta.id_atleta,
        numero_camisa: i
      }, 'inscrever atleta');
      criados.inscricoes.push(inscricao.id_inscricao);
    }

    elenco.set(equipe.id, doTime);
  }
  conferir(criados.atletas.length === equipes.length * 3, `${criados.atletas.length} atletas criados e inscritos`);

  const inscritos = await exigir('GET', `/inscricoes/equipe/${equipes[0].id}`, null, 'listar inscritos');
  conferir(inscritos.total_inscritos === 3, 'a equipe lista os 3 inscritos', `veio ${inscritos.total_inscritos}`);
  // Elenco abaixo do mínimo é aviso, não bloqueio (decisão de 28/09/2026)
  conferir(Boolean(inscritos.aviso), 'elenco abaixo do mínimo gera aviso, e não erro', inscritos.aviso);

  // ---- um jogo com placar -------------------------------------------------
  // Marca de gols por equipe; quem vence é decidido aqui, para a classificação
  // depois ser conferida contra um resultado conhecido.
  const lancar = async (jogo_id, equipeA, golsA, equipeB, golsB) => {
    const linhasDe = (equipe_id, gols) => {
      const ids = elenco.get(equipe_id);
      return ids.map((atleta_id, indice) => ({
        atleta_id,
        presente: true,
        capitao: indice === 0,
        gols: indice === 0 ? gols : 0,
        amarelos: 0,
        vermelho: false,
        faltas: 0
      }));
    };

    return exigir('POST', '/sumulas', {
      jogo_id,
      finalizar: true,
      equipes: [
        { equipe_id: equipeA, atletas: linhasDe(equipeA, golsA), faltas_1t: 0, faltas_2t: 0 },
        { equipe_id: equipeB, atletas: linhasDe(equipeB, golsB), faltas_1t: 0, faltas_2t: 0 }
      ]
    }, `lançar a súmula do jogo ${jogo_id}`);
  };

  const agendar = async (equipe_1_id, equipe_2_id, fase, quando) => {
    const jogo = await exigir('POST', '/jogos', {
      competicao_id: competicao.id,
      equipe_1_id,
      equipe_2_id,
      fase,
      data_hora: quando
    }, 'agendar jogo');
    criados.jogos.push(jogo.id_jogo);
    return jogo.id_jogo;
  };

  // ---- fase de grupos ------------------------------------------------------
  secao('-- fase de grupos');
  const grupos = [...new Set(equipes.map((e) => e.grupo_nome))].sort();
  const primeiroDoGrupo = new Map();

  // Todos contra todos dentro do grupo, e quem vem antes na lista sempre vence:
  // a classificação fica previsível e dá para conferi-la contra um resultado
  // conhecido, em vez de contra ela mesma.
  for (const nome of grupos) {
    const doGrupo = equipes.filter((e) => e.grupo_nome === nome);

    for (let i = 0; i < doGrupo.length; i++) {
      for (let j = i + 1; j < doGrupo.length; j++) {
        const jogo = await agendar(doGrupo[i].id, doGrupo[j].id, 'GRUPOS', '2026-11-23T09:00');
        await lancar(jogo, doGrupo[i].id, 3, doGrupo[j].id, 1);
      }
    }

    primeiroDoGrupo.set(nome, doGrupo[0]);
  }
  conferir(criados.jogos.length >= grupos.length, `${criados.jogos.length} jogos de grupo lançados pela súmula`);

  const classificacao = await exigir('GET', `/classificacao/competicao/${competicao.id}`, null, 'a classificação');
  const grupoA = classificacao.grupos.find((g) => g.nome === grupos[0]);
  const vitoriasDoLider = equipes.filter((e) => e.grupo_nome === grupos[0]).length - 1;

  conferir(
    grupoA.equipes[0].escola_nome === primeiroDoGrupo.get(grupos[0]).escola_nome,
    'quem venceu tudo lidera o grupo na classificação',
    `líder calculado: ${grupoA.equipes[0].escola_nome}`
  );
  conferir(
    grupoA.equipes[0].pontos === vitoriasDoLider * 3,
    `${vitoriasDoLider} ${vitoriasDoLider === 1 ? 'vitória vale' : 'vitórias valem'} ${vitoriasDoLider * 3} pontos`,
    `pontos: ${grupoA.equipes[0].pontos}`
  );
  conferir(
    grupoA.equipes[0].saldo === vitoriasDoLider * 2,
    'o saldo de gols sai da súmula',
    `saldo: ${grupoA.equipes[0].saldo}`
  );

  const suspensoes = await exigir('GET', `/suspensoes/competicao/${competicao.id}`, null, 'as suspensões');
  conferir(Array.isArray(suspensoes.atletas), 'a tela de cartões responde');

  // ---- mata-mata -----------------------------------------------------------
  secao('-- mata-mata');
  const semifinais = await exigir(
    'POST', `/matamata/competicao/${competicao.id}/gerar`, { fase: 'SEMIFINAL' }, 'gerar a semifinal'
  );
  const idsSemi = (semifinais.jogos || []).map((j) => j.id ?? j.jogo_id).filter(Boolean);
  criados.jogos.push(...idsSemi);
  conferir(idsSemi.length === 2, 'a semifinal nasceu com 2 jogos', `nasceram: ${idsSemi.length}`);

  const chaveAntes = await exigir('GET', `/matamata/competicao/${competicao.id}`, null, 'a chave');
  const jogosSemi = chaveAntes.chave.semifinal.jogos;
  conferir(chaveAntes.chave.semifinal.gerada === true, 'a chave mostra a semifinal como gerada');
  conferir(
    jogosSemi.every((j) => 'local_id' in j && 'local_nome' in j),
    'os jogos da chave trazem o local (a definir enquanto não marcado)'
  );

  const vencedores = [];
  for (const jogo of jogosSemi) {
    await lancar(jogo.id, jogo.equipe_1_id, 2, jogo.equipe_2_id, 0);
    vencedores.push(jogo.equipe_1_id);
  }
  conferir(vencedores.length === 2, 'as duas semifinais foram lançadas');

  const final = await exigir(
    'POST', `/matamata/competicao/${competicao.id}/gerar`, { fase: 'FINAL' }, 'gerar a final'
  );
  const idFinal = (final.jogos || [])[0]?.id ?? (final.jogos || [])[0]?.jogo_id;
  criados.jogos.push(idFinal);
  conferir(Boolean(idFinal), 'a final nasceu');

  const chaveComFinal = await exigir('GET', `/matamata/competicao/${competicao.id}`, null, 'a chave com final');
  const jogoFinal = chaveComFinal.chave.final.jogos[0];
  await lancar(jogoFinal.id, jogoFinal.equipe_1_id, 4, jogoFinal.equipe_2_id, 2);

  const chaveFinal = await exigir('GET', `/matamata/competicao/${competicao.id}`, null, 'o pódio');
  const podio = chaveFinal.colocacoes || [];
  conferir(podio.length >= 3, 'o pódio saiu com pelo menos 3 colocações', `saíram ${podio.length}`);
  conferir(
    podio[0]?.equipe_id === jogoFinal.equipe_1_id,
    'campeão é quem venceu a final',
    `campeão calculado: ${podio[0]?.escola_nome}`
  );
  conferir(
    podio[1]?.equipe_id === jogoFinal.equipe_2_id,
    'vice é quem perdeu a final'
  );
  conferir(
    podio[2] && podio[2].como,
    'o 3º vem com a explicação de como foi decidido',
    podio[2]?.como
  );

  // 4º provisório: quem perdeu a semifinal para o vice (não há jogo de 3º)
  const semiDoVice = jogosSemi.find((j) => j.equipe_1_id === jogoFinal.equipe_2_id);
  const quarto = podio.find((c) => c.posicao === 4);
  conferir(
    quarto?.equipe_id === semiDoVice?.equipe_2_id && quarto?.provisoria === false,
    '4º é quem perdeu a semifinal para o vice, sem marca de provisório (confirmado em 07/10)',
    JSON.stringify(quarto)
  );
  // 5º provisório: com mais de 4 equipes na competição, a melhor campanha
  // entre quem não chegou à semifinal
  const naSemifinal = new Set(jogosSemi.flatMap((j) => [j.equipe_1_id, j.equipe_2_id]));
  const quintos = podio.filter((c) => c.posicao === 5);
  if (equipes.length > 4) {
    conferir(
      quintos.length > 0
        && quintos.every((q) => !naSemifinal.has(q.equipe_id) && q.provisoria === false),
      `com ${equipes.length} equipes, o 5º é de quem não chegou à semifinal, sem marca de provisório`,
      JSON.stringify(quintos)
    );
  } else {
    conferir(quintos.length === 0, `com ${equipes.length} equipes não há 5º`, JSON.stringify(quintos));
  }

  // O passeio faz todo mundo perder pelo mesmo placar, então com grupos do
  // mesmo tamanho os últimos de cada grupo empatam em tudo: dividem o 5º.
  // É exatamente o texto que o card do mata-mata mostra na linha de cada uma.
  const tamanhos = new Set(grupos.map((g) => equipes.filter((e) => e.grupo_nome === g).length));
  if (equipes.length > 4 && tamanhos.size === 1 && [...tamanhos][0] === 3) {
    conferir(
      quintos.length === 2,
      'grupos iguais de 3: os dois últimos empatam em tudo e os dois aparecem como 5º',
      JSON.stringify(quintos)
    );
  }
  if (quintos.length > 1) {
    const texto = REGRAS_DA_CHAVE.quartoEQuinto.textoDoEmpate;
    console.log(`  (na tela: ${quintos.map((q) => `"5º ${q.escola_nome} — ${q.como}"`).join(' e ')})`);
    conferir(
      quintos.every((q) => q.dividida === true && q.como.startsWith(texto)),
      `empate em tudo: ${quintos.length} equipes dividem o 5º, com "${texto}"`,
      JSON.stringify(quintos)
    );
  }

  // ---- tabela geral --------------------------------------------------------
  secao('-- tabela geral');
  const tabela = await exigir('GET', '/tabela-geral', null, 'a tabela geral');
  const campeao = podio[0];
  const naGeral = tabela.geral.find((e) => e.escola_nome === campeao.escola_nome);
  conferir(Boolean(naGeral), 'a escola campeã entrou na soma geral');
  conferir(naGeral?.primeiros >= 1, 'com um primeiro lugar contado');

  const escolaDoQuarto = podio.find((c) => c.posicao === 4)?.escola_nome;
  const origemDoQuarto = tabela.geral
    .find((e) => e.escola_nome === escolaDoQuarto)?.origens
    .find((o) => o.competicao_id === competicao.id && o.posicao === 4);
  conferir(
    origemDoQuarto?.pontos === 4 && origemDoQuarto?.provisoria === false,
    'o 4º soma 4 pontos na tabela geral, sem marca de provisório',
    JSON.stringify(origemDoQuarto)
  );
  // Cada escola que divide o 5º soma os 2 pontos inteiros
  for (const quinto of podio.filter((c) => c.posicao === 5)) {
    const origemDoQuinto = tabela.geral
      .find((e) => e.escola_nome === quinto.escola_nome)?.origens
      .find((o) => o.competicao_id === competicao.id && o.posicao === 5);
    conferir(
      origemDoQuinto?.pontos === 2 && origemDoQuinto?.provisoria === false,
      `5º (${quinto.escola_nome}) soma 2 pontos na tabela geral, sem marca de provisório`,
      JSON.stringify(origemDoQuinto)
    );
  }
  conferir(
    (tabela.regras.posicoes_provisorias?.posicoes || []).length === 0,
    'a tabela geral não avisa mais 4º e 5º provisórios'
  );

  // colocacoes traz a equipe; a escola vem da lista que o teste já montou
  const escolaDoCampeao = equipes.find((e) => e.id === campeao.equipe_id)?.escola_id;

  const comPontos = naGeral?.pontos ?? 0;
  const punicao = await exigir('POST', '/ajustes-pontos', {
    escola_id: escolaDoCampeao,
    pontos: -5,
    motivo: `${MARCA} punição do teste de fumaça`
  }, 'aplicar a punição');
  criados.ajustes.push(punicao.id_ajuste ?? punicao.id);

  const tabelaPunida = await exigir('GET', '/tabela-geral', null, 'a tabela com punição');
  const depoisDaPunicao = tabelaPunida.geral.find((e) => e.escola_nome === campeao.escola_nome);
  conferir(
    depoisDaPunicao.pontos === comPontos - 5,
    'a punição desconta da soma geral',
    `${comPontos} - 5 deveria dar ${comPontos - 5}, deu ${depoisDaPunicao.pontos}`
  );

  // ---- desfazer ------------------------------------------------------------
  secao('-- desfazer');
  conferir(
    (await chamar('DELETE', `/matamata/competicao/${competicao.id}/FINAL`)).status >= 400,
    'não desfaz uma fase já finalizada'
  );

  await exigir('DELETE', `/ajustes-pontos/${criados.ajustes[0]}`, null, 'remover a punição');
  criados.ajustes = [];
  const semPunicao = await exigir('GET', '/tabela-geral', null, 'a tabela sem punição');
  conferir(
    semPunicao.geral.find((e) => e.escola_nome === campeao.escola_nome).pontos === comPontos,
    'desfeita a punição, a soma volta ao que era'
  );

  await testarConflitoDeLocal(competicao, equipes, grupos);

  testarRegrasDoChefe();
  testarSemifinalDeTresGrupos();
  await testarTerceiroSemSemifinal();
  testarQuintoLugar();
  testarDesempatePorModalidade();
  testarFolhasOficiais();
  await testarEmpateDoBaleado();
};

// ---------------------------------------------------------------------------
// Empate no baleado (chefe, 07/10/2026) — pela API, numa competição livre
// ---------------------------------------------------------------------------
// Fase de grupos: empate vale. Final: acréscimo de 4 minutos, vence quem
// balear primeiro (jogos.baleou_primeiro_equipe_id). Semifinal: o chefe não
// respondeu, segue o 409 de regra pendente.
const testarEmpateDoBaleado = async () => {
  secao('-- empate no baleado');

  const [[comp]] = await db.query(
    `SELECT c.id, c.genero, cat.idade_maxima, e1.id AS e1, e2.id AS e2,
            e1.escola_id AS esc1, e2.escola_id AS esc2
       FROM competicoes c
       INNER JOIN modalidades m ON m.id = c.modalidade_id
       INNER JOIN categorias cat ON cat.id = c.categoria_id
       INNER JOIN equipes e1 ON e1.competicao_id = c.id
       INNER JOIN equipes e2 ON e2.competicao_id = c.id AND e2.grupo_id = e1.grupo_id AND e2.id > e1.id
      WHERE m.slug = 'baleado' AND c.turno = 'UNICO' AND c.id <> ?
        AND NOT EXISTS (SELECT 1 FROM jogos j WHERE j.competicao_id = c.id)
      ORDER BY c.id LIMIT 1`,
    [COMPETICAO_PROTEGIDA]
  );
  if (!comp) throw new Error('Não achei uma competição de baleado livre para o teste de empate.');

  const [[{ ano }]] = await db.query('SELECT ano FROM configuracao_evento WHERE id = 1');
  const nascimento = `${comp.idade_maxima ? ano - comp.idade_maxima : ano - 20}-03-15`;
  const sexo = comp.genero === 'FEMININO' ? 'F' : 'M';

  const atletaDe = async (equipe_id, escola_id, n) => {
    const atleta = await exigir('POST', '/atletas', {
      nome: `${MARCA} BALEADO ${n}`, rg: `${MARCA}BAL${n}`, data_nascimento: nascimento, sexo, escola_id
    }, 'cadastrar atleta do baleado');
    criados.atletas.push(atleta.id_atleta);
    await exigir('POST', '/inscricoes', { equipe_id, atleta_id: atleta.id_atleta, numero_camisa: 1 }, 'inscrever no baleado');
    return atleta.id_atleta;
  };
  const a1 = await atletaDe(comp.e1, comp.esc1, 1);
  const a2 = await atletaDe(comp.e2, comp.esc2, 2);

  const jogoNa = async (fase) => {
    const jogo = await exigir('POST', '/jogos', {
      competicao_id: comp.id, equipe_1_id: comp.e1, equipe_2_id: comp.e2, fase
    }, `agendar ${fase} do baleado`);
    criados.jogos.push(jogo.id_jogo);
    return jogo.id_jogo;
  };
  const linha = (atleta_id) => ({ atleta_id, presente: true, capitao: true, gols: 0, amarelos: 0, vermelho: false, faltas: 0 });
  // 3 baleadas de cada lado: empate
  const sumula = (jogo_id, extra = {}) => chamar('POST', '/sumulas', {
    jogo_id, finalizar: true, ...extra,
    equipes: [
      { equipe_id: comp.e1, baleados: 3, atletas: [linha(a1)] },
      { equipe_id: comp.e2, baleados: 3, atletas: [linha(a2)] }
    ]
  });

  const grupos = await jogoNa('GRUPOS');
  const rGrupos = await sumula(grupos);
  const [[jGrupos]] = await db.query('SELECT status, vencedor_equipe_id FROM jogos WHERE id = ?', [grupos]);
  conferir(
    rGrupos.status === 201 && jGrupos.status === 'FINALIZADO' && jGrupos.vencedor_equipe_id === null,
    'fase de grupos: empate finaliza, sem vencedor (1 ponto a cada)',
    `${rGrupos.status} ${rGrupos.corpo.erro || ''} ${JSON.stringify(jGrupos)}`
  );

  const semi = await jogoNa('SEMIFINAL');
  const rSemi = await sumula(semi);
  conferir(rSemi.status === 409, 'semifinal empatada: segue 409 de regra pendente', `${rSemi.status} ${rSemi.corpo.erro || ''}`);

  const final = await jogoNa('FINAL');
  const rSemInformar = await sumula(final);
  conferir(
    rSemInformar.status === 400,
    'final empatada sem dizer quem baleou primeiro: recusada',
    `${rSemInformar.status} ${rSemInformar.corpo.erro || ''}`
  );
  const rFinal = await sumula(final, { baleou_primeiro_equipe_id: comp.e2 });
  const [[jFinal]] = await db.query(
    'SELECT status, vencedor_equipe_id, baleou_primeiro_equipe_id, placar_1, placar_2 FROM jogos WHERE id = ?', [final]
  );
  conferir(
    rFinal.status === 201 && jFinal.status === 'FINALIZADO' && jFinal.vencedor_equipe_id === comp.e2
      && jFinal.baleou_primeiro_equipe_id === comp.e2 && jFinal.placar_1 === jFinal.placar_2,
    'final empatada: vence quem baleou primeiro no acréscimo, e o placar fica empatado',
    `${rFinal.status} ${rFinal.corpo.erro || ''} ${JSON.stringify(jFinal)}`
  );
};

// ---------------------------------------------------------------------------
// Folhas oficiais de 2026 (docs/referencias/SUMULA_HANDEBOL.pdf e SUMULA_BALEADO.pdf)
// ---------------------------------------------------------------------------
const testarFolhasOficiais = () => {
  secao('-- folhas oficiais de súmula');

  const handebol = folhaDaModalidade('handebol', 'Handebol');
  conferir(
    handebol.tipo === 'HANDEBOL' && handebol.titulo === 'SÚMULA DE HANDEBOL' && !handebol.provisoria,
    'handebol tem folha própria, sem aviso de provisória'
  );
  conferir(
    handebol.caixasEstatistica === 10 && handebol.cartoes && handebol.maxAmarelos === 1
      && handebol.faltasIndividuais === 0 && handebol.faltasAcumuladas === 0 && handebol.tempoTecnico,
    'handebol: 10 caixas de gols, um amarelo, sem faltas, com tempo técnico'
  );
  conferir(
    handebol.linhas === 12 && handebol.linhasMaximas === 14,
    'handebol: 12 linhas no papel, até 14 na folha preenchida'
  );
  conferir(
    folhaDaModalidade('futsal', 'Futsal').linhas === 14,
    'futsal segue com as 14 linhas da decisão de 29/09'
  );
};

// ---------------------------------------------------------------------------
// Empate no mata-mata — cada modalidade segue o regulamento (06/10/2026)
// ---------------------------------------------------------------------------
// Não há cobrança genérica: onde o regulamento é omisso, a regra é pendente.
const testarDesempatePorModalidade = () => {
  secao('-- empate no mata-mata, por modalidade');

  const futsal = desempateDaModalidade('futsal');
  conferir(
    futsal.sequencia.join(',') === 'PENALTIS' && futsal.nomeCobranca.includes('3x1x1'),
    'futsal: pênaltis 3x1x1, como no regulamento'
  );
  for (const slug of ['handebol', 'basquete']) {
    conferir(
      desempateDaModalidade(slug).sequencia[0] === 'PRORROGACAO',
      `${slug}: prorrogação antes de qualquer cobrança`
    );
  }
  conferir(
    desempateDaModalidade('baleado').pendente === true && !desempateDaModalidade('baleado').nomeCobranca,
    'baleado: regulamento omisso, regra pendente e sem cobrança'
  );
  conferir(
    desempateDaModalidade('modalidade-que-nao-existe').pendente === true,
    'modalidade sem regra cai em pendente, nunca em pênalti genérico'
  );
};

// ---------------------------------------------------------------------------
// 5º lugar — só lógica
// ---------------------------------------------------------------------------
// O passeio já confere o 5º numa competição real. Aqui, duas de mentira,
// com desempate decidido pelos pontos: uma de 5 equipes (há 5º) e uma de 4
// (não há).
const testarQuintoLugar = () => {
  secao('-- 5º lugar');

  const equipe = (grupo, posicao, equipe_id, pontos) => ({
    ...equipeDeTeste(grupo, posicao, equipe_id), pontos, saldo: 0, vitorias: 0, marcados: 0,
    vermelhos: 0, amarelos: 0, jogos: 2
  });
  const jogo = (id, fase, um, dois) => ({
    id, fase, status: 'FINALIZADO', vencedor_equipe_id: um,
    equipe_1_id: um, equipe_2_id: dois, escola_1_nome: `E${um}`, escola_2_nome: `E${dois}`
  });
  // Semifinais 1×4 e 3×2, final 1×3: campeão 1, vice 3, 3º 4, 4º 2
  const mataMata = [
    jogo(1, 'SEMIFINAL', 1, 4), jogo(2, 'SEMIFINAL', 3, 2), jogo(3, 'FINAL', 1, 3)
  ];
  const colocar = (grupos) => colocacoesFinais({
    competicao: { proxima_fase: 'SEMIFINAL', qtd_grupos: 2, tipo_placar: 'GOLS' },
    todosOsJogos: mataMata,
    grupos,
    criterios: ['saldo', 'vitorias', 'marcados', 'menos_vermelhos', 'menos_amarelos'],
    jogos: [],
    comparacoes: {},
    faseDeGrupos: { completa: true }
  });

  // 5 equipes: grupo A com 3 (a 5 ficou de fora), grupo B com 2
  const cinco = colocar([
    { nome: 'A', equipes: [equipe('A', 1, 1, 6), equipe('A', 2, 2, 3), equipe('A', 3, 5, 1)] },
    { nome: 'B', equipes: [equipe('B', 1, 3, 3), equipe('B', 2, 4, 0)] }
  ]);
  const quinto = cinco.find((c) => c.posicao === 5);
  conferir(
    quinto?.equipe_id === 5 && quinto?.provisoria === false,
    'competição de 5 equipes: o 5º é quem não chegou à semifinal',
    JSON.stringify(quinto)
  );
  conferir(
    cinco.find((c) => c.posicao === 4)?.equipe_id === 2,
    'e o 4º é quem perdeu a semifinal para o vice'
  );

  // 6 equipes, e as duas fora da semifinal (5 e 6) empatam em tudo — mesmos
  // pontos, saldo, vitórias, gols e cartões, de grupos diferentes, sem
  // confronto direto: dividem o 5º, sem sorteio
  const seis = colocar([
    { nome: 'A', equipes: [equipe('A', 1, 1, 6), equipe('A', 2, 2, 3), equipe('A', 3, 5, 0)] },
    { nome: 'B', equipes: [equipe('B', 1, 3, 6), equipe('B', 2, 4, 3), equipe('B', 3, 6, 0)] }
  ]);
  const divididos = seis.filter((c) => c.posicao === 5);
  conferir(
    divididos.map((c) => c.equipe_id).sort().join(',') === '5,6'
      && divididos.every((c) => c.dividida && c.provisoria === false
        && c.como.startsWith(REGRAS_DA_CHAVE.quartoEQuinto.textoDoEmpate)),
    'empate em tudo: as duas candidatas aparecem como 5º, com "5º lugar dividido"',
    JSON.stringify(divididos)
  );

  // 4 equipes: todas jogam a semifinal, e não há 5º
  const quatro = colocar([
    { nome: 'A', equipes: [equipe('A', 1, 1, 3), equipe('A', 2, 2, 0)] },
    { nome: 'B', equipes: [equipe('B', 1, 3, 3), equipe('B', 2, 4, 0)] }
  ]);
  conferir(!quatro.some((c) => c.posicao === 5), 'competição de 4 equipes: não há 5º');
};

// ---------------------------------------------------------------------------
// Regras confirmadas pelo chefe em 06/10/2026 — só lógica, sem banco
// ---------------------------------------------------------------------------
// Um campeonato de verdade levaria muitas competições para produzir um empate
// na soma geral ou um "melhor segundo" de grupos de tamanhos diferentes. Os
// dois casos são conferidos direto nas funções que decidem.
const testarRegrasDoChefe = () => {
  secao('-- regras de 06/10/2026');

  // Mesma soma (07/10/2026): desempata quem tem mais 1ºs, depois 2ºs e 3ºs.
  // BETA e ALFA somam 10, mas ALFA tem um 1º lugar e BETA não; GAMA e DELTA
  // empatam em tudo e dividem a posição (numeração de competição).
  const soma = posicionar([
    { escola_nome: 'BETA', pontos: 10, primeiros: 0, segundos: 1, terceiros: 0 },
    { escola_nome: 'ALFA', pontos: 10, primeiros: 1, segundos: 0, terceiros: 0 },
    { escola_nome: 'GAMA', pontos: 6, primeiros: 0, segundos: 0, terceiros: 1 },
    { escola_nome: 'DELTA', pontos: 6, primeiros: 0, segundos: 0, terceiros: 1 },
    { escola_nome: 'EPSILON', pontos: 2, primeiros: 0, segundos: 0, terceiros: 0 }
  ]);
  const posicoes = soma.map((e) => `${e.escola_nome} ${e.posicao}`).join(', ');
  conferir(
    posicoes === 'ALFA 1, BETA 2, DELTA 3, GAMA 3, EPSILON 5',
    'mesma soma: mais 1ºs desempata; empate em tudo divide a posição',
    `saiu ${posicoes}`
  );

  // "Melhor segundo" sem descartar jogos: o segundo do grupo de 4 jogou 3
  // vezes e fez 6 pontos; o do grupo de 3 jogou 2 e fez 4. Pela regra
  // recusada, os jogos contra o último do grupo maior seriam descartados;
  // pela de 06/10, vale a campanha inteira e o de 6 pontos fica à frente.
  const segundoDe = (grupo, equipe_id, jogos, pontos) => ({
    equipe_id, escola_nome: `ESCOLA ${equipe_id}`, grupo_nome: grupo, posicao: 2,
    jogos, pontos, saldo: 0, vitorias: 0, marcados: 0, vermelhos: 0, amarelos: 0
  });
  const primeiroDe = (grupo, equipe_id) => ({ ...segundoDe(grupo, equipe_id, 3, 9), posicao: 1 });

  const comparacao = compararEntreGrupos(2, {
    competicao: { tipo_placar: 'GOLS' },
    criterios: ['saldo', 'vitorias', 'marcados', 'menos_vermelhos', 'menos_amarelos'],
    jogos: [],
    grupos: [
      { nome: 'A', equipes: [primeiroDe('A', 1), segundoDe('A', 2, 3, 6), {}, {}] },
      { nome: 'B', equipes: [primeiroDe('B', 3), segundoDe('B', 4, 2, 4), {}] }
    ]
  });
  conferir(
    comparacao.ordenadas[0]?.equipe_id === 2 && comparacao.ordenadas[0]?.pontos === 6,
    'melhor segundo comparado com todos os jogos, sem descartar nenhum',
    `primeiro da comparação: equipe ${comparacao.ordenadas[0]?.equipe_id}, ${comparacao.ordenadas[0]?.pontos} pts`
  );
  conferir(
    comparacao.jogos_diferentes === true,
    'números de jogos diferentes ligam o aviso da tela'
  );
};

// Equipe de mentira para as conferências de chave e colocação
const equipeDeTeste = (grupo, posicao, equipe_id) => ({
  equipe_id, escola_nome: `ESCOLA ${grupo}${posicao}`, grupo_id: grupo.charCodeAt(0),
  grupo_nome: grupo, posicao
});

// ---------------------------------------------------------------------------
// Semifinal com 3 grupos — decisão de 06/10/2026
// ---------------------------------------------------------------------------
// Só lógica, como a seção anterior: a função que monta a chave recebe uma
// competição de mentira.
const testarSemifinalDeTresGrupos = () => {
  secao('-- semifinal com 3 grupos');

  const equipe = equipeDeTeste;
  const formatoD = { qtd_grupos: 3, classificados_por_grupo: 1, melhores_segundos: 1 };
  // Fora de ordem de propósito: "A", "B" e "C" saem do nome do grupo
  const classificadosPorGrupo = ['C', 'A', 'B'].map((g, i) => ({
    grupo_id: g.charCodeAt(0), grupo_nome: g, equipes: [equipe(g, 1, 10 + i)]
  }));
  const primeiroDe = (g) => classificadosPorGrupo.find((x) => x.grupo_nome === g).equipes[0].equipe_id;
  const par = (c) => `${c.equipe_1_id}x${c.equipe_2_id}`;

  // Melhor 2º do grupo B: 1ºA × 2ºB e 1ºB × 1ºC, sem aviso
  const semRevanche = chaveDaSemifinal(formatoD, {
    classificadosPorGrupo, melhoresSegundos: [equipe('B', 2, 21)]
  });
  conferir(
    par(semRevanche.confrontos[0]) === `${primeiroDe('A')}x21`
      && par(semRevanche.confrontos[1]) === `${primeiroDe('B')}x${primeiroDe('C')}`,
    '3 grupos: 1ºA × melhor 2º e 1ºB × 1ºC',
    semRevanche.confrontos.map(par).join(' / ')
  );
  conferir(!semRevanche.observacao, 'sem revanche, sem aviso', semRevanche.observacao);

  // Melhor 2º do grupo A: a chave sai mesmo assim, com o aviso da regra pendente
  const comRevanche = chaveDaSemifinal(formatoD, {
    classificadosPorGrupo, melhoresSegundos: [equipe('A', 2, 22)]
  });
  conferir(
    !comRevanche.erro && par(comRevanche.confrontos[0]) === `${primeiroDe('A')}x22`,
    'revanche (1ºA × 2ºA) não bloqueia a semifinal',
    comRevanche.erro || comRevanche.confrontos.map(par).join(' / ')
  );
  conferir(
    !comRevanche.observacao && REGRAS_DA_CHAVE.revancheNaSemifinal.provisorio === false,
    'revanche aceita sem aviso (confirmado pelo chefe em 07/10)',
    comRevanche.observacao
  );
};

// ---------------------------------------------------------------------------
// 3º lugar sem semifinal — decisão de 06/10/2026
// ---------------------------------------------------------------------------
// As colocações saem de uma competição de mentira; o banco só é lido, para
// conferir quantos pontos o 3º lugar vale.
const testarTerceiroSemSemifinal = async () => {
  secao('-- 3º lugar sem semifinal');

  const equipe = equipeDeTeste;

  // Dois grupos, 1º de cada à final: o 3º é o melhor 2º pela campanha
  const final = {
    id: 1, fase: 'FINAL', status: 'FINALIZADO', vencedor_equipe_id: 1,
    equipe_1_id: 1, equipe_2_id: 2, escola_1_nome: 'ESCOLA A1', escola_2_nome: 'ESCOLA B1'
  };
  const melhorSegundo = equipe('B', 2, 4);
  const colocacoes = colocacoesFinais({
    competicao: { proxima_fase: 'FINAL', qtd_grupos: 2 },
    todosOsJogos: [final],
    grupos: [
      { nome: 'A', equipes: [equipe('A', 1, 1), equipe('A', 2, 3)] },
      { nome: 'B', equipes: [equipe('B', 1, 2), melhorSegundo] }
    ],
    comparacoes: { segundos: { ordenadas: [melhorSegundo, equipe('A', 2, 3)] } },
    faseDeGrupos: { completa: true }
  });
  const terceiro = colocacoes.find((c) => c.posicao === 3);
  conferir(
    terceiro?.equipe_id === 4 && terceiro.provisoria === false,
    '3º sem semifinal é o melhor 2º, sem marca de regra provisória',
    JSON.stringify(terceiro)
  );

  const [[pontuacao]] = await db.query('SELECT pontos FROM pontuacao_geral WHERE posicao = 3');
  conferir(
    pontuacao?.pontos === 6 && REGRAS.tabelaGeral.posicoesQuePontuam.includes(3),
    'o 3º lugar vale 6 pontos na tabela geral',
    `pontuacao_geral(3) = ${pontuacao?.pontos}`
  );
};

// ---------------------------------------------------------------------------
// Conflito de local (regrasProvisorias.conflitoDeLocal)
// ---------------------------------------------------------------------------
// Roda depois do passeio para os jogos extras não mexerem na classificação e
// no pódio já conferidos. Usa os locais que já existem (db/04_locais.sql), sem
// criar nem apagar nenhum, e um dia em que esses locais estão vazios. Os
// intervalos saem da regra, então o teste acompanha se ela mudar.
const testarConflitoDeLocal = async (competicao, equipes, grupos) => {
  secao('-- conflito de local');

  // Só o horário de INÍCIO conta (a duração das partidas está em aberto):
  // um minuto a menos que o intervalo conflita, o intervalo exato não.
  const { intervaloMinutos } = REGRAS.conflitoDeLocal;
  const quase = intervaloMinutos - 1;

  const [locais] = await db.query('SELECT id, nome FROM locais_disputa ORDER BY id LIMIT 2');
  if (locais.length < 2) {
    throw new Error('O teste de conflito precisa de dois locais em locais_disputa (db/04_locais.sql).');
  }
  const [L1, L2] = locais;

  // Primeiro dia, a partir de dezembro (depois do evento), sem jogo nenhum
  // nos dois locais: os jogos de quem usa o sistema não interferem no teste.
  let dia = null;
  for (let d = 0; d < 120 && !dia; d++) {
    const candidato = new Date(Date.UTC(2026, 11, 1 + d)).toISOString().slice(0, 10);
    const [[{ ocupados }]] = await db.query(
      `SELECT COUNT(*) AS ocupados FROM jogos
        WHERE local_id IN (?, ?) AND data_hora >= ? AND data_hora < ? + INTERVAL 1 DAY`,
      [L1.id, L2.id, candidato, candidato]
    );
    if (ocupados === 0) dia = candidato;
  }
  if (!dia) throw new Error('Não achei um dia livre nos locais para o teste de conflito.');

  // Minutos a partir das 08:00 do dia livre -> "AAAA-MM-DD HH:MM"
  const as = (minutos) => {
    const total = 8 * 60 + minutos;
    const hh = String(Math.floor(total / 60)).padStart(2, '0');
    const mm = String(total % 60).padStart(2, '0');
    return `${dia} ${hh}:${mm}`;
  };

  const doGrupo = equipes.filter((e) => e.grupo_nome === grupos[0]);
  const [a, b] = doGrupo;

  const tentar = async (local, quando, competicao_id = competicao.id, e1 = a.id, e2 = b.id) => {
    const r = await chamar('POST', '/jogos', {
      competicao_id, equipe_1_id: e1, equipe_2_id: e2, fase: 'GRUPOS',
      local_id: local.id, data_hora: quando
    });
    if (r.corpo.id_jogo) criados.jogos.push(r.corpo.id_jogo);
    return r;
  };

  console.log(`  locais ${L1.nome} e ${L2.nome}, dia ${dia}, intervalo ${intervaloMinutos} min`);

  const j1 = await tentar(L1, as(0));
  conferir(j1.status === 201, 'local e horário livres -> 201', `${j1.status} ${j1.corpo.erro || ''}`);

  const perto = await tentar(L1, as(quase));
  conferir(
    perto.status === 409,
    `mesmo local a ${quase} min do início -> 409`,
    `${perto.status} ${perto.corpo.erro || ''}`
  );
  conferir(
    perto.status === 409 && perto.corpo.erro.includes(L1.nome)
      && perto.corpo.erro.includes(`nº ${j1.corpo.numero_jogo}`)
      && perto.corpo.erro.includes(`${intervaloMinutos} minutos entre os horários de início`),
    'a recusa diz o local, o número do jogo que ocupa e o intervalo da regra',
    perto.corpo.erro
  );

  const j3 = await tentar(L1, as(intervaloMinutos));
  conferir(j3.status === 201, `mesmo local a exatamente ${intervaloMinutos} min -> 201`, `${j3.status} ${j3.corpo.erro || ''}`);

  const j4 = await tentar(L2, as(0));
  conferir(j4.status === 201, 'mesmo horário em outro local -> 201', `${j4.status} ${j4.corpo.erro || ''}`);

  const wo = await chamar('PUT', `/jogos/${j1.corpo.id_jogo}/wo`, {
    vencedor_equipe_id: a.id,
    motivo: `${MARCA} W.O. do teste de conflito`
  });
  conferir(wo.status === 200, 'W.O. declarado no primeiro jogo', `${wo.status} ${wo.corpo.erro || ''}`);

  const j5 = await tentar(L1, as(0));
  conferir(j5.status === 201, 'o W.O. libera o horário: agendar de novo passa', `${j5.status} ${j5.corpo.erro || ''}`);

  const semMudar = await chamar('PUT', `/jogos/${j3.corpo.id_jogo}`, {
    local_id: L1.id, data_hora: as(intervaloMinutos), arbitro_1: `${MARCA} árbitro`
  });
  conferir(
    semMudar.status === 200,
    'editar sem mudar a agenda -> 200',
    `${semMudar.status} ${semMudar.corpo.erro || ''}`
  );

  // Andar menos que o intervalo continua perto do horário antigo do próprio
  // jogo, que não pode contar como conflito consigo mesmo.
  const mexeuPouco = await chamar('PUT', `/jogos/${j3.corpo.id_jogo}`, {
    data_hora: as(intervaloMinutos + quase)
  });
  conferir(
    mexeuPouco.status === 200,
    `reagendar ${quase} min ignora o próprio jogo -> 200`,
    `${mexeuPouco.status} ${mexeuPouco.corpo.erro || ''}`
  );

  // Limpar a agenda volta o jogo para "a definir". Sem local nem horário não
  // há o que conferir, então a checagem de conflito não entra.
  const limpou = await chamar('PUT', `/jogos/${j3.corpo.id_jogo}`, { data_hora: '', local_id: '' });
  const [[limpo]] = await db.query('SELECT local_id, data_hora FROM jogos WHERE id = ?', [j3.corpo.id_jogo]);
  conferir(
    limpou.status === 200 && limpo.local_id === null && limpo.data_hora === null,
    'limpar data e local de jogo AGENDADO -> 200 e grava NULL',
    `${limpou.status} ${limpou.corpo.erro || ''} local=${limpo.local_id} data=${limpo.data_hora}`
  );

  // Só o local, mantendo o horário: também sai da checagem
  const soLocal = await chamar('PUT', `/jogos/${j5.corpo.id_jogo}`, { local_id: null });
  conferir(soLocal.status === 200, 'tirar só o local -> 200', `${soLocal.status} ${soLocal.corpo.erro || ''}`);

  // O primeiro jogo do passeio já está FINALIZADO pela súmula
  const finalizado = criados.jogos[0];
  const mudarFinalizado = await chamar('PUT', `/jogos/${finalizado}`, { local_id: L2.id, data_hora: as(300) });
  conferir(
    mudarFinalizado.status === 409,
    'mudar data/hora/local de jogo FINALIZADO -> 409',
    `${mudarFinalizado.status} ${mudarFinalizado.corpo.erro || ''}`
  );
  const arbitroFinalizado = await chamar('PUT', `/jogos/${finalizado}`, { arbitro_2: `${MARCA} árbitro` });
  conferir(
    arbitroFinalizado.status === 200,
    'árbitro de jogo FINALIZADO continua editável -> 200',
    `${arbitroFinalizado.status} ${arbitroFinalizado.corpo.erro || ''}`
  );

  await exigir('PUT', `/jogos/${j4.corpo.id_jogo}/iniciar`, null, 'iniciar o jogo');
  const mudarEmAndamento = await chamar('PUT', `/jogos/${j4.corpo.id_jogo}`, { data_hora: as(300) });
  conferir(
    mudarEmAndamento.status === 409,
    'mudar data/hora de jogo EM_ANDAMENTO -> 409',
    `${mudarEmAndamento.status} ${mudarEmAndamento.corpo.erro || ''}`
  );

  // ---- corrida -------------------------------------------------------------
  // Dois agendamentos ao mesmo tempo, no mesmo local e horário. Vêm de
  // competições DIFERENTES de propósito: na mesma competição eles já fariam
  // fila na trava da competição (numero_jogo), e o que se quer provar é a
  // trava do local. Três rodadas, em horários distintos.
  const [[outra]] = await db.query(
    `SELECT e1.competicao_id, e1.id AS e1, e2.id AS e2
       FROM equipes e1
       INNER JOIN equipes e2 ON e2.competicao_id = e1.competicao_id
                            AND e2.grupo_id = e1.grupo_id AND e2.id > e1.id
      WHERE e1.competicao_id NOT IN (?, ?)
        AND NOT EXISTS (SELECT 1 FROM jogos j WHERE j.competicao_id = e1.competicao_id)
      ORDER BY e1.competicao_id, e1.id
      LIMIT 1`,
    [competicao.id, COMPETICAO_PROTEGIDA]
  );
  if (!outra) throw new Error('Não achei uma segunda competição sem jogos para o teste de corrida.');

  for (const rodada of [1, 2, 3]) {
    const quando = as(240 + rodada * 2 * intervaloMinutos);
    const respostas = await Promise.all([
      tentar(L2, quando),
      tentar(L2, quando, outra.competicao_id, outra.e1, outra.e2)
    ]);
    const status = respostas.map((r) => r.status).sort();
    conferir(
      status[0] === 201 && status[1] === 409,
      `corrida ${rodada}: dois POST simultâneos no mesmo local e horário -> um 201 e um 409`,
      `saiu ${status.join(' e ')} ${respostas.map((r) => r.corpo.erro || '').join(' | ')}`
    );
  }
};

// ---------------------------------------------------------------------------
(async () => {
  let erroDoPasseio = null;

  try {
    await rodar();
  } catch (erro) {
    erroDoPasseio = erro;
    falhou++;
    console.log(`\n  FALHA ${erro.message}`);
  }

  secao('-- limpeza');
  try {
    await limpar();
  } catch (erro) {
    console.log(`  FALHA ao limpar: ${erro.sqlMessage || erro.message}`);
    falhou++;
  }

  const [[depois]] = await db.query(
    `SELECT (SELECT COUNT(*) FROM jogos) AS jogos,
            (SELECT COUNT(*) FROM atletas) AS atletas,
            (SELECT COUNT(*) FROM inscricoes_atletas) AS inscricoes,
            (SELECT COUNT(*) FROM sumula_atletas) AS sumulas,
            (SELECT COUNT(*) FROM ajustes_pontos_geral) AS ajustes,
            (SELECT COUNT(*) FROM usuarios) AS usuarios`
  );
  console.log(`  ${JSON.stringify(depois)}`);

  const [jogosDepois] = await db.query('SELECT id FROM jogos ORDER BY id');
  console.log(`  jogos que ficaram: ${jogosDepois.map((j) => j.id).join(', ') || '(nenhum)'}`);

  console.log(
    `\n${falhou === 0 ? 'TUDO PASSOU' : 'TEM FALHA'} — ${passou} ok, ${falhou} ${falhou === 1 ? 'falha' : 'falhas'}`
  );
  if (problemas.length > 0) {
    console.log(problemas.map((p) => `  - ${p}`).join('\n'));
  }
  if (erroDoPasseio) {
    console.log(`\n${erroDoPasseio.stack}`);
  }

  process.exit(falhou === 0 ? 0 : 1);
})();
