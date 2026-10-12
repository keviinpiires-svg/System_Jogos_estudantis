const express = require('express');
const router = express.Router();
const { rateLimit } = require('express-rate-limit');
const authController = require('../controllers/authController');

// Freia a tentativa de adivinhar senha por força bruta. Só as tentativas que
// falham contam, então quem entra e sai várias vezes no dia do evento não é
// punido. Depende do app.set('trust proxy', 1) no server.js para enxergar o IP
// real por trás do proxy do Render.
const limiteLogin = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 10,
  skipSuccessfulRequests: true,
  standardHeaders: true,
  legacyHeaders: false,
  message: { erro: 'Muitas tentativas de login. Espere alguns minutos e tente de novo.' }
});

router.post('/login', limiteLogin, authController.login);

module.exports = router;
