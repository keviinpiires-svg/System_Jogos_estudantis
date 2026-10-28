const db = require('../config/db');
const {
  lerCsv, normalizar, normalizarCategoria, APELIDOS_MODALIDADE
} = require('./importacaoJogosController');
const {
  normalizarRg, normalizarNome, dataValida, validarAtleta, sexoCombina, idadeCabe,
  motivoDeInelegibilidade, ADJETIVO_GENERO, plural
} = require('../config/elegibilidade');

// ============================================================================
// Importação de atletas por CSV (só ADMIN), no molde da importação de jogos.
//
// Cada linha é um aluno numa modalidade: o mesmo aluno pode aparecer em várias
// linhas, uma por modalidade. A linha vira um atleta novo (na primeira vez que
// o RG aparece) e uma inscrição na equipe da escola na competição.
//
// - PRÉVIA: analisa o arquivo e diz o que cada linha vai virar, sem gravar.
// - CONFIRMAR: refaz a análise numa transação única, com as equipes travadas,
//   e grava só as linhas OK. Qualquer falha desfaz tudo. Com linha em ERRO,
//   só grava se a tela pedir explicitamente (apenas_ok=true).
// - RG já cadastrado: a linha é PULADA (AVISO) e o atleta existente nunca é
//   alterado, nem ganha inscrição.
// - As regras de elegibilidade são as da inscrição (src/config/elegibilidade).
// - Dado pessoal de menor: RG e nascimento não vão para o log.
// ============================================================================

const MAX_LINHAS = 2000;

// [chave, rótulo do modelo, nomes aceitos no cabeçalho (já normalizados)]
const COLUNAS = [
  ['escola', 'Escola', ['ESCOLA']],
  ['nome', 'Nome', ['NOME', 'NOME DO ATLETA', 'NOME DO ALUNO', 'ATLETA', 'ALUNO']],
  ['rg', 'RG', ['RG', 'R G', 'RG DO ATLETA']],
  ['nascimento', 'Nascimento', ['NASCIMENTO', 'DATA DE NASCIMENTO', 'DATA NASCIMENTO', 'DT NASCIMENTO']],
  ['genero', 'Gênero', ['GENERO', 'SEXO']],
  ['modalidade', 'Modalidade', ['MODALIDADE']],
  ['categoria', 'Categoria', ['CATEGORIA']]
];
const OPCIONAIS = ['escola', 'categoria'];

const SEXO_DO_TEXTO = {
  M: 'M', MASC: 'M', MASCULINO: 'M',
  F: 'F', FEM: 'F', FEMININO: 'F'
};

const NOME_GENERO = { MASCULINO: 'Masculino', FEMININO: 'Feminino', MISTO: 'Misto' };

const doisDigitos = (n) => String(n).padStart(2, '0');

// "05/03/2012", "5/3/2012", "05-03-2012", "05.03.2012" ou "2012-03-05".
// Ano com 4 dígitos (nascimento com 2 dígitos é ambíguo). Devolve
// "AAAA-MM-DD", ou undefined se inválido.
const lerNascimento = (texto) => {
  const t = String(texto || '').trim();
  let m = /^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$/.exec(t);
  let iso;
  if (m) iso = `${m[3]}-${doisDigitos(m[2])}-${doisDigitos(m[1])}`;
  else if ((m = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(t))) iso = `${m[1]}-${doisDigitos(m[2])}-${doisDigitos(m[3])}`;
  return iso && dataValida(iso) ? iso : undefined;
};

// ----------------------------------------------------------------------------
// Cadastro: tudo o que a análise consulta, lido de uma vez
// ----------------------------------------------------------------------------

const carregarCadastro = async (conexao) => {
  const consultar = async (sql) => (await conexao.query(sql))[0];

  const [config] = await consultar('SELECT ano FROM configuracao_evento WHERE id = 1');
  const modalidades = await consultar('SELECT id, nome, slug FROM modalidades');
  const categorias = await consultar('SELECT id, nome, idade_maxima FROM categorias');
  const competicoes = await consultar(
    `SELECT c.id, c.modalidade_id, c.categoria_id, c.genero,
            m.nome AS modalidade_nome, m.tipo AS modalidade_tipo, m.max_atletas,
            cat.nome AS categoria_nome, cat.idade_maxima
       FROM competicoes c
       INNER JOIN modalidades m ON m.id = c.modalidade_id
       INNER JOIN categorias cat ON cat.id = c.categoria_id`
  );
  const equipes = await consultar('SELECT id, competicao_id, escola_id FROM equipes');
  const escolas = await consultar('SELECT id, nome FROM escolas');
  const apelidos = await consultar('SELECT escola_id, apelido FROM escola_apelidos');

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
    modalidadePorNome,
    categoriaPorNome: new Map(categorias.map((c) => [normalizarCategoria(c.nome), c])),
    competicoes,
    equipes,
    escolaNome: new Map(escolas.map((e) => [e.id, e.nome])),
    escolasPorNome
  };
};

