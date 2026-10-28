const db = require('../config/db');
const { REGRAS } = require('../config/regrasProvisorias');

// ============================================================================
// Importação de jogos da fase de grupos por CSV (só ADMIN).
//
// Duas rotas com a mesma análise: a PRÉVIA lê o arquivo e diz o que cada
// linha vai virar, sem gravar nada; a IMPORTAÇÃO refaz a análise dentro de
// uma transação única, com as competições travadas, e grava as linhas novas.
//
// - Linha com ERRO não entra; as outras entram.
// - AVISO não bloqueia (data fora do evento, equipe em dois jogos no mesmo
//   horário, local ocupado, confronto repetido no grupo).
// - Idempotente: um jogo é o mesmo quando tem a mesma competição, o mesmo
//   par de equipes (em qualquer ordem) e a mesma data e hora. Reimportar a
//   linha não duplica nem altera o jogo que já existe.
// - Os jogos novos de cada competição são numerados por data e hora, a
//   partir do maior número que a competição já tem.
// - Não gera partida nenhuma: a lista vem pronta, inclusive a partida extra
//   do grupo de 4.
// ============================================================================

const MAX_LINHAS = 1000;

// Colunas do arquivo, na ordem do modelo (docs/modelo_importacao_jogos.csv).
// O cabeçalho é comparado sem acento, maiúscula nem espaço sobrando, e as
// colunas podem vir em qualquer ordem.
const COLUNAS = [
  ['modalidade', 'Modalidade'],
  ['categoria', 'Categoria'],
  ['genero', 'Gênero'],
  ['grupo', 'Grupo'],
  ['equipe_1', 'Equipe 1'],
  ['equipe_2', 'Equipe 2'],
  ['data', 'Data'],
  ['hora', 'Hora'],
  ['local', 'Local'],
  ['rodada', 'Rodada'],
  ['arbitro', 'Árbitro']
];

const OBRIGATORIAS = ['modalidade', 'categoria', 'genero', 'equipe_1', 'equipe_2'];

// Coluna OPCIONAL (db/15, 20/10/2026): o número do jogo na tabela oficial do
// chefe, global (1 a 338). O arquivo pode vir com ou sem ela, e a célula pode
// ficar vazia. Aceita "Nº Tabela", "N° Tabela", "No Tabela", "Numero Tabela"...
const COLUNA_NUMERO_TABELA = 'Nº Tabela';
const cabecalhoDoNumeroTabela = (texto) => ['N TABELA', 'NO TABELA', 'NUMERO TABELA', 'NUMERO DA TABELA']
  .includes(normalizar(texto).replace(/[º°]/g, '').replace(/\s+/g, ' ').trim());

// Outros nomes aceitos para as modalidades, além do nome e do slug cadastrados
const APELIDOS_MODALIDADE = {
  VOLEIBOL: 'volei',
  BASQUETEBOL: 'basquete',
  SOCIETY: 'futebol-society',
  'FUTEBOL SOCIETY': 'futebol-society'
};

const GENEROS = {
  M: 'MASCULINO', MASC: 'MASCULINO', MASCULINO: 'MASCULINO',
  F: 'FEMININO', FEM: 'FEMININO', FEMININO: 'FEMININO',
  MISTO: 'MISTO'
};

const NOME_GENERO = { MASCULINO: 'Masculino', FEMININO: 'Feminino', MISTO: 'Misto' };

// "Maria da Glória", "MARIA DA GLORIA" e "maria  da gloria" são o mesmo
// nome; "F. AMORIM" e "F AMORIM" também.
const normalizar = (texto) => String(texto ?? '')
  .normalize('NFD')
  .replace(/[̀-ͯ]/g, '')
  .toUpperCase()
  .replace(/\./g, ' ')
  .replace(/\s+/g, ' ')
  .trim();

const doisDigitos = (n) => String(n).padStart(2, '0');

// ----------------------------------------------------------------------------
// Leitura do CSV
// ----------------------------------------------------------------------------

