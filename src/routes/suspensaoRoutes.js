const express = require('express');
const router = express.Router();
const suspensaoController = require('../controllers/suspensaoController');
const { verificarToken, exigirPerfil } = require('../middlewares/authMiddleware');

// Leitura pública: a mesa precisa ver isso antes de escalar, e o técnico
// também. As suspensões por cartão são calculadas, nunca gravadas.
router.get('/competicao/:competicao_id', suspensaoController.situacaoDaCompeticao);
router.get('/jogo/:jogo_id', suspensaoController.suspensosNoJogo);
// Lista do dia, para imprimir com as súmulas em branco (ADMIN; 17/11/2026)
router.get('/dia/:data', verificarToken, exigirPerfil('ADMIN'), suspensaoController.suspensosDoDia);

module.exports = router;
