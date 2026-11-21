-- =====================================================================
-- MIGRAÇÃO 51 — empate no tabuleiro (21/11/2026)
--
-- Pedido do usuário: nas modalidades individuais de tabuleiro (xadrez, dama
-- e dominó, lançadas juntas como "Tabuleiro") pode haver EMPATE: duas ou mais
-- escolas na mesma colocação da mesma categoria. Cada escola empatada leva os
-- pontos inteiros daquela colocação na Tabela Geral.
--
-- Tira só o índice único que impedia a mesma colocação duas vezes
-- (uq_tabuleiro_col_colocacao). Continua valendo uma colocação por escola em
-- cada categoria (uq_tabuleiro_col_escola, que também serve à chave
-- estrangeira da modalidade). Não altera nenhum dado. Idempotente. Sem dado
-- de aluno. Rode antes do deploy do backend que aceita o empate.
-- =====================================================================

SET @existe := (SELECT COUNT(*) FROM information_schema.STATISTICS
                 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'tabuleiro_colocacoes'
                   AND INDEX_NAME = 'uq_tabuleiro_col_colocacao');
SET @sql := IF(@existe > 0,
  'ALTER TABLE tabuleiro_colocacoes DROP INDEX uq_tabuleiro_col_colocacao',
  'SELECT ''uq_tabuleiro_col_colocacao já não existe'' AS aviso');
PREPARE passo FROM @sql;
EXECUTE passo;
DEALLOCATE PREPARE passo;

-- Conferência: tem de sobrar o uq_tabuleiro_col_escola (e não o de colocação)
SELECT INDEX_NAME, NON_UNIQUE, GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS colunas
  FROM information_schema.STATISTICS
 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'tabuleiro_colocacoes'
 GROUP BY INDEX_NAME, NON_UNIQUE;