// O separador é o que mais aparece no cabeçalho: ";" (Excel em português),
// "," ou tabulação. Aceita campos entre aspas, com "" dentro e quebra de
// linha. Devolve as linhas com o número que elas têm no arquivo.
const lerCsv = (texto) => {
  const conteudo = String(texto || '').replace(/^﻿/, '');
  const cabecalho = conteudo.split(/\r?\n/, 1)[0] || '';
  const contar = (sep) => cabecalho.split(sep).length - 1;
  const separador = [',', '\t'].reduce((melhor, sep) => (contar(sep) > contar(melhor) ? sep : melhor), ';');

  const linhas = [];
  let campos = [];
  let campo = '';
  let aspas = false;
  let numero = 1;
  let inicio = 1;

  const fecharLinha = () => {
    campos.push(campo);
    linhas.push({ numero: inicio, campos });
    campos = [];
    campo = '';
  };

  for (let i = 0; i < conteudo.length; i += 1) {
    const c = conteudo[i];

    if (aspas) {
      if (c === '"' && conteudo[i + 1] === '"') {
        campo += '"';
        i += 1;
      } else if (c === '"') {
        aspas = false;
      } else {
        if (c === '\n') numero += 1;
        campo += c;
      }
    } else if (c === '"') {
      aspas = true;
    } else if (c === separador) {
      campos.push(campo);
      campo = '';
    } else if (c === '\n' || c === '\r') {
      if (c === '\r' && conteudo[i + 1] === '\n') i += 1;
      fecharLinha();
      numero += 1;
      inicio = numero;
    } else {
      campo += c;
    }
  }

  if (campo !== '' || campos.length > 0) fecharLinha();

  return {
    separador,
    aspasAbertas: aspas,
    linhas: linhas.filter((l) => l.campos.some((c) => c.trim() !== ''))
  };
};

// "23/11/2026", "23/11/26", "23/11" (ano do evento) ou "2026-11-23".
// Devolve "AAAA-MM-DD", null se vazio, undefined se inválido.
const lerData = (texto, anoDoEvento) => {
  const t = String(texto || '').trim();
  if (!t) return null;

  let dia;
  let mes;
  let ano;
  let m = /^(\d{1,2})\/(\d{1,2})(?:\/(\d{2}|\d{4}))?$/.exec(t);

  if (m) {
    dia = Number(m[1]);
    mes = Number(m[2]);
    if (!m[3]) ano = anoDoEvento;
    else ano = m[3].length === 2 ? 2000 + Number(m[3]) : Number(m[3]);
  } else if ((m = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(t))) {
    ano = Number(m[1]);
    mes = Number(m[2]);
    dia = Number(m[3]);
  } else {
    return undefined;
  }

  // 31/11 não existe: o Date "corrige" para 01/12, e a conferência pega
  const data = new Date(Date.UTC(ano, mes - 1, dia));
  if (data.getUTCFullYear() !== ano || data.getUTCMonth() !== mes - 1 || data.getUTCDate() !== dia) {
    return undefined;
  }

  return `${ano}-${doisDigitos(mes)}-${doisDigitos(dia)}`;
};

// "14:30", "14:30:00", "14h30" ou "14h". Devolve "HH:MM", null ou undefined.
const lerHora = (texto) => {
  const t = String(texto || '').trim().toLowerCase();
  if (!t) return null;

  const m = /^(\d{1,2})(?::(\d{2})(?::\d{2})?|h(\d{2})?)$/.exec(t);
  if (!m) return undefined;

  const hora = Number(m[1]);
  const minuto = Number(m[2] ?? m[3] ?? 0);
  if (hora > 23 || minuto > 59) return undefined;

  return `${doisDigitos(hora)}:${doisDigitos(minuto)}`;
};

// "Sub 11", "SUB-11", "sub11" e "Sub 08" viram "SUB 11"/"SUB 8"
const normalizarCategoria = (texto) => {
  const nome = normalizar(texto);
  const sub = /^SUB\s*-?\s*0*(\d+)$/.exec(nome);
  return sub ? `SUB ${sub[1]}` : nome;
};

const normalizarGrupo = (texto) => normalizar(texto).replace(/^GRUPO\s+/, '');

// "2026-11-24 10:30:00" -> "24/11/2026 10:30"
const formatarQuando = (dataHora) => {
  if (!dataHora) return 'sem data';
  const [data, hora] = dataHora.split(' ');
  const [ano, mes, dia] = data.split('-');
  return `${dia}/${mes}/${ano} ${hora.slice(0, 5)}`;
};

const segundos = (dataHora) => Date.parse(`${dataHora.replace(' ', 'T')}Z`) / 1000;

// ----------------------------------------------------------------------------
// Cadastro: tudo o que a análise consulta, lido de uma vez
// ----------------------------------------------------------------------------

