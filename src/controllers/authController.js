const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const db = require('../config/db');

const login = async (req, res) => {
  const { email, senha } = req.body;

  if (!email || !senha) {
    return res.status(400).json({ erro: 'Informe e-mail e senha.' });
  }

  try {
    const [usuarios] = await db.query('SELECT id, nome, email, senha FROM usuarios WHERE email = ?', [email]);
    const usuario = usuarios[0];

    // Mesma resposta para e-mail inexistente e senha errada: não revela quais e-mails existem
    if (!usuario || !(await bcrypt.compare(senha, usuario.senha))) {
      return res.status(401).json({ erro: 'E-mail ou senha inválidos.' });
    }

    const token = jwt.sign(
      { id: usuario.id, nome: usuario.nome, email: usuario.email },
      process.env.JWT_SECRET,
      { expiresIn: '8h' }
    );

    res.status(200).json({
      token,
      usuario: { id: usuario.id, nome: usuario.nome, email: usuario.email }
    });
  } catch (erro) {
    console.error('Erro ao realizar login:', erro);
    res.status(500).json({ erro: 'Erro ao realizar login.' });
  }
};

module.exports = { login };
