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
      'SELECT id, nome, email, senha, perfil, ativo FROM usuarios WHERE email = ?',
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

    res.status(200).json({
      token,
      usuario: {
        id: usuario.id,
        nome: usuario.nome,
        email: usuario.email,
        perfil: usuario.perfil
      }
    });
  } catch (erro) {
    console.error('Erro ao realizar login:', erro);
    res.status(500).json({ erro: 'Erro ao realizar login.' });
  }
};

module.exports = { login };
