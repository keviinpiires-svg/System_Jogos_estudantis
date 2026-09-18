const express = require('express');
const router = express.Router();
const atletaController = require('../controllers/atletaController');
const verificarToken = require('../middlewares/authMiddleware');

// Rota para cadastrar um atleta
router.post('/', verificarToken, atletaController.cadastrarAtleta);

// Rota para listar atletas de uma equipe específica
router.get('/equipe/:escola_id', atletaController.listarAtletasPorEquipe);

// Rota para excluir um atleta
router.delete('/:id', verificarToken, atletaController.excluirAtleta);

// Rota para atualizar um atleta
router.put('/:id', verificarToken, atletaController.atualizarAtleta);

module.exports = router;
