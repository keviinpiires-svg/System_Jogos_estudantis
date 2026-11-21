const express = require('express');
const router = express.Router();
const importacaoJogosController = require('../controllers/importacaoJogosController');
const { verificarToken, exigirPerfil } = require('../middlewares/authMiddleware');

const somenteAdmin = [verificarToken, exigirPerfil('ADMIN')];

// O corpo é o próprio CSV (Content-Type: text/csv), lido como texto. O
// express.json global não o toca, e o limite daqui comporta os 1000 jogos
// que a importação aceita por arquivo.
const csv = express.text({ type: ['text/csv', 'text/plain'], limit: '1mb' });

// Prévia: analisa e não grava. Importação: refaz a análise e grava.
router.post('/previa', somenteAdmin, csv, importacaoJogosController.previaImportacao);
router.post('/', somenteAdmin, csv, importacaoJogosController.importarJogos);

module.exports = router;
