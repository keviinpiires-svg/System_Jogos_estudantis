const db = require('../config/db');
const { REGRAS } = require('../config/regrasProvisorias');

// Suspensão por cartões (regulamento, seção 5 do contexto):
//   - 2 amarelos acumulados = 1 jogo de suspensão;
//   - os amarelos são zerados na 2ª fase (mata-mata);
//   - qualquer expulsão = 1 jogo de suspensão automática, mais julgamento.
// Nada disso é gravado: é calculado das súmulas, como a classificação.
// A tabela `suspensoes` guarda só as disciplinares, que entram somadas aqui.
//
// O regulamento define esta regra para FUTSAL e FUTEBOL SOCIETY; o HANDEBOL
// ganhou a sua em 16/11/2026 (só o vermelho suspende, amarelos de jogos
// diferentes não acumulam). Basquete, vôlei e baleado não têm regra: nessas
// o cálculo não é aplicado e a tela recebe um aviso, em vez de o código
// inventar uma regra. As regras moram em regrasProvisorias.suspensaoPorCartoes.
const regraDaModalidade = (slug) => REGRAS.suspensaoPorCartoes.porModalidade[slug] || null;

const AMARELOS_POR_SUSPENSAO = 2;

// A 2ª fase começa no mata-mata: é onde os amarelos zeram
const segundaFase = (fase) => fase === 'SEMIFINAL' || fase === 'FINAL';

// Como o motivo cita o jogo: pelo nº da tabela do chefe (o que está no papel e na
// Agenda); sem ele, pelo nº na competição
const rotuloDoJogo = (jogo) => (jogo.numero_tabela ? `Nº ${jogo.numero_tabela}` : `#${jogo.numero_jogo}`);

// Ordem cronológica dos jogos: a data manda; sem data, o número do jogo.
// data_hora chega do banco como texto ("2026-11-24 10:30:00"), e nesse formato
// a ordem alfabética já é a ordem do relógio.
const ordenarJogos = (a, b) => {
  if (a.data_hora && b.data_hora && a.data_hora !== b.data_hora) {
    return a.data_hora < b.data_hora ? -1 : 1;
  }
  if (a.data_hora && !b.data_hora) return -1;
  if (!a.data_hora && b.data_hora) return 1;
  return a.numero_jogo - b.numero_jogo;
};

