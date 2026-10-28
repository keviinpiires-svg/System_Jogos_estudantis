const db = require('../config/db');
const { veDadosPessoais } = require('../middlewares/authMiddleware');
const { normalizarRg, normalizarNome, validarAtleta } = require('../config/elegibilidade');

const lerCorpo = (corpo) => ({
  nome: normalizarNome(corpo.nome),
  rg: normalizarRg(corpo.rg),
  data_nascimento: (corpo.data_nascimento || '').trim(),
  sexo: (corpo.sexo || '').trim().toUpperCase(),
  escola_id: Number(corpo.escola_id)
});

const cadastrarAtleta = async (req, res) => {
  const atleta = lerCorpo(req.body);
  const problema = validarAtleta(atleta);

  if (problema) {
    return res.status(400).json({ erro: problema });
  }

  try {
    const [resultado] = await db.query(
      'INSERT INTO atletas (nome, rg, data_nascimento, sexo, escola_id) VALUES (?, ?, ?, ?, ?)',
      [atleta.nome, atleta.rg, atleta.data_nascimento, atleta.sexo, atleta.escola_id]
    );

    res.status(201).json({
      mensagem: 'Atleta cadastrado com sucesso!',
      id_atleta: resultado.insertId
    });
  } catch (erro) {
    if (erro.code === 'ER_DUP_ENTRY') {
      // Quem já tem esse RG entra na resposta: a tela usa isso para oferecer
      // seguir com o atleta existente, em vez de deixar o usuário travado
      // tentando cadastrar de novo o mesmo aluno.
      const [[existente]] = await db.query(
        `SELECT a.id, a.nome, a.escola_id, esc.nome AS escola_nome
           FROM atletas a
           INNER JOIN escolas esc ON esc.id = a.escola_id
          WHERE a.rg = ?`,
        [atleta.rg]
      );

      return res.status(409).json({
        erro: existente
          ? `${existente.nome} já está cadastrado com este RG (${existente.escola_nome}).`
          : 'Já existe um atleta cadastrado com este RG.',
        atleta: existente || null
      });
    }
    if (erro.code === 'ER_NO_REFERENCED_ROW_2') {
      return res.status(400).json({ erro: 'A escola informada não existe.' });
    }
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao cadastrar o atleta. Verifique os dados.' });
  }
};

// Lista pública: o RG fica de fora de propósito, é dado pessoal e não faz falta
// em tela de consulta. Quem edita busca o atleta por id, numa rota de ADMIN.
const listarAtletasPorEscola = async (req, res) => {
  const escola_id = Number(req.params.escola_id);

  if (!Number.isInteger(escola_id) || escola_id <= 0) {
    return res.status(400).json({ erro: 'Identificador de escola inválido.' });
  }

  try {
    const [atletas] = await db.query(
      `SELECT id, nome, data_nascimento, sexo, escola_id
       FROM atletas WHERE escola_id = ? ORDER BY nome ASC`,
      [escola_id]
    );

    // Sexo e nascimento só para o ADMIN; o público vê id, nome e escola
    res.status(200).json(veDadosPessoais(req)
      ? atletas
      : atletas.map(({ id, nome, escola_id }) => ({ id, nome, escola_id })));
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao buscar os atletas da escola.' });
  }
};

// Só ADMIN: devolve o RG, para preencher a tela de edição.
const buscarAtletaPorId = async (req, res) => {
  const id = Number(req.params.id);

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ erro: 'Identificador de atleta inválido.' });
  }

  try {
    const [[atleta]] = await db.query(
      'SELECT id, nome, rg, data_nascimento, sexo, escola_id FROM atletas WHERE id = ?',
      [id]
    );

    if (!atleta) {
      return res.status(404).json({ erro: 'Atleta não encontrado.' });
    }

    res.status(200).json(atleta);
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao buscar o atleta.' });
  }
};

const excluirAtleta = async (req, res) => {
  const id = Number(req.params.id);

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ erro: 'Identificador de atleta inválido.' });
  }

  try {
    const [resultado] = await db.query('DELETE FROM atletas WHERE id = ?', [id]);

    if (resultado.affectedRows === 0) {
      return res.status(404).json({ erro: 'Atleta não encontrado.' });
    }

    res.status(200).json({ mensagem: 'Atleta excluído com sucesso!' });
  } catch (erro) {
    // inscricoes_atletas e resultados_atletismo apontam para cá com RESTRICT:
    // apagar um atleta inscrito levaria o elenco junto.
    if (erro.code === 'ER_ROW_IS_REFERENCED_2') {
      return res.status(409).json({
        erro: 'Este atleta está inscrito em alguma equipe. Remova as inscrições antes de excluí-lo.'
      });
    }
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao excluir o atleta.' });
  }
};

// Trocar a escola de um atleta já inscrito quebraria a regra de que atleta e
// equipe são da mesma escola, e o banco recusaria pela chave composta. Por isso
// a troca só passa enquanto ele não tiver inscrição.
const atualizarAtleta = async (req, res) => {
  const id = Number(req.params.id);
  const atleta = lerCorpo(req.body);
  const problema = validarAtleta(atleta);

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ erro: 'Identificador de atleta inválido.' });
  }

  if (problema) {
    return res.status(400).json({ erro: problema });
  }

  try {
    const [[atual]] = await db.query('SELECT escola_id FROM atletas WHERE id = ?', [id]);

    if (!atual) {
      return res.status(404).json({ erro: 'Atleta não encontrado.' });
    }

    if (atual.escola_id !== atleta.escola_id) {
      const [[{ inscricoes }]] = await db.query(
        'SELECT COUNT(*) AS inscricoes FROM inscricoes_atletas WHERE atleta_id = ?',
        [id]
      );

      if (inscricoes > 0) {
        return res.status(409).json({
          erro: 'Não dá para mudar a escola de um atleta já inscrito. Remova as inscrições primeiro.'
        });
      }
    }

    await db.query(
      'UPDATE atletas SET nome = ?, rg = ?, data_nascimento = ?, sexo = ?, escola_id = ? WHERE id = ?',
      [atleta.nome, atleta.rg, atleta.data_nascimento, atleta.sexo, atleta.escola_id, id]
    );

    res.status(200).json({ mensagem: 'Atleta atualizado com sucesso!', id_atleta: id });
  } catch (erro) {
    if (erro.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({ erro: 'Já existe um atleta cadastrado com este RG.' });
    }
    if (erro.code === 'ER_NO_REFERENCED_ROW_2') {
      return res.status(400).json({ erro: 'A escola informada não existe.' });
    }
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao atualizar o atleta.' });
  }
};

module.exports = {
  cadastrarAtleta,
  listarAtletasPorEscola,
  buscarAtletaPorId,
  excluirAtleta,
  atualizarAtleta
};
