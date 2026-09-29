const db = require('../config/db');

// Suspensão por cartões (regulamento, seção 5 do contexto):
//   - 2 amarelos acumulados = 1 jogo de suspensão;
//   - os amarelos são zerados na 2ª fase (mata-mata);
//   - qualquer expulsão = 1 jogo de suspensão automática, mais julgamento.
// Nada disso é gravado: é calculado das súmulas, como a classificação.
// A tabela `suspensoes` guarda só as disciplinares, que entram somadas aqui.
//
// O regulamento define esta regra para FUTSAL e FUTEBOL SOCIETY. Handebol,
// basquete, vôlei e baleado não têm regra escrita de suspensão por cartão:
// nessas modalidades o cálculo não é aplicado e a tela recebe um aviso, em
// vez de o código inventar uma regra. [PENDENTE no contexto]
const MODALIDADES_COM_REGRA = ['futsal', 'futebol-society'];

const AMARELOS_POR_SUSPENSAO = 2;

// A 2ª fase começa no mata-mata: é onde os amarelos zeram
const segundaFase = (fase) => fase === 'SEMIFINAL' || fase === 'FINAL';

// Ordem cronológica dos jogos: a data manda; sem data, o número do jogo
const ordenarJogos = (a, b) => {
  if (a.data_hora && b.data_hora && a.data_hora.getTime() !== b.data_hora.getTime()) {
    return a.data_hora - b.data_hora;
  }
  if (a.data_hora && !b.data_hora) return -1;
  if (!a.data_hora && b.data_hora) return 1;
  return a.numero_jogo - b.numero_jogo;
};

