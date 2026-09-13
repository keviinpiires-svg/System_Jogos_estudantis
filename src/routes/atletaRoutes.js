const express = require('express');
const router = express.Router();
const atletaController = require('../controllers/atletaController');

// Rota para cadastrar um atleta
router.post('/', atletaController.cadastrarAtleta);

// Rota para listar atletas de uma equipe específica
router.get('/equipe/:equipe_id', atletaController.listarAtletasPorEquipe);

module.exports = router;

