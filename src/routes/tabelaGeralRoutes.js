const express = require('express');
const router = express.Router();
const tabelaGeralController = require('../controllers/tabelaGeralController');

// Leitura pública: a tabela geral é o placar do evento inteiro.
// Os ajustes de pontos (escrita) entram na 8b, só para ADMIN.
router.get('/', tabelaGeralController.tabelaGeral);

module.exports = router;
