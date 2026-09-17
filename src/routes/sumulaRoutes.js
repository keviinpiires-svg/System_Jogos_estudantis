const express = require('express');
const router = express.Router();
const sumulaController = require('../controllers/sumulaController');

// Rotas estáticas primeiro
router.post('/', sumulaController.registrarSumula);
router.post('/placar', sumulaController.registrarPartida);
router.get('/atleta/:atleta_id/status', sumulaController.verificarSuspensao);

// Rota dinâmica por último: relatório da súmula de um jogo
router.get('/:jogo_id', sumulaController.buscarSumulaPorJogo);

module.exports = router;
