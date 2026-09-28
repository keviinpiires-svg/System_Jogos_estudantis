const express = require('express');
const router = express.Router();
const escolaController = require('../controllers/escolaController');
const { verificarToken, exigirPerfil } = require('../middlewares/authMiddleware');

const somenteAdmin = [verificarToken, exigirPerfil('ADMIN')];

// Quando a requisição bater aqui, envia pro Controller fazer o trabalho pesado
router.post('/', somenteAdmin, escolaController.cadastrarEscola);

// Nova porta aberta para o React conseguir ler os dados do banco
router.get('/', escolaController.listarEscolas);

// Edição pela tela: mesma normalização e o mesmo 409 do cadastro
router.put('/:id', somenteAdmin, escolaController.atualizarEscola);

module.exports = router;
