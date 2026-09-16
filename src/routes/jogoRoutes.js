const express = require('express');
const router = express.Router();
const jogoController = require('../controllers/jogoController');

// 1. Rotas estáticas (não recebem parâmetros) ficam em cima
router.post('/agendar', jogoController.agendarJogo);
router.get('/', jogoController.listarJogos);

// 2. Rotas dinâmicas (que recebem /:id) ficam embaixo
router.get('/:id', jogoController.buscarPorId);
router.put('/finalizar/:id', jogoController.finalizarJogo);

module.exports = router;