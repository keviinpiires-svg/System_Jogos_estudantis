const express = require('express');
const router = express.Router();
const atletaController = require('../controllers/atletaController');
const { verificarToken, exigirPerfil, identificarSeLogado } = require('../middlewares/authMiddleware');

const somenteAdmin = [verificarToken, exigirPerfil('ADMIN')];

router.post('/', somenteAdmin, atletaController.cadastrarAtleta);

// Rotas com prefixo fixo vêm antes de /:id para não serem engolidas por ele
// Pública, mas sem dado pessoal para quem não é ADMIN: anônimo recebe só id,
// nome e escola; o ADMIN recebe também sexo e nascimento (pendência 19)
router.get('/escola/:escola_id', identificarSeLogado, atletaController.listarAtletasPorEscola);

// Caminho antigo, mantido enquanto o frontend não for migrado. "Equipe" aqui
// sempre significou escola; no schema novo equipe é escola x competição.
router.get('/equipe/:escola_id', identificarSeLogado, atletaController.listarAtletasPorEscola);

// Traz o RG, por isso é restrita ao administrador
router.get('/:id', somenteAdmin, atletaController.buscarAtletaPorId);

router.put('/:id', somenteAdmin, atletaController.atualizarAtleta);
router.delete('/:id', somenteAdmin, atletaController.excluirAtleta);

module.exports = router;
