const db = require('../config/db');
const { anoMinimoDaCategoria } = require('../config/elegibilidade');

// Equipes filtradas por escola e/ou competição, com o que a tela de inscrição
// precisa para decidir: a competição a que pertencem, o grupo, quantos atletas
// já estão inscritos e qual é o teto da modalidade.
const listarEquipes = async (req, res) => {
  const condicoes = [];
  const valores = [];

  if (req.query.escola_id) {
    const escola_id = Number(req.query.escola_id);
    if (!Number.isInteger(escola_id) || escola_id <= 0) {
      return res.status(400).json({ erro: 'Identificador de escola inválido.' });
    }
    condicoes.push('e.escola_id = ?');
    valores.push(escola_id);
  }

  if (req.query.competicao_id) {
    const competicao_id = Number(req.query.competicao_id);
    if (!Number.isInteger(competicao_id) || competicao_id <= 0) {
      return res.status(400).json({ erro: 'Identificador de competição inválido.' });
    }
    condicoes.push('e.competicao_id = ?');
    valores.push(competicao_id);
  }

  const onde = condicoes.length > 0 ? `WHERE ${condicoes.join(' AND ')}` : '';

  try {
    const [equipes] = await db.query(
      `SELECT e.id, e.escola_id, e.competicao_id, e.tecnico_nome,
              esc.nome AS escola_nome,
              g.id AS grupo_id, g.nome AS grupo_nome,
              m.id AS modalidade_id, m.nome AS modalidade_nome, m.slug AS modalidade_slug,
              m.tipo AS modalidade_tipo, m.min_atletas, m.max_atletas,
              cat.nome AS categoria_nome, cat.idade_maxima, c.genero,
              (SELECT COUNT(*) FROM inscricoes_atletas i WHERE i.equipe_id = e.id) AS total_inscritos
         FROM equipes e
         INNER JOIN escolas esc ON esc.id = e.escola_id
         INNER JOIN competicoes c ON c.id = e.competicao_id
         INNER JOIN modalidades m ON m.id = c.modalidade_id
         INNER JOIN categorias cat ON cat.id = c.categoria_id
         LEFT JOIN grupos g ON g.id = e.grupo_id
         ${onde}
        ORDER BY m.ordem, cat.ordem, c.genero, esc.nome`,
      valores
    );

    res.status(200).json(equipes);
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao buscar as equipes.' });
  }
};

