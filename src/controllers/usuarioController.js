const bcrypt = require('bcryptjs');
const db = require('../config/db');

const PERFIS = ['ADMIN', 'PLACAR'];
const MINIMO_SENHA = 8;
const CUSTO_HASH = 10;

// O e-mail é a chave de login: guardar sempre em minúsculas evita que
// "Kevin@x.com" e "kevin@x.com" virem duas contas.
const normalizarEmail = (s) => (s || '').trim().toLowerCase();

// Local da mesa (db/18): undefined = não mexer; vazio ou null = sem local;
// número = precisa existir em locais_disputa. Devolve { local_id } ou { erro }.
const lerLocal = async (valor) => {
  if (valor === undefined) return {};
  if (valor === null || valor === '') return { local_id: null };
  const local_id = Number(valor);
  if (!Number.isInteger(local_id) || local_id <= 0) return { erro: 'Local inválido.' };
  const [[local]] = await db.query('SELECT id FROM locais_disputa WHERE id = ?', [local_id]);
  return local ? { local_id } : { erro: 'O local informado não existe.' };
};

// A senha (hash) nunca sai destas consultas.
const listarUsuarios = async (req, res) => {
  try {
    const [usuarios] = await db.query(
      `SELECT u.id, u.nome, u.email, u.perfil, u.ativo, u.criado_em, u.local_id, l.nome AS local_nome
         FROM usuarios u
         LEFT JOIN locais_disputa l ON l.id = u.local_id
        ORDER BY u.nome`
    );
    res.status(200).json(usuarios);
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao buscar os usuários.' });
  }
};

const criarUsuario = async (req, res) => {
  const nome = (req.body.nome || '').trim();
  const email = normalizarEmail(req.body.email);
  const senha = req.body.senha || '';
  const perfil = (req.body.perfil || '').trim().toUpperCase();

  if (!nome || !email) {
    return res.status(400).json({ erro: 'Informe o nome e o e-mail.' });
  }

  if (senha.length < MINIMO_SENHA) {
    return res.status(400).json({ erro: `A senha precisa ter pelo menos ${MINIMO_SENHA} caracteres.` });
  }

  if (!PERFIS.includes(perfil)) {
    return res.status(400).json({ erro: 'O perfil precisa ser ADMIN ou PLACAR.' });
  }

  try {
    const local = await lerLocal(req.body.local_id);
    if (local.erro) return res.status(400).json({ erro: local.erro });

    const hash = await bcrypt.hash(senha, CUSTO_HASH);

    // Só a mesa tem local; o ADMIN nunca é travado
    const [resultado] = await db.query(
      'INSERT INTO usuarios (nome, email, senha, perfil, local_id) VALUES (?, ?, ?, ?, ?)',
      [nome, email, hash, perfil, perfil === 'PLACAR' ? local.local_id ?? null : null]
    );

    res.status(201).json({ mensagem: 'Usuário criado com sucesso!', id_usuario: resultado.insertId });
  } catch (erro) {
    if (erro.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({ erro: 'Já existe um usuário com esse e-mail.' });
    }
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao criar o usuário.' });
  }
};

// Não existe exclusão: usuarios é referenciada por suspensoes e
// ajustes_pontos_geral (ON DELETE RESTRICT), e apagar quem aplicou uma punição
// apagaria a autoria dela. Desativar em ativo = false tira o acesso e preserva
// o histórico.
const atualizarUsuario = async (req, res) => {
  const id = Number(req.params.id);

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ erro: 'Identificador de usuário inválido.' });
  }

  const alterarPerfil = req.body.perfil !== undefined;
  const alterarAtivo = req.body.ativo !== undefined;

  // Trava contra auto-bloqueio: um administrador que se rebaixa ou se desativa
  // pode deixar o sistema sem ninguém capaz de desfazer isso.
  if (id === req.usuario.id && (alterarPerfil || alterarAtivo)) {
    return res.status(400).json({
      erro: 'Você não pode alterar o próprio perfil nem desativar a própria conta.'
    });
  }

  const campos = [];
  const valores = [];

  if (req.body.nome !== undefined) {
    const nome = (req.body.nome || '').trim();
    if (!nome) {
      return res.status(400).json({ erro: 'Informe o nome.' });
    }
    campos.push('nome = ?');
    valores.push(nome);
  }

  if (req.body.email !== undefined) {
    const email = normalizarEmail(req.body.email);
    if (!email) {
      return res.status(400).json({ erro: 'Informe o e-mail.' });
    }
    campos.push('email = ?');
    valores.push(email);
  }

  if (alterarPerfil) {
    const perfil = (req.body.perfil || '').trim().toUpperCase();
    if (!PERFIS.includes(perfil)) {
      return res.status(400).json({ erro: 'O perfil precisa ser ADMIN ou PLACAR.' });
    }
    campos.push('perfil = ?');
    valores.push(perfil);
  }

  if (alterarAtivo) {
    campos.push('ativo = ?');
    valores.push(req.body.ativo ? 1 : 0);
  }

  try {
    // Local da mesa (db/18). Quem vira ou já é ADMIN fica sem local.
    const local = await lerLocal(req.body.local_id);
    if (local.erro) return res.status(400).json({ erro: local.erro });

    const perfilNovo = alterarPerfil ? (req.body.perfil || '').trim().toUpperCase() : null;
    if (perfilNovo === 'ADMIN') {
      campos.push('local_id = NULL');
    } else if (local.local_id !== undefined) {
      const [[atual]] = await db.query('SELECT perfil FROM usuarios WHERE id = ?', [id]);
      if ((perfilNovo || atual?.perfil) === 'PLACAR') {
        campos.push('local_id = ?');
        valores.push(local.local_id);
      }
    }

    if (campos.length === 0) {
      return res.status(400).json({ erro: 'Informe ao menos um campo para alterar.' });
    }

    valores.push(id);

    const [resultado] = await db.query(
      `UPDATE usuarios SET ${campos.join(', ')} WHERE id = ?`,
      valores
    );

    if (resultado.affectedRows === 0) {
      return res.status(404).json({ erro: 'Usuário não encontrado.' });
    }

    res.status(200).json({ mensagem: 'Usuário atualizado com sucesso!', id_usuario: id });
  } catch (erro) {
    if (erro.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({ erro: 'Já existe um usuário com esse e-mail.' });
    }
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao atualizar o usuário.' });
  }
};

// Redefinição feita por um administrador. Não pede a senha atual de propósito:
// serve justamente para quem esqueceu a própria.
const trocarSenha = async (req, res) => {
  const id = Number(req.params.id);
  const senha = req.body.senha || '';

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ erro: 'Identificador de usuário inválido.' });
  }

  if (senha.length < MINIMO_SENHA) {
    return res.status(400).json({ erro: `A senha precisa ter pelo menos ${MINIMO_SENHA} caracteres.` });
  }

  try {
    const hash = await bcrypt.hash(senha, CUSTO_HASH);
    const [resultado] = await db.query('UPDATE usuarios SET senha = ? WHERE id = ?', [hash, id]);

    if (resultado.affectedRows === 0) {
      return res.status(404).json({ erro: 'Usuário não encontrado.' });
    }

    res.status(200).json({ mensagem: 'Senha alterada com sucesso!' });
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao alterar a senha.' });
  }
};

module.exports = { listarUsuarios, criarUsuario, atualizarUsuario, trocarSenha };
