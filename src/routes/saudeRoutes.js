const express = require('express');
const router = express.Router();
const saudeController = require('../controllers/saudeController');

router.get('/', saudeController.verificarSaude);

module.exports = router;
