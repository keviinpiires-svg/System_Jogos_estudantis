const express = require('express');
const router = express.Router();
const equipeController = require('../controllers/equipeController');
const { verificarToken, exigirPerfil, travarMesaPorLocal } = require('../middlewares/authMiddleware');

// Leitura pública. Filtros: escola_id, competicao_id.
router.get('/', equipeController.listarEquipes);

// Quem da escola ainda pode ser inscrito nesta equipe. Traz sexo e ano de
// nascimento e só serve ao painel de inscrição do ADMIN: exige login de ADMIN
// (pendência 19, 20/10/2026; antes era pública).
router.get('/:id/atletas-elegiveis', verificarToken, exigirPerfil('ADMIN'), equipeController.listarElegiveis);

// Número da camisa na hora da partida: ADMIN em qualquer jogo; PLACAR só no jogo do local da conta
// (a trava lê o jogo_id do corpo, e o controller exige o jogo_id para ninguém escapar da trava).
router.put('/:equipeId/camisas', verificarToken, exigirPerfil('ADMIN', 'PLACAR'),
  travarMesaPorLocal((req) => req.body?.jogo_id), equipeController.salvarCamisas);

module.exports = router;
