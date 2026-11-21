const express = require('express');
const router = express.Router();
const mesaAtletasController = require('../controllers/mesaAtletasController');
const { verificarToken, exigirPerfil, travarMesaPorLocal } = require('../middlewares/authMiddleware');

// Adicionar atleta pela súmula: a mesa (PLACAR) só no jogo do local dela (o jogo
// vai na URL, que é onde a trava lê o id; db/45). Desde 17/11/2026 o ADMIN também
// (lança a súmula do papel), sem trava de local e com a opção de exceção.
const mesaDoLocal = [verificarToken, exigirPerfil('ADMIN', 'PLACAR'), travarMesaPorLocal((req) => req.params.jogoId)];

router.get('/:jogoId/equipes/:equipeId/atletas-da-escola', mesaDoLocal, mesaAtletasController.buscarAtletasDaEscola);
router.post('/:jogoId/equipes/:equipeId/atletas', mesaDoLocal, mesaAtletasController.adicionarAtleta);
router.delete('/:jogoId/inscricoes/:inscricaoId', mesaDoLocal, mesaAtletasController.removerAtleta);

module.exports = router;
