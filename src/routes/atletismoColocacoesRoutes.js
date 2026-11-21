const express = require('express');
const router = express.Router();
const atletismoColocacoesController = require('../controllers/atletismoColocacoesController');
const { verificarToken, exigirPerfil } = require('../middlewares/authMiddleware');

// Lançar, corrigir e apagar resultado do atletismo é só do ADMIN (a mesa não
// lança: a folha do juiz chega à organização)
const somenteAdmin = [verificarToken, exigirPerfil('ADMIN')];

// Leitura pública: a página /atletismo mostra o pódio de cada prova
router.get('/', atletismoColocacoesController.listarColocacoes);
router.post('/', somenteAdmin, atletismoColocacoesController.criarColocacao);
// O pódio inteiro de uma prova + categoria + gênero ("/podio" antes de "/:id")
router.put('/podio', somenteAdmin, atletismoColocacoesController.salvarPodio);
router.put('/:id', somenteAdmin, atletismoColocacoesController.atualizarColocacao);
router.delete('/:id', somenteAdmin, atletismoColocacoesController.apagarColocacao);

module.exports = router;
