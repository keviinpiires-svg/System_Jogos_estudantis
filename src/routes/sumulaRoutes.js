const express = require('express');
const router = express.Router();
const sumulaController = require('../controllers/sumulaController');
const verificarToken = require('../middlewares/authMiddleware');

// Rotas estáticas primeiro
router.post('/', verificarToken, sumulaController.registrarSumula);
router.get('/atleta/:atleta_id/status', sumulaController.verificarSuspensao);

// Rota dinâmica por último: relatório da súmula de um jogo
router.get('/:jogo_id', sumulaController.buscarSumulaPorJogo);

module.exports = router;
