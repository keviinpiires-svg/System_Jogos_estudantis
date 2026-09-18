const express = require('express');
const router = express.Router();
const campeonatoController = require('../controllers/campeonatoController');
const verificarToken = require('../middlewares/authMiddleware');

router.delete('/reset', verificarToken, campeonatoController.resetarCampeonato);

module.exports = router;