const carregarCadastro = async (conexao) => {
  const consultar = async (sql) => (await conexao.query(sql))[0];

  const [config] = await consultar(
    'SELECT ano, data_inicio, data_fim FROM configuracao_evento WHERE id = 1'
  );
  const modalidades = await consultar('SELECT id, nome, slug FROM modalidades');
  const categorias = await consultar('SELECT id, nome FROM categorias');
  const competicoes = await consultar(
    `SELECT c.id, c.modalidade_id, c.categoria_id, c.genero,
            m.nome AS modalidade_nome, cat.nome AS categoria_nome
       FROM competicoes c
       INNER JOIN modalidades m ON m.id = c.modalidade_id
       INNER JOIN categorias cat ON cat.id = c.categoria_id`
  );
  const grupos = await consultar('SELECT id, competicao_id, nome FROM grupos');
  const equipes = await consultar('SELECT id, competicao_id, escola_id, grupo_id FROM equipes');
  const escolas = await consultar('SELECT id, nome FROM escolas');
  const apelidos = await consultar('SELECT escola_id, apelido FROM escola_apelidos');
  const locais = await consultar('SELECT id, nome FROM locais_disputa');

  // Nome normalizado -> escolas que respondem por ele. Mais de uma = ambíguo.
  const escolasPorNome = new Map();
  const registrar = (nome, escola_id) => {
    const chave = normalizar(nome);
    if (!escolasPorNome.has(chave)) escolasPorNome.set(chave, new Set());
    escolasPorNome.get(chave).add(escola_id);
  };
  escolas.forEach((e) => registrar(e.nome, e.id));
  apelidos.forEach((a) => registrar(a.apelido, a.escola_id));

  const modalidadePorNome = new Map();
  modalidades.forEach((m) => {
    modalidadePorNome.set(normalizar(m.nome), m);
    modalidadePorNome.set(normalizar(m.slug.replace(/-/g, ' ')), m);
  });
  Object.entries(APELIDOS_MODALIDADE).forEach(([apelido, slug]) => {
    const modalidade = modalidades.find((m) => m.slug === slug);
    if (modalidade && !modalidadePorNome.has(apelido)) modalidadePorNome.set(apelido, modalidade);
  });

  return {
    ano: config?.ano,
    dataInicio: config?.data_inicio || null,
    dataFim: config?.data_fim || null,
    modalidadePorNome,
    categoriaPorNome: new Map(categorias.map((c) => [normalizarCategoria(c.nome), c])),
    competicoes,
    grupos,
    equipes,
    escolaNome: new Map(escolas.map((e) => [e.id, e.nome])),
    escolasPorNome,
    localPorNome: new Map(locais.map((l) => [normalizar(l.nome), l]))
  };
};

// ----------------------------------------------------------------------------
// Validação de cada linha, só contra o cadastro
// ----------------------------------------------------------------------------

