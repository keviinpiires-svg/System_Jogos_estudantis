const express = require('express');
const router = express.Router();
const competicaoController = require('../controllers/competicaoController');

// Leituras públicas. Filtros aceitos em GET /: modalidade (slug ou id),
// genero e categoria_id.
router.get('/', competicaoController.listarCompeticoes);
router.get('/:id', competicaoController.buscarCompeticao);

module.exports = router;