// Percorre os jogos de cada equipe em ordem e devolve, por atleta, o que
// ele deve e o que já cumpriu. `ateJogo` limita a leitura aos jogos
// anteriores a um jogo (é o que a súmula precisa: quem não pode entrar hoje).
const calcular = ({ jogos, lancamentos, disciplinares, ateJogo, amarelosAcumulam = true }) => {
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

      // Os 2 amarelos do MESMO jogo que viraram o vermelho (2º amarelo = expulsão) já valem a suspensão da
      // expulsão: não contam de novo como "2 amarelos". Um vermelho direto (com 0 ou 1 amarelo) segue
      // somando à parte, e amarelos de jogos diferentes continuam acumulando como antes.
      const expulsoPeloSegundoAmarelo = Boolean(linha.vermelho) && linha.amarelos >= AMARELOS_POR_SUSPENSAO;

      if (linha.amarelos > 0) {
        atleta.amarelos_na_fase += expulsoPeloSegundoAmarelo ? linha.amarelos - AMARELOS_POR_SUSPENSAO : linha.amarelos;
        atleta.amarelos_total += linha.amarelos;

        // Handebol: amarelos de jogos diferentes não acumulam suspensão (só o vermelho conta)
        while (amarelosAcumulam && atleta.amarelos_na_fase >= AMARELOS_POR_SUSPENSAO) {
          atleta.amarelos_na_fase -= AMARELOS_POR_SUSPENSAO;
          atleta.devidos += 1;
          atleta.motivos.push(`2 amarelos (até o jogo ${rotuloDoJogo(jogo)})`);
        }
      }

      if (linha.vermelho) {
        atleta.vermelhos += 1;
        atleta.devidos += 1;
        atleta.motivos.push(expulsoPeloSegundoAmarelo
          ? `2º amarelo, expulsão no jogo ${rotuloDoJogo(jogo)}`
          : `expulsão no jogo ${rotuloDoJogo(jogo)}`);
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
    `SELECT id, numero_jogo, numero_tabela, fase, data_hora, equipe_1_id, equipe_2_id
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
    `O regulamento escreve a suspensão por cartões para futsal e futebol society (e o chefe definiu a do handebol em 16/11/2026). ` +
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

    const regra = regraDaModalidade(competicao.modalidade_slug);
    const temRegra = Boolean(regra);
    const { jogos, lancamentos, disciplinares } = await carregar(competicao_id);
    const atletas = calcular({ jogos, lancamentos, disciplinares, amarelosAcumulam: regra ? regra.amarelosAcumulam : true });

    res.status(200).json({
      competicao: {
        id: competicao.id,
        modalidade_nome: competicao.modalidade_nome,
        modalidade_slug: competicao.modalidade_slug
      },
      regra_definida: temRegra,
      // O texto da regra da modalidade, para a tela mostrar (futsal e society; handebol desde 16/11/2026)
      regra: regra ? { amarelos_acumulam: regra.amarelosAcumulam, descricao: regra.descricao } : null,
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
    const regra = regraDaModalidade(competicao.modalidade_slug);
    const temRegra = Boolean(regra);
    const { jogos, lancamentos, disciplinares } = await carregar(jogo.competicao_id);

    // ateJogo corta a leitura neste jogo: só o que veio antes pesa
    const atletas = calcular({
      jogos, lancamentos, disciplinares, ateJogo: jogo_id, amarelosAcumulam: regra ? regra.amarelosAcumulam : true
    });
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

// GET /api/suspensoes/dia/:data — ADMIN. Lista para imprimir junto com as
// súmulas em branco do dia (17/11/2026: os locais não têm internet, a mesa
// anota no papel e o ADMIN lança depois). Para cada atleta com suspensão
// pendente ANTES do dia, aponta o(s) jogo(s) do dia em que ele cumpre: os
// próximos jogos da equipe naquele dia, na ordem do relógio. Agrupa pelo local
// do jogo em que cumpre, na ordem da tabela do chefe (numero_tabela).
//
// Limite: só entra o que já foi lançado. Um vermelho de um jogo do próprio dia,
// ou de súmula anterior ainda não lançada, não aparece; por isso a resposta
// conta os jogos anteriores dessas competições que ainda estão sem súmula.
const suspensosDoDia = async (req, res) => {
  const dia = String(req.params.data || '');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dia)) {
    return res.status(400).json({ erro: 'Data inválida. Use AAAA-MM-DD.' });
  }
  const inicioDoDia = `${dia} 00:00:00`;

  try {
    const [jogosDoDia] = await db.query(
      `SELECT j.id, j.competicao_id, j.numero_jogo, j.numero_tabela, j.data_hora, j.status,
              j.equipe_1_id, j.equipe_2_id, j.local_id, l.nome AS local_nome
         FROM jogos j
         LEFT JOIN locais_disputa l ON l.id = j.local_id
        WHERE DATE(j.data_hora) = ?`,
      [dia]
    );

    // Ordem da tabela: local pelo menor nº do dia, jogo pelo nº
    const ordemDoLocal = new Map();
    for (const j of jogosDoDia) {
      const chave = j.local_id ?? 0;
      const n = j.numero_tabela ?? Number.MAX_SAFE_INTEGER;
      if (!ordemDoLocal.has(chave) || n < ordemDoLocal.get(chave)) ordemDoLocal.set(chave, n);
    }

    const competicoesDoDia = [...new Set(jogosDoDia.map((j) => j.competicao_id))];
    // Todos os locais do dia, na ordem da tabela, mesmo os sem suspenso
    const locais = new Map();
    for (const j of jogosDoDia) {
      const chave = j.local_id ?? 0;
      if (!locais.has(chave)) {
        locais.set(chave, {
          local_id: j.local_id, local_nome: j.local_nome || 'Local a definir', ordem: ordemDoLocal.get(chave), suspensos: []
        });
      }
    }
    const semRegra = [];
    let jogosAnterioresSemSumula = 0;

    for (const competicao_id of competicoesDoDia) {
      const competicao = await dadosDaCompeticao(competicao_id);
      const regra = regraDaModalidade(competicao.modalidade_slug);
      const [[nomes]] = await db.query(
        `SELECT m.nome AS modalidade, cat.nome AS categoria, c.genero
           FROM competicoes c
           INNER JOIN modalidades m ON m.id = c.modalidade_id
           INNER JOIN categorias cat ON cat.id = c.categoria_id
          WHERE c.id = ?`,
        [competicao_id]
      );
      if (!regra) {
        if (!semRegra.includes(competicao.modalidade_nome)) semRegra.push(competicao.modalidade_nome);
        continue;
      }

      const [[{ pendentes }]] = await db.query(
        `SELECT COUNT(*) AS pendentes FROM jogos
          WHERE competicao_id = ? AND data_hora < ? AND status IN ('AGENDADO', 'EM_ANDAMENTO')
            AND equipe_1_id IS NOT NULL AND equipe_2_id IS NOT NULL`,
        [competicao_id, inicioDoDia]
      );
      jogosAnterioresSemSumula += Number(pendentes);

      // Só o que aconteceu ANTES do dia pesa (reimprimir no meio do dia não
      // mistura os jogos de hoje)
      const { jogos, lancamentos, disciplinares } = await carregar(competicao_id);
      const anteriores = jogos.filter((j) => !j.data_hora || j.data_hora < inicioDoDia);
      const anterioresIds = new Set(anteriores.map((j) => j.id));
      const atletas = calcular({
        jogos: anteriores,
        lancamentos: lancamentos.filter((l) => anterioresIds.has(l.jogo_id)),
        disciplinares,
        amarelosAcumulam: regra.amarelosAcumulam
      }).filter((a) => a.pendentes > 0);

      const daCompeticaoHoje = jogosDoDia
        .filter((j) => j.competicao_id === competicao_id)
        .sort(ordenarJogos);

      for (const atleta of atletas) {
        const jogosDaEquipe = daCompeticaoHoje.filter(
          (j) => j.equipe_1_id === atleta.equipe_id || j.equipe_2_id === atleta.equipe_id
        );
        if (jogosDaEquipe.length === 0) continue; // a equipe não joga neste dia
        const cumpre = jogosDaEquipe.slice(0, atleta.pendentes);
        // Uma linha por jogo em que cumpre, no local DESSE jogo (a equipe pode
        // jogar em dois locais no mesmo dia)
        cumpre.forEach((j, indice) => {
          const chaveLocal = j.local_id ?? 0;
          locais.get(chaveLocal).suspensos.push({
            atleta_id: atleta.atleta_id,
            atleta_nome: atleta.nome,
            escola_nome: atleta.escola_nome,
            competicao_id,
            competicao: { modalidade: nomes.modalidade, categoria: nomes.categoria, genero: nomes.genero },
            motivo: atleta.motivos[atleta.motivos.length - 1] || 'suspensão pendente',
            jogos_pendentes: atleta.pendentes,
            // 1º, 2º... jogo de suspensão que ele cumpre neste dia
            cumprimento: indice + 1,
            jogo: {
              id: j.id,
              numero_tabela: j.numero_tabela,
              hora: j.data_hora ? j.data_hora.slice(11, 16) : null
            },
            // Suspensão maior que os jogos da equipe no dia: o resto fica para os próximos dias
            restam_depois: Math.max(0, atleta.pendentes - cumpre.length)
          });
        });
      }
    }

    const ordenados = [...locais.values()].sort((a, b) => a.ordem - b.ordem);
    for (const local of ordenados) {
      local.suspensos.sort((a, b) =>
        (a.jogo.numero_tabela ?? Infinity) - (b.jogo.numero_tabela ?? Infinity)
        || a.atleta_nome.localeCompare(b.atleta_nome, 'pt-BR'));
      delete local.ordem;
    }

    res.status(200).json({
      dia,
      locais: ordenados,
      // Linhas (atleta x jogo em que cumpre)
      total: ordenados.reduce((soma, l) => soma + l.suspensos.length, 0),
      jogos_anteriores_sem_sumula: jogosAnterioresSemSumula,
      modalidades_sem_regra: semRegra
    });
  } catch (erro) {
    console.error('Erro ao montar a lista de suspensos do dia:', erro);
    res.status(500).json({ erro: 'Erro ao montar a lista de suspensos do dia.' });
  }
};

module.exports = { situacaoDaCompeticao, suspensosNoJogo, suspensosDoDia };
