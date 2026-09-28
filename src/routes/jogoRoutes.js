const express = require('express');
const router = express.Router();
const jogoController = require('../controllers/jogoController');
const { verificarToken, exigirPerfil } = require('../middlewares/authMiddleware');

const somenteAdmin = [verificarToken, exigirPerfil('ADMIN')];
// Encerrar a partida é trabalho de mesa, então o perfil de placar também pode
const mesaOuAdmin = [verificarToken, exigirPerfil('ADMIN', 'PLACAR')];

// 1. Rotas estáticas (não recebem parâmetros) ficam em cima
router.post('/agendar', somenteAdmin, jogoController.agendarJogo);
router.get('/', jogoController.listarJogos);

// 2. Rotas dinâmicas (que recebem /:id) ficam embaixo
router.get('/:id', jogoController.buscarPorId);
router.put('/finalizar/:id', mesaOuAdmin, jogoController.finalizarJogo);
router.delete('/:id', somenteAdmin, jogoController.excluirJogo);

module.exports = router;
