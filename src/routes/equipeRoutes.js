const express = require('express');
const router = express.Router();
const equipeController = require('../controllers/equipeController');

// Leitura pública. Filtros: escola_id, competicao_id.
router.get('/', equipeController.listarEquipes);

// Quem da escola ainda pode ser inscrito nesta equipe
router.get('/:id/atletas-elegiveis', equipeController.listarElegiveis);

module.exports = router;
