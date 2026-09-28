const db = require('../config/db');

const SEXOS = ['M', 'F'];

// O RG é o que impede o mesmo aluno de entrar duas vezes, e o índice UNIQUE
// compara texto literal: "12.345.678-9" e "123456789" seriam dois atletas
// diferentes. Guardar só letras e números, em maiúsculas, faz as duas grafias
// colidirem como deveriam.
const normalizarRg = (s) => (s || '').replace(/[^0-9A-Za-z]/g, '').toUpperCase();

const normalizarNome = (s) => (s || '').trim().replace(/\s+/g, ' ');

// Só AAAA-MM-DD, e a data precisa existir: o construtor Date transforma
// 2011-02-30 em 2011-03-02 sem reclamar, e o erro passaria despercebido.
const dataValida = (s) => {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s || '')) return false;
  const data = new Date(`${s}T00:00:00Z`);
  return !Number.isNaN(data.getTime()) && data.toISOString().slice(0, 10) === s;
};

// A idade em si não é conferida aqui: ela só faz sentido contra a categoria da
// competição, e isso acontece na inscrição.
const validarAtleta = ({ nome, rg, data_nascimento, sexo, escola_id }) => {
  if (!nome) return 'Informe o nome do atleta.';
  if (!rg) return 'O RG é obrigatório para inscrever o atleta.';
  if (!dataValida(data_nascimento)) return 'Informe a data de nascimento no formato AAAA-MM-DD.';
  if (data_nascimento > new Date().toISOString().slice(0, 10)) {
    return 'A data de nascimento não pode estar no futuro.';
  }
  if (!SEXOS.includes(sexo)) return 'Informe o sexo do atleta (M ou F).';
  if (!Number.isInteger(escola_id) || escola_id <= 0) return 'Informe a escola do atleta.';
  return null;
};

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
      return res.status(409).json({ erro: 'Já existe um atleta cadastrado com este RG.' });
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

    res.status(200).json(atletas);
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
