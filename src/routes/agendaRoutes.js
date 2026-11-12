const express = require('express');
const router = express.Router();
const agendaController = require('../controllers/agendaController');

// Públicas e só de leitura: a agenda é aberta pelo público no celular
router.get('/', agendaController.listarAgenda);
router.get('/jogos/:id', agendaController.detalharJogo);

module.exports = router;