const validarLinha = (valores, cadastro) => {
  const erros = [];
  const linha = { erros, avisos: [] };

  for (const chave of OBRIGATORIAS) {
    if (!valores[chave]) {
      const rotulo = COLUNAS.find(([c]) => c === chave)[1];
      erros.push(`${rotulo} em branco.`);
    }
  }
  if (erros.length) return linha;

  const modalidade = cadastro.modalidadePorNome.get(normalizar(valores.modalidade));
  const categoria = cadastro.categoriaPorNome.get(normalizarCategoria(valores.categoria));
  const genero = GENEROS[normalizar(valores.genero)];

  if (!modalidade) erros.push(`Modalidade "${valores.modalidade}" não existe.`);
  if (!categoria) erros.push(`Categoria "${valores.categoria}" não existe.`);
  if (!genero) erros.push(`Gênero "${valores.genero}" inválido: use Masculino, Feminino ou Misto.`);
  if (erros.length) return linha;

  const competicao = cadastro.competicoes.find((c) => c.modalidade_id === modalidade.id
    && c.categoria_id === categoria.id && c.genero === genero);
  const nomeCompeticao = `${modalidade.nome} ${categoria.nome} ${NOME_GENERO[genero]}`;

  if (!competicao) {
    erros.push(`Não existe a competição ${nomeCompeticao}.`);
    return linha;
  }

  linha.competicao_id = competicao.id;
  linha.competicao = nomeCompeticao;

  // Escola pelo nome oficial ou pelo apelido, e daí a equipe na competição
  const equipeDe = (texto, lado) => {
    const encontradas = [...(cadastro.escolasPorNome.get(normalizar(texto)) || [])];

    if (encontradas.length === 0) {
      erros.push(`${lado}: escola "${texto}" não encontrada (nem pelo nome nem pelos apelidos).`);
      return null;
    }
    if (encontradas.length > 1) {
      const nomes = encontradas.map((id) => cadastro.escolaNome.get(id)).join(', ');
      erros.push(`${lado}: "${texto}" é ambíguo, serve para ${nomes}.`);
      return null;
    }

    const escola_id = encontradas[0];
    const equipe = cadastro.equipes.find((e) => e.competicao_id === competicao.id && e.escola_id === escola_id);
    if (!equipe) {
      erros.push(`${lado}: ${cadastro.escolaNome.get(escola_id)} não joga ${nomeCompeticao}.`);
      return null;
    }
    return { ...equipe, nome: cadastro.escolaNome.get(escola_id) };
  };

  const equipe1 = equipeDe(valores.equipe_1, 'Equipe 1');
  const equipe2 = equipeDe(valores.equipe_2, 'Equipe 2');

  if (equipe1 && equipe2) {
    linha.equipe_1_id = equipe1.id;
    linha.equipe_2_id = equipe2.id;
    linha.equipe_1 = equipe1.nome;
    linha.equipe_2 = equipe2.nome;

    // Fase de grupos: as duas equipes do mesmo grupo, que é o grupo do jogo
    if (equipe1.id === equipe2.id) {
      erros.push(`${equipe1.nome} não pode jogar contra si mesma.`);
    } else if (!equipe1.grupo_id || !equipe2.grupo_id) {
      erros.push('Há equipe sem grupo definido nesta competição.');
    } else if (equipe1.grupo_id !== equipe2.grupo_id) {
      erros.push(`${equipe1.nome} e ${equipe2.nome} estão em grupos diferentes.`);
    } else {
      const grupo = cadastro.grupos.find((g) => g.id === equipe1.grupo_id);
      linha.grupo_id = grupo.id;
      linha.grupo = grupo.nome;

      if (valores.grupo && normalizarGrupo(valores.grupo) !== normalizar(grupo.nome)) {
        erros.push(`O grupo informado (${valores.grupo}) não é o das equipes (grupo ${grupo.nome}).`);
      }
    }
  }

  // Data e hora: as duas, ou nenhuma (o jogo fica sem agenda)
  const data = lerData(valores.data, cadastro.ano);
  const hora = lerHora(valores.hora);

  if (data === undefined) erros.push(`Data "${valores.data}" inválida: use DD/MM/AAAA.`);
  if (hora === undefined) erros.push(`Hora "${valores.hora}" inválida: use HH:MM.`);
  if (data && hora === null) erros.push('Informe a hora junto com a data.');
  if (hora && data === null) erros.push('Informe a data junto com a hora.');
  linha.data_hora = data && hora ? `${data} ${hora}:00` : null;

  if (valores.local) {
    const local = cadastro.localPorNome.get(normalizar(valores.local));
    if (!local) {
      erros.push(`Local "${valores.local}" não está cadastrado.`);
    } else {
      linha.local_id = local.id;
      linha.local = local.nome;
    }
  }

  if (valores.rodada) {
    const rodada = Number(valores.rodada);
    if (!Number.isInteger(rodada) || rodada < 1 || rodada > 99) {
      erros.push(`Rodada "${valores.rodada}" inválida: use um número de 1 a 99.`);
    } else {
      linha.rodada = rodada;
    }
  }

  if (valores.arbitro.length > 150) erros.push('Árbitro com mais de 150 caracteres.');

  // Nº Tabela: vazio é permitido; preenchido, um inteiro de 1 a 65535
  linha.numero_tabela = null;
  if (valores.numero_tabela) {
    const numero = Number(valores.numero_tabela);
    if (!/^\d+$/.test(valores.numero_tabela) || numero < 1 || numero > 65535) {
      erros.push(`${COLUNA_NUMERO_TABELA} "${valores.numero_tabela}" inválido: use um número inteiro a partir de 1.`);
    } else {
      linha.numero_tabela = numero;
    }
  }
  linha.arbitro = valores.arbitro || null;

  return linha;
};

// ----------------------------------------------------------------------------
// Análise do arquivo inteiro: erros, jogos que já existem, avisos e números
// ----------------------------------------------------------------------------

const mesmoPar = (a, b) => (a.equipe_1_id === b.equipe_1_id && a.equipe_2_id === b.equipe_2_id)
  || (a.equipe_1_id === b.equipe_2_id && a.equipe_2_id === b.equipe_1_id);

