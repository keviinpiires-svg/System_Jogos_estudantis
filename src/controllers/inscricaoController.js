const db = require('../config/db');

// Decisão do usuário (28/09/2026): o limite conta COMPETIÇÕES coletivas, não
// modalidades. Futsal Sub 13 + Futsal Sub 15 são duas, mesmo sendo a mesma
// modalidade. Atletismo é INDIVIDUAL e não entra na conta.
const LIMITE_COMPETICOES_COLETIVAS = 2;

const CAMISA_MINIMA = 1;
const CAMISA_MAXIMA = 99;

const sexoCombina = (genero, sexo) => {
  if (genero === 'MISTO') return true;
  return genero === 'MASCULINO' ? sexo === 'M' : sexo === 'F';
};

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

    // FOR UPDATE trava a equipe: sem isso, duas inscrições simultâneas leriam
    // o mesmo total de inscritos e o elenco poderia terminar com 15.
    const [[equipe]] = await conexao.query(
      'SELECT id, escola_id, competicao_id FROM equipes WHERE id = ? FOR UPDATE',
      [equipe_id]
    );

    if (!equipe) {
      await conexao.rollback();
      return res.status(404).json({ erro: 'Equipe não encontrada.' });
    }

    const [[competicao]] = await conexao.query(
      `SELECT c.id, c.genero,
              cat.nome AS categoria_nome, cat.idade_maxima,
              m.nome AS modalidade_nome, m.tipo AS modalidade_tipo,
              m.min_atletas, m.max_atletas
       FROM competicoes c
       INNER JOIN categorias cat ON cat.id = c.categoria_id
       INNER JOIN modalidades m ON m.id = c.modalidade_id
       WHERE c.id = ?`,
      [equipe.competicao_id]
    );

    // YEAR() vem do banco de propósito: uma coluna DATE chega ao Node como
    // Date na hora local, e converter aqui erraria o ano por um dia.
    const [[atleta]] = await conexao.query(
      'SELECT id, nome, escola_id, sexo, YEAR(data_nascimento) AS ano_nascimento FROM atletas WHERE id = ?',
      [atleta_id]
    );

    if (!atleta) {
      await conexao.rollback();
      return res.status(404).json({ erro: 'Atleta não encontrado.' });
    }

    // 1. Atleta e equipe precisam ser da mesma escola. O banco também barra
    // pela chave composta, mas com uma mensagem que não ajuda o usuário.
    if (atleta.escola_id !== equipe.escola_id) {
      await conexao.rollback();
      return res.status(400).json({ erro: 'Este atleta é de outra escola e não pode entrar nesta equipe.' });
    }

    // 2. Sexo do atleta x gênero da competição (MISTO aceita os dois)
    if (!sexoCombina(competicao.genero, atleta.sexo)) {
      await conexao.rollback();
      return res.status(400).json({
        erro: `${competicao.modalidade_nome} ${competicao.categoria_nome} é uma competição ${competicao.genero.toLowerCase()}.`
      });
    }

    // 3. Idade pela categoria: Sub N aceita quem nasceu em (ano do evento - N)
    // ou depois. Aberto tem idade_maxima nula e não limita.
    if (competicao.idade_maxima !== null) {
      const [[evento]] = await conexao.query('SELECT ano FROM configuracao_evento WHERE id = 1');
      const anoMinimo = evento.ano - competicao.idade_maxima;

      if (atleta.ano_nascimento < anoMinimo) {
        await conexao.rollback();
        return res.status(400).json({
          erro: `${competicao.categoria_nome} aceita nascidos em ${anoMinimo} ou depois. ${atleta.nome} nasceu em ${atleta.ano_nascimento}.`
        });
      }
    }

    // 4. No máximo 2 competições de modalidade COLETIVA por atleta.
    // A competição de destino sai da conta: se ele já estiver inscrito nela,
    // quem barra é o índice UNIQUE, com mensagem própria.
    if (competicao.modalidade_tipo === 'COLETIVO') {
      const [[{ coletivas }]] = await conexao.query(
        `SELECT COUNT(DISTINCT c.id) AS coletivas
         FROM inscricoes_atletas i
         INNER JOIN equipes e ON e.id = i.equipe_id
         INNER JOIN competicoes c ON c.id = e.competicao_id
         INNER JOIN modalidades m ON m.id = c.modalidade_id
         WHERE i.atleta_id = ? AND m.tipo = 'COLETIVO' AND c.id <> ?`,
        [atleta_id, competicao.id]
      );

      if (coletivas >= LIMITE_COMPETICOES_COLETIVAS) {
        await conexao.rollback();
        return res.status(409).json({
          erro: `${atleta.nome} já está em ${coletivas} competições coletivas, o máximo permitido pelo regulamento.`
        });
      }
    }

    // 5. Teto de atletas da modalidade (14). Nulo = sem limite (atletismo).
    const [[{ inscritos }]] = await conexao.query(
      'SELECT COUNT(*) AS inscritos FROM inscricoes_atletas WHERE equipe_id = ?',
      [equipe_id]
    );

    if (competicao.max_atletas !== null && inscritos >= competicao.max_atletas) {
      await conexao.rollback();
      return res.status(409).json({
        erro: `Esta equipe já tem ${inscritos} atletas, o máximo permitido em ${competicao.modalidade_nome}.`
      });
    }

    const [resultado] = await conexao.query(
      'INSERT INTO inscricoes_atletas (equipe_id, atleta_id, escola_id, numero_camisa) VALUES (?, ?, ?, ?)',
      [equipe_id, atleta_id, atleta.escola_id, numero_camisa]
    );

    await conexao.commit();

    const total = inscritos + 1;

    // O mínimo do regulamento é aviso, nunca bloqueio (decisão do usuário)
    const aviso = competicao.min_atletas !== null && total < competicao.min_atletas
      ? `A equipe tem ${total} atletas e ${competicao.modalidade_nome} pede pelo menos ${competicao.min_atletas}.`
      : null;

    res.status(201).json({
      mensagem: 'Inscrição realizada com sucesso!',
      id_inscricao: resultado.insertId,
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
      ? `A equipe tem ${atletas.length} atletas e ${equipe.modalidade_nome} pede pelo menos ${equipe.min_atletas}.`
      : null;

    res.status(200).json({ equipe, atletas, total_inscritos: atletas.length, aviso });
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
