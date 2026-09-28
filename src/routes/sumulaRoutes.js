const express = require('express');
const router = express.Router();
const sumulaController = require('../controllers/sumulaController');
const { verificarToken, exigirPerfil } = require('../middlewares/authMiddleware');

// Lançar a súmula é a razão de existir do perfil PLACAR.
// Reabrir uma súmula já finalizada exige ADMIN — a checagem fica no
// controller, que é quem enxerga o status do jogo.
const mesaOuAdmin = [verificarToken, exigirPerfil('ADMIN', 'PLACAR')];

// Rotas estáticas primeiro
router.post('/', mesaOuAdmin, sumulaController.registrarSumula);
router.get('/atleta/:atleta_id/status', sumulaController.verificarSuspensao);

// Rota dinâmica por último: relatório da súmula de um jogo
router.get('/:jogo_id', sumulaController.buscarSumulaPorJogo);

module.exports = router;
