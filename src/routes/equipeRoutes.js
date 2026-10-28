const express = require('express');
const router = express.Router();
const equipeController = require('../controllers/equipeController');
const { verificarToken, exigirPerfil } = require('../middlewares/authMiddleware');

// Leitura pública. Filtros: escola_id, competicao_id.
router.get('/', equipeController.listarEquipes);

// Quem da escola ainda pode ser inscrito nesta equipe. Traz sexo e ano de
// nascimento e só serve ao painel de inscrição do ADMIN: exige login de ADMIN
// (pendência 19, 20/10/2026; antes era pública).
router.get('/:id/atletas-elegiveis', verificarToken, exigirPerfil('ADMIN'), equipeController.listarElegiveis);

module.exports = router;
