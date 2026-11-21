const express = require('express');
const router = express.Router();
const importacaoAtletasController = require('../controllers/importacaoAtletasController');
const { verificarToken, exigirPerfil } = require('../middlewares/authMiddleware');

// Tudo de ADMIN: a prévia devolve RG e nascimento de menores
const somenteAdmin = [verificarToken, exigirPerfil('ADMIN')];

// O corpo é o próprio CSV (text/csv), lido como texto
const csv = express.text({ type: ['text/csv', 'text/plain'], limit: '1mb' });

router.post('/previa', somenteAdmin, csv, importacaoAtletasController.previaAtletas);
router.post('/confirmar', somenteAdmin, csv, importacaoAtletasController.confirmarAtletas);

module.exports = router;
