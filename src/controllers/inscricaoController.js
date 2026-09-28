const db = require('../config/db');

// Inscreve o atleta numa equipe (escola dentro de uma competição).
// O escola_id vem do próprio atleta: as chaves estrangeiras compostas de
// inscricoes_atletas exigem que atleta e equipe sejam da mesma escola.
//
// ATENÇÃO: as regras de elenco (máximo de 14, idade pela categoria, sexo ×
// gênero e o limite de 2 modalidades coletivas) entram na fatia de atletas e
// inscrições. Hoje só o banco protege: duplicidade e número de camisa repetido.
const inscreverAtleta = async (req, res) => {
  const { equipe_id, atleta_id } = req.body;
  const numero_camisa = req.body.numero_camisa ?? null;

  if (!equipe_id || !atleta_id) {
    return res.status(400).json({ erro: 'Informe a equipe e o atleta.' });
  }

  try {
    const [atleta] = await db.query('SELECT escola_id FROM atletas WHERE id = ?', [atleta_id]);

    if (atleta.length === 0) {
      return res.status(404).json({ erro: 'Atleta não encontrado.' });
    }

    const [resultado] = await db.query(
      'INSERT INTO inscricoes_atletas (equipe_id, atleta_id, escola_id, numero_camisa) VALUES (?, ?, ?, ?)',
      [equipe_id, atleta_id, atleta[0].escola_id, numero_camisa]
    );

    res.status(201).json({
      mensagem: 'Inscrição realizada com sucesso!',
      id_inscricao: resultado.insertId
    });
  } catch (erro) {
    console.error(erro);

    if (erro.code === 'ER_DUP_ENTRY') {
      const conflitoDeCamisa = /camisa/i.test(erro.sqlMessage || '');
      return res.status(409).json({
        erro: conflitoDeCamisa
          ? 'Esse número de camisa já está em uso nesta equipe.'
          : 'Este atleta já está inscrito nesta equipe.'
      });
    }

    // A equipe não existe, ou é de outra escola que não a do atleta
    if (erro.code === 'ER_NO_REFERENCED_ROW_2') {
      return res.status(400).json({ erro: 'Equipe inválida para este atleta.' });
    }

    res.status(500).json({ erro: 'Erro ao processar a inscrição do atleta.' });
  }
};

module.exports = {
  inscreverAtleta
};
