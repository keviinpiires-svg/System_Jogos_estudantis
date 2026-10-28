const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const db = require('../config/db');

const login = async (req, res) => {
  const { email, senha } = req.body;

  if (!email || !senha) {
    return res.status(400).json({ erro: 'Informe e-mail e senha.' });
  }

  try {
    const [usuarios] = await db.query(
      `SELECT u.id, u.nome, u.email, u.senha, u.perfil, u.ativo, u.local_id, l.nome AS local_nome
         FROM usuarios u LEFT JOIN locais_disputa l ON l.id = u.local_id
        WHERE u.email = ?`,
      [email]
    );
    const usuario = usuarios[0];

    // A comparação roda antes da checagem de ativo de propósito: assim uma conta
    // desativada demora o mesmo que uma ativa e o tempo de resposta não denuncia
    // quais contas existem.
    const senhaConfere = usuario ? await bcrypt.compare(senha, usuario.senha) : false;

    // Mesma resposta para e-mail inexistente, senha errada e conta desativada
    if (!usuario || !senhaConfere || !usuario.ativo) {
      return res.status(401).json({ erro: 'E-mail ou senha inválidos.' });
    }

    const token = jwt.sign(
      { id: usuario.id, nome: usuario.nome, email: usuario.email, perfil: usuario.perfil },
      process.env.JWT_SECRET,
      { expiresIn: '8h' }
    );

    // O local da mesa NÃO vai no token: a trava o relê do banco a cada escrita
    res.status(200).json({ token, usuario: dadosDaSessao(usuario) });
  } catch (erro) {
    console.error('Erro ao realizar login:', erro);
    res.status(500).json({ erro: 'Erro ao realizar login.' });
  }
};

const dadosDaSessao = (u) => ({
  id: u.id,
  nome: u.nome,
  email: u.email,
  perfil: u.perfil,
  local_id: u.local_id ?? null,
  local_nome: u.local_nome ?? null
});

// GET /api/eu — a sessão atual, relida do banco (perfil, local da mesa).
// Conta desativada ou apagada depois do login: 401, e a tela sai.
const eu = async (req, res) => {
  try {
    const [[usuario]] = await db.query(
      `SELECT u.id, u.nome, u.email, u.perfil, u.ativo, u.local_id, l.nome AS local_nome
         FROM usuarios u LEFT JOIN locais_disputa l ON l.id = u.local_id
        WHERE u.id = ?`,
      [req.usuario.id]
    );
    if (!usuario || !usuario.ativo) {
      return res.status(401).json({ erro: 'Sua conta não está ativa. Fale com um administrador.' });
    }
    res.json(dadosDaSessao(usuario));
  } catch (erro) {
    console.error('Erro ao ler a sessão:', erro);
    res.status(500).json({ erro: 'Erro ao ler a sessão.' });
  }
};

module.exports = { login, eu };
