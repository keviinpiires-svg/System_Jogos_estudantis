const jwt = require('jsonwebtoken');
const db = require('../config/db');

// Autenticação: confirma que o token é válido e deixa o usuário em req.usuario.
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

// Autorização por perfil. O perfil gravado no token é uma fotografia do momento
// do login e valeria por 8h: reler do banco faz um rebaixamento ou uma
// desativação valer na hora. Só rotas de escrita passam por aqui, então é uma
// query por escrita — as leituras seguem públicas e sem custo.
const exigirPerfil = (...perfisPermitidos) => async (req, res, next) => {
  if (!req.usuario) {
    return res.status(401).json({ erro: 'Sessão inválida ou expirada. Faça login novamente.' });
  }

  try {
    const [[usuario]] = await db.query(
      'SELECT perfil, ativo FROM usuarios WHERE id = ?',
      [req.usuario.id]
    );

    // Conta apagada ou desativada depois que o token foi emitido
    if (!usuario || !usuario.ativo) {
      return res.status(401).json({ erro: 'Sua conta não está ativa. Fale com um administrador.' });
    }

    if (!perfisPermitidos.includes(usuario.perfil)) {
      return res.status(403).json({ erro: 'Você não tem permissão para esta ação.' });
    }

    // O perfil do banco vence o do token no resto da requisição
    req.usuario.perfil = usuario.perfil;
    next();
  } catch (erro) {
    console.error('Erro ao verificar o perfil do usuário:', erro);
    res.status(500).json({ erro: 'Erro ao verificar suas permissões.' });
  }
};

module.exports = { verificarToken, exigirPerfil };
