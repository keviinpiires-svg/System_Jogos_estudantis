const express = require('express');
const router = express.Router();
const modalidadeController = require('../controllers/modalidadeController');

// Leitura pública: é o que monta o menu lateral, visível a quem não logou.
router.get('/', modalidadeController.listarModalidades);

module.exports = router;
