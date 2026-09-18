const express = require('express');
const router = express.Router();
const jogoController = require('../controllers/jogoController');
const verificarToken = require('../middlewares/authMiddleware');

// 1. Rotas estáticas (não recebem parâmetros) ficam em cima
router.post('/agendar', verificarToken, jogoController.agendarJogo);
router.get('/', jogoController.listarJogos);

// 2. Rotas dinâmicas (que recebem /:id) ficam embaixo
router.get('/:id', jogoController.buscarPorId);
router.put('/finalizar/:id', verificarToken, jogoController.finalizarJogo);
router.delete('/:id', verificarToken, jogoController.excluirJogo);

module.exports = router;