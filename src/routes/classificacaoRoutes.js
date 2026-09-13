const express = require('express');
const router = express.Router();
const classificacaoController = require('../controllers/classificacaoController');

router.get('/', classificacaoController.listarClassificacao);

module.exports = router;