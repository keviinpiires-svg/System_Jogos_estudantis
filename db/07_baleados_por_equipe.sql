-- =====================================================================
-- MIGRAÇÃO 07 — contador de BALEADOS por equipe (súmula do baleado)
--
-- Motivo: a súmula oficial do baleado (docs/referencias/SUMULA BALEADO.pdf)
-- não conta eliminações por atleta. Cada bloco de equipe tem um contador só,
-- com as caixas de 1 a 10: as atletas DAQUELA equipe que foram baleadas
-- (decisão do usuário de 06/10/2026). O placar de uma equipe é o número de
-- baleadas da adversária.
--
-- A tabela sumula_equipes guarda o rodapé de cada equipe (técnico, faltas,
-- tempo técnico) e não tem onde guardar esse contador.
--
-- O que NÃO muda:
--   * sumula_atletas.gols continua existindo; no baleado ela deixa de ser
--     usada (a API recusa lançamento por atleta nessa modalidade).
--
-- Rode depois do 01_schema.sql, num banco que já tenha as tabelas.
-- É seguro rodar com dados: a coluna nasce com 0 em todas as linhas.
-- ⚠️ O código que lê esta coluna só pode ir ao ar DEPOIS deste script rodar
-- no banco de destino: sem a coluna, a leitura da súmula falha.
-- =====================================================================

SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- 1) A coluna, ao lado do resto do rodapé da equipe.
-- ---------------------------------------------------------------------
ALTER TABLE sumula_equipes
  ADD COLUMN baleados TINYINT NOT NULL DEFAULT 0 AFTER tempo_tecnico_2t;

-- ---------------------------------------------------------------------
-- 2) O limite do papel: as caixas vão de 1 a 10 (10 atletas em quadra).
--    (CHECK vale a partir do MySQL 8.0.16; no MariaDB 10.4+ também.)
-- ---------------------------------------------------------------------
ALTER TABLE sumula_equipes
  ADD CONSTRAINT chk_sumula_equipes_baleados CHECK (baleados BETWEEN 0 AND 10);

-- ---------------------------------------------------------------------
-- 3) Conferência (o esperado é a coluna aparecer com tipo tinyint e
--    NOT NULL, e a contagem de linhas com baleados > 0 ser zero)
-- ---------------------------------------------------------------------
SELECT COLUMN_NAME AS coluna, COLUMN_TYPE AS tipo, IS_NULLABLE AS aceita_nulo,
       COLUMN_DEFAULT AS padrao
  FROM information_schema.COLUMNS
 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sumula_equipes' AND COLUMN_NAME = 'baleados';

SELECT COUNT(*) AS linhas_com_baleados FROM sumula_equipes WHERE baleados > 0;
