const express = require('express');
const router = express.Router();
const sumulaController = require('../controllers/sumulaController');
const { verificarToken, exigirPerfil } = require('../middlewares/authMiddleware');

// Lançar a súmula é a razão de existir do perfil PLACAR.
// Reabrir uma súmula já finalizada exige ADMIN — a checagem fica no
// controller, que é quem enxerga o status do jogo.
const mesaOuAdmin = [verificarToken, exigirPerfil('ADMIN', 'PLACAR')];

router.post('/', mesaOuAdmin, sumulaController.registrarSumula);

// Leitura pública: é o que a impressão consome, em branco ou preenchida
router.get('/:jogo_id', sumulaController.buscarSumulaPorJogo);

// GET /atleta/:id/status saiu daqui: o cálculo antigo não seguia o regulamento
// (2 amarelos = 1 jogo, amarelos zerados na 2ª fase, expulsão = 1 jogo).
// Volta refeito na fatia 5e — suspensão por cartões.

module.exports = router;