const nomeDaCompeticao = (c) => `${c.modalidade_nome} ${c.categoria_nome} ${NOME_GENERO[c.genero]}`;

// Sub 7 antes de Sub 17, e o Aberto (sem idade) por último
const porIdade = (a, b) => (a.idade_maxima ?? Infinity) - (b.idade_maxima ?? Infinity);

// ----------------------------------------------------------------------------
// 1ª etapa: cada linha sozinha, só contra o cadastro
// ----------------------------------------------------------------------------

const validarLinha = (valores, cadastro, escolaFixa) => {
  const erros = [];
  const l = { erros, avisos: [] };

  // Escola: a coluna, ou a escolhida na tela quando a planilha não tem a coluna
  let escola_id = null;
  if (escolaFixa) {
    escola_id = escolaFixa;
  } else if (!valores.escola) {
    erros.push('Escola em branco.');
  } else {
    const encontradas = [...(cadastro.escolasPorNome.get(normalizar(valores.escola)) || [])];
    if (encontradas.length === 0) {
      erros.push(`Escola "${valores.escola}" não encontrada (nem pelo nome nem pelos apelidos).`);
    } else if (encontradas.length > 1) {
      const nomes = encontradas.map((id) => cadastro.escolaNome.get(id)).join(', ');
      erros.push(`"${valores.escola}" é ambíguo, serve para ${nomes}.`);
    } else {
      [escola_id] = encontradas;
    }
  }
  if (escola_id) l.escola = cadastro.escolaNome.get(escola_id);

  const nome = normalizarNome(valores.nome);
  const rg = normalizarRg(valores.rg);
  const sexo = SEXO_DO_TEXTO[normalizar(valores.genero)];
  const data_nascimento = lerNascimento(valores.nascimento);

  if (!rg) erros.push('RG vazio: o RG é obrigatório.');
  if (!valores.nascimento) erros.push('Nascimento em branco.');
  else if (!data_nascimento) erros.push(`Nascimento "${valores.nascimento}" inválido: use DD/MM/AAAA.`);
  if (!sexo) {
    erros.push(valores.genero
      ? `Gênero "${valores.genero}" inválido: use M ou F (Masculino ou Feminino).`
      : 'Gênero em branco: use M ou F.');
  }

  // As demais regras do atleta (nome, tamanhos, data no futuro): as mesmas do cadastro
  if (rg && data_nascimento && sexo && escola_id) {
    const problema = validarAtleta({ nome, rg, data_nascimento, sexo, escola_id });
    if (problema) erros.push(problema);
  } else if (!nome) {
    erros.push('Informe o nome do atleta.');
  }

  const modalidade = valores.modalidade ? cadastro.modalidadePorNome.get(normalizar(valores.modalidade)) : null;
  if (!valores.modalidade) erros.push('Modalidade em branco.');
  else if (!modalidade) erros.push(`Modalidade "${valores.modalidade}" não encontrada.`);

  const categoria = valores.categoria ? cadastro.categoriaPorNome.get(normalizarCategoria(valores.categoria)) : null;
  if (valores.categoria && !categoria) erros.push(`Categoria "${valores.categoria}" não existe.`);

  Object.assign(l, { escola_id, nome, rg, sexo, data_nascimento });
  if (erros.length) return l;

  // Competição: a da modalidade que aceita o sexo do atleta (MISTO aceita os
  // dois; havendo a do gênero e a mista na mesma categoria, vale a do gênero)
  const anoNascimento = Number(data_nascimento.slice(0, 4));
  const doSexo = cadastro.competicoes
    .filter((c) => c.modalidade_id === modalidade.id && sexoCombina(c.genero, sexo))
    .sort((a, b) => porIdade(a, b) || (a.genero === 'MISTO') - (b.genero === 'MISTO'));
  const generoDoAtleta = sexo === 'M' ? 'MASCULINO' : 'FEMININO';

  if (doSexo.length === 0) {
    erros.push(`${modalidade.nome} não tem competição ${ADJETIVO_GENERO[generoDoAtleta]} nem mista.`);
    return l;
  }

  let competicao;
  if (categoria) {
    competicao = doSexo.find((c) => c.categoria_id === categoria.id);
    if (!competicao) {
      erros.push(`Não existe a competição ${modalidade.nome} ${categoria.nome} para o gênero do atleta.`);
      return l;
    }
  } else {
    // Sem a coluna Categoria: a categoria do atleta pela idade, a menor em que
    // ele cabe. Jogar acima da própria categoria só com a Categoria preenchida.
    competicao = doSexo.find((c) => idadeCabe(cadastro.ano, c.idade_maxima, anoNascimento));
    if (!competicao) {
      const existentes = [...new Set(doSexo.map((c) => c.categoria_nome))].join(', ');
      erros.push(`Nascido em ${anoNascimento}: fora das categorias de ${modalidade.nome} para o gênero do atleta (${existentes}).`);
      return l;
    }
    l.categoria_pela_idade = true;
  }

  l.competicao = nomeDaCompeticao(competicao);
  l.competicao_dados = competicao;
  l.ano_nascimento = anoNascimento;

  const equipe = cadastro.equipes.find((e) => e.competicao_id === competicao.id && e.escola_id === escola_id);
  if (!equipe) {
    erros.push(`${l.escola} não tem equipe em ${l.competicao}`
      + `${l.categoria_pela_idade ? ' (categoria pela idade; se o atleta joga acima, preencha a Categoria)' : ''}.`);
    return l;
  }
  l.equipe_id = equipe.id;

  return l;
};

