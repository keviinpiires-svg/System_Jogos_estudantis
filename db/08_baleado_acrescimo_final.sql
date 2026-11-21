-- =====================================================================
-- MIGRAÇÃO 08 — quem baleou primeiro no acréscimo da final do baleado
--
-- Motivo: resposta do chefe de 07/10/2026. No baleado, o empate vale na fase
-- de grupos (1 ponto para cada equipe), mas na FINAL há um acréscimo de 4
-- minutos e vence quem balear primeiro. A súmula precisa registrar quem foi.
--
-- Menor desenho possível: uma coluna no JOGO, ao lado dos outros desempates
-- que já moram lá (penaltis_1/penaltis_2 e prorrogacao). É nula em todo jogo
-- que não for final de baleado empatada; quando preenchida, é a equipe
-- vencedora do acréscimo. A chave estrangeira é composta com competicao_id,
-- como a de vencedor_equipe_id, para garantir que a equipe é do jogo.
--
-- Compatível com o backend que está no ar: a coluna nasce nula e nada do
-- código atual a escreve. O código que a grava e lê só pode ir ao ar DEPOIS
-- deste script rodar no banco de destino.
--
-- Rode depois do 07, num banco que já tenha as tabelas. Sintaxe para MySQL
-- 8.0.16+ e MariaDB 10.4+ (sem IF NOT EXISTS).
-- =====================================================================

SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- 1) A coluna, logo depois da prorrogação.
-- ---------------------------------------------------------------------
ALTER TABLE jogos
  ADD COLUMN baleou_primeiro_equipe_id INT NULL AFTER prorrogacao;

-- ---------------------------------------------------------------------
-- 2) A equipe precisa ser da mesma competição do jogo.
-- ---------------------------------------------------------------------
ALTER TABLE jogos
  ADD CONSTRAINT fk_jogos_baleou_primeiro FOREIGN KEY (baleou_primeiro_equipe_id, competicao_id)
    REFERENCES equipes (id, competicao_id) ON DELETE RESTRICT;

-- ---------------------------------------------------------------------
-- 3) Conferência (o esperado é a coluna aparecer como int, aceitando nulo,
--    e nenhum jogo com ela preenchida)
-- ---------------------------------------------------------------------
SELECT COLUMN_NAME AS coluna, COLUMN_TYPE AS tipo, IS_NULLABLE AS aceita_nulo
  FROM information_schema.COLUMNS
 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jogos' AND COLUMN_NAME = 'baleou_primeiro_equipe_id';

SELECT COUNT(*) AS jogos_com_acrescimo FROM jogos WHERE baleou_primeiro_equipe_id IS NOT NULL;
