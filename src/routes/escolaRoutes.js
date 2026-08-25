const express = require('express');
const router = express.Router();
const escolaController = require('../controllers/escolaController');

// Quando a requisição bater aqui, envia pro Controller fazer o trabalho pesado
router.post('/', escolaController.cadastrarEscola);

module.exports = router;