const db = require('../config/db');

// Health check do serviço.
//
// Duas funções durante o evento (23 a 28/11/2026):
//   * o Render consulta esta rota para saber se o deploy subiu de pé;
//   * um ping de 5 em 5 minutos a chama para o serviço não dormir e a mesa não
//     esperar um minuto pela primeira requisição do dia.
//
// Consulta o banco de propósito: um servidor que responde mas não alcança o
// MySQL está quebrado para quem usa, e é isso que o Render precisa enxergar —
// por isso o 503, que faz o deploy ruim ser recusado em vez de entrar no ar.
//
// A rota é pública: não devolve host, versão, nome de banco nem variável de
// ambiente. Só se está de pé.
const verificarSaude = async (req, res) => {
  try {
    await db.query('SELECT 1');
    res.json({
      status: 'ok',
      banco: 'ok',
      emPeHaSegundos: Math.round(process.uptime())
    });
  } catch (erro) {
    console.error('Health check: o banco não respondeu.', erro.message);
    res.status(503).json({ status: 'indisponivel', banco: 'erro' });
  }
};

module.exports = {
  verificarSaude
};
