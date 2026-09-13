const db = require('../config/db');

// ============================================================================
// 1. GESTÃO INDIVIDUAL DOS ATLETAS (O código que você já tinha)
// ============================================================================

const registrarSumula = async (req, res) => {
  const { jogo_id, aluno_id, gols, cartoes_amarelos, cartao_vermelho } = req.body;
  try {
    const query = `
      INSERT INTO sumulas (jogo_id, aluno_id, gols, cartoes_amarelos, cartao_vermelho)
      VALUES (?, ?, ?, ?, ?)
    `;
    await db.query(query, [jogo_id, aluno_id, gols, cartoes_amarelos, cartao_vermelho]);
    res.status(201).json({ mensagem: 'Súmula do atleta registrada com sucesso!' });
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao registrar a súmula.' });
  }
};

const verificarSuspensao = async (req, res) => {
  const { aluno_id } = req.params;
  try {
    const [resultado] = await db.query(`
      SELECT cartao_vermelho FROM sumulas 
      WHERE aluno_id = ? ORDER BY jogo_id DESC LIMIT 1
    `, [aluno_id]);

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
  const { grupo, timeA_id, golsA, timeB_id, golsB } = req.body;
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
  vitorias = vitorias + ?, empates = empates + ?, derrotas = derrotas + ? 
  WHERE escola_id = ?
`;


await conexao.query(queryUpdate, [pontosA, vitoriasA, empatesA, derrotasA, timeA_id]);
await conexao.query(queryUpdate, [pontosB, vitoriasB, empatesB, derrotasB, timeB_id]);

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
  verificarSuspensao,
  registrarPartida
};