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

// Leitura pública que mostra MAIS para quem está logado (pendência 19,
// 20/10/2026: dado pessoal de atleta — nascimento e sexo — só para o ADMIN).
// Com token válido e conta ativa, deixa o usuário em req.usuario, com o perfil
// relido do banco; sem token, ou com token vencido, segue anônimo
// (req.usuario = null) — a leitura pública nunca falha por causa de login.
const identificarSeLogado = async (req, res, next) => {
  req.usuario = null;
  const [tipo, token] = (req.headers.authorization || '').split(' ');
  if (tipo !== 'Bearer' || !token) return next();

  let dados;
  try {
    dados = jwt.verify(token, process.env.JWT_SECRET);
  } catch {
    return next();
  }

  try {
    const [[usuario]] = await db.query('SELECT perfil, ativo FROM usuarios WHERE id = ?', [dados.id]);
    if (usuario && usuario.ativo) req.usuario = { ...dados, perfil: usuario.perfil };
    next();
  } catch (erro) {
    console.error('Erro ao identificar o usuário da leitura:', erro);
    next();
  }
};

// Quem pode ver dado pessoal de atleta (nascimento, sexo): só o ADMIN
const veDadosPessoais = (req) => req.usuario?.perfil === 'ADMIN';

module.exports = { verificarToken, exigirPerfil, identificarSeLogado, veDadosPessoais };
