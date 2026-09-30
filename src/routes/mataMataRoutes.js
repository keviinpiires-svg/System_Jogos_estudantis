const express = require('express');
const router = express.Router();
const mataMataController = require('../controllers/mataMataController');

// Leitura pública, como as outras da competição: a chave, os classificados e
// as colocações finais são todos calculados a partir dos jogos.
// A geração e o desfazer entram na parte 7b, só para ADMIN.
router.get('/competicao/:competicao_id', mataMataController.chaveDaCompeticao);

module.exports = router;