// ----------------------------------------------------------------------------
// Análise do arquivo inteiro
// ----------------------------------------------------------------------------

// `travar` = dentro da transação do confirmar: as equipes e os RGs das linhas
// são travados antes de contar inscritos e de procurar RG já cadastrado.
const analisar = async (conexao, texto, { escolaId = null, travar = false } = {}) => {
  const csv = lerCsv(texto);

  if (csv.aspasAbertas) {
    return { erroDoArquivo: 'O arquivo tem aspas abertas que não fecham: confira o CSV.' };
  }
  if (csv.linhas.length < 2) {
    return { erroDoArquivo: 'O arquivo não tem atletas: precisa do cabeçalho e de pelo menos uma linha.' };
  }
  if (csv.linhas.length - 1 > MAX_LINHAS) {
    return { erroDoArquivo: `O arquivo tem mais de ${MAX_LINHAS} linhas. Divida em arquivos menores.` };
  }

  const cabecalho = csv.linhas[0].campos.map(normalizar);
  const posicao = {};
  const faltando = [];
  for (const [chave, rotulo, aceitos] of COLUNAS) {
    const indice = cabecalho.findIndex((c) => aceitos.includes(c));
    if (indice !== -1) posicao[chave] = indice;
    else if (!OPCIONAIS.includes(chave)) faltando.push(rotulo);
  }
  if (faltando.length) {
    return {
      erroDoArquivo: `Faltam colunas no cabeçalho: ${faltando.join(', ')}. `
        + `O arquivo precisa de: ${COLUNAS.map(([, r]) => r).join(', ')} (Escola e Categoria são opcionais).`
    };
  }

  // O cadastro é lido fora da transação: não muda durante a importação
  const cadastro = await carregarCadastro(travar ? db : conexao);

  // Sem a coluna Escola, a planilha é de uma escola só, escolhida na tela
  const temColunaEscola = posicao.escola !== undefined;
  let escolaFixa = null;
  if (!temColunaEscola) {
    escolaFixa = Number(escolaId);
    if (!Number.isInteger(escolaFixa) || escolaFixa <= 0 || !cadastro.escolaNome.has(escolaFixa)) {
      return { erroDoArquivo: 'A planilha não tem a coluna Escola: escolha a escola antes de enviar.' };
    }
  }

  const linhas = csv.linhas.slice(1).map((l) => {
    const valores = Object.fromEntries(
      COLUNAS.map(([chave]) => [chave, posicao[chave] === undefined ? '' : String(l.campos[posicao[chave]] ?? '').trim()])
    );
    return { linha: l.numero, valores, ...validarLinha(valores, cadastro, escolaFixa) };
  });

  // Travas e o que já está gravado: equipes das linhas (elenco) e RGs
  const equipesIds = [...new Set(linhas.filter((l) => l.equipe_id).map((l) => l.equipe_id))].sort((a, b) => a - b);
  const rgs = [...new Set(linhas.filter((l) => l.rg).map((l) => l.rg))];

  if (travar && equipesIds.length) {
    await conexao.query('SELECT id FROM equipes WHERE id IN (?) ORDER BY id FOR UPDATE', [equipesIds]);
  }

  const [inscritosPorEquipe] = equipesIds.length
    ? await conexao.query(
      'SELECT equipe_id, COUNT(*) AS inscritos FROM inscricoes_atletas WHERE equipe_id IN (?) GROUP BY equipe_id',
      [equipesIds]
    )
    : [[]];
  const inscritos = new Map(inscritosPorEquipe.map((r) => [r.equipe_id, Number(r.inscritos)]));

  const [jaCadastrados] = rgs.length
    ? await conexao.query(
      `SELECT a.rg, a.nome, esc.nome AS escola_nome
         FROM atletas a INNER JOIN escolas esc ON esc.id = a.escola_id
        WHERE a.rg IN (?)${travar ? ' FOR UPDATE' : ''}`,
      [rgs]
    )
    : [[]];
  const cadastradoPorRg = new Map(jaCadastrados.map((a) => [a.rg, a]));

  // 2ª etapa, na ordem do arquivo: RG já cadastrado, o mesmo aluno em várias
  // linhas e os limites contando o que as linhas anteriores já vão gravar
  const primeiraDoRg = new Map();       // rg -> primeira linha (define o atleta)
  const okDoRg = new Map();             // rg -> linhas OK anteriores
  const okNaEquipe = new Map();         // equipe_id -> linhas OK anteriores

  for (const l of linhas) {
    if (l.rg && cadastradoPorRg.has(l.rg)) {
      const existente = cadastradoPorRg.get(l.rg);
      l.pulada = true;
      l.erros.length = 0;
      l.avisos.push(`RG já cadastrado (${existente.nome}, ${existente.escola_nome}): linha pulada, `
        + 'o atleta existente não é alterado.');
      continue;
    }

    if (l.rg) {
      const primeira = primeiraDoRg.get(l.rg);
      if (!primeira) {
        primeiraDoRg.set(l.rg, l);
      } else {
        const diferentes = [];
        if (normalizar(primeira.nome) !== normalizar(l.nome)) diferentes.push('nome');
        if (primeira.data_nascimento !== l.data_nascimento) diferentes.push('nascimento');
        if (primeira.sexo !== l.sexo) diferentes.push('gênero');
        if (primeira.escola_id !== l.escola_id) diferentes.push('escola');
        if (diferentes.length) {
          l.erros.push(`Mesmo RG da linha ${primeira.linha} com ${diferentes.join(', ')} diferente.`);
        }
      }
    }

    if (l.erros.length) continue;

    const anteriores = okDoRg.get(l.rg) || [];
    const repetida = anteriores.find((o) => o.equipe_id === l.equipe_id);
    if (repetida) {
      l.pulada = true;
      l.avisos.push(`Repete a linha ${repetida.linha} (mesmo atleta na mesma competição): entra uma vez só.`);
      continue;
    }

    const competicao = l.competicao_dados;
    const coletivas = new Set(anteriores
      .filter((o) => o.competicao_dados.modalidade_tipo === 'COLETIVO')
      .map((o) => o.competicao_dados.id)).size;
    const naEquipe = (inscritos.get(l.equipe_id) || 0) + (okNaEquipe.get(l.equipe_id) || []).length;

    const recusa = motivoDeInelegibilidade({
      competicao,
      atleta: { nome: l.nome, sexo: l.sexo, ano_nascimento: l.ano_nascimento },
      anoDoEvento: cadastro.ano,
      coletivas,
      inscritos: naEquipe
    });
    if (recusa) {
      l.erros.push(recusa.erro);
      continue;
    }

    okDoRg.set(l.rg, [...anteriores, l]);
    okNaEquipe.set(l.equipe_id, [...(okNaEquipe.get(l.equipe_id) || []), l]);
  }

  for (const l of linhas) {
    if (l.erros.length) l.situacao = 'ERRO';
    else if (l.pulada) l.situacao = 'AVISO';
    else l.situacao = 'OK';
  }

  const ok = linhas.filter((l) => l.situacao === 'OK');

  return {
    linhas: linhas.map((l) => ({
      linha: l.linha,
      situacao: l.situacao,
      valores: l.valores,
      escola: l.escola || null,
      competicao: l.competicao || null,
      categoria_pela_idade: Boolean(l.categoria_pela_idade),
      erros: l.erros,
      avisos: l.avisos,
      // Só o backend usa: o que vai para os INSERT
      _gravar: l.situacao === 'OK' ? l : undefined
    })),
    resumo: {
      linhas: linhas.length,
      ok: ok.length,
      avisos: linhas.filter((l) => l.situacao === 'AVISO').length,
      erros: linhas.filter((l) => l.situacao === 'ERRO').length,
      atletas_novos: new Set(ok.map((l) => l.rg)).size,
      inscricoes: ok.length
    },
    sem_coluna_escola: !temColunaEscola
  };
};

