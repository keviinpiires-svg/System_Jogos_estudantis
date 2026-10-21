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
const { apurarSets } = require('../src/controllers/sumulaController');
const { lerData, lerHora } = require('../src/controllers/importacaoJogosController');
const { chaveDaSemifinal, REGRAS_DA_CHAVE } = require('../src/config/chavesMataMata');

const API = process.env.FUMACA_API || 'http://localhost:3000/api';
const MARCA = 'FUMACA';
const EMAIL = 'fumaca@local';
const EMAIL_MESA = 'fumaca-mesa@local';
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
  await db.query(
    `DELETE p FROM pontos_lancados p
       INNER JOIN usuarios u ON u.id = p.criado_por OR u.id = p.alterado_por
      WHERE u.email IN (?)`,
    [[EMAIL, EMAIL_MESA]]
  );
  // O histórico dos pontos lançados (db/17) aponta para os usuários de teste
  await db.query(
    `DELETE h FROM pontos_lancados_historico h
       INNER JOIN usuarios u ON u.id = h.usuario_id OR u.id = h.anterior_por
      WHERE u.email IN (?)`,
    [[EMAIL, EMAIL_MESA]]
  );
  await db.query('DELETE FROM usuarios WHERE email IN (?)', [[EMAIL, EMAIL_MESA]]);
  await db.query('DELETE FROM escola_apelidos WHERE apelido LIKE ?', [`${MARCA}%`]);

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
  testarSetsDoVolei();
  await testarTerceiroSemSemifinal();
  testarQuintoLugar();
  testarDesempatePorModalidade();
  testarFolhasOficiais();
  await testarEmpateDoBaleado();
  await testarMelhorDeDoisJogos('futsal');
  await testarMelhorDeDoisJogos('baleado');
  await testarJogoUnico();
  await testarAgenda();
  await testarDadosPessoais();
  await testarImportacaoDeJogos();
  await testarNumeroTabela();
  await testarPontosLancados();
  await testarPontosLancadosNaTabelaGeral();
  await testarAtletismoPorProva();
};

// ---------------------------------------------------------------------------
// Empate no baleado (chefe, 07/10/2026) — pela API, numa competição livre
// ---------------------------------------------------------------------------
// Fase de grupos: empate vale. Semifinal (chefe, 12/10/2026) e final (07/10):
// acréscimo de 4 minutos, vence quem balear primeiro
// (jogos.baleou_primeiro_equipe_id). O ida e volta com a soma empatada fica em
// testarMelhorDeDoisJogos (20/10/2026).
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
  const rSemiSemInformar = await sumula(semi);
  conferir(
    rSemiSemInformar.status === 400,
    'semifinal empatada sem dizer quem baleou primeiro: recusada (não é mais 409)',
    `${rSemiSemInformar.status} ${rSemiSemInformar.corpo.erro || ''}`
  );
  const rSemi = await sumula(semi, { baleou_primeiro_equipe_id: comp.e1 });
  const [[jSemi]] = await db.query(
    'SELECT status, vencedor_equipe_id, baleou_primeiro_equipe_id, placar_1, placar_2 FROM jogos WHERE id = ?', [semi]
  );
  conferir(
    rSemi.status === 201 && jSemi.status === 'FINALIZADO' && jSemi.vencedor_equipe_id === comp.e1
      && jSemi.baleou_primeiro_equipe_id === comp.e1 && jSemi.placar_1 === jSemi.placar_2,
    'semifinal empatada: vence quem baleou primeiro no acréscimo, e o placar fica empatado',
    `${rSemi.status} ${rSemi.corpo.erro || ''} ${JSON.stringify(jSemi)}`
  );

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

// "Melhor de dois jogos" (ida e volta de duas equipes, sem mata-mata) — pela
// API, no futsal e no baleado (20/10/2026). O campeão é quem soma mais nos
// dois jogos, pela soma direta dos placares, sem passar pela classificação.
// Empatada a soma, o 2º jogo exige o desempate: pênaltis no futsal; no
// baleado, o acréscimo de 4 minutos, e quem baleou primeiro é a campeã.
const testarMelhorDeDoisJogos = async (slug) => {
  secao(`-- melhor de dois jogos: ${slug}`);

  const [[comp]] = await db.query(
    `SELECT c.id, c.genero, cat.idade_maxima, e1.id AS e1, e2.id AS e2,
            e1.escola_id AS esc1, e2.escola_id AS esc2
       FROM competicoes c
       INNER JOIN modalidades m ON m.id = c.modalidade_id
       INNER JOIN categorias cat ON cat.id = c.categoria_id
       INNER JOIN equipes e1 ON e1.competicao_id = c.id
       INNER JOIN equipes e2 ON e2.competicao_id = c.id AND e2.id > e1.id
      WHERE m.slug = ? AND c.turno = 'IDA_E_VOLTA' AND c.proxima_fase = 'NENHUMA' AND c.id <> ?
        AND (SELECT COUNT(*) FROM equipes e WHERE e.competicao_id = c.id) = 2
        AND NOT EXISTS (SELECT 1 FROM jogos j WHERE j.competicao_id = c.id)
      ORDER BY c.id LIMIT 1`,
    [slug, COMPETICAO_PROTEGIDA]
  );
  if (!comp) throw new Error(`Não achei uma competição de ${slug} em ida e volta livre para o teste.`);
  const baleado = slug === 'baleado';

  const [[{ ano }]] = await db.query('SELECT ano FROM configuracao_evento WHERE id = 1');
  const nascimento = `${comp.idade_maxima ? ano - comp.idade_maxima : ano - 20}-03-15`;
  const sexo = comp.genero === 'FEMININO' ? 'F' : 'M';

  const atletaDe = async (equipe_id, escola_id, n) => {
    const atleta = await exigir('POST', '/atletas', {
      nome: `${MARCA} IV ${slug.toUpperCase()} ${n}`, rg: `${MARCA}IV${slug.slice(0, 3)}${n}`,
      data_nascimento: nascimento, sexo, escola_id
    }, 'cadastrar atleta do ida e volta');
    criados.atletas.push(atleta.id_atleta);
    await exigir('POST', '/inscricoes', { equipe_id, atleta_id: atleta.id_atleta, numero_camisa: 1 }, 'inscrever no ida e volta');
    return atleta.id_atleta;
  };
  const a1 = await atletaDe(comp.e1, comp.esc1, 1);
  const a2 = await atletaDe(comp.e2, comp.esc2, 2);

  const jogoEntre = async (um, dois) => {
    const jogo = await exigir('POST', '/jogos', {
      competicao_id: comp.id, equipe_1_id: um, equipe_2_id: dois, fase: 'GRUPOS'
    }, 'agendar jogo do ida e volta');
    criados.jogos.push(jogo.id_jogo);
    return jogo.id_jogo;
  };
  const apagarJogos = async (ids) => {
    await db.query('DELETE FROM sumula_atletas WHERE jogo_id IN (?)', [ids]);
    await db.query('DELETE FROM sumula_equipes WHERE jogo_id IN (?)', [ids]);
    await db.query('DELETE FROM jogos WHERE id IN (?)', [ids]);
    criados.jogos = criados.jogos.filter((id) => !ids.includes(id));
  };
  // Placar de cada equipe: gols no futsal; no baleado, o próprio contador de
  // adversárias eliminadas (chefe, 12/10/2026). `de1`/`de2` são de comp.e1/e2.
  const linha = (atleta_id, gols) => ({
    atleta_id, presente: true, capitao: true, gols: baleado ? 0 : gols, amarelos: 0, vermelho: false, faltas: 0
  });
  const sumula = (jogo_id, de1, de2, extra = {}) => chamar('POST', '/sumulas', {
    jogo_id, finalizar: true, ...extra,
    equipes: [
      { equipe_id: comp.e1, ...(baleado ? { baleados: de1 } : {}), atletas: [linha(a1, de1)] },
      { equipe_id: comp.e2, ...(baleado ? { baleados: de2 } : {}), atletas: [linha(a2, de2)] }
    ]
  });
  const podio = async () => ((await chamar('GET', `/matamata/competicao/${comp.id}`)).corpo.colocacoes || []);

  // Caso 1 — a soma decide: e1 vence a ida por 5 x 4 e perde a volta por
  // 1 x 3. Soma 6 x 7: a e2 é campeã, mesmo com uma vitória para cada (no
  // baleado, antes de 20/10, a classificação podia pôr a e1 em 1º).
  const ida = await jogoEntre(comp.e1, comp.e2);
  const rIda = await sumula(ida, 5, 4);
  const volta = await jogoEntre(comp.e2, comp.e1);
  const rVolta = await sumula(volta, 1, 3);
  const [campeao, vice] = await podio();
  conferir(
    rIda.status === 201 && rVolta.status === 201
      && campeao?.equipe_id === comp.e2 && campeao?.como.includes('6') && vice?.equipe_id === comp.e1,
    `${slug}: 5 x 4 e 1 x 3 (soma 6 x 7) — campeã é quem soma mais, pela soma direta`,
    `${rIda.status}/${rVolta.status} ${rVolta.corpo.erro || ''} ${JSON.stringify([campeao, vice])}`
  );
  await apagarJogos([ida, volta]);

  // Caso 2 — soma empatada: 5 x 4 na ida e 4 x 5 na volta (9 x 9)
  const ida2 = await jogoEntre(comp.e1, comp.e2);
  await sumula(ida2, 5, 4);
  const volta2 = await jogoEntre(comp.e2, comp.e1);
  const semDesempate = await sumula(volta2, 4, 5);
  conferir(
    semDesempate.status === 400,
    `${slug}: soma empatada sem o desempate do 2º jogo é recusada (400, não 409)`,
    `${semDesempate.status} ${semDesempate.corpo.erro || ''}`
  );

  // Na volta a equipe 1 do jogo é a e2: penaltis_2 = 3 dá a vitória à e1
  const comDesempate = baleado
    ? await sumula(volta2, 4, 5, { baleou_primeiro_equipe_id: comp.e1 })
    : await sumula(volta2, 4, 5, { penaltis_1: 2, penaltis_2: 3 });
  const esperado = comp.e1;
  const [[jVolta2]] = await db.query(
    'SELECT status, vencedor_equipe_id, baleou_primeiro_equipe_id, penaltis_1, penaltis_2 FROM jogos WHERE id = ?', [volta2]
  );
  const [campeao2] = await podio();
  conferir(
    comDesempate.status === 201 && jVolta2.vencedor_equipe_id === esperado && campeao2?.equipe_id === esperado
      && (baleado ? jVolta2.baleou_primeiro_equipe_id === comp.e1 : jVolta2.penaltis_1 === 2),
    baleado
      ? 'baleado: soma empatada — quem baleou primeiro no acréscimo do 2º jogo é a campeã'
      : 'futsal: soma empatada — os pênaltis do 2º jogo dão o título',
    `${comDesempate.status} ${comDesempate.corpo.erro || ''} ${JSON.stringify(jVolta2)} ${JSON.stringify(campeao2)}`
  );
  await apagarJogos([ida2, volta2]);
};