// `travar` = dentro da transação da importação: as competições das linhas
// são travadas ANTES de qualquer leitura dos jogos, para que a numeração e a
// checagem de "já existe" vejam o que outro agendamento acabou de gravar.
const analisar = async (conexao, texto, { travar = false } = {}) => {
  const csv = lerCsv(texto);

  if (csv.aspasAbertas) {
    return { erroDoArquivo: 'O arquivo tem aspas abertas que não fecham: confira o CSV.' };
  }
  if (csv.linhas.length < 2) {
    return { erroDoArquivo: 'O arquivo não tem jogos: precisa do cabeçalho e de pelo menos uma linha.' };
  }
  if (csv.linhas.length - 1 > MAX_LINHAS) {
    return { erroDoArquivo: `O arquivo tem mais de ${MAX_LINHAS} jogos. Divida em arquivos menores.` };
  }

  // Cabeçalho: onde está cada coluna
  const cabecalho = csv.linhas[0].campos.map(normalizar);
  const posicao = {};
  const faltando = [];
  for (const [chave, rotulo] of COLUNAS) {
    const indice = cabecalho.indexOf(normalizar(rotulo));
    if (indice === -1) faltando.push(rotulo);
    else posicao[chave] = indice;
  }
  if (faltando.length) {
    return {
      erroDoArquivo: `Faltam colunas no cabeçalho: ${faltando.join(', ')}. `
        + `O arquivo precisa de: ${COLUNAS.map(([, r]) => r).join(', ')}.`
    };
  }

  // A coluna opcional do número da tabela do chefe: -1 = o arquivo não tem
  const indiceNumeroTabela = csv.linhas[0].campos.findIndex(cabecalhoDoNumeroTabela);

  // O cadastro é lido fora da transação: não muda durante a importação, e
  // uma leitura comum aqui fixaria a foto da transação antes da trava.
  const cadastro = await carregarCadastro(travar ? db : conexao);

  const linhas = csv.linhas.slice(1).map((l) => {
    const valores = Object.fromEntries(
      COLUNAS.map(([chave]) => [chave, String(l.campos[posicao[chave]] ?? '').trim()])
    );
    valores.numero_tabela = indiceNumeroTabela === -1 ? '' : String(l.campos[indiceNumeroTabela] ?? '').trim();
    return { linha: l.numero, valores, ...validarLinha(valores, cadastro) };
  });

  // Nº Tabela repetido dentro do próprio arquivo: erro em todas as linhas que
  // o repetem (não dá para saber qual delas está certa)
  const linhasPorNumero = new Map();
  for (const l of linhas) {
    if (!l.numero_tabela) continue;
    if (!linhasPorNumero.has(l.numero_tabela)) linhasPorNumero.set(l.numero_tabela, []);
    linhasPorNumero.get(l.numero_tabela).push(l);
  }
  for (const [numero, doNumero] of linhasPorNumero) {
    if (doNumero.length < 2) continue;
    for (const l of doNumero) {
      const outras = doNumero.filter((o) => o !== l).map((o) => o.linha).join(', ');
      l.erros.push(`${COLUNA_NUMERO_TABELA} ${numero} repetido no arquivo (também na linha ${outras}).`);
    }
  }

  const validas = linhas.filter((l) => l.erros.length === 0);
  const competicoesIds = [...new Set(validas.map((l) => l.competicao_id))].sort((a, b) => a - b);

  if (travar && competicoesIds.length) {
    await conexao.query(
      'SELECT id FROM competicoes WHERE id IN (?) ORDER BY id FOR UPDATE',
      [competicoesIds]
    );
  }

  // Jogos já gravados nas competições das linhas (para "já existe", número,
  // equipe no mesmo horário e confronto repetido) e jogos de todo o evento
  // que ocupam algum local (para o aviso de local)
  const [jogosDasCompeticoes] = competicoesIds.length
    ? await conexao.query(
      `SELECT id, competicao_id, numero_jogo, numero_tabela, fase, grupo_id, equipe_1_id, equipe_2_id,
              data_hora, local_id, rodada, arbitro_1, status
         FROM jogos WHERE competicao_id IN (?)${travar ? ' FOR UPDATE' : ''}`,
      [competicoesIds]
    )
    : [[]];

  // Números da tabela do chefe já usados em QUALQUER jogo do evento (o índice
  // único do db/15 é global): número -> jogo que o tem
  const comNumero = linhas.some((l) => l.numero_tabela);
  const [jogosComNumero] = comNumero
    ? await conexao.query(
      `SELECT j.id, j.numero_jogo, j.numero_tabela, m.nome AS modalidade_nome,
              cat.nome AS categoria_nome, c.genero
         FROM jogos j
         INNER JOIN competicoes c ON c.id = j.competicao_id
         INNER JOIN modalidades m ON m.id = c.modalidade_id
         INNER JOIN categorias cat ON cat.id = c.categoria_id
        WHERE j.numero_tabela IS NOT NULL`
    )
    : [[]];
  const donoDoNumero = new Map(jogosComNumero.map((j) => [j.numero_tabela, j]));
  const descreverJogo = (j) => `jogo nº ${j.numero_jogo} de ${j.modalidade_nome} ${j.categoria_nome} `
    + `${NOME_GENERO[j.genero] || j.genero}`;

  const { intervaloMinutos, statusQueOcupam } = REGRAS.conflitoDeLocal;
  const [jogosComLocal] = await conexao.query(
    `SELECT j.id, j.numero_jogo, j.local_id, j.data_hora, m.nome AS modalidade_nome,
            cat.nome AS categoria_nome, c.genero
       FROM jogos j
       INNER JOIN competicoes c ON c.id = j.competicao_id
       INNER JOIN modalidades m ON m.id = c.modalidade_id
       INNER JOIN categorias cat ON cat.id = c.categoria_id
      WHERE j.local_id IS NOT NULL AND j.data_hora IS NOT NULL AND j.status IN (?)`,
    [statusQueOcupam]
  );

  // 1) Já existe no banco, ou repete uma linha anterior do próprio arquivo
  const novas = [];
  for (const l of validas) {
    const existente = jogosDasCompeticoes.find((j) => j.fase === 'GRUPOS'
      && j.competicao_id === l.competicao_id && mesmoPar(j, l) && j.data_hora === l.data_hora);

    if (existente) {
      l.situacao = 'EXISTENTE';
      l.numero_jogo = existente.numero_jogo;
      l.jogo_id = existente.id;

      const diferencas = [];
      if ((existente.local_id || null) !== (l.local_id || null)) diferencas.push('local');
      if ((existente.rodada || null) !== (l.rodada || null)) diferencas.push('rodada');
      if ((existente.arbitro_1 || null) !== l.arbitro) diferencas.push('árbitro');
      if (diferencas.length) {
        l.avisos.push(`O jogo nº ${existente.numero_jogo} já cadastrado tem ${diferencas.join(', ')} `
          + 'diferente desta linha. A importação não altera jogos que já existem.');
      }

      // Nº Tabela de um jogo que já existe: só PREENCHE quando ele está sem
      // número; o resto do jogo não muda, e um número já gravado não é trocado
      if (l.numero_tabela && existente.numero_tabela !== l.numero_tabela) {
        const dono = donoDoNumero.get(l.numero_tabela);
        if (existente.numero_tabela) {
          l.avisos.push(`O jogo nº ${existente.numero_jogo} já tem o ${COLUNA_NUMERO_TABELA} `
            + `${existente.numero_tabela}; a importação não troca um número já gravado.`);
        } else if (dono && dono.id !== existente.id) {
          l.erros.push(`${COLUNA_NUMERO_TABELA} ${l.numero_tabela} já é do ${descreverJogo(dono)}.`);
        } else {
          l.preencher_numero = true;
        }
      }
      continue;
    }

    // Jogo novo com Nº Tabela que outro jogo já tem
    if (l.numero_tabela && donoDoNumero.has(l.numero_tabela)) {
      l.erros.push(`${COLUNA_NUMERO_TABELA} ${l.numero_tabela} já é do ${descreverJogo(donoDoNumero.get(l.numero_tabela))}.`);
      continue;
    }

    const repetida = novas.find((n) => n.competicao_id === l.competicao_id
      && mesmoPar(n, l) && n.data_hora === l.data_hora);
    if (repetida) {
      l.situacao = 'DUPLICADA';
      l.avisos.push(`Repete a linha ${repetida.linha}: entra uma vez só.`);
      continue;
    }

    l.situacao = 'NOVA';
    novas.push(l);
  }
  linhas.filter((l) => l.erros.length).forEach((l) => { l.situacao = 'ERRO'; });

  // 2) Números: por competição, em ordem de data e hora (sem agenda vai por
  //    último), continuando do maior número que a competição já tem
  for (const competicao_id of competicoesIds) {
    let proximo = jogosDasCompeticoes
      .filter((j) => j.competicao_id === competicao_id)
      .reduce((maior, j) => Math.max(maior, j.numero_jogo), 0);

    novas
      .filter((l) => l.competicao_id === competicao_id)
      .sort((a, b) => {
        if (a.data_hora !== b.data_hora) {
          if (!a.data_hora) return 1;
          if (!b.data_hora) return -1;
          return a.data_hora < b.data_hora ? -1 : 1;
        }
        return a.linha - b.linha;
      })
      .forEach((l) => {
        proximo += 1;
        l.numero_jogo = proximo;
      });
  }

  // 3) Avisos das linhas novas
  const nomeDoJogo = (j) => `jogo nº ${j.numero_jogo} de ${j.modalidade_nome} ${j.categoria_nome} `
    + `${NOME_GENERO[j.genero] || j.genero}`;

  for (const l of novas) {
    if (!l.data_hora) {
      l.avisos.push('Sem data e hora: o jogo entra sem agenda e fica com o último número.');
    } else {
      const dia = l.data_hora.slice(0, 10);
      if ((cadastro.dataInicio && dia < cadastro.dataInicio) || (cadastro.dataFim && dia > cadastro.dataFim)) {
        l.avisos.push(`Data fora do evento (${formatarQuando(`${cadastro.dataInicio} 00:00`).slice(0, 10)} `
          + `a ${formatarQuando(`${cadastro.dataFim} 00:00`).slice(0, 10)}).`);
      }

      // Equipe em dois jogos no mesmo horário
      for (const [id, nome] of [[l.equipe_1_id, l.equipe_1], [l.equipe_2_id, l.equipe_2]]) {
        const joga = (j) => j.equipe_1_id === id || j.equipe_2_id === id;
        const noBanco = jogosDasCompeticoes.find((j) => j.status !== 'WO' && joga(j) && j.data_hora === l.data_hora);
        const noArquivo = novas.find((n) => n !== l && joga(n) && n.data_hora === l.data_hora);
        if (noBanco) l.avisos.push(`${nome} já joga no mesmo horário (jogo nº ${noBanco.numero_jogo}).`);
        if (noArquivo) l.avisos.push(`${nome} também joga no mesmo horário na linha ${noArquivo.linha}.`);
      }

      // Mesmo local em horário próximo demais (regrasProvisorias.conflitoDeLocal)
      if (l.local_id) {
        const perto = (dataHora) => Math.abs(segundos(dataHora) - segundos(l.data_hora)) < intervaloMinutos * 60;
        const noBanco = jogosComLocal.find((j) => j.local_id === l.local_id && perto(j.data_hora));
        const noArquivo = novas.find((n) => n !== l && n.local_id === l.local_id && n.data_hora && perto(n.data_hora));
        const regra = `menos de ${intervaloMinutos} minutos entre os inícios`;
        if (noBanco) {
          l.avisos.push(`${l.local} já tem o ${nomeDoJogo(noBanco)} em ${formatarQuando(noBanco.data_hora)} (${regra}).`);
        }
        if (noArquivo) {
          l.avisos.push(`${l.local} também é usado na linha ${noArquivo.linha}, em ${formatarQuando(noArquivo.data_hora)} (${regra}).`);
        }
      }
    }

    // Confronto repetido no mesmo grupo (ida e volta, partida extra...)
    const repetidoNoBanco = jogosDasCompeticoes.find((j) => j.fase === 'GRUPOS'
      && j.grupo_id === l.grupo_id && mesmoPar(j, l));
    const repetidoNoArquivo = novas.find((n) => n !== l && n.grupo_id === l.grupo_id && mesmoPar(n, l));
    if (repetidoNoBanco) {
      l.avisos.push(`Confronto repetido no grupo ${l.grupo}: já existe o jogo nº ${repetidoNoBanco.numero_jogo}.`);
    }
    if (repetidoNoArquivo) {
      l.avisos.push(`Confronto repetido no grupo ${l.grupo}: também na linha ${repetidoNoArquivo.linha}.`);
    }
  }

  const contar = (situacao) => linhas.filter((l) => l.situacao === situacao).length;

  return {
    linhas: linhas.map((l) => ({
      linha: l.linha,
      situacao: l.situacao,
      valores: l.valores,
      competicao: l.competicao || null,
      grupo: l.grupo || null,
      equipe_1: l.equipe_1 || null,
      equipe_2: l.equipe_2 || null,
      data_hora: l.data_hora || null,
      local: l.local || null,
      rodada: l.rodada || null,
      arbitro: l.arbitro || null,
      numero_tabela: l.numero_tabela || null,
      // Jogo que já existe e vai ganhar o Nº Tabela na importação
      preencher_numero: Boolean(l.preencher_numero),
      numero_jogo: l.numero_jogo || null,
      jogo_id: l.jogo_id || null,
      erros: l.erros,
      avisos: l.avisos,
      // Só o backend usa: o que vai para o INSERT
      _gravar: l.situacao === 'NOVA' || (l.situacao === 'EXISTENTE' && l.preencher_numero) ? l : undefined
    })),
    resumo: {
      linhas: linhas.length,
      novas: contar('NOVA'),
      existentes: contar('EXISTENTE'),
      duplicadas: contar('DUPLICADA'),
      erros: contar('ERRO'),
      numeros_a_preencher: linhas.filter((l) => l.situacao === 'EXISTENTE' && l.preencher_numero).length,
      com_avisos: linhas.filter((l) => l.avisos.length > 0 && l.situacao !== 'ERRO').length
    }
  };
};

