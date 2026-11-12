const express = require('express');
const router = express.Router();
const tabuleiroColocacoesController = require('../controllers/tabuleiroColocacoesController');
const { verificarToken, exigirPerfil } = require('../middlewares/authMiddleware');

// Lançar, corrigir e apagar resultado do tabuleiro é só do ADMIN (a mesa não
// lança: a folha do juiz chega à organização)
const somenteAdmin = [verificarToken, exigirPerfil('ADMIN')];

// Leitura pública: a página /tabuleiro mostra o pódio de cada jogo
router.get('/', tabuleiroColocacoesController.listarColocacoes);
router.post('/', somenteAdmin, tabuleiroColocacoesController.criarColocacao);
// O pódio inteiro de um jogo + categoria ("/podio" antes de "/:id")
router.put('/podio', somenteAdmin, tabuleiroColocacoesController.salvarPodio);
router.put('/:id', somenteAdmin, tabuleiroColocacoesController.atualizarColocacao);
router.delete('/:id', somenteAdmin, tabuleiroColocacoesController.apagarColocacao);

module.exports = router;