// Percorre os jogos de cada equipe em ordem e devolve, por atleta, o que
// ele deve e o que já cumpriu. `ateJogo` limita a leitura aos jogos
// anteriores a um jogo (é o que a súmula precisa: quem não pode entrar hoje).
const calcular = ({ jogos, lancamentos, disciplinares, ateJogo }) => {
  const ordenados = [...jogos].sort(ordenarJogos);
  const corte = ateJogo ? ordenados.findIndex((j) => j.id === ateJogo) : -1;
  const considerados = corte >= 0 ? ordenados.slice(0, corte) : ordenados;

  // jogo_id -> equipe_id -> atleta_id -> lançamento
  const porJogo = new Map();
  for (const linha of lancamentos) {
    if (!porJogo.has(linha.jogo_id)) porJogo.set(linha.jogo_id, new Map());
    porJogo.get(linha.jogo_id).set(linha.atleta_id, linha);
  }

  const atletas = new Map();
  const doAtleta = (id, base) => {
    if (!atletas.has(id)) {
      atletas.set(id, {
        atleta_id: id,
        nome: base.nome,
        equipe_id: base.equipe_id,
        escola_nome: base.escola_nome,
        amarelos_na_fase: 0,
        amarelos_total: 0,
        vermelhos: 0,
        devidos: 0,
        cumpridos: 0,
        motivos: []
      });
    }
    return atletas.get(id);
  };

  // Estado por equipe: qual fase estava valendo no último jogo visto
  const faseDaEquipe = new Map();

  for (const jogo of considerados) {
    const lancados = porJogo.get(jogo.id) || new Map();

    for (const equipe_id of [jogo.equipe_1_id, jogo.equipe_2_id]) {
      // Virou a fase: os amarelos da fase anterior somem (o que já foi
      // convertido em suspensão continua devendo)
      if (faseDaEquipe.get(equipe_id) !== undefined
        && segundaFase(jogo.fase) !== segundaFase(faseDaEquipe.get(equipe_id))) {
        for (const atleta of atletas.values()) {
          if (atleta.equipe_id === equipe_id) atleta.amarelos_na_fase = 0;
        }
      }
      faseDaEquipe.set(equipe_id, jogo.fase);
    }

    for (const linha of lancados.values()) {
      const atleta = doAtleta(linha.atleta_id, linha);

      if (linha.amarelos > 0) {
        atleta.amarelos_na_fase += linha.amarelos;
        atleta.amarelos_total += linha.amarelos;

        while (atleta.amarelos_na_fase >= AMARELOS_POR_SUSPENSAO) {
          atleta.amarelos_na_fase -= AMARELOS_POR_SUSPENSAO;
          atleta.devidos += 1;
          atleta.motivos.push(`2 amarelos (até o jogo #${jogo.numero_jogo})`);
        }
      }

      if (linha.vermelho) {
        atleta.vermelhos += 1;
        atleta.devidos += 1;
        atleta.motivos.push(`expulsão no jogo #${jogo.numero_jogo}`);
      }
    }

    // Ausência num jogo posterior ao castigo cumpre um jogo de suspensão
    for (const atleta of atletas.values()) {
      const jogoDaEquipe = atleta.equipe_id === jogo.equipe_1_id || atleta.equipe_id === jogo.equipe_2_id;
      if (!jogoDaEquipe) continue;

      const lancamento = lancados.get(atleta.atleta_id);
      const ausente = !lancamento || !lancamento.presente;
      const pendia = atleta.devidos - atleta.cumpridos;

      // Só conta se o castigo já existia ANTES deste jogo: um vermelho
      // tirado hoje não é cumprido no mesmo jogo em que aconteceu
      const punidoHoje = lancamento && (lancamento.vermelho || lancamento.amarelos >= AMARELOS_POR_SUSPENSAO);

      if (ausente && pendia > 0 && !punidoHoje) {
        atleta.cumpridos += 1;
      }
    }
  }

  // Suspensões disciplinares (Comissão): somam ao que o atleta deve
  for (const disciplinar of disciplinares) {
    const atleta = atletas.get(disciplinar.atleta_id);
    if (!atleta) continue;
    atleta.devidos += disciplinar.qtd_jogos ?? 1;
    atleta.motivos.push(disciplinar.motivo);
  }

  return [...atletas.values()]
    .map((atleta) => ({
      ...atleta,
      pendentes: Math.max(0, atleta.devidos - atleta.cumpridos)
    }))
    .filter((atleta) => atleta.amarelos_total > 0 || atleta.vermelhos > 0 || atleta.pendentes > 0)
    .sort((a, b) => b.pendentes - a.pendentes || a.nome.localeCompare(b.nome, 'pt-BR'));
};

// Carrega jogos, lançamentos e suspensões disciplinares de uma competição
const carregar = async (competicao_id) => {
  const [jogos] = await db.query(
    `SELECT id, numero_jogo, fase, data_hora, equipe_1_id, equipe_2_id
       FROM jogos
      WHERE competicao_id = ? AND status IN ('FINALIZADO', 'WO', 'EM_ANDAMENTO')`,
    [competicao_id]
  );

  const [lancamentos] = await db.query(
    `SELECT s.jogo_id, s.equipe_id, s.atleta_id, s.presente, s.amarelos, s.vermelho,
            a.nome, esc.nome AS escola_nome
       FROM sumula_atletas s
       INNER JOIN jogos j ON j.id = s.jogo_id
       INNER JOIN atletas a ON a.id = s.atleta_id
       INNER JOIN equipes e ON e.id = s.equipe_id
       INNER JOIN escolas esc ON esc.id = e.escola_id
      WHERE j.competicao_id = ?`,
    [competicao_id]
  );

  const [disciplinares] = await db.query(
    `SELECT s.atleta_id, s.qtd_jogos, s.motivo
       FROM suspensoes s
       INNER JOIN inscricoes_atletas i ON i.atleta_id = s.atleta_id
       INNER JOIN equipes e ON e.id = i.equipe_id
      WHERE e.competicao_id = ?`,
    [competicao_id]
  );

  return { jogos, lancamentos, disciplinares };
};

