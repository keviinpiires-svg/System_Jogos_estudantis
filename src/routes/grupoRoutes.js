const express = require('express');
const router = express.Router();
const grupoController = require('../controllers/grupoController');
const verificarToken = require('../middlewares/authMiddleware');

router.get('/', grupoController.listarGrupos);
router.put('/distribuicao', verificarToken, grupoController.salvarDistribuicao);

module.exports = router;
