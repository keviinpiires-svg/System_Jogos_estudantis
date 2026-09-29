const express = require('express');
const router = express.Router();
const equipeController = require('../controllers/equipeController');

// Leitura pública. Filtros: escola_id, competicao_id.
router.get('/', equipeController.listarEquipes);

module.exports = router;
