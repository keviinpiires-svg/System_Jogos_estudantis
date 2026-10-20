const express = require('express');
const router = express.Router();
const inscricaoController = require('../controllers/inscricaoController');
const { verificarToken, exigirPerfil, identificarSeLogado } = require('../middlewares/authMiddleware');

// Inscrever e remover é do administrador; ver o elenco é leitura pública
// (nomes e camisas). Sexo e ano de nascimento, só para o ADMIN (pendência 19).
const somenteAdmin = [verificarToken, exigirPerfil('ADMIN')];

router.post('/', somenteAdmin, inscricaoController.inscreverAtleta);
router.get('/equipe/:equipe_id', identificarSeLogado, inscricaoController.listarInscritos);
router.delete('/:id', somenteAdmin, inscricaoController.removerInscricao);

module.exports = router;
