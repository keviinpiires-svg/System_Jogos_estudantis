// src/config/db.js
const mysql = require('mysql2/promise');
require('dotenv').config();

const emProducao = process.env.NODE_ENV === 'production';

// Bancos na nuvem (Railway, Aiven) costumam entregar uma URL única de conexão.
// Quando ela existe, tem prioridade sobre os parâmetros separados.
const urlDeConexao = process.env.DATABASE_URL || process.env.MYSQL_URL;

// Em produção nada de fallback: é melhor falhar na subida, com mensagem clara,
// do que tentar conectar como root sem senha e gerar um erro confuso depois.
if (emProducao && !urlDeConexao) {
    const faltando = ['DB_HOST', 'DB_USER', 'DB_NAME'].filter((chave) => !process.env[chave]);
    if (faltando.length > 0) {
        throw new Error(
            `Configuração do banco incompleta. Defina DATABASE_URL ou as variáveis: ${faltando.join(', ')}.`
        );
    }
}

// Provedores em nuvem exigem TLS; no MySQL local ele fica desligado.
// rejectUnauthorized: false aceita o certificado autoassinado da Railway, que
// não é emitido por uma autoridade pública. A conexão continua criptografada,
// mas sem validação da cadeia — o que é o custo de usar o certificado deles.
const ssl = process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : undefined;

const opcoes = urlDeConexao
    ? { uri: urlDeConexao, ssl }
    : {
        host: process.env.DB_HOST || 'localhost',
        port: Number(process.env.DB_PORT) || 3306,
        user: process.env.DB_USER || 'root',
        password: process.env.DB_PASSWORD || '',
        database: process.env.DB_NAME || 'jogos_estudantis',
        ssl
    };

const db = mysql.createPool({
    ...opcoes,
    waitForConnections: true,
    connectionLimit: Number(process.env.DB_POOL_LIMIT) || 10,
    queueLimit: 0
});

module.exports = db;
