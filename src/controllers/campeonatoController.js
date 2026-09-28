const db = require('../config/db');

// Tabelas zeradas pelo reset, na ordem: filhos antes dos pais. Assim as chaves
// estrangeiras continuam ativas durante todo o reset e o banco valida cada passo.
//
// O reset apaga só o que é produzido durante o evento. A base importada da
// tabela de grupos (escolas, competições, grupos e equipes), os atletas, as
// inscrições e os cadastros fixos (usuários, modalidades, categorias, locais,
// etapas de ensino, pontuação da tabela geral e provas de atletismo) ficam de
// pé — nada precisa ser reimportado depois.
const TABELAS_EM_ORDEM = [
  'sumula_atletas',
  'sumula_equipes',
  'jogo_sets',
  'suspensoes',
  'colocacoes_finais',
  'ajustes_pontos_geral',
  'resultados_atletismo',
  'jogos'
];

// Zera os jogos e as súmulas do campeonato, preservando a base importada,
// os atletas, as inscrições e os cadastros fixos.
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
      mensagem: 'Jogos e súmulas apagados! As escolas, equipes e atletas continuam cadastrados.',
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