// Competição de 2 escolas com um jogo só (Handebol M Sub 9, db/14, tabela do
// chefe de 20/10/2026): funciona como final única, e os textos falam do jogo,
// não da "soma dos dois jogos". Sem a competição no banco, o teste é pulado.
const testarJogoUnico = async () => {
  secao('-- 2 escolas e 1 jogo só (Handebol M Sub 9)');

  const [[comp]] = await db.query(
    `SELECT c.id FROM competicoes c
       INNER JOIN modalidades m ON m.id = c.modalidade_id
       INNER JOIN categorias cat ON cat.id = c.categoria_id
      WHERE m.slug = 'handebol' AND cat.nome = 'Sub 9' AND c.genero = 'MASCULINO'
        AND c.turno = 'IDA_E_VOLTA' AND c.id <> ?
        AND NOT EXISTS (SELECT 1 FROM jogos j WHERE j.competicao_id = c.id)`,
    [COMPETICAO_PROTEGIDA]
  );
  if (!comp) {
    console.log('  (pulado: sem o Handebol M Sub 9 livre — o db/14 não rodou neste banco)');
    return;
  }
  const [eq] = await db.query('SELECT id, grupo_id FROM equipes WHERE competicao_id = ? ORDER BY id', [comp.id]);
  const podio = async () => ((await chamar('GET', `/matamata/competicao/${comp.id}`)).corpo.colocacoes || []);

  // Vitória: o jogo gravado já finalizado, 3 x 2
  const [vitoria] = await db.query(
    `INSERT INTO jogos (competicao_id, numero_jogo, fase, grupo_id, equipe_1_id, equipe_2_id,
                        status, placar_1, placar_2, vencedor_equipe_id)
     VALUES (?, 1, 'GRUPOS', ?, ?, ?, 'FINALIZADO', 3, 2, ?)`,
    [comp.id, eq[0].grupo_id, eq[0].id, eq[1].id, eq[0].id]
  );
  criados.jogos.push(vitoria.insertId);
  const [campeao] = await podio();
  conferir(
    campeao?.equipe_id === eq[0].id && campeao.como === 'venceu o jogo (3 × 2)',
    'jogo único vencido: "venceu o jogo", sem falar em soma',
    JSON.stringify(campeao)
  );
  await db.query('DELETE FROM jogos WHERE id = ?', [vitoria.insertId]);
  criados.jogos = criados.jogos.filter((id) => id !== vitoria.insertId);

  // Empate pela súmula (sem gols: 0 x 0): prorrogação e 7 metros, como numa final
  const jogo = await exigir('POST', '/jogos', {
    competicao_id: comp.id, equipe_1_id: eq[0].id, equipe_2_id: eq[1].id, fase: 'GRUPOS'
  }, 'agendar o jogo único');
  criados.jogos.push(jogo.id_jogo);
  const sumula = (extra) => chamar('POST', '/sumulas', {
    jogo_id: jogo.id_jogo, finalizar: true, ...extra, equipes: eq.map((e) => ({ equipe_id: e.id, atletas: [] }))
  });
  const semProrrogacao = await sumula({});
  const comCobranca = await sumula({ prorrogacao: true, penaltis_1: 3, penaltis_2: 4 });
  const [campeao2] = await podio();
  conferir(
    semProrrogacao.status === 400 && (semProrrogacao.corpo.erro || '').startsWith('O jogo terminou empatado')
      && comCobranca.status === 201 && campeao2?.equipe_id === eq[1].id && campeao2.como === 'campeão nas cobranças',
    'jogo único empatado: "O jogo terminou empatado", prorrogação e 7 metros, e "campeão nas cobranças"',
    `${semProrrogacao.status} ${semProrrogacao.corpo.erro || ''} | ${comCobranca.status} ${comCobranca.corpo.erro || ''} | ${JSON.stringify(campeao2)}`
  );
};

