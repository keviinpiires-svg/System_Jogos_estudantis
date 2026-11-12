const express = require('express');
const router = express.Router();
const atletaController = require('../controllers/atletaController');
const { verificarToken, exigirPerfil } = require('../middlewares/authMiddleware');

const somenteAdmin = [verificarToken, exigirPerfil('ADMIN')];
// Listas de atletas (são menores de idade): só para quem está logado, ADMIN ou mesa (PLACAR). A mesa
// recebe só id, nome e escola; sexo e nascimento continuam só para o ADMIN (veDadosPessoais).
const somenteLogados = [verificarToken, exigirPerfil('ADMIN', 'PLACAR')];

router.post('/', somenteAdmin, atletaController.cadastrarAtleta);

// Rotas com prefixo fixo vêm antes de /:id para não serem engolidas por ele
// Exigem login (ADMIN ou PLACAR; 11/11/2026: antes eram públicas). A mesa recebe só id, nome e escola;
// o ADMIN recebe também sexo e nascimento (pendência 19)
router.get('/escola/:escola_id', somenteLogados, atletaController.listarAtletasPorEscola);

// Busca pelo nome em todas as escolas (mín. 3 letras, até 50 resultados): mesma regra da lista por escola
router.get('/busca', somenteLogados, atletaController.buscarAtletasPorNome);

// Caminho antigo, mantido enquanto o frontend não for migrado. "Equipe" aqui
// sempre significou escola; no schema novo equipe é escola x competição.
router.get('/equipe/:escola_id', somenteLogados, atletaController.listarAtletasPorEscola);

// Competições do atleta: só para logados, como a lista (sem RG nem nascimento; a marca de exceção só para o ADMIN)
router.get('/:id/inscricoes', somenteLogados, atletaController.listarInscricoesDoAtleta);

// Traz o RG, por isso é restrita ao administrador
router.get('/:id', somenteAdmin, atletaController.buscarAtletaPorId);

router.put('/:id', somenteAdmin, atletaController.atualizarAtleta);
router.delete('/:id', somenteAdmin, atletaController.excluirAtleta);

module.exports = router;
