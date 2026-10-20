-- =====================================================================
-- MIGRAÇÃO 15 — número do jogo na tabela oficial do chefe (20/10/2026)
--
-- Motivo: a tabela de jogos do chefe numera os jogos de 1 a 338, de forma
-- GLOBAL, e é esse número que o público e as escolas usam ("o jogo 163").
-- O sistema só tinha o numero_jogo, que é POR COMPETIÇÃO (1, 2, 3...).
--
-- Coluna OPCIONAL: jogo cadastrado à mão, ou de lote sem o número, fica com
-- NULL. Índice ÚNICO: o mesmo número não pode estar em dois jogos (vários
-- NULL são permitidos). O CHECK recusa 0.
--
-- Quem preenche: a importação por CSV, pela coluna opcional "Nº Tabela"
-- (importacaoJogosController). Reimportar o mesmo arquivo com a coluna só
-- preenche o número dos jogos que já existem e estão sem número — não muda
-- nada mais neles.
--
-- RODA UMA VEZ (como o 08): o MySQL não tem ADD COLUMN IF NOT EXISTS. Rodar de
-- novo falha inteiro, sem mudar nada: erro 3822 (CHECK com nome repetido) no
-- MySQL 8, 1060 (coluna duplicada) no MariaDB.
--
-- Compatível com o backend que está no ar (coluna nula, ninguém lê). O
-- backend que lê a coluna (agenda e importação) precisa dele ANTES.
-- Rode depois do 14. A trava de mesa por local, antes planejada como 15,
-- passa a ser o 16.
-- =====================================================================

SET NAMES utf8mb4;

ALTER TABLE jogos
  ADD COLUMN numero_tabela SMALLINT UNSIGNED NULL AFTER numero_jogo,
  ADD UNIQUE KEY uq_jogos_numero_tabela (numero_tabela),
  ADD CONSTRAINT chk_jogos_numero_tabela CHECK (numero_tabela IS NULL OR numero_tabela >= 1);

-- ---------------------------------------------------------------------
-- Conferência: a coluna (nula, sem padrão) e o índice único
-- ---------------------------------------------------------------------
SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_DEFAULT
  FROM information_schema.COLUMNS
 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jogos' AND COLUMN_NAME = 'numero_tabela';
SELECT INDEX_NAME, NON_UNIQUE
  FROM information_schema.STATISTICS
 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jogos' AND INDEX_NAME = 'uq_jogos_numero_tabela';
