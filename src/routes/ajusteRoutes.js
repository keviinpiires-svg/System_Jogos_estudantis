const express = require('express');
const router = express.Router();
const ajusteController = require('../controllers/ajusteController');
const { verificarToken, exigirPerfil } = require('../middlewares/authMiddleware');

// Aplicar e remover punição é da Comissão, pelo administrador. Ver quem foi
// punido e por quê é público: a escola precisa poder conferir a própria soma.
const somenteAdmin = [verificarToken, exigirPerfil('ADMIN')];

router.get('/', ajusteController.listarAjustes);
router.post('/', somenteAdmin, ajusteController.aplicarAjuste);
router.delete('/:id', somenteAdmin, ajusteController.removerAjuste);

module.exports = router;
