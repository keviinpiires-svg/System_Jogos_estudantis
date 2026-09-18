const db = require('../config/db');

// Lista os grupos com as escolas já vinculadas, para o painel de sorteio
const listarGrupos = async (req, res) => {
  try {
    const [linhas] = await db.query(`
      SELECT g.id, g.nome, ge.escola_id, e.nome AS escola_nome
      FROM grupos g
      LEFT JOIN grupos_escolas ge ON ge.grupo_id = g.id
      LEFT JOIN escolas e ON e.id = ge.escola_id
      ORDER BY g.nome, e.nome
    `);

    const grupos = [];
    for (const linha of linhas) {
      let grupo = grupos.find((g) => g.id === linha.id);
      if (!grupo) {
        grupo = { id: linha.id, nome: linha.nome, escolas: [] };
        grupos.push(grupo);
      }
      if (linha.escola_id) {
        grupo.escolas.push({ id: linha.escola_id, nome: linha.escola_nome });
      }
    }

    res.status(200).json(grupos);
  } catch (erro) {
    console.error('Erro ao buscar os grupos:', erro);
    res.status(500).json({ erro: 'Erro ao buscar os grupos.' });
  }
};

// Substitui a distribuição atual: { "A": [1, 9], "B": [10, 11] }
const salvarDistribuicao = async (req, res) => {
  const { distribuicao } = req.body;

  if (!distribuicao || typeof distribuicao !== 'object') {
    return res.status(400).json({ erro: 'Informe a distribuição das escolas por grupo.' });
  }

  const escolhidas = Object.values(distribuicao).flat();
  if (new Set(escolhidas).size !== escolhidas.length) {
    return res.status(400).json({ erro: 'Uma escola não pode estar em dois grupos ao mesmo tempo.' });
  }

  let conexao;
  try {
    conexao = await db.getConnection();
    await conexao.beginTransaction();

    for (const [nomeGrupo, escolas] of Object.entries(distribuicao)) {
      const [[grupo]] = await conexao.query('SELECT id FROM grupos WHERE nome = ?', [nomeGrupo]);

      if (!grupo) {
        await conexao.rollback();
        return res.status(404).json({ erro: `O grupo "${nomeGrupo}" não existe.` });
      }

      await conexao.query('DELETE FROM grupos_escolas WHERE grupo_id = ?', [grupo.id]);

      for (const escolaId of escolas) {
        await conexao.query(
          'INSERT INTO grupos_escolas (grupo_id, escola_id) VALUES (?, ?)',
          [grupo.id, Number(escolaId)]
        );
      }
    }

    await conexao.commit();
    res.status(200).json({ mensagem: 'Distribuição dos grupos salva com sucesso!' });
  } catch (erro) {
    if (conexao) await conexao.rollback();
    console.error('Erro ao salvar a distribuição dos grupos:', erro);
    res.status(500).json({ erro: 'Erro ao salvar a distribuição dos grupos.' });
  } finally {
    if (conexao) conexao.release();
  }
};

module.exports = { listarGrupos, salvarDistribuicao };
