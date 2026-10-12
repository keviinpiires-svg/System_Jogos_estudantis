const express = require('express');
const router = express.Router();
const artilhariaController = require('../controllers/artilhariaController');

// Leituras públicas.
// A artilharia é por competição; /lideres traz o artilheiro de cada uma,
// que é o que o painel geral mostra.
router.get('/lideres', artilhariaController.listarLideres);
router.get('/competicao/:competicao_id', artilhariaController.listarPorCompeticao);

module.exports = router;
