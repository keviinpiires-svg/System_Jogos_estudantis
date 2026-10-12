const express = require('express');
const router = express.Router();
const usuarioController = require('../controllers/usuarioController');
const { verificarToken, exigirPerfil } = require('../middlewares/authMiddleware');

// Gestão de usuários é exclusiva do administrador, inclusive a leitura:
// a lista revela quem tem acesso ao sistema.
const somenteAdmin = [verificarToken, exigirPerfil('ADMIN')];

router.get('/', somenteAdmin, usuarioController.listarUsuarios);
router.post('/', somenteAdmin, usuarioController.criarUsuario);
router.put('/:id', somenteAdmin, usuarioController.atualizarUsuario);
router.put('/:id/senha', somenteAdmin, usuarioController.trocarSenha);

module.exports = router;
