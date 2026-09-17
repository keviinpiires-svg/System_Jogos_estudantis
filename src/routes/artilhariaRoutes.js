const express = require('express');
const router = express.Router();
const artilhariaController = require('../controllers/artilhariaController');

router.get('/', artilhariaController.listarArtilharia);

module.exports = router;
