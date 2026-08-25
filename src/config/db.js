// src/config/db.js
const mysql = require('mysql2/promise');
require('dotenv').config(); // Se estiver usando o arquivo .env

// Cria a conexão com o banco
const db = mysql.createPool({
    host: process.env.DB_HOST || 'localhost',
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD || '',
    database: process.env.DB_NAME || 'jogos_estudantis'
});

// Exporta o banco para quem quiser usar
module.exports = db;