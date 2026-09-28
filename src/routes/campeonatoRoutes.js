const express = require('express');
const router = express.Router();
const campeonatoController = require('../controllers/campeonatoController');
const { verificarToken, exigirPerfil } = require('../middlewares/authMiddleware');

router.delete('/reset', verificarToken, exigirPerfil('ADMIN'), campeonatoController.resetarCampeonato);

module.exports = router;
