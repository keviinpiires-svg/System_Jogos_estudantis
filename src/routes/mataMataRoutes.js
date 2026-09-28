const express = require('express');
const router = express.Router();
const mataMataController = require('../controllers/mataMataController');
const { verificarToken, exigirPerfil } = require('../middlewares/authMiddleware');

const somenteAdmin = [verificarToken, exigirPerfil('ADMIN')];

router.get('/', mataMataController.listarMataMata);

// Rota POST para gerar as semis a partir da classificação dinâmica dos grupos
router.post('/gerar', somenteAdmin, mataMataController.gerarSemifinais);

// NOVA: Rota POST para gerar a final e 3º lugar
router.post('/final', somenteAdmin, mataMataController.gerarFinal);

module.exports = router;
