const express = require('express');
const router = express.Router();
const alunoController = require('../controllers/alunoController');

router.get('/escola/:escola_id', alunoController.listarElenco);

module.exports = router;