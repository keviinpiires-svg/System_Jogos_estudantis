const express = require('express');
const router = express.Router();
const inscricaoController = require('../controllers/inscricaoController');
const { verificarToken, exigirPerfil } = require('../middlewares/authMiddleware');

// Inscrever e remover é do administrador; ver o elenco é leitura pública
// (nomes e camisas, sem RG).
const somenteAdmin = [verificarToken, exigirPerfil('ADMIN')];

router.post('/', somenteAdmin, inscricaoController.inscreverAtleta);
router.get('/equipe/:equipe_id', inscricaoController.listarInscritos);
router.delete('/:id', somenteAdmin, inscricaoController.removerInscricao);

module.exports = router;
