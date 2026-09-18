const express = require('express');
const router = express.Router();
const mataMataController = require('../controllers/mataMataController');
const verificarToken = require('../middlewares/authMiddleware');

router.get('/', mataMataController.listarMataMata);

// Rota POST para gerar as semis a partir da classificação dinâmica dos grupos
router.post('/gerar', verificarToken, mataMataController.gerarSemifinais);

// NOVA: Rota POST para gerar a final e 3º lugar
router.post('/final', verificarToken, mataMataController.gerarFinal);

module.exports = router;