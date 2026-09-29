const express = require('express');
const router = express.Router();
const jogoController = require('../controllers/jogoController');
const { verificarToken, exigirPerfil } = require('../middlewares/authMiddleware');

const somenteAdmin = [verificarToken, exigirPerfil('ADMIN')];
// Iniciar a partida é trabalho de mesa, então o perfil de placar também pode
const mesaOuAdmin = [verificarToken, exigirPerfil('ADMIN', 'PLACAR')];

// Agendar e listar. Filtros do GET: competicao_id, fase, status.
router.post('/', somenteAdmin, jogoController.agendarJogo);
router.get('/', jogoController.listarJogos);

// Rotas por id
router.get('/:id', jogoController.buscarPorId);
router.put('/:id', somenteAdmin, jogoController.atualizarJogo);
router.put('/:id/iniciar', mesaOuAdmin, jogoController.iniciarJogo);
router.put('/:id/wo', somenteAdmin, jogoController.declararWO);
router.delete('/:id', somenteAdmin, jogoController.excluirJogo);

module.exports = router;
