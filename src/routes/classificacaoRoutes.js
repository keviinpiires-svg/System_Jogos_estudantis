const express = require('express');
const router = express.Router();
const classificacaoController = require('../controllers/classificacaoController');

router.get('/:grupo_id', classificacaoController.calcularClassificacao);

module.exports = router;