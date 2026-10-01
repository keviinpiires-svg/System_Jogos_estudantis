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

  // ---- tabela geral --------------------------------------------------------
  secao('-- tabela geral');
  const tabela = await exigir('GET', '/tabela-geral', null, 'a tabela geral');
  const campeao = podio[0];
  const naGeral = tabela.geral.find((e) => e.escola_nome === campeao.escola_nome);
  conferir(Boolean(naGeral), 'a escola campeã entrou na soma geral');
  conferir(naGeral?.primeiros >= 1, 'com um primeiro lugar contado');

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
