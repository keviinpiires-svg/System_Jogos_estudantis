const express = require('express');
const router = express.Router();
const classificacaoController = require('../controllers/classificacaoController');

// Leitura pública. A classificação existe por competição: não há mais tabela
// global, porque cada competição tem seus grupos e seu critério de desempate.
router.get('/competicao/:competicao_id', classificacaoController.classificacaoDaCompeticao);

module.exports = router;