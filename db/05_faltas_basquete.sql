-- =====================================================================
-- MIGRAÇÃO 05 — faltas individuais do basquete
--
-- Motivo: a súmula de basquete (docs/referencias/SUMULA_BASQUETE_MODELO.pdf)
-- marca, por atleta, as faltas cometidas de 1 a 5 — a 5ª elimina o jogador.
-- A tabela sumula_atletas não tem onde guardar isso: hoje ela só tem gols,
-- amarelos e vermelho, que são de futsal/handebol.
--
-- O que NÃO precisa mudar:
--   * os pontos do basquete usam a coluna `gols`, que passa a significar
--     "gols ou pontos", conforme modalidades.tipo_placar;
--   * as faltas acumuladas por tempo já cabem em sumula_equipes.faltas_1t /
--     faltas_2t, que são TINYINT sem teto — o basquete vai até 7, o futsal
--     até 5, e o limite de cada um fica no código.
--
-- Rode depois do 01_schema.sql, num banco que já tenha as tabelas.
-- É seguro rodar com dados: a coluna nasce com 0 em todas as linhas.
-- =====================================================================

SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- 1) A coluna. Fica ao lado dos outros lançamentos por atleta.
-- ---------------------------------------------------------------------
ALTER TABLE sumula_atletas
  ADD COLUMN faltas TINYINT NOT NULL DEFAULT 0 AFTER amarelos;

-- ---------------------------------------------------------------------
-- 2) O limite do papel: 5 faltas por atleta.
--    (CHECK vale a partir do MySQL 8.0.16; no MariaDB 10.4+ também.)
-- ---------------------------------------------------------------------
ALTER TABLE sumula_atletas
  ADD CONSTRAINT chk_sumula_atletas_faltas CHECK (faltas BETWEEN 0 AND 5);

-- ---------------------------------------------------------------------
-- 3) Conferência (o esperado é a coluna aparecer com tipo tinyint e
--    NOT NULL, e a contagem de linhas com falta > 0 ser zero)
-- ---------------------------------------------------------------------
SELECT COLUMN_NAME AS coluna, COLUMN_TYPE AS tipo, IS_NULLABLE AS aceita_nulo,
       COLUMN_DEFAULT AS padrao
  FROM information_schema.COLUMNS
 WHERE TABLE_SCHEMA = DATABASE()
   AND TABLE_NAME = 'sumula_atletas'
   AND COLUMN_NAME = 'faltas';

SELECT COUNT(*) AS linhas_com_falta FROM sumula_atletas WHERE faltas > 0;


-- ---------------------------------------------------------------------
-- PARA DESFAZER (se precisar voltar atrás)
-- ---------------------------------------------------------------------
-- ALTER TABLE sumula_atletas DROP CONSTRAINT chk_sumula_atletas_faltas;
-- ALTER TABLE sumula_atletas DROP COLUMN faltas;