// Atletas da escola que PODEM entrar nesta equipe: mesma escola, sexo
// compatível com o gênero da competição, idade dentro da categoria e ainda não
// inscritos nela. As regras são as mesmas que a inscrição valida — repetidas
// aqui em SQL para a tela oferecer só quem passa, em vez de deixar o usuário
// escolher e levar um erro.
// O limite de 2 competições coletivas NÃO filtra a lista: o atleta vem com a
// contagem, e a tela avisa. Quem barra continua sendo a inscrição.
const listarElegiveis = async (req, res) => {
  const id = Number(req.params.id);

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ erro: 'Identificador de equipe inválido.' });
  }

  try {
    const [[equipe]] = await db.query(
      `SELECT e.id, e.escola_id, e.competicao_id,
              esc.nome AS escola_nome,
              c.genero, cat.nome AS categoria_nome, cat.idade_maxima,
              m.nome AS modalidade_nome, m.tipo AS modalidade_tipo, m.max_atletas,
              (SELECT COUNT(*) FROM inscricoes_atletas i WHERE i.equipe_id = e.id) AS total_inscritos
         FROM equipes e
         INNER JOIN escolas esc ON esc.id = e.escola_id
         INNER JOIN competicoes c ON c.id = e.competicao_id
         INNER JOIN categorias cat ON cat.id = c.categoria_id
         INNER JOIN modalidades m ON m.id = c.modalidade_id
        WHERE e.id = ?`,
      [id]
    );

    if (!equipe) {
      return res.status(404).json({ erro: 'Equipe não encontrada.' });
    }

    const condicoes = [
      'a.escola_id = ?',
      'NOT EXISTS (SELECT 1 FROM inscricoes_atletas i WHERE i.equipe_id = ? AND i.atleta_id = a.id)'
    ];
    const valores = [equipe.escola_id, id];

    // MISTO aceita os dois sexos; os demais exigem o correspondente
    if (equipe.genero !== 'MISTO') {
      condicoes.push('a.sexo = ?');
      valores.push(equipe.genero === 'MASCULINO' ? 'M' : 'F');
    }

    // Aberto tem idade_maxima nula e não limita
    if (equipe.idade_maxima !== null) {
      const [[evento]] = await db.query('SELECT ano FROM configuracao_evento WHERE id = 1');
      condicoes.push('YEAR(a.data_nascimento) >= ?');
      valores.push(anoMinimoDaCategoria(evento.ano, equipe.idade_maxima));
    }

    const [elegiveis] = await db.query(
      `SELECT a.id, a.nome, a.sexo, YEAR(a.data_nascimento) AS ano_nascimento,
              (SELECT COUNT(DISTINCT c2.id)
                 FROM inscricoes_atletas i2
                 INNER JOIN equipes e2 ON e2.id = i2.equipe_id
                 INNER JOIN competicoes c2 ON c2.id = e2.competicao_id
                 INNER JOIN modalidades m2 ON m2.id = c2.modalidade_id
                WHERE i2.atleta_id = a.id AND m2.tipo = 'COLETIVO') AS competicoes_coletivas
         FROM atletas a
        WHERE ${condicoes.join(' AND ')}
        ORDER BY a.nome`,
      valores
    );

    res.status(200).json({ equipe, elegiveis });
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao buscar os atletas elegíveis.' });
  }
};

const CAMISA_MINIMA = 1;
const CAMISA_MAXIMA = 99;