const semInterno = (analise) => ({
  resumo: analise.resumo,
  linhas: analise.linhas.map(({ _gravar, ...resto }) => resto)
});

// POST /api/importacao-jogos/previa — corpo: o CSV (text/csv). Não grava nada.
const previaImportacao = async (req, res) => {
  try {
    const analise = await analisar(db, req.body);
    if (analise.erroDoArquivo) return res.status(400).json({ erro: analise.erroDoArquivo });
    res.json(semInterno(analise));
  } catch (erro) {
    console.error('Erro na prévia da importação de jogos:', erro);
    res.status(500).json({ erro: 'Erro ao analisar o arquivo de jogos.' });
  }
};

// POST /api/importacao-jogos — corpo: o mesmo CSV. Refaz a análise numa
// transação única e grava as linhas novas; as com erro ficam de fora.
const importarJogos = async (req, res) => {
  let conexao;
  try {
    conexao = await db.getConnection();
    await conexao.beginTransaction();

    const analise = await analisar(conexao, req.body, { travar: true });
    if (analise.erroDoArquivo) {
      await conexao.rollback();
      return res.status(400).json({ erro: analise.erroDoArquivo });
    }

    for (const { _gravar: l } of analise.linhas.filter((x) => x._gravar)) {
      // Jogo que já existe: só ganha o Nº Tabela, e só se ainda estiver sem
      if (l.situacao === 'EXISTENTE') {
        await conexao.query(
          'UPDATE jogos SET numero_tabela = ? WHERE id = ? AND numero_tabela IS NULL',
          [l.numero_tabela, l.jogo_id]
        );
        continue;
      }
      const [resultado] = await conexao.query(
        `INSERT INTO jogos
           (competicao_id, numero_jogo, numero_tabela, fase, rodada, grupo_id, local_id, data_hora,
            equipe_1_id, equipe_2_id, arbitro_1)
         VALUES (?, ?, ?, 'GRUPOS', ?, ?, ?, ?, ?, ?, ?)`,
        [l.competicao_id, l.numero_jogo, l.numero_tabela || null, l.rodada || null, l.grupo_id, l.local_id || null,
          l.data_hora, l.equipe_1_id, l.equipe_2_id, l.arbitro]
      );
      l.jogo_id = resultado.insertId;
    }

    await conexao.commit();

    const resposta = semInterno(analise);
    resposta.linhas.forEach((linha, i) => {
      if (analise.linhas[i]._gravar) linha.jogo_id = analise.linhas[i]._gravar.jogo_id;
    });
    const { novas, numeros_a_preencher: preenchidos } = resposta.resumo;
    const partes = [];
    if (novas > 0) partes.push(`${novas} ${novas === 1 ? 'jogo importado' : 'jogos importados'}`);
    if (preenchidos > 0) {
      partes.push(`${preenchidos} ${preenchidos === 1 ? 'jogo que já existia ganhou' : 'jogos que já existiam ganharam'} o ${COLUNA_NUMERO_TABELA}`);
    }

    res.status(novas > 0 || preenchidos > 0 ? 201 : 200).json({
      mensagem: partes.length ? `${partes.join(' e ')}.` : 'Nada novo: nada foi gravado.',
      ...resposta
    });
  } catch (erro) {
    if (conexao) await conexao.rollback();
    console.error('Erro ao importar jogos:', erro);
    res.status(500).json({ erro: 'Erro ao importar os jogos. Nada foi gravado.' });
  } finally {
    if (conexao) conexao.release();
  }
};

module.exports = {
  previaImportacao,
  importarJogos,
  // Exportados para o teste de fumaça e para a importação de atletas
  lerCsv,
  lerData,
  lerHora,
  normalizar,
  normalizarCategoria,
  APELIDOS_MODALIDADE,
  COLUNAS
};
