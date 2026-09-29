const express = require('express');
const router = express.Router();
const suspensaoController = require('../controllers/suspensaoController');

// Leitura pública: a mesa precisa ver isso antes de escalar, e o técnico
// também. As suspensões por cartão são calculadas, nunca gravadas.
router.get('/competicao/:competicao_id', suspensaoController.situacaoDaCompeticao);
router.get('/jogo/:jogo_id', suspensaoController.suspensosNoJogo);

module.exports = router;
