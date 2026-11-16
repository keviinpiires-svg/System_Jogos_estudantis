const express = require('express');
const router = express.Router();
const mesaAtletasController = require('../controllers/mesaAtletasController');
const { verificarToken, exigirPerfil, travarMesaPorLocal } = require('../middlewares/authMiddleware');

// Adicionar atleta na hora do jogo é só da mesa (PLACAR), e só no jogo do local
// dela: o jogo vai na URL, que é onde a trava lê o id (db/45). O ADMIN cadastra e
// inscreve pelas telas de sempre.
const mesaDoLocal = [verificarToken, exigirPerfil('PLACAR'), travarMesaPorLocal((req) => req.params.jogoId)];

router.get('/:jogoId/equipes/:equipeId/atletas-da-escola', mesaDoLocal, mesaAtletasController.buscarAtletasDaEscola);
router.post('/:jogoId/equipes/:equipeId/atletas', mesaDoLocal, mesaAtletasController.adicionarAtleta);
router.delete('/:jogoId/inscricoes/:inscricaoId', mesaDoLocal, mesaAtletasController.removerAtleta);

module.exports = router;