const semInterno = (analise) => ({
  resumo: analise.resumo,
  sem_coluna_escola: analise.sem_coluna_escola,
  linhas: analise.linhas.map(({ _gravar, ...resto }) => resto)
});

// Erro do banco traz o valor que colidiu (o RG) na mensagem e o SQL com os
// parâmetros: no log vai só o código. Erro de programa vai com a pilha.
const registrarErro = (contexto, erro) => {
  if (erro && erro.sqlState) console.error(`${contexto}:`, erro.code, erro.errno);
  else console.error(`${contexto}:`, erro && erro.stack ? erro.stack : erro);
};

const verdadeiro = (v) => ['1', 'true', 'sim'].includes(String(v || '').toLowerCase());

// POST /api/importar-atletas/previa?escola_id= — corpo: o CSV (text/csv). Não grava.
const previaAtletas = async (req, res) => {
  try {
    const analise = await analisar(db, req.body, { escolaId: req.query.escola_id });
    if (analise.erroDoArquivo) return res.status(400).json({ erro: analise.erroDoArquivo });
    res.json(semInterno(analise));
  } catch (erro) {
    registrarErro('Erro na prévia da importação de atletas', erro);
    res.status(500).json({ erro: 'Erro ao analisar o arquivo de atletas.' });
  }
};

