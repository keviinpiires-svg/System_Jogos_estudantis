const express = require('express');
const router = express.Router();
const etapaEnsinoController = require('../controllers/etapaEnsinoController');

router.get('/', etapaEnsinoController.listarEtapas);

module.exports = router;
