const db = require('../config/db');
const { veDadosPessoais } = require('../middlewares/authMiddleware');
const { plural } = require('../config/elegibilidade');
const {
  lerEquipeTravada, lerCompeticao, lerAtleta, avaliarEntrada, gravarInscricao, avisoDeMinimo
} = require('../services/inscricaoService');

const CAMISA_MINIMA = 1;
const CAMISA_MAXIMA = 99;

// Inscreve o atleta numa equipe (escola dentro de uma competição).
// O escola_id vem do próprio atleta: as chaves estrangeiras compostas de
// inscricoes_atletas exigem que atleta e equipe sejam da mesma escola.
const inscreverAtleta = async (req, res) => {
  const equipe_id = Number(req.body.equipe_id);
  const atleta_id = Number(req.body.atleta_id);
  const camisaInformada = req.body.numero_camisa !== undefined
    && req.body.numero_camisa !== null
    && req.body.numero_camisa !== '';
  const numero_camisa = camisaInformada ? Number(req.body.numero_camisa) : null;

  if (!Number.isInteger(equipe_id) || equipe_id <= 0 || !Number.isInteger(atleta_id) || atleta_id <= 0) {
    return res.status(400).json({ erro: 'Informe a equipe e o atleta.' });
  }

  if (camisaInformada
    && (!Number.isInteger(numero_camisa) || numero_camisa < CAMISA_MINIMA || numero_camisa > CAMISA_MAXIMA)) {
    return res.status(400).json({
      erro: `O número da camisa precisa ser um inteiro entre ${CAMISA_MINIMA} e ${CAMISA_MAXIMA}.`
    });
  }

  let conexao;
  try {
    conexao = await db.getConnection();
    await conexao.beginTransaction();

    // A equipe travada, a competição, o atleta e as regras (sexo x gênero, idade,
    // 2 coletivas, teto do elenco) vivem em src/services/inscricaoService.js, que a
    // mesa também usa. Aqui é o ADMIN: criado_por fica NULL, como sempre.
    const equipe = await lerEquipeTravada(conexao, equipe_id);

    if (!equipe) {
      await conexao.rollback();
      return res.status(404).json({ erro: 'Equipe não encontrada.' });
    }

    const competicao = await lerCompeticao(conexao, equipe.competicao_id);
    const atleta = await lerAtleta(conexao, atleta_id);

    if (!atleta) {
      await conexao.rollback();
      return res.status(404).json({ erro: 'Atleta não encontrado.' });
    }

    const { recusa, inscritos } = await avaliarEntrada(conexao, { equipe, competicao, atleta });
    if (recusa) {
      await conexao.rollback();
      return res.status(recusa.status).json({ erro: recusa.erro });
    }

    const id_inscricao = await gravarInscricao(conexao, {
      equipe_id, atleta_id, escola_id: atleta.escola_id, numero_camisa
    });

    await conexao.commit();

    const total = inscritos + 1;

    // O mínimo do regulamento é aviso, nunca bloqueio (decisão do usuário)
    const aviso = avisoDeMinimo(competicao, total);

    res.status(201).json({
      mensagem: 'Inscrição realizada com sucesso!',
      id_inscricao,
      total_inscritos: total,
      max_atletas: competicao.max_atletas,
      min_atletas: competicao.min_atletas,
      aviso
    });
  } catch (erro) {
    if (conexao) await conexao.rollback();

    if (erro.code === 'ER_DUP_ENTRY') {
      const conflitoDeCamisa = /camisa/i.test(erro.sqlMessage || '');
      return res.status(409).json({
        erro: conflitoDeCamisa
          ? 'Esse número de camisa já está em uso nesta equipe.'
          : 'Este atleta já está inscrito nesta equipe.'
      });
    }

    console.error(erro);
    res.status(500).json({ erro: 'Erro ao processar a inscrição do atleta.' });
  } finally {
    if (conexao) conexao.release();
  }
};

// Elenco da equipe, com o estado do limite e o aviso de mínimo.
const listarInscritos = async (req, res) => {
  const equipe_id = Number(req.params.equipe_id);

  if (!Number.isInteger(equipe_id) || equipe_id <= 0) {
    return res.status(400).json({ erro: 'Identificador de equipe inválido.' });
  }

  try {
    const [[equipe]] = await db.query(
      `SELECT e.id, esc.nome AS escola_nome,
              m.nome AS modalidade_nome, m.min_atletas, m.max_atletas,
              cat.nome AS categoria_nome, c.genero
       FROM equipes e
       INNER JOIN escolas esc ON esc.id = e.escola_id
       INNER JOIN competicoes c ON c.id = e.competicao_id
       INNER JOIN categorias cat ON cat.id = c.categoria_id
       INNER JOIN modalidades m ON m.id = c.modalidade_id
       WHERE e.id = ?`,
      [equipe_id]
    );

    if (!equipe) {
      return res.status(404).json({ erro: 'Equipe não encontrada.' });
    }

    const [atletas] = await db.query(
      `SELECT i.id AS inscricao_id, i.numero_camisa,
              a.id AS atleta_id, a.nome, a.sexo, YEAR(a.data_nascimento) AS ano_nascimento
       FROM inscricoes_atletas i
       INNER JOIN atletas a ON a.id = i.atleta_id
       WHERE i.equipe_id = ?
       ORDER BY i.numero_camisa IS NULL, i.numero_camisa, a.nome`,
      [equipe_id]
    );

    const aviso = equipe.min_atletas !== null && atletas.length < equipe.min_atletas
      ? `A equipe tem ${plural(atletas.length, 'atleta', 'atletas')} e ${equipe.modalidade_nome} pede pelo menos ${equipe.min_atletas}.`
      : null;

    // Sexo e ano de nascimento só para o ADMIN; o público vê camisa e nome
    const elenco = veDadosPessoais(req)
      ? atletas
      : atletas.map(({ inscricao_id, numero_camisa, atleta_id, nome }) => ({ inscricao_id, numero_camisa, atleta_id, nome }));

    res.status(200).json({ equipe, atletas: elenco, total_inscritos: atletas.length, aviso });
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao buscar o elenco da equipe.' });
  }
};

const removerInscricao = async (req, res) => {
  const id = Number(req.params.id);

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ erro: 'Identificador de inscrição inválido.' });
  }

  try {
    const [resultado] = await db.query('DELETE FROM inscricoes_atletas WHERE id = ?', [id]);

    if (resultado.affectedRows === 0) {
      return res.status(404).json({ erro: 'Inscrição não encontrada.' });
    }

    res.status(200).json({ mensagem: 'Inscrição removida com sucesso!' });
  } catch (erro) {
    // sumula_atletas aponta para a inscrição com RESTRICT: quem já entrou em
    // súmula não sai do elenco sem apagar a súmula antes.
    if (erro.code === 'ER_ROW_IS_REFERENCED_2') {
      return res.status(409).json({
        erro: 'Este atleta já aparece na súmula de um jogo e não pode ser retirado do elenco.'
      });
    }
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao remover a inscrição.' });
  }
};

module.exports = {
  inscreverAtleta,
  listarInscritos,
  removerInscricao
};
