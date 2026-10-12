const express = require('express');
const router = express.Router();
const mataMataController = require('../controllers/mataMataController');
const { verificarToken, exigirPerfil } = require('../middlewares/authMiddleware');

const somenteAdmin = [verificarToken, exigirPerfil('ADMIN')];

// Leitura pública, como as outras da competição: a chave, os classificados e
// as colocações finais são todos calculados a partir dos jogos.
// Gerar e desfazer são do administrador.
router.get('/competicao/:competicao_id', mataMataController.chaveDaCompeticao);

router.post('/competicao/:competicao_id/gerar', somenteAdmin, mataMataController.gerarFase);
router.delete('/competicao/:competicao_id/:fase', somenteAdmin, mataMataController.desfazerFase);

module.exports = router;
