const express = require('express');
const router = express.Router();
const atletaController = require('../controllers/atletaController');
const { verificarToken, exigirPerfil } = require('../middlewares/authMiddleware');

const somenteAdmin = [verificarToken, exigirPerfil('ADMIN')];

// Rota para cadastrar um atleta
router.post('/', somenteAdmin, atletaController.cadastrarAtleta);

// Rota para listar atletas de uma equipe específica
router.get('/equipe/:escola_id', atletaController.listarAtletasPorEquipe);

// Rota para excluir um atleta
router.delete('/:id', somenteAdmin, atletaController.excluirAtleta);

// Rota para atualizar um atleta
router.put('/:id', somenteAdmin, atletaController.atualizarAtleta);

module.exports = router;
