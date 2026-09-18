const jwt = require('jsonwebtoken');

const verificarToken = (req, res, next) => {
  const cabecalho = req.headers.authorization || '';
  const [tipo, token] = cabecalho.split(' ');

  if (tipo !== 'Bearer' || !token) {
    return res.status(401).json({ erro: 'Token não informado. Faça login para continuar.' });
  }

  try {
    req.usuario = jwt.verify(token, process.env.JWT_SECRET);
    next();
  } catch (erro) {
    res.status(401).json({ erro: 'Sessão inválida ou expirada. Faça login novamente.' });
  }
};

module.exports = verificarToken;
