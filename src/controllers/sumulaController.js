const db = require('../config/db');

// ============================================================================
// SÚMULA: única fonte de verdade da partida.
// Os gols individuais dos atletas definem o placar do jogo, que por sua vez
// alimenta a classificação. Artilharia e classificação nunca divergem.
// ============================================================================

const registrarSumula = async (req, res) => {
  const jogo_id = Number(req.body.jogo_id);
  const eventos = Array.isArray(req.body.eventos) ? req.body.eventos : [];

  if (!jogo_id) {
    return res.status(400).json({ erro: 'Informe o jogo da súmula.' });
  }

  for (const evento of eventos) {
    const numeros = [evento.gols, evento.cartoes_amarelos, evento.cartao_vermelho].map(Number);
    if (!Number(evento.atleta_id) || numeros.some((n) => !Number.isInteger(n) || n < 0)) {
      return res.status(400).json({ erro: 'Cada evento precisa de um atleta e de números inteiros não negativos.' });
    }
  }

  let conexao;
  try {
    conexao = await db.getConnection();
    await conexao.beginTransaction();

    const [[jogo]] = await conexao.query(
      'SELECT id, escola_1_id, escola_2_id FROM jogos WHERE id = ?',
      [jogo_id]
    );

    if (!jogo) {
      await conexao.rollback();
      return res.status(404).json({ erro: 'Jogo não encontrado.' });
    }

    // Todo atleta lançado precisa pertencer a uma das duas escolas da partida
    const escolaPorAtleta = new Map();
    if (eventos.length > 0) {
      const ids = eventos.map((evento) => Number(evento.atleta_id));
      const [atletas] = await conexao.query('SELECT id, escola_id FROM atletas WHERE id IN (?)', [ids]);

      for (const atleta of atletas) {
        escolaPorAtleta.set(atleta.id, atleta.escola_id);
      }

      const intruso = ids.find((id) => {
        const escola = escolaPorAtleta.get(id);
        return escola !== jogo.escola_1_id && escola !== jogo.escola_2_id;
      });

      if (intruso) {
        await conexao.rollback();
        return res.status(400).json({ erro: 'Há atletas que não pertencem a nenhuma das duas escolas da partida.' });
      }
    }

    // Regrava a súmula inteira: permite corrigir um lançamento errado
    await conexao.query('DELETE FROM sumulas WHERE jogo_id = ?', [jogo_id]);

    let placar1 = 0;
    let placar2 = 0;

    for (const evento of eventos) {
      const atletaId = Number(evento.atleta_id);
      const gols = Number(evento.gols);

      await conexao.query(
        `INSERT INTO sumulas (jogo_id, atleta_id, gols, cartoes_amarelos, cartao_vermelho)
         VALUES (?, ?, ?, ?, ?)`,
        [jogo_id, atletaId, gols, Number(evento.cartoes_amarelos), Number(evento.cartao_vermelho)]
      );

      if (escolaPorAtleta.get(atletaId) === jogo.escola_1_id) {
        placar1 += gols;
      } else {
        placar2 += gols;
      }
    }

    await conexao.query(
      `UPDATE jogos SET placar_escola_1 = ?, placar_escola_2 = ?, status = 'FINALIZADO' WHERE id = ?`,
      [placar1, placar2, jogo_id]
    );

    await conexao.commit();
    res.status(201).json({
      mensagem: 'Súmula salva! O placar e a classificação foram atualizados.',
      placar_escola_1: placar1,
      placar_escola_2: placar2
    });
  } catch (erro) {
    if (conexao) await conexao.rollback();
    console.error('Erro ao registrar a súmula:', erro);
    res.status(500).json({ erro: 'Erro ao registrar a súmula.' });
  } finally {
    if (conexao) conexao.release();
  }
};

// Relatório completo da partida: dados do jogo (com nomes e placar) + eventos
// dos atletas. A tela de detalhes monta o documento oficial só com isso.
const buscarSumulaPorJogo = async (req, res) => {
  const { jogo_id } = req.params;
  try {
    const [[jogo]] = await db.query(`
      SELECT j.id, j.numero_jogo, j.fase, j.data_hora, j.status,
             j.escola_1_id, e1.nome AS escola_1_nome, j.placar_escola_1,
             j.escola_2_id, e2.nome AS escola_2_nome, j.placar_escola_2,
             l.nome AS local_nome
      FROM jogos j
      INNER JOIN escolas e1 ON j.escola_1_id = e1.id
      INNER JOIN escolas e2 ON j.escola_2_id = e2.id
      LEFT JOIN locais_disputa l ON j.local_id = l.id
      WHERE j.id = ?
    `, [jogo_id]);

    if (!jogo) {
      return res.status(404).json({ erro: 'Jogo não encontrado.' });
    }

    const [eventos] = await db.query(`
      SELECT s.atleta_id, a.nome AS atleta_nome, a.escola_id, e.nome AS escola_nome,
             s.gols, s.cartoes_amarelos, s.cartao_vermelho
      FROM sumulas s
      INNER JOIN atletas a ON s.atleta_id = a.id
      INNER JOIN escolas e ON a.escola_id = e.id
      WHERE s.jogo_id = ?
      ORDER BY e.nome, a.nome
    `, [jogo_id]);

    res.status(200).json({ jogo, eventos });
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

// Exportando todas as funções
module.exports = {
  registrarSumula,
  buscarSumulaPorJogo,
  verificarSuspensao
};