// POST /api/importar-atletas/confirmar?escola_id=&apenas_ok=true — corpo: o mesmo
// CSV. Refaz a análise numa transação única e grava as linhas OK: tudo ou nada.
const confirmarAtletas = async (req, res) => {
  let conexao;
  try {
    conexao = await db.getConnection();
    await conexao.beginTransaction();

    const analise = await analisar(conexao, req.body, { escolaId: req.query.escola_id, travar: true });
    if (analise.erroDoArquivo) {
      await conexao.rollback();
      return res.status(400).json({ erro: analise.erroDoArquivo });
    }

    const { resumo } = analise;
    if (resumo.erros > 0 && !verdadeiro(req.query.apenas_ok)) {
      await conexao.rollback();
      return res.status(422).json({
        erro: `O arquivo tem ${plural(resumo.erros, 'linha', 'linhas')} com erro. Corrija o arquivo `
          + 'ou confirme "importar só as linhas OK". Nada foi gravado.',
        ...semInterno(analise)
      });
    }

    const atletaPorRg = new Map();
    for (const { _gravar: l } of analise.linhas.filter((x) => x._gravar)) {
      if (!atletaPorRg.has(l.rg)) {
        const [novo] = await conexao.query(
          'INSERT INTO atletas (nome, rg, data_nascimento, sexo, escola_id) VALUES (?, ?, ?, ?, ?)',
          [l.nome, l.rg, l.data_nascimento, l.sexo, l.escola_id]
        );
        atletaPorRg.set(l.rg, novo.insertId);
      }
      await conexao.query(
        'INSERT INTO inscricoes_atletas (equipe_id, atleta_id, escola_id, numero_camisa) VALUES (?, ?, ?, NULL)',
        [l.equipe_id, atletaPorRg.get(l.rg), l.escola_id]
      );
    }

    await conexao.commit();

    const final = {
      criados: atletaPorRg.size,
      inscricoes: resumo.ok,
      pulados: resumo.avisos,
      com_erro: resumo.erros
    };
    const mensagem = resumo.ok === 0
      ? 'Nada novo: nenhum atleta foi gravado.'
      : `${plural(final.criados, 'atleta criado', 'atletas criados')} e `
        + `${plural(final.inscricoes, 'inscrição feita', 'inscrições feitas')}; `
        + `${plural(final.pulados, 'linha pulada', 'linhas puladas')} e `
        + `${plural(final.com_erro, 'linha com erro', 'linhas com erro')} ficaram de fora.`;

    res.status(resumo.ok > 0 ? 201 : 200).json({ mensagem, final, ...semInterno(analise) });
  } catch (erro) {
    if (conexao) await conexao.rollback();
    registrarErro('Erro ao importar atletas', erro);
    if (erro.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({
        erro: 'Outro cadastro gravou um destes atletas enquanto a importação rodava. Nada foi gravado: refaça a prévia.'
      });
    }
    res.status(500).json({ erro: 'Erro ao importar os atletas. Nada foi gravado.' });
  } finally {
    if (conexao) conexao.release();
  }
};

module.exports = {
  previaAtletas,
  confirmarAtletas,
  // Exportados para o teste de fumaça
  lerNascimento,
  COLUNAS
};
