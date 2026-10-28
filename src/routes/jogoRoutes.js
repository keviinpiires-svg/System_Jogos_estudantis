const express = require('express');
const router = express.Router();
const jogoController = require('../controllers/jogoController');
const { verificarToken, exigirPerfil, travarMesaPorLocal } = require('../middlewares/authMiddleware');

const somenteAdmin = [verificarToken, exigirPerfil('ADMIN')];
// Iniciar a partida é trabalho de mesa, então o perfil de placar também pode,
// mas só no jogo do local dela (db/18)
const mesaDoLocalOuAdmin = [verificarToken, exigirPerfil('ADMIN', 'PLACAR'), travarMesaPorLocal((req) => req.params.id)];

// Agendar e listar. Filtros do GET: competicao_id, fase, status.
router.post('/', somenteAdmin, jogoController.agendarJogo);
router.get('/', jogoController.listarJogos);

// Rotas por id
router.get('/:id', jogoController.buscarPorId);
router.put('/:id', somenteAdmin, jogoController.atualizarJogo);
router.put('/:id/iniciar', mesaDoLocalOuAdmin, jogoController.iniciarJogo);
router.put('/:id/wo', somenteAdmin, jogoController.declararWO);
router.delete('/:id', somenteAdmin, jogoController.excluirJogo);

module.exports = router;