// Número da camisa da equipe, na hora da partida (a mesa e o ADMIN, pela tela de súmula).
// PUT /api/equipes/:equipeId/camisas  { jogo_id, camisas: [{ inscricaoId, numero }] }
// - grava em inscricoes_atletas.numero_camisa (vale para os próximos jogos da equipe);
// - "numero" vazio ou null = sem número; 1 a 99; único dentro da equipe (conta quem já tem número);
// - o jogo é obrigatório: é por ele que a mesa com local é travada (travarMesaPorLocal) e é dele
//   que sai a conferência "a equipe joga este jogo"; jogo encerrado (finalizado ou W.O.) não muda.
const salvarCamisas = async (req, res) => {
  const equipe_id = Number(req.params.equipeId);
  const jogo_id = Number(req.body?.jogo_id);
  const lista = req.body?.camisas;

  if (!Number.isInteger(equipe_id) || equipe_id <= 0) {
    return res.status(400).json({ erro: 'Equipe inválida.' });
  }
  // Sem o jogo a trava de mesa por local não teria o que conferir
  if (!Number.isInteger(jogo_id) || jogo_id <= 0) {
    return res.status(400).json({ erro: 'Informe o jogo (jogo_id) em que a camisa está sendo lançada.' });
  }
  if (!Array.isArray(lista) || lista.length === 0) {
    return res.status(400).json({ erro: 'Informe a lista de camisas: [{ inscricaoId, numero }].' });
  }

  const pedidos = new Map();
  for (const item of lista) {
    const inscricaoId = Number(item?.inscricaoId);
    if (!Number.isInteger(inscricaoId) || inscricaoId <= 0) {
      return res.status(400).json({ erro: 'Cada camisa precisa de uma inscrição (inscricaoId).' });
    }
    if (pedidos.has(inscricaoId)) {
      return res.status(400).json({ erro: 'A mesma inscrição aparece duas vezes na lista.' });
    }
    const vazio = item.numero === undefined || item.numero === null || String(item.numero).trim() === '';
    const numero = vazio ? null : Number(item.numero);
    if (!vazio && (!Number.isInteger(numero) || numero < CAMISA_MINIMA || numero > CAMISA_MAXIMA)) {
      return res.status(400).json({
        erro: `O número da camisa precisa ser um inteiro entre ${CAMISA_MINIMA} e ${CAMISA_MAXIMA}.`
      });
    }
    pedidos.set(inscricaoId, numero);
  }

  let conexao;
  try {
    conexao = await db.getConnection();
    await conexao.beginTransaction();

    const [[jogo]] = await conexao.query(
      'SELECT id, status, equipe_1_id, equipe_2_id FROM jogos WHERE id = ? FOR UPDATE',
      [jogo_id]
    );
    if (!jogo) {
      await conexao.rollback();
      return res.status(404).json({ erro: 'Jogo não encontrado.' });
    }
    if (jogo.equipe_1_id !== equipe_id && jogo.equipe_2_id !== equipe_id) {
      await conexao.rollback();
      return res.status(400).json({ erro: 'Esta equipe não joga este jogo.' });
    }
    if (['FINALIZADO', 'WO'].includes(jogo.status)) {
      await conexao.rollback();
      return res.status(409).json({ erro: 'Jogo encerrado: o número da camisa não muda por aqui.' });
    }

    // Todas as inscrições da equipe, travadas: a conferência de repetição vale para o conjunto
    const [inscricoes] = await conexao.query(
      `SELECT i.id, i.numero_camisa, a.nome
         FROM inscricoes_atletas i
         INNER JOIN atletas a ON a.id = i.atleta_id
        WHERE i.equipe_id = ?
        FOR UPDATE`,
      [equipe_id]
    );
    const porId = new Map(inscricoes.map((i) => [i.id, i]));

    for (const inscricaoId of pedidos.keys()) {
      if (!porId.has(inscricaoId)) {
        await conexao.rollback();
        return res.status(400).json({ erro: 'Há inscrição que não é desta equipe.' });
      }
    }

    // Como ficaria a equipe inteira: quem não veio no pedido mantém o número que tem
    const donos = new Map();
    for (const inscricao of inscricoes) {
      const numero = pedidos.has(inscricao.id) ? pedidos.get(inscricao.id) : inscricao.numero_camisa;
      if (numero === null || numero === undefined) continue;
      if (donos.has(numero)) {
        await conexao.rollback();
        return res.status(409).json({
          erro: `O número ${numero} está repetido na equipe (${donos.get(numero)} e ${inscricao.nome}).`
        });
      }
      donos.set(numero, inscricao.nome);
    }

    // Em duas fases: trocar dois números entre atletas passaria por um repetido no meio do caminho
    const mudam = [...pedidos].filter(([id, numero]) => (porId.get(id).numero_camisa ?? null) !== numero);
    for (const [id] of mudam) {
      await conexao.query('UPDATE inscricoes_atletas SET numero_camisa = NULL WHERE id = ?', [id]);
    }
    for (const [id, numero] of mudam) {
      if (numero !== null) {
        await conexao.query('UPDATE inscricoes_atletas SET numero_camisa = ? WHERE id = ?', [numero, id]);
      }
    }

    await conexao.commit();
    res.status(200).json({
      mensagem: mudam.length ? 'Camisas salvas.' : 'Nada mudou.',
      alteradas: mudam.length,
      camisas: inscricoes.map((i) => ({
        inscricao_id: i.id,
        numero_camisa: pedidos.has(i.id) ? pedidos.get(i.id) : i.numero_camisa
      }))
    });
  } catch (erro) {
    if (conexao) await conexao.rollback().catch(() => {});
    if (erro.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({ erro: 'Esse número acabou de ser usado por outro atleta da equipe. Confira a lista.' });
    }
    console.error('Erro ao salvar as camisas da equipe:', erro);
    res.status(500).json({ erro: 'Erro ao salvar as camisas.' });
  } finally {
    if (conexao) conexao.release();
  }
};

module.exports = { listarEquipes, listarElegiveis, salvarCamisas };
