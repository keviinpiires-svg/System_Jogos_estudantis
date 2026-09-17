const express = require('express');
const router = express.Router();
const mataMataController = require('../controllers/mataMataController');

router.get('/', mataMataController.listarMataMata);

// Rota POST para gerar as semis
router.post('/semifinais', mataMataController.gerarSemifinais);

// NOVA: Rota POST para gerar a final e 3º lugar
router.post('/finais', mataMataController.gerarFinais);

module.exports = router;