const db = require('../config/db');

// Ordem obrigatória: filhos antes dos pais. Assim as chaves estrangeiras
// continuam ativas durante todo o reset e o banco valida cada passo.
const TABELAS_EM_ORDEM = [
  'sumulas',
  'sumulas_jogadores',
  'resultados_provas',
  'inscricoes_atletas',
  'jogos',
  'grupos_escolas',
  'classificacao',
  'alunos',
  'diretores',
  'atletas',
  'escolas'
];

// Zera o campeonato inteiro, preservando o login do administrador e os
// cadastros base (locais, modalidades, categorias, etapas de ensino e grupos).
const resetarCampeonato = async (req, res) => {
  const { confirmacao } = req.body;

  if (confirmacao !== 'REINICIAR') {
    return res.status(400).json({
      erro: 'Ação não confirmada. Envie { "confirmacao": "REINICIAR" } para zerar o campeonato.'
    });
  }

  let conexao;
  try {
    conexao = await db.getConnection();
    await conexao.beginTransaction();

    const apagados = {};
    for (const tabela of TABELAS_EM_ORDEM) {
      const [resultado] = await conexao.query(`DELETE FROM \`${tabela}\``);
      if (resultado.affectedRows > 0) {
        apagados[tabela] = resultado.affectedRows;
      }
    }

    await conexao.commit();

    // Fora da transação: TRUNCATE/ALTER não são transacionais, e reiniciar os
    // contadores aqui garante que o novo campeonato comece com os IDs em 1.
    for (const tabela of TABELAS_EM_ORDEM) {
      await conexao.query(`ALTER TABLE \`${tabela}\` AUTO_INCREMENT = 1`);
    }

    res.status(200).json({
      mensagem: 'Campeonato reiniciado! O sistema está pronto para um novo torneio.',
      registros_apagados: apagados
    });
  } catch (erro) {
    if (conexao) await conexao.rollback();
    console.error('Erro ao reiniciar o campeonato:', erro);
    res.status(500).json({ erro: 'Erro ao reiniciar o campeonato. Nada foi apagado.' });
  } finally {
    if (conexao) conexao.release();
  }
};

module.exports = { resetarCampeonato };
