const express = require('express');
const router = express.Router();
const pontosLancadosController = require('../controllers/pontosLancadosController');
const { verificarToken, exigirPerfil } = require('../middlewares/authMiddleware');

const somenteAdmin = [verificarToken, exigirPerfil('ADMIN')];
// A mesa recebe a folha do juiz e digita os pontos: lança e edita como o ADMIN
const mesaOuAdmin = [verificarToken, exigirPerfil('ADMIN', 'PLACAR')];

// Leitura pública: a escola confere de onde veio a própria soma
router.get('/', pontosLancadosController.listarPontosLancados);
router.put('/', mesaOuAdmin, pontosLancadosController.salvarPontosLancados);
// Apagar o lançamento inteiro de uma categoria e gênero é só do ADMIN
router.delete('/:modalidade/:categoria_id/:genero', somenteAdmin, pontosLancadosController.apagarLancamento);

module.exports = router;
