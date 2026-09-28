const express = require('express');
const router = express.Router();
const grupoController = require('../controllers/grupoController');
const { verificarToken, exigirPerfil } = require('../middlewares/authMiddleware');

router.get('/', grupoController.listarGrupos);
router.put('/distribuicao', verificarToken, exigirPerfil('ADMIN'), grupoController.salvarDistribuicao);

module.exports = router;
