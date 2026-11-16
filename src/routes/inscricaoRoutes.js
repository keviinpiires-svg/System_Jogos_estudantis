const express = require('express');
const router = express.Router();
const inscricaoController = require('../controllers/inscricaoController');
const mesaAtletasController = require('../controllers/mesaAtletasController');
const { verificarToken, exigirPerfil, identificarSeLogado } = require('../middlewares/authMiddleware');

// Inscrever e remover é do administrador; ver o elenco é leitura pública
// (nomes e camisas). Sexo e ano de nascimento, só para o ADMIN (pendência 19).
const somenteAdmin = [verificarToken, exigirPerfil('ADMIN')];

router.post('/', somenteAdmin, inscricaoController.inscreverAtleta);
// Conferência depois do evento: o que as mesas adicionaram (db/45)
router.get('/adicionadas-pela-mesa', somenteAdmin, mesaAtletasController.listarAdicionadasPelaMesa);
router.get('/equipe/:equipe_id', identificarSeLogado, inscricaoController.listarInscritos);
router.delete('/:id', somenteAdmin, inscricaoController.removerInscricao);

module.exports = router;
