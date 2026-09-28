const express = require('express');
const router = express.Router();
const inscricaoController = require('../controllers/inscricaoController');
const { verificarToken, exigirPerfil } = require('../middlewares/authMiddleware');

router.post('/', verificarToken, exigirPerfil('ADMIN'), inscricaoController.inscreverAtleta);

module.exports = router;
