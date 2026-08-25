const express = require('express');
const router = express.Router();
const jogoController = require('../controllers/jogoController');

// Se for um POST na raiz, agenda o jogo
router.post('/', jogoController.agendarJogo);

// Se for um PUT com um ID e /finalizar, encerra o jogo
router.put('/:id/finalizar', jogoController.finalizarJogo);
// Adicione esta linha junto com as suas outras rotas de jogos
router.get('/', jogoController.listarJogos);

module.exports = router;