const dadosDaCompeticao = async (competicao_id) => {
  const [[competicao]] = await db.query(
    `SELECT c.id, m.nome AS modalidade_nome, m.slug AS modalidade_slug
       FROM competicoes c
       INNER JOIN modalidades m ON m.id = c.modalidade_id
      WHERE c.id = ?`,
    [competicao_id]
  );
  return competicao;
};

const avisoDeRegra = (competicao) => ({
  titulo: 'Suspensão por cartões sem regra definida',
  texto:
    `O regulamento escreve a suspensão por cartões para futsal e futebol society. ` +
    `Em ${competicao.modalidade_nome} não há regra escrita, então o sistema mostra os cartões ` +
    'mas não declara ninguém suspenso. Defina a regra com a Comissão antes de usar isto em quadra.'
});

// GET /api/suspensoes/competicao/:competicao_id
const situacaoDaCompeticao = async (req, res) => {
  const competicao_id = Number(req.params.competicao_id);

  if (!Number.isInteger(competicao_id) || competicao_id <= 0) {
    return res.status(400).json({ erro: 'Identificador de competição inválido.' });
  }

  try {
    const competicao = await dadosDaCompeticao(competicao_id);

    if (!competicao) {
      return res.status(404).json({ erro: 'Competição não encontrada.' });
    }

    const temRegra = MODALIDADES_COM_REGRA.includes(competicao.modalidade_slug);
    const { jogos, lancamentos, disciplinares } = await carregar(competicao_id);
    const atletas = calcular({ jogos, lancamentos, disciplinares });

    res.status(200).json({
      competicao: {
        id: competicao.id,
        modalidade_nome: competicao.modalidade_nome,
        modalidade_slug: competicao.modalidade_slug
      },
      regra_definida: temRegra,
      avisos: temRegra ? [] : [avisoDeRegra(competicao)],
      // Sem regra escrita, os cartões aparecem mas ninguém fica suspenso
      atletas: temRegra ? atletas : atletas.map((a) => ({ ...a, pendentes: 0, motivos: [] }))
    });
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao calcular as suspensões.' });
  }
};

// GET /api/suspensoes/jogo/:jogo_id — quem não pode entrar neste jogo
const suspensosNoJogo = async (req, res) => {
  const jogo_id = Number(req.params.jogo_id);

  if (!Number.isInteger(jogo_id) || jogo_id <= 0) {
    return res.status(400).json({ erro: 'Identificador de jogo inválido.' });
  }

  try {
    const [[jogo]] = await db.query(
      'SELECT id, competicao_id, equipe_1_id, equipe_2_id FROM jogos WHERE id = ?',
      [jogo_id]
    );

    if (!jogo) {
      return res.status(404).json({ erro: 'Jogo não encontrado.' });
    }

    const competicao = await dadosDaCompeticao(jogo.competicao_id);
    const temRegra = MODALIDADES_COM_REGRA.includes(competicao.modalidade_slug);
    const { jogos, lancamentos, disciplinares } = await carregar(jogo.competicao_id);

    // ateJogo corta a leitura neste jogo: só o que veio antes pesa
    const atletas = calcular({ jogos, lancamentos, disciplinares, ateJogo: jogo_id });
    const equipes = [jogo.equipe_1_id, jogo.equipe_2_id];

    const suspensos = temRegra
      ? atletas.filter((a) => a.pendentes > 0 && equipes.includes(a.equipe_id))
      : [];

    res.status(200).json({
      jogo_id,
      regra_definida: temRegra,
      avisos: temRegra ? [] : [avisoDeRegra(competicao)],
      suspensos: suspensos.map((a) => ({
        atleta_id: a.atleta_id,
        nome: a.nome,
        equipe_id: a.equipe_id,
        escola_nome: a.escola_nome,
        jogos_pendentes: a.pendentes,
        motivo: a.motivos[a.motivos.length - 1] || 'suspensão pendente'
      }))
    });
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao verificar as suspensões do jogo.' });
  }
};

module.exports = { situacaoDaCompeticao, suspensosNoJogo };
