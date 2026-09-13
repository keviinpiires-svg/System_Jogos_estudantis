const express = require('express');
const router = express.Router();
const sumulaController = require('../controllers/sumulaController');

// Rota POST para gravar os eventos do atleta no jogo
router.post('/', sumulaController.registrarSumula);

// Rota GET para o React consultar se o atleta tá suspenso
router.get('/atleta/:aluno_id/status', sumulaController.verificarSuspensao);

router.post('/placar', sumulaController.registrarPartida); 

module.exports = router;