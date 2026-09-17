const db = require('../config/db');

// ============================================================================
// 1. GESTÃO INDIVIDUAL DOS ATLETAS (O código que você já tinha)
// ============================================================================

const registrarSumula = async (req, res) => {
  console.log('BODY RECEBIDO:', req.body);

  // Transforma em array mesmo se vier apenas um objeto
  const eventos = Array.isArray(req.body) ? req.body : [req.body];

  try {
    for (const evento of eventos) {
      // Tenta pegar o jogo_id (ou id_jogo) e o aluno_id (ou atleta_id)
      const idDoJogo = evento.jogo_id || evento.id_jogo;
      const idDoAluno = evento.aluno_id || evento.atleta_id;

      if (!idDoJogo) {
        return res.status(400).json({ erro: 'Campo jogo_id (ou id_jogo) ausente em um dos registros.' });
      }
      if (!idDoAluno) {
        return res.status(400).json({ erro: 'Campo aluno_id (ou atleta_id) ausente em um dos registros.' });
      }

      // Se os valores numéricos não vierem, assume 0
      const gols = evento.gols || 0;
      const cartoes_amarelos = evento.cartoes_amarelos || 0;
      const cartao_vermelho = evento.cartao_vermelho || 0;

      const query = `
        INSERT INTO sumulas (jogo_id, atleta_id, gols, cartoes_amarelos, cartao_vermelho)
        VALUES (?, ?, ?, ?, ?)
      `;
      await db.query(query, [idDoJogo, idDoAluno, gols, cartoes_amarelos, cartao_vermelho]);
    }

    res.status(201).json({ mensagem: 'Súmula(s) registrada(s) com sucesso!' });
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao registrar a súmula.' });
  }
};

const buscarSumulaPorJogo = async (req, res) => {
  const { jogo_id } = req.params;
  try {
    const [resultado] = await db.query(`
      SELECT s.*, a.nome AS atleta_nome, a.escola_id
      FROM sumulas s
      INNER JOIN atletas a ON s.atleta_id = a.id
      WHERE s.jogo_id = ?
      ORDER BY a.escola_id, a.nome
    `, [jogo_id]);
    res.status(200).json(resultado);
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao buscar a súmula do jogo.' });
  }
};

const verificarSuspensao = async (req, res) => {
  const { atleta_id } = req.params;
  try {
    const [resultado] = await db.query(`
      SELECT cartao_vermelho FROM sumulas
      WHERE atleta_id = ? ORDER BY jogo_id DESC LIMIT 1
    `, [atleta_id]);

    if (resultado.length > 0 && resultado[0].cartao_vermelho === 1) {
      return res.status(200).json({ status: 'SUSPENSO', mensagem: 'Atleta suspenso. Recebeu cartão vermelho.' });
    }
    res.status(200).json({ status: 'LIBERADO', mensagem: 'Atleta apto para jogar.' });
  } catch (erro) {
    res.status(500).json({ erro: 'Erro ao verificar suspensão.' });
  }
};

// ============================================================================
// 2. GESTÃO GLOBAL DA PARTIDA (O código novo para a classificação)
// ============================================================================

const registrarPartida = async (req, res) => {
    console.log('DADOS RECEBIDOS:', req.body); // Log para depuração 
  const { grupo, timeA_id, timeB_id } = req.body;
  const golsA = Number(req.body.golsA) || 0;
  const golsB = Number(req.body.golsB) || 0;
  const conexao = await db.getConnection();
  
  try {
    await conexao.beginTransaction();

    let pontosA = 0, vitoriasA = 0, empatesA = 0, derrotasA = 0;
    let pontosB = 0, vitoriasB = 0, empatesB = 0, derrotasB = 0;

    if (golsA > golsB) {
      pontosA = 3; vitoriasA = 1; derrotasB = 1;
    } else if (golsA < golsB) {
      pontosB = 3; vitoriasB = 1; derrotasA = 1;
    } else {
      pontosA = 1; empatesA = 1; pontosB = 1; empatesB = 1;
    }


const queryUpdate = `
  UPDATE classificacao SET pontos = pontos + ?, jogos = jogos + 1,
  vitorias = vitorias + ?, empates = empates + ?, derrotas = derrotas + ?,
  gols_pro = gols_pro + ?, gols_contra = gols_contra + ?, saldo_gols = saldo_gols + ?
  WHERE escola_id = ?
`;


await conexao.query(queryUpdate, [pontosA, vitoriasA, empatesA, derrotasA, golsA, golsB, golsA - golsB, timeA_id]);
await conexao.query(queryUpdate, [pontosB, vitoriasB, empatesB, derrotasB, golsB, golsA, golsB - golsA, timeB_id]);

    await conexao.commit();
    conexao.release();
    res.status(200).json({ mensagem: 'Placar processado e classificação atualizada!' });
  } catch (erro) {
    await conexao.rollback();
    conexao.release();
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao processar o placar.' });
  }
};

// Exportando todas as funções
module.exports = {
  registrarSumula,
  buscarSumulaPorJogo,
  verificarSuspensao,
  registrarPartida
};