// Agenda de jogos (pública, 20/10/2026): a lista e o detalhe trazem só os
// campos da tela; os atletas só com nome e camisa — nunca RG nem nascimento.
const testarAgenda = async () => {
  secao('-- agenda de jogos (pública)');

  const [[comp]] = await db.query(
    `SELECT c.id, c.genero, cat.idade_maxima, e1.id AS e1, e2.id AS e2, e1.escola_id AS esc1
       FROM competicoes c
       INNER JOIN categorias cat ON cat.id = c.categoria_id
       INNER JOIN modalidades m ON m.id = c.modalidade_id
       INNER JOIN equipes e1 ON e1.competicao_id = c.id
       INNER JOIN equipes e2 ON e2.competicao_id = c.id AND e2.grupo_id = e1.grupo_id AND e2.id > e1.id
      WHERE m.tipo = 'COLETIVO' AND c.turno = 'UNICO' AND c.id <> ?
        AND NOT EXISTS (SELECT 1 FROM jogos j WHERE j.competicao_id = c.id)
        AND NOT EXISTS (SELECT 1 FROM inscricoes_atletas i WHERE i.equipe_id IN (e1.id, e2.id))
      ORDER BY c.id DESC LIMIT 1`,
    [COMPETICAO_PROTEGIDA]
  );
  if (!comp) throw new Error('Não achei uma competição livre para o teste da agenda.');
  const [[local]] = await db.query('SELECT id, nome FROM locais_disputa ORDER BY id LIMIT 1');
  const [[{ ano }]] = await db.query('SELECT ano FROM configuracao_evento WHERE id = 1');

  const atleta = await exigir('POST', '/atletas', {
    nome: `${MARCA} AGENDA`, rg: `${MARCA}AGENDA`, sexo: comp.genero === 'FEMININO' ? 'F' : 'M',
    data_nascimento: `${comp.idade_maxima ? ano - comp.idade_maxima : ano - 20}-03-15`, escola_id: comp.esc1
  }, 'cadastrar atleta da agenda');
  criados.atletas.push(atleta.id_atleta);
  await exigir('POST', '/inscricoes', { equipe_id: comp.e1, atleta_id: atleta.id_atleta, numero_camisa: 10 }, 'inscrever na agenda');
  const jogo = await exigir('POST', '/jogos', {
    competicao_id: comp.id, equipe_1_id: comp.e1, equipe_2_id: comp.e2, fase: 'GRUPOS',
    data_hora: '2026-11-25T05:41', local_id: local.id
  }, 'agendar jogo da agenda');
  criados.jogos.push(jogo.id_jogo);

  // Sem token: as duas rotas são públicas
  const lista = await fetch(`${API}/agenda`);
  const corpoLista = await lista.text();
  const doJogo = lista.ok ? JSON.parse(corpoLista).find((j) => j.id === jogo.id_jogo) : null;
  conferir(
    lista.status === 200 && doJogo?.data === '2026-11-25' && doJogo?.hora === '05:41'
      && doJogo?.local?.nome === local.nome && doJogo?.status === 'AGENDADO' && doJogo?.placar === null,
    'GET /agenda sem login: o jogo com dia e hora de parede, local e status, sem placar antes de encerrar',
    `${lista.status} ${JSON.stringify(doJogo)}`
  );

  const detalhe = await fetch(`${API}/agenda/jogos/${jogo.id_jogo}`);
  const corpoDetalhe = await detalhe.text();
  const d = detalhe.ok ? JSON.parse(corpoDetalhe) : {};
  conferir(
    detalhe.status === 200 && d.equipe_1?.atletas?.length === 1
      && JSON.stringify(d.equipe_1.atletas[0]) === JSON.stringify({ nome: `${MARCA} AGENDA`, numero_camisa: 10 })
      && Array.isArray(d.equipe_2?.atletas) && d.equipe_2.atletas.length === 0,
    'GET /agenda/jogos/:id sem login: atletas só com nome e camisa; equipe sem inscritos vem vazia',
    `${detalhe.status} ${JSON.stringify(d.equipe_1)} ${JSON.stringify(d.equipe_2)}`
  );
  conferir(
    ![corpoLista, corpoDetalhe].some((c) => /"rg"|nascimento|"sexo"|arbitro|observac/i.test(c))
      && !corpoDetalhe.includes(`${MARCA}AGENDA"`),
    'resposta pública sem RG, nascimento, sexo, árbitros nem observações'
  );
  const inexistente = await fetch(`${API}/agenda/jogos/999999999`);
  conferir(inexistente.status === 404, 'detalhe de jogo inexistente -> 404', `saiu ${inexistente.status}`);
};

// Dado pessoal de atleta nas rotas públicas (pendência 19, 20/10/2026): sem
// login, nenhuma leitura traz RG, nascimento nem sexo; com login de ADMIN, as
// telas de cadastro e inscrição continuam recebendo o que precisam.
const PESSOAL = /"rg"|nascimento|"sexo"/i;
const testarDadosPessoais = async () => {
  secao('-- dado pessoal de atleta nas rotas públicas');

  const [[equipe]] = await db.query(
    `SELECT e.id, e.escola_id, e.competicao_id, c.genero, cat.idade_maxima
       FROM equipes e
       INNER JOIN competicoes c ON c.id = e.competicao_id
       INNER JOIN categorias cat ON cat.id = c.categoria_id
       INNER JOIN modalidades m ON m.id = c.modalidade_id
      WHERE m.tipo = 'COLETIVO' AND c.id <> ?
        AND NOT EXISTS (SELECT 1 FROM inscricoes_atletas i WHERE i.equipe_id = e.id)
      ORDER BY e.id DESC LIMIT 1`,
    [COMPETICAO_PROTEGIDA]
  );
  const [[{ ano }]] = await db.query('SELECT ano FROM configuracao_evento WHERE id = 1');
  const atleta = await exigir('POST', '/atletas', {
    nome: `${MARCA} PRIVADO`, rg: `${MARCA}PRIV`, sexo: equipe.genero === 'FEMININO' ? 'F' : 'M',
    data_nascimento: `${equipe.idade_maxima ? ano - equipe.idade_maxima : ano - 20}-03-15`, escola_id: equipe.escola_id
  }, 'cadastrar atleta do teste de privacidade');
  criados.atletas.push(atleta.id_atleta);
  await exigir('POST', '/inscricoes', { equipe_id: equipe.id, atleta_id: atleta.id_atleta, numero_camisa: 4 }, 'inscrever no teste de privacidade');

  const semLogin = async (caminho) => {
    const r = await fetch(`${API}${caminho}`);
    return { status: r.status, texto: await r.text() };
  };

  // As três rotas reduzidas: sem login, só nome (e camisa/ids internos)
  for (const caminho of [`/atletas/escola/${equipe.escola_id}`, `/atletas/equipe/${equipe.escola_id}`, `/inscricoes/equipe/${equipe.id}`]) {
    const r = await semLogin(caminho);
    conferir(
      r.status === 200 && r.texto.includes(`${MARCA} PRIVADO`) && !PESSOAL.test(r.texto) && !r.texto.includes(`${MARCA}PRIV"`),
      `GET ${caminho.replace(/\d+/, ':id')} sem login: o nome aparece, sem RG, nascimento nem sexo`,
      `${r.status} ${r.texto.slice(0, 160)}`
    );
  }

  // Com login de ADMIN, cadastro e inscrição seguem recebendo sexo e nascimento
  const admin = await chamar('GET', `/atletas/escola/${equipe.escola_id}`);
  const doAdmin = (admin.corpo || []).find((a) => a.id === atleta.id_atleta);
  const elencoAdmin = await chamar('GET', `/inscricoes/equipe/${equipe.id}`);
  const inscritoAdmin = (elencoAdmin.corpo.atletas || []).find((a) => a.atleta_id === atleta.id_atleta);
  conferir(
    Boolean(doAdmin?.data_nascimento && doAdmin?.sexo) && Boolean(inscritoAdmin?.ano_nascimento && inscritoAdmin?.sexo),
    'com login de ADMIN, atletas e elenco continuam com sexo e nascimento (telas de cadastro e inscrição)',
    JSON.stringify({ doAdmin, inscritoAdmin })
  );

  // Elegíveis: só o ADMIN
  const elegiveisSemLogin = await semLogin(`/equipes/${equipe.id}/atletas-elegiveis`);
  const elegiveisAdmin = await chamar('GET', `/equipes/${equipe.id}/atletas-elegiveis`);
  conferir(
    elegiveisSemLogin.status === 401 && elegiveisAdmin.status === 200,
    'GET /equipes/:id/atletas-elegiveis: 401 sem login, 200 para o ADMIN',
    `${elegiveisSemLogin.status} / ${elegiveisAdmin.status}`
  );

  // Varredura das outras leituras públicas que trazem atleta
  const [[jogo]] = await db.query('SELECT id, competicao_id FROM jogos ORDER BY id LIMIT 1');
  const publicas = ['/artilharia/lideres', `/artilharia/competicao/${equipe.competicao_id}`,
    `/suspensoes/competicao/${equipe.competicao_id}`, `/competicoes/${equipe.competicao_id}`,
    `/classificacao/competicao/${equipe.competicao_id}`, `/matamata/competicao/${equipe.competicao_id}`,
    '/agenda', '/dashboard', '/tabela-geral', '/equipes'];
  if (jogo) publicas.push(`/sumulas/${jogo.id}`, `/suspensoes/jogo/${jogo.id}`, `/agenda/jogos/${jogo.id}`, `/jogos/${jogo.id}`);
  const vazando = [];
  for (const caminho of publicas) {
    const r = await semLogin(caminho);
    if (r.status !== 200) vazando.push(`${caminho}: HTTP ${r.status}`);
    else if (PESSOAL.test(r.texto)) vazando.push(`${caminho}: ${r.texto.match(PESSOAL)[0]}`);
  }
  conferir(vazando.length === 0, `${publicas.length} leituras públicas sem RG, nascimento nem sexo`, vazando.join(' | '));
};

