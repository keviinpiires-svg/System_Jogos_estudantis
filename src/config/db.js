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
    // DATE e DATETIME são HORA DE PAREDE: o jogo é às 10:30 em Barra do Choça,
    // não num fuso. Vêm como texto ("2026-11-24 10:30:00") e ninguém os desloca.
    // Sem isto o mysql2 os lia no fuso de onde o Node roda, e o mesmo jogo
    // aparecia às 10:30 em produção (servidor em UTC) e às 13:30 na máquina de
    // quem desenvolve (UTC-3). TIMESTAMP (criado_em) segue como Date: é um
    // instante de verdade, não hora de parede.
    dateStrings: ['DATE', 'DATETIME'],
    waitForConnections: true,
    connectionLimit: Number(process.env.DB_POOL_LIMIT) || 10,
    queueLimit: 0
});

module.exports = db;