// ---------------------------------------------------------------------------
// Sets do vôlei (chefe, 12/10/2026) — só lógica
// ---------------------------------------------------------------------------
// Três sets de 21, o 3º inclusive, com 2 de vantagem e sem teto.
const testarSetsDoVolei = () => {
  secao('-- sets do vôlei');

  const volei = folhaDaModalidade('volei', 'Vôlei');
  const jogo = (...placares) => placares.map(([pontos_1, pontos_2], i) => ({ numero_set: i + 1, pontos_1, pontos_2 }));

  const tresSets = apurarSets(jogo([21, 15], [18, 21], [21, 19]), volei, true);
  conferir(
    !tresSets.erro && tresSets.vencidos.um === 2 && tresSets.vencidos.dois === 1,
    '3º set de 21 x 19 fecha o jogo em 2 x 1',
    tresSets.erro
  );
  const setCurto = apurarSets(jogo([21, 15], [18, 21], [15, 13]), volei, true);
  conferir(Boolean(setCurto.erro), '3º set de 15 x 13 não fecha: o 3º set também é de 21', setCurto.erro || 'aceito');
  const semTeto = apurarSets(jogo([21, 15], [18, 21], [27, 25]), volei, true);
  conferir(!semTeto.erro && semTeto.vencidos.um === 2, '3º set sem teto: 27 x 25 fecha', semTeto.erro);
  const semVantagem = apurarSets(jogo([21, 15], [18, 21], [21, 20]), volei, true);
  conferir(Boolean(semVantagem.erro), '3º set de 21 x 20 não fecha: precisa de 2 de vantagem', semVantagem.erro || 'aceito');
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
    handebol.linhas === 12 && handebol.linhasMaximas === 12
      && folhaDaModalidade('baleado', 'Baleado').linhasMaximas === 12,
    'handebol e baleado: sempre 12 linhas (elenco de 12, 07/10/2026)'
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
  const baleado = desempateDaModalidade('baleado');
  conferir(
    !baleado.pendente && !baleado.nomeCobranca && baleado.acrescimo?.somaDosDoisJogos === true
      && baleado.acrescimo.fases.join(',') === 'SEMIFINAL,FINAL',
    'baleado: sem cobrança; acréscimo na semifinal, na final e no 2º jogo do ida e volta'
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
// Importação de jogos por CSV — pela API, numa competição livre
// ---------------------------------------------------------------------------
// Prévia sem gravar, linhas com erro de fora, avisos que não bloqueiam,
// numeração por data e hora, e reimportação que não duplica.
const enviarCsv = async (caminho, csv) => {
  const resposta = await fetch(`${API}${caminho}`, {
    method: 'POST',
    headers: { 'Content-Type': 'text/csv', Authorization: `Bearer ${token}` },
    body: csv
  });
  return { status: resposta.status, corpo: await resposta.json().catch(() => ({})) };
};

// Nº Tabela — o número do jogo na tabela oficial do chefe (db/15, 20/10/2026).
// Coluna opcional do CSV: com ou sem ela, célula vazia aceita, número repetido
// no arquivo ou já usado no banco é erro, e reimportar só preenche o número de
// jogo que já existe e está sem — sem mudar mais nada nem trocar número gravado.
const testarNumeroTabela = async () => {
  secao('-- Nº Tabela (número da tabela do chefe)');

  const [[comp]] = await db.query(
    `SELECT c.id, m.nome AS modalidade, cat.nome AS categoria, c.genero, g.id AS grupo_id
       FROM competicoes c
       INNER JOIN modalidades m ON m.id = c.modalidade_id
       INNER JOIN categorias cat ON cat.id = c.categoria_id
       INNER JOIN grupos g ON g.competicao_id = c.id
       INNER JOIN equipes e ON e.grupo_id = g.id
      WHERE c.id <> ? AND NOT EXISTS (SELECT 1 FROM jogos j WHERE j.competicao_id = c.id)
      GROUP BY c.id, g.id
     HAVING COUNT(e.id) >= 3
      ORDER BY c.id LIMIT 1`,
    [COMPETICAO_PROTEGIDA]
  );
  if (!comp) throw new Error('Não achei uma competição livre com grupo de 3 equipes para o teste do Nº Tabela.');
  const [eq] = await db.query(
    'SELECT esc.nome FROM equipes e INNER JOIN escolas esc ON esc.id = e.escola_id WHERE e.grupo_id = ? ORDER BY e.id LIMIT 3',
    [comp.grupo_id]
  );
  const [[{ maior }]] = await db.query('SELECT COALESCE(MAX(numero_tabela), 0) AS maior FROM jogos');
  const n = (k) => 9000 + Number(maior) + k; // números que o banco ainda não usa (o MAX volta como texto)
  const CAB = 'Modalidade;Categoria;Gênero;Grupo;Equipe 1;Equipe 2;Data;Hora;Local;Rodada;Árbitro;Nº Tabela';
  const linhaCsv = (a, b, hora, numero) => [comp.modalidade, comp.categoria, comp.genero, '', eq[a].nome, eq[b].nome,
    '26/11/2026', hora, '', '', '', numero].join(';');
  const meus = async () => (await db.query(
    'SELECT id, numero_tabela, data_hora, local_id, rodada, arbitro_1, numero_jogo FROM jogos WHERE competicao_id = ? ORDER BY data_hora',
    [comp.id]
  ))[0];
  const linha = (r, k) => (r.corpo.linhas || []).find((l) => l.linha === k) || { erros: [], avisos: [] };

  // 1) Com a coluna: número, célula vazia e um par repetido no arquivo
  const csv1 = [CAB,
    linhaCsv(0, 1, '05:01', n(1)), // 2: nova com número
    linhaCsv(0, 2, '05:02', ''), // 3: nova sem número (célula vazia)
    linhaCsv(1, 2, '05:03', n(2)), // 4: repetido...
    linhaCsv(1, 0, '05:04', n(2)) // 5: ...com a linha 4
  ].join('\r\n');
  const previa1 = await enviarCsv('/importacao-jogos/previa', csv1);
  conferir(
    previa1.status === 200 && linha(previa1, 2).situacao === 'NOVA' && linha(previa1, 2).numero_tabela === n(1)
      && linha(previa1, 3).situacao === 'NOVA' && linha(previa1, 3).numero_tabela === null
      && [4, 5].every((k) => linha(previa1, k).situacao === 'ERRO' && linha(previa1, k).erros.some((e) => e.includes('repetido no arquivo'))),
    'com a coluna: número aceito, célula vazia aceita, número repetido no arquivo é erro nas duas linhas',
    JSON.stringify(previa1.corpo.resumo || previa1.corpo)
  );
  const imp1 = await enviarCsv('/importacao-jogos', csv1);
  let gravados = await meus();
  criados.jogos.push(...gravados.map((j) => j.id));
  conferir(
    imp1.status === 201 && gravados.length === 2 && gravados[0].numero_tabela === n(1) && gravados[1].numero_tabela === null,
    'importação grava o número da nova e deixa vazio o da célula vazia; as repetidas não entram',
    JSON.stringify(gravados)
  );

  // 2) Número que já é de outro jogo no banco
  const previa2 = await enviarCsv('/importacao-jogos/previa', [CAB, linhaCsv(1, 2, '05:05', n(1))].join('\r\n'));
  conferir(
    linha(previa2, 2).situacao === 'ERRO' && linha(previa2, 2).erros.some((e) => e.includes(`${n(1)} já é do jogo`)),
    'número que já é de outro jogo do banco: erro',
    JSON.stringify(linha(previa2, 2).erros)
  );

  // 3) Reimportar: preenche o número do jogo sem número; não troca o já gravado
  const antes = await meus();
  const csv3 = [CAB, linhaCsv(0, 1, '05:01', n(9)), linhaCsv(0, 2, '05:02', n(3))].join('\r\n');
  const previa3 = await enviarCsv('/importacao-jogos/previa', csv3);
  conferir(
    previa3.corpo.resumo?.numeros_a_preencher === 1 && previa3.corpo.resumo?.novas === 0
      && linha(previa3, 3).preencher_numero === true
      && linha(previa3, 2).avisos.some((a) => a.includes('não troca')),
    'reimportação: 1 número a preencher, nenhum jogo novo, aviso para o número já gravado',
    JSON.stringify(previa3.corpo.resumo)
  );
  const imp3 = await enviarCsv('/importacao-jogos', csv3);
  gravados = await meus();
  const igualFora = (a, b) => JSON.stringify({ ...a, numero_tabela: 0 }) === JSON.stringify({ ...b, numero_tabela: 0 });
  conferir(
    imp3.status === 201 && gravados.length === 2 && gravados[0].numero_tabela === n(1) && gravados[1].numero_tabela === n(3)
      && gravados.every((g, i) => igualFora(g, antes[i])),
    'reimportação preenche só o número do jogo sem número; o resto do jogo e o número já gravado não mudam',
    JSON.stringify(gravados)
  );

  // 4) Sem a coluna: o arquivo é aceito e o número gravado continua
  const semColuna = await enviarCsv('/importacao-jogos/previa',
    [CAB.replace(';Nº Tabela', ''), linhaCsv(0, 1, '05:01', '').replace(/;$/, '')].join('\r\n'));
  conferir(
    semColuna.status === 200 && linha(semColuna, 2).situacao === 'EXISTENTE' && !linha(semColuna, 2).preencher_numero,
    'sem a coluna Nº Tabela: arquivo aceito, nada a preencher',
    JSON.stringify(semColuna.corpo.resumo || semColuna.corpo)
  );

  // 5) A agenda (pública) devolve o número
  const agenda = await (await fetch(`${API}/agenda`)).json();
  conferir(
    agenda.find((j) => j.id === gravados[0].id)?.numero_tabela === n(1)
      && agenda.find((j) => j.id === gravados[1].id)?.numero_tabela === n(3),
    'GET /agenda devolve o numero_tabela de cada jogo'
  );
};

const testarImportacaoDeJogos = async () => {
  secao('-- importação de jogos por CSV');

  conferir(
    lerData('31/11/2026', 2026) === undefined && lerData('23/11', 2026) === '2026-11-23'
      && lerHora('14h') === '14:00' && lerHora('25:00') === undefined,
    'datas e horas: 31/11 recusado, ano do evento quando falta, 14h e 25:00'
  );

  const [[comp]] = await db.query(
    `SELECT c.id, m.nome AS modalidade, cat.nome AS categoria, c.genero, g.nome AS grupo,
            MIN(e.id) AS qualquer
       FROM competicoes c
       INNER JOIN modalidades m ON m.id = c.modalidade_id
       INNER JOIN categorias cat ON cat.id = c.categoria_id
       INNER JOIN grupos g ON g.competicao_id = c.id
       INNER JOIN equipes e ON e.grupo_id = g.id
      WHERE c.id <> ? AND NOT EXISTS (SELECT 1 FROM jogos j WHERE j.competicao_id = c.id)
      GROUP BY c.id, g.id
     HAVING COUNT(e.id) >= 3
      ORDER BY c.id DESC LIMIT 1`,
    [COMPETICAO_PROTEGIDA]
  );
  if (!comp) throw new Error('Não achei uma competição livre com grupo de 3 equipes para a importação.');

  const [equipes] = await db.query(
    `SELECT e.id, esc.id AS escola_id, esc.nome FROM equipes e
       INNER JOIN escolas esc ON esc.id = e.escola_id
       INNER JOIN grupos g ON g.id = e.grupo_id
      WHERE e.competicao_id = ? AND g.nome = ? ORDER BY e.id LIMIT 3`,
    [comp.id, comp.grupo]
  );
  const [e1, e2, e3] = equipes;
  const [locais] = await db.query('SELECT nome FROM locais_disputa ORDER BY id LIMIT 2');

  // Nome ambíguo: dois apelidos que só diferem no ponto servem a escolas diferentes
  await db.query('INSERT INTO escola_apelidos (escola_id, apelido) VALUES (?, ?), (?, ?)',
    [e2.escola_id, `${MARCA} AMBIGUA`, e3.escola_id, `${MARCA} AMBIGUA.`]);

  // Escrita torta de propósito: minúsculas, espaços e "SUB-0N"
  const torto = (nome) => `  ${nome.toLowerCase().replace(/ /g, '  ')} `;
  const categoria = comp.categoria.replace(/^Sub (\d+)$/, 'SUB-0$1');
  const genero = { MASCULINO: 'M', FEMININO: 'f', MISTO: 'misto' }[comp.genero];
  const base = (eq1, eq2, data, hora, local, extra = {}) => [
    extra.modalidade || comp.modalidade, categoria, genero, extra.grupo || '',
    eq1, eq2, data, hora, local, extra.rodada || '', extra.arbitro || ''
  ].join(';');

  const csv = [
    'Modalidade;Categoria;Gênero;Grupo;Equipe 1;Equipe 2;Data;Hora;Local;Rodada;Árbitro',
    base(torto(e1.nome), e2.nome, '24/11/2026', '05:13', locais[0].nome, { grupo: `Grupo ${comp.grupo}`, rodada: 1, arbitro: `${MARCA} árbitro` }), // 2
    base(e1.nome, e3.nome, '23/11/2026', '05:13', locais[0].nome, { modalidade: comp.modalidade.toUpperCase() }), // 3
    base(e2.nome, e3.nome, '24/11/2026', '05h13', locais[0].nome), // 4: e2 e local no mesmo horário da linha 2
    base(e2.nome, e1.nome, '24/11/2026', '05:13', locais[0].nome), // 5: repete a linha 2
    base(e1.nome, e2.nome, '30/11/2026', '05:13', locais[1].nome), // 6: fora do evento, confronto repetido
    base('ESCOLA QUE NAO EXISTE', e1.nome, '25/11/2026', '05:13', ''), // 7
    base(`${MARCA} ambígua`, e1.nome, '25/11/2026', '05:13', ''), // 8
    base(e1.nome, e3.nome, '25/11/2026', '05:13', 'Quadra Inexistente') // 9
  ].join('\r\n');

  const contarJogos = async () => (await db.query('SELECT COUNT(*) AS n FROM jogos WHERE competicao_id = ?', [comp.id]))[0][0].n;
  const linha = (resposta, n) => resposta.corpo.linhas.find((l) => l.linha === n);
  const temAviso = (l, trecho) => l.avisos.some((a) => a.includes(trecho));

  const semToken = await fetch(`${API}/importacao-jogos/previa`, {
    method: 'POST', headers: { 'Content-Type': 'text/csv' }, body: csv
  });
  conferir(semToken.status === 401, 'prévia sem login -> 401', `saiu ${semToken.status}`);

  const previa = await enviarCsv('/importacao-jogos/previa', csv);
  const r = previa.corpo.resumo || {};
  conferir(
    previa.status === 200 && r.novas === 4 && r.duplicadas === 1 && r.erros === 3 && r.existentes === 0,
    'prévia: 4 novas, 1 duplicada e 3 com erro',
    `${previa.status} ${previa.corpo.erro || JSON.stringify(r)}`
  );
  conferir(await contarJogos() === 0, 'a prévia não grava nada');

  if (previa.status === 200) {
    conferir(
      [linha(previa, 3), linha(previa, 2), linha(previa, 4), linha(previa, 6)].map((l) => l.numero_jogo).join(',') === '1,2,3,4',
      'numeração por data e hora: a linha do dia 23 é o jogo 1, mesmo vindo depois no arquivo'
    );
    conferir(
      linha(previa, 2).equipe_1 === e1.nome && linha(previa, 2).grupo === comp.grupo,
      'escola reconhecida sem maiúsculas e com espaços sobrando; grupo "Grupo X" aceito'
    );
    conferir(
      temAviso(linha(previa, 4), 'mesmo horário') && temAviso(linha(previa, 4), 'minutos entre os inícios'),
      'aviso: equipe em dois jogos no mesmo horário e local ocupado'
    );
    conferir(
      temAviso(linha(previa, 6), 'fora do evento') && temAviso(linha(previa, 6), 'Confronto repetido'),
      'aviso: data fora de 23 a 28/11 e confronto repetido no grupo'
    );
    conferir(
      linha(previa, 7).situacao === 'ERRO' && linha(previa, 7).erros[0].includes('não encontrada')
        && linha(previa, 8).erros[0].includes('ambíguo')
        && linha(previa, 9).erros.some((e) => e.includes('não está cadastrado')),
      'erros: escola desconhecida, nome ambíguo e local fora do cadastro'
    );
  }

  const importacao = await enviarCsv('/importacao-jogos', csv);
  const [gravados] = await db.query(
    'SELECT id, numero_jogo, data_hora, arbitro_1, rodada FROM jogos WHERE competicao_id = ? ORDER BY numero_jogo',
    [comp.id]
  );
  criados.jogos.push(...gravados.map((j) => j.id));
  conferir(
    importacao.status === 201 && gravados.length === 4 && gravados[0].data_hora.startsWith('2026-11-23')
      && gravados[1].arbitro_1 === `${MARCA} árbitro` && gravados[1].rodada === 1,
    'importação: grava as 4 novas, numeradas por data, com árbitro e rodada',
    `${importacao.status} ${importacao.corpo.erro || ''} ${JSON.stringify(gravados)}`
  );

  const de_novo = await enviarCsv('/importacao-jogos', csv);
  conferir(
    // A linha 5, que repetia a 2, agora também casa com o jogo gravado
    de_novo.status === 200 && de_novo.corpo.resumo.novas === 0 && de_novo.corpo.resumo.existentes === 5
      && await contarJogos() === 4,
    'reimportar o mesmo arquivo não duplica: tudo já existe, nada gravado',
    `${de_novo.status} ${JSON.stringify(de_novo.corpo.resumo)}`
  );

  // Grupo em branco (a tabela do chefe não traz grupo, 20/10/2026): vale o
  // grupo das equipes; grupos diferentes e equipe fora da competição são erro.
  // Só prévia: não grava nada.
  const [[dois]] = await db.query(
    `SELECT c.id, m.nome AS modalidade, cat.nome AS categoria, c.genero
       FROM competicoes c
       INNER JOIN modalidades m ON m.id = c.modalidade_id
       INNER JOIN categorias cat ON cat.id = c.categoria_id
      WHERE (SELECT COUNT(DISTINCT e.grupo_id) FROM equipes e WHERE e.competicao_id = c.id) >= 2
      ORDER BY c.id LIMIT 1`
  );
  const [doDois] = await db.query(
    `SELECT esc.nome, g.nome AS grupo FROM equipes e
       INNER JOIN escolas esc ON esc.id = e.escola_id
       INNER JOIN grupos g ON g.id = e.grupo_id
      WHERE e.competicao_id = ? ORDER BY g.nome, e.id`,
    [dois.id]
  );
  const [[fora]] = await db.query(
    'SELECT nome FROM escolas WHERE id NOT IN (SELECT escola_id FROM equipes WHERE competicao_id = ?) ORDER BY id LIMIT 1',
    [dois.id]
  );
  const [a1, a2] = doDois.filter((e) => e.grupo === doDois[0].grupo);
  const b1 = doDois.find((e) => e.grupo !== doDois[0].grupo);
  const semGrupo = (eq1, eq2) => [dois.modalidade, dois.categoria, dois.genero, '', eq1, eq2,
    '25/11/2026', '05:13', '', '', ''].join(';');
  const grupoVazio = await enviarCsv('/importacao-jogos/previa', [
    'Modalidade;Categoria;Gênero;Grupo;Equipe 1;Equipe 2;Data;Hora;Local;Rodada;Árbitro',
    semGrupo(a1.nome, a2.nome), // 2: mesmo grupo
    semGrupo(a1.nome, b1.nome), // 3: grupos diferentes
    semGrupo(fora.nome, a1.nome) // 4: escola fora da competição
  ].join('\r\n'));
  const gv = (n) => (grupoVazio.corpo.linhas || []).find((l) => l.linha === n) || { erros: [] };
  conferir(
    gv(2).situacao === 'NOVA' && gv(2).grupo === a1.grupo
      && gv(3).situacao === 'ERRO' && gv(3).erros.some((e) => e.includes('grupos diferentes'))
      && gv(4).situacao === 'ERRO' && gv(4).erros.some((e) => e.includes('não joga')),
    'grupo em branco: vale o das equipes; grupos diferentes e equipe fora da competição são erro',
    JSON.stringify(grupoVazio.corpo.resumo || grupoVazio.corpo)
  );

  const semColuna = await enviarCsv('/importacao-jogos/previa', 'Modalidade;Categoria\r\nFutsal;Sub 8');
  conferir(
    semColuna.status === 400 && (semColuna.corpo.erro || '').includes('Faltam colunas'),
    'cabeçalho sem as colunas -> 400 dizendo quais faltam'
  );
};


// ---------------------------------------------------------------------------
// Pontos lançados (atletismo, xadrez, dama e dominó) — pela API
// ---------------------------------------------------------------------------
// A mesa lança e edita; só o ADMIN apaga; acima do esperado pede confirmação;
// teto de 99; quem salva com a grade velha leva 409; e o rastro de quem
// digitou e de quem alterou.
const comToken = async (tok, metodo, caminho, corpo) => {
  const resposta = await fetch(`${API}${caminho}`, {
    method: metodo,
    headers: { 'Content-Type': 'application/json', ...(tok ? { Authorization: `Bearer ${tok}` } : {}) },
    ...(corpo ? { body: JSON.stringify(corpo) } : {})
  });
  return { status: resposta.status, corpo: await resposta.json().catch(() => ({})) };
};

const testarPontosLancados = async () => {
  secao('-- pontos lançados (atletismo, xadrez, dama e dominó)');

  await db.query('INSERT INTO usuarios (nome, email, senha, perfil) VALUES (?, ?, ?, ?)',
    [`Mesa (${MARCA})`, EMAIL_MESA, bcrypt.hashSync(SENHA, 10), 'PLACAR']);
  const mesa = (await exigir('POST', '/login', { email: EMAIL_MESA, senha: SENHA }, 'login da mesa')).token;

  const publica = await comToken(null, 'GET', '/pontos-lancados');
  const abas = (publica.corpo.configuracao?.modalidades || []).map((m) => m.slug).join(',');
  conferir(publica.status === 200 && abas === 'atletismo,xadrez,dama,domino',
    'leitura pública, com as quatro abas na ordem', `${publica.status} ${abas}`);
  // A busca da escola da folha usa nome e apelido (21/10/2026)
  const comApelido = publica.corpo.escolas.find((e) => (e.apelidos || []).length > 0);
  conferir(publica.corpo.escolas.every((e) => Array.isArray(e.apelidos)) && Boolean(comApelido),
    'as escolas vêm com os apelidos, para a busca da folha', comApelido ? `${comApelido.nome}: ${comApelido.apelidos.join(', ')}` : '');

  // Uma categoria e gênero da dama ainda sem lançamento nenhum
  const dama = publica.corpo.configuracao.modalidades.find((m) => m.slug === 'dama');
  const ocupadas = new Set(publica.corpo.lancamentos
    .filter((l) => l.modalidade === 'dama').map((l) => `${l.categoria_id}|${l.genero}`));
  const alvo = dama.combinacoes.find((c) => !ocupadas.has(`${c.categoria_id}|${c.genero}`));
  if (!alvo) throw new Error('Não achei categoria livre na dama para o teste.');
  const [e1, e2, e3] = publica.corpo.escolas;

  const recorte = { modalidade: 'dama', categoria_id: alvo.categoria_id, genero: alvo.genero };
  const lerRecorte = async () => (await db.query(
    `SELECT p.escola_id, p.pontos, p.colocacao, uc.email AS criado_por, ua.email AS alterado_por,
            p.alterado_em
       FROM pontos_lancados p
       INNER JOIN modalidades m ON m.id = p.modalidade_id
       INNER JOIN usuarios uc ON uc.id = p.criado_por
       LEFT JOIN usuarios ua ON ua.id = p.alterado_por
      WHERE m.slug = 'dama' AND p.categoria_id = ? AND p.genero = ? ORDER BY p.escola_id`,
    [alvo.categoria_id, alvo.genero]
  ))[0];
  const salvar = (tok, linhas, base, extra = {}) => comToken(tok, 'PUT', '/pontos-lancados',
    { ...recorte, linhas, base, ...extra });

  const semLogin = await salvar(null, [{ escola_id: e1.id, pontos: 8 }], []);
  conferir(semLogin.status === 401, 'lançar sem login -> 401', `saiu ${semLogin.status}`);

  const primeiro = await salvar(mesa, [
    { escola_id: e1.id, pontos: 8, colocacao: 1 },
    { escola_id: e2.id, pontos: 6 },
    { escola_id: e3.id, pontos: null }
  ], []);
  let linhas = await lerRecorte();
  conferir(
    primeiro.status === 200 && linhas.length === 2 && linhas.every((l) => l.criado_por === EMAIL_MESA && !l.alterado_por)
      && primeiro.corpo.resumo?.texto.endsWith('2 escolas, total 14 pontos'),
    'a mesa lança: 2 escolas (a em branco fica de fora), com o resumo e quem digitou',
    `${primeiro.status} ${primeiro.corpo.erro || primeiro.corpo.resumo?.texto} ${JSON.stringify(linhas)}`
  );
  const base = linhas.map(({ escola_id, pontos, colocacao }) => ({ escola_id, pontos, colocacao }));

  const teto = await salvar(mesa, [{ escola_id: e3.id, pontos: 100 }], base);
  conferir(teto.status === 400, 'acima do teto de 99 -> 400', `saiu ${teto.status}`);

  const acima = await salvar(mesa, [{ escola_id: e3.id, pontos: alvo.esperado + 2 }], base);
  conferir(
    acima.status === 422 && acima.corpo.acima_do_esperado?.includes(e3.id),
    `acima dos ${alvo.esperado} esperados sem confirmar -> 422 com a escola`,
    `saiu ${acima.status} ${acima.corpo.erro || ''}`
  );
  const confirmado = await salvar(mesa, [{ escola_id: e3.id, pontos: alvo.esperado + 2 }], base, { confirmado: true });
  conferir(confirmado.status === 200 && (await lerRecorte()).length === 3,
    'confirmado, o valor acima do esperado é salvo', `${confirmado.status} ${confirmado.corpo.erro || ''}`);

  const velha = await salvar(mesa, [{ escola_id: e1.id, pontos: 9 }], base);
  conferir(velha.status === 409, 'salvar com a grade velha (outra pessoa salvou no meio) -> 409',
    `saiu ${velha.status} ${velha.corpo.erro || ''}`);

  linhas = await lerRecorte();
  const baseAtual = linhas.map(({ escola_id, pontos, colocacao }) => ({ escola_id, pontos, colocacao }));
  // Sobrescrever sem confirmar: 422 com o que seria substituído (21/10/2026)
  const semConfirmar = await salvar(token, [{ escola_id: e1.id, pontos: 9, colocacao: 1 }], baseAtual);
  const sub = semConfirmar.corpo.substituicoes?.[0];
  conferir(
    semConfirmar.status === 422 && sub?.escola_id === e1.id && sub?.pontos_antes === 8 && sub?.pontos_depois === 9
      && sub?.por && sub?.em && (await lerRecorte()).find((l) => l.escola_id === e1.id).pontos === 8,
    'sobrescrever sem confirmar -> 422 com "já tinha 8, digitado por…, quando", e nada muda',
    `${semConfirmar.status} ${JSON.stringify(sub)}`
  );
  const edicao = await salvar(token, [{ escola_id: e1.id, pontos: 9, colocacao: 1 }], baseAtual, { substituir: true });
  const editada = (await lerRecorte()).find((l) => l.escola_id === e1.id);
  conferir(
    edicao.status === 200 && editada.pontos === 9 && editada.criado_por === EMAIL_MESA
      && editada.alterado_por === EMAIL && editada.alterado_em,
    'correção no lugar: guarda quem digitou (mesa) e quem alterou por último (ADMIN)',
    `${edicao.status} ${edicao.corpo.erro || ''} ${JSON.stringify(editada)}`
  );

  // Histórico (db/17): a correção guarda o valor de antes; só o ADMIN lê
  const filtro = `modalidade=dama&categoria_id=${alvo.categoria_id}&genero=${alvo.genero}`;
  const historicoMesa = await comToken(mesa, 'GET', `/pontos-lancados/historico?${filtro}`);
  const historico = await comToken(token, 'GET', `/pontos-lancados/historico?${filtro}`);
  const alteracao = (historico.corpo.historico || []).find((h) => h.acao === 'ALTERACAO' && h.escola_id === e1.id);
  conferir(
    historicoMesa.status === 403 && historico.status === 200 && alteracao?.pontos_antes === 8 && alteracao?.pontos_depois === 9
      && alteracao?.anterior_por_nome?.startsWith('Mesa') && Boolean(alteracao?.usuario_nome) && Boolean(alteracao?.feito_em),
    'histórico da correção: 8 -> 9, quem tinha digitado (mesa), quem alterou e quando; a mesa não lê (403)',
    `${historicoMesa.status} / ${historico.status} ${JSON.stringify(alteracao)}`
  );

  const invalida = await comToken(mesa, 'PUT', '/pontos-lancados',
    { modalidade: 'futsal', categoria_id: alvo.categoria_id, genero: alvo.genero, linhas: [], base: [] });
  conferir(invalida.status === 400, 'modalidade fora das quatro -> 400', `saiu ${invalida.status}`);

  const caminho = `/pontos-lancados/dama/${alvo.categoria_id}/${alvo.genero}`;
  const apagaMesa = await comToken(mesa, 'DELETE', caminho);
  conferir(apagaMesa.status === 403, 'a mesa não apaga o lançamento inteiro -> 403', `saiu ${apagaMesa.status}`);
  const apagaAdmin = await comToken(token, 'DELETE', caminho);
  conferir(apagaAdmin.status === 200 && (await lerRecorte()).length === 0,
    'o ADMIN apaga o lançamento inteiro', `${apagaAdmin.status} ${apagaAdmin.corpo.erro || ''}`);
  const depoisDeApagar = await comToken(token, 'GET', `/pontos-lancados/historico?${filtro}`);
  const exclusoes = (depoisDeApagar.corpo.historico || []).filter((h) => h.acao === 'EXCLUSAO_LANCAMENTO');
  conferir(exclusoes.length === 3 && exclusoes.every((h) => h.pontos_depois === null),
    'apagar o lançamento inteiro registra cada escola no histórico', `${exclusoes.length} exclusões`);
};


// Os pontos lançados somam na Tabela Geral, mas não desempatam: a colocação
// digitada é só informação (regrasProvisorias.pontosLancados.contaNoDesempate)
const testarPontosLancadosNaTabelaGeral = async () => {
  secao('-- pontos lançados na tabela geral');

  const leitura = await exigir('GET', '/pontos-lancados?modalidade=xadrez', null, 'ler o xadrez');
  const xadrez = leitura.configuracao.modalidades.find((m) => m.slug === 'xadrez');
  const ocupadas = new Set(leitura.lancamentos.map((l) => `${l.categoria_id}|${l.genero}`));
  const alvo = xadrez.combinacoes.find((c) => !ocupadas.has(`${c.categoria_id}|${c.genero}`));
  if (!alvo) throw new Error('Não achei categoria livre no xadrez para o teste.');
  const escola = leitura.escolas[0];

  const daEscola = (tabela) => tabela.geral.find((e) => e.escola_id === escola.id)
    || { pontos: 0, primeiros: 0, origens: [] };
  const antes = daEscola(await exigir('GET', '/tabela-geral', null, 'a tabela geral antes'));

  await exigir('PUT', '/pontos-lancados', {
    modalidade: 'xadrez', categoria_id: alvo.categoria_id, genero: alvo.genero,
    linhas: [{ escola_id: escola.id, pontos: 7, colocacao: 1 }], base: []
  }, 'lançar pontos do xadrez');

  const tabela = await exigir('GET', '/tabela-geral', null, 'a tabela geral com o xadrez');
  const depois = daEscola(tabela);
  const origem = depois.origens.find((o) => o.lancado && o.modalidade_nome === 'Xadrez');
  conferir(
    depois.pontos === antes.pontos + 7 && origem?.pontos === 7 && origem?.colocacao === 1,
    'os 7 pontos lançados no xadrez somam para a escola, e a abertura mostra de onde vieram',
    `antes ${antes.pontos}, depois ${depois.pontos}, origem ${JSON.stringify(origem)}`
  );
  conferir(
    depois.primeiros === antes.primeiros && tabela.regras.pontos_lancados?.conta_no_desempate === false,
    'a colocação digitada (1º) não conta como 1º lugar no desempate'
  );

  await exigir('DELETE', `/pontos-lancados/xadrez/${alvo.categoria_id}/${alvo.genero}`, null, 'apagar o xadrez');
  const final = daEscola(await exigir('GET', '/tabela-geral', null, 'a tabela geral sem o xadrez'));
  conferir(final.pontos === antes.pontos, 'apagado o lançamento, a soma volta ao que era');
};

// Atletismo por prova (db/16, 21/10/2026): cada prova é um lançamento
// próprio, e lançar as duas provas SOMA na Tabela Geral, não substitui.
const testarAtletismoPorProva = async () => {
  secao('-- atletismo por prova');

  const leitura = await exigir('GET', '/pontos-lancados?modalidade=atletismo', null, 'ler o atletismo');
  const atletismo = leitura.configuracao.modalidades.find((m) => m.slug === 'atletismo');
  const rotulos = (cat) => (atletismo.combinacoes.find((c) => c.categoria_nome === cat)?.provas || []).map((p) => p.rotulo).join(',');
  conferir(
    rotulos('Sub 8') === '50 m' && rotulos('Sub 9') === '50 m'
      && ['Sub 11', 'Sub 13', 'Sub 15', 'Sub 17'].every((c) => rotulos(c) === 'Salto,100 m')
      && atletismo.combinacoes.every((c) => c.esperado === 10),
    'provas do regulamento: Sub 8 e 9 só 50 m; Sub 11 a 17 salto e 100 m; 10 pontos esperados por prova'
  );
  const porModalidade = Object.fromEntries(leitura.configuracao.modalidades.map((m) => [m.slug, m.combinacoes]));
  conferir(
    !porModalidade.atletismo.some((c) => c.categoria_nome === 'Aberto') && porModalidade.atletismo.length === 12
      && ['xadrez', 'dama', 'domino'].every((slug) => porModalidade[slug]?.length === 14),
    'atletismo sem o Aberto (12 combinações); xadrez, dama e dominó com as 14',
    Object.entries(porModalidade).map(([k, v]) => `${k}:${v.length}`).join(' ')
  );

  const ocupadas = new Set(leitura.lancamentos.map((l) => `${l.categoria_id}|${l.genero}`));
  const alvo = atletismo.combinacoes.find((c) => c.provas.length === 2 && !ocupadas.has(`${c.categoria_id}|${c.genero}`));
  if (!alvo) throw new Error('Não achei categoria livre do atletismo com duas provas.');
  const [salto, cem] = alvo.provas;
  const escola = leitura.escolas[1];
  const recorte = { modalidade: 'atletismo', categoria_id: alvo.categoria_id, genero: alvo.genero };
  const daEscola = async () => ((await exigir('GET', '/tabela-geral', null, 'a tabela geral')).geral
    .find((e) => e.escola_id === escola.id) || { pontos: 0, origens: [] });
  const antes = await daEscola();

  const semProva = await chamar('PUT', '/pontos-lancados', { ...recorte, linhas: [{ escola_id: escola.id, pontos: 10 }], base: [] });
  const tabuleiroComProva = await chamar('PUT', '/pontos-lancados', {
    modalidade: 'xadrez', categoria_id: alvo.categoria_id, genero: alvo.genero, prova_id: salto.id,
    linhas: [{ escola_id: escola.id, pontos: 1 }], base: []
  });
  conferir(semProva.status === 400 && tabuleiroComProva.status === 400,
    'atletismo sem prova -> 400; xadrez com prova -> 400', `${semProva.status} / ${tabuleiroComProva.status}`);

  // A folha do salto e, depois, a dos 100 m: duas linhas, que somam
  await exigir('PUT', '/pontos-lancados', { ...recorte, prova_id: salto.id, linhas: [{ escola_id: escola.id, pontos: 10, colocacao: 1 }], base: [] }, 'lançar o salto');
  await exigir('PUT', '/pontos-lancados', { ...recorte, prova_id: cem.id, linhas: [{ escola_id: escola.id, pontos: 8, colocacao: 2 }], base: [] }, 'lançar os 100 m');
  const [gravadas] = await db.query(
    `SELECT p.prova_id, p.pontos FROM pontos_lancados p INNER JOIN modalidades m ON m.id = p.modalidade_id
      WHERE m.slug = 'atletismo' AND p.categoria_id = ? AND p.genero = ? AND p.escola_id = ? ORDER BY p.prova_id`,
    [alvo.categoria_id, alvo.genero, escola.id]
  );
  const depois = await daEscola();
  const provasNaAbertura = depois.origens.filter((o) => o.lancado && o.modalidade_nome === 'Atletismo').map((o) => `${o.prova}:${o.pontos}`).sort();
  conferir(
    gravadas.length === 2 && depois.pontos === antes.pontos + 18
      && provasNaAbertura.join() === ['100 m:8', 'Salto:10'].join(),
    'lançar as duas provas SOMA (10 + 8 = 18) e não substitui; a abertura mostra cada prova',
    `linhas ${JSON.stringify(gravadas)} | antes ${antes.pontos}, depois ${depois.pontos} | ${provasNaAbertura}`
  );

  // Apagar uma prova não mexe na outra
  await exigir('DELETE', `/pontos-lancados/atletismo/${alvo.categoria_id}/${alvo.genero}?prova_id=${salto.id}`, null, 'apagar o salto');
  const soCem = await daEscola();
  conferir(soCem.pontos === antes.pontos + 8, 'apagar o lançamento do salto deixa os 100 m', `${soCem.pontos}`);
  await exigir('DELETE', `/pontos-lancados/atletismo/${alvo.categoria_id}/${alvo.genero}?prova_id=${cem.id}`, null, 'apagar os 100 m');
  conferir((await daEscola()).pontos === antes.pontos, 'apagadas as duas provas, a soma volta ao que era');
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
