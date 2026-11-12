-- =====================================================================
-- MIGRAÇÃO 26 — tabela de jogos 20264 do chefe (06/11/2026)
--
-- O chefe mandou a tabela de jogos nova e o usuário decidiu segui-la. O mapa
-- jogo a jogo (docs/importacao/mapa_tabela_20264.csv e contexto_tabela_20264.md,
-- fora do git) foi comparado com o jogos_2026: 232 jogos de grupo hoje, 234 na
-- tabela nova. Este script aplica o mapa inteiro, numa transação:
--
--   MANTER    65  mesmo número, nada muda
--   RENUMERAR 123 só o numero_tabela muda
--   ALTERAR   36  muda dia, hora, local ou mando (a maioria também muda de nº)
--   REMOVER   8   saem os jogos 36, 37, 43, 129, 132, 191, 194 e 209
--   INCLUIR   10  entram os jogos 36, 37, 43, 101, 126, 130, 192, 204, 206 e 286
--
-- O chefe renumerou a tabela inteira (159 jogos mudam de número), então a
-- renumeração é em DUAS FASES por causa do índice único de numero_tabela:
-- primeiro o número novo + 10000, depois - 10000 (como no db/20).
--
-- Equipes:
--   * a CETI SAI do Futebol Society Sub 15 M e do Futsal Sub 15 M (só se não
--     tiver atleta inscrito, súmula nem colocação, e só depois de saírem os
--     jogos dela);
--   * a CETI VOLTA ao Basquete Sub 17 F (grupo A, com CEJA e CEBC): desfaz em
--     parte o db/23, por decisão do usuário (06/11/2026).
--
-- Society Sub 17 M: os 3 jogos de hoje saem e entram 4, todos entre uma
-- equipe do grupo A e uma do grupo B. Eles entram SEM grupo (grupo_id vazio);
-- a regra de disputa e os grupos NÃO mudam aqui. A mudança para grupo único é
-- o db/27, que roda logo depois.
--
-- Casos conhecidos entre o mapa e o banco (decisões do usuário, 06/11/2026):
--   * jogo 6 (CEJA x CEBC, Futsal Aberto M, 18/11): fica 17:50, como no banco; o
--     18:50 do mapa é erro (bateria com o jogo 7, às 18:30, na mesma quadra);
--   * jogo 223 → 218 (CEJA x Lucia Rocha, Handebol Aberto M, 20/11, Quadra do
--     CEBC): passa de 18:00 a 17:20, como na tabela nova (o 18:00 existia por
--     conflito com CETI x Lucia Rocha às 17:20, que foi para 14:40, nº 140);
--   * Vôlei Sub 15 e Sub 17 aparecem como "Masculino" no mapa, e no banco são
--     Misto; o jogo 70 aparece como "Sub 1" (é Sub 11). Só o rótulo;
--   * jogo 286 (Baleado Sub 8 M, ACM x Marlene Santana, 21/11 16:40): o mapa o
--     chama de "FINAL"; entra como 2º jogo de GRUPOS, sem mudar a regra.
--
-- Os jogos novos ficam AGENDADOS, e o numero_jogo de cada um é o maior da
-- competição + 1, na ordem do número da tabela (os buracos que já existem no
-- numero_jogo não são compactados). Mata-mata (75 linhas da tabela) NÃO é
-- criado aqui.
--
-- SEGURANÇA: uma transação só. Duas travas (CHECK em tabela temporária, erro
-- 3819 no MySQL e 4025 no MariaDB) param o script sem gravar nada:
--   tabela_20264_nao_bate_com_o_banco     (antes de qualquer escrita)
--   conferencia_do_db26_divergiu          (antes do COMMIT)
-- A primeira só deixa passar dois estados: o ORIGINAL (os 232 jogos casam com o
-- "nº atual" do mapa em número, competição, dia e hora, local e as duas equipes;
-- todos os que mudam ou saem estão AGENDADOS, sem placar, súmula nem set; a CETI
-- das duas Sub 15 sem atleta, súmula nem colocação) e o JÁ FEITO (os 234 jogos já
-- casam com o "nº novo"). Qualquer outra coisa para o script.
-- No cliente mysql o erro encerra a sessão e a transação é desfeita. No
-- DBeaver, se um comando falhar, rode ROLLBACK antes de qualquer outra coisa.
--
-- IDEMPOTENTE: rodado de novo depois, cai em "já feito", não grava nada e as
-- conferências passam.
--
-- Só dados. Rode depois do 25. MySQL 8.0.16+ ou MariaDB 10.2+ (CHECK de
-- verdade). FAÇA O DUMP do banco antes, na produção.
-- =====================================================================

SET NAMES utf8mb4;

START TRANSACTION;

-- ---------------------------------------------------------------------
-- O mapa (242 linhas): uma por jogo que existe hoje ou que existirá
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS mapa_db26;
CREATE TEMPORARY TABLE mapa_db26 (
  tab_atual   SMALLINT UNSIGNED NULL,
  tab_novo    SMALLINT UNSIGNED NULL,
  acao        VARCHAR(10)  NOT NULL,
  data_atual  DATETIME     NULL,
  data_nova   DATETIME     NULL,
  local_atual VARCHAR(100) NULL,
  local_novo  VARCHAR(100) NULL,
  eq1_atual   VARCHAR(100) NULL,
  eq2_atual   VARCHAR(100) NULL,
  eq1_novo    VARCHAR(100) NULL,
  eq2_novo    VARCHAR(100) NULL,
  modalidade  VARCHAR(100) NOT NULL,
  categoria   VARCHAR(50)  NOT NULL,
  genero      VARCHAR(20)  NOT NULL,
  jogo_id     INT          NULL,
  KEY ix_mapa_atual (tab_atual),
  KEY ix_mapa_novo (tab_novo)
);

INSERT INTO mapa_db26
  (tab_atual, tab_novo, acao, data_atual, data_nova, local_atual, local_novo,
   eq1_atual, eq2_atual, eq1_novo, eq2_novo, modalidade, categoria, genero)
VALUES
  (1, 1, 'MANTER', '2026-11-18 14:30:00', '2026-11-18 14:30:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'MARIA DA GLORIA', 'FRANCISCO AMORIM', 'MARIA DA GLORIA', 'FRANCISCO AMORIM', 'Baleado', 'Sub 11', 'MASCULINO'),
  (2, 2, 'MANTER', '2026-11-18 15:10:00', '2026-11-18 15:10:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'Conveniada', 'ADELIETA RAMALHO', 'Conveniada', 'ADELIETA RAMALHO', 'Baleado', 'Sub 13', 'MASCULINO'),
  (3, 3, 'MANTER', '2026-11-18 15:50:00', '2026-11-18 15:50:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'ADELIETA RAMALHO', 'PORTAL DO SABER', 'ADELIETA RAMALHO', 'PORTAL DO SABER', 'Baleado', 'Sub 13', 'FEMININO'),
  (4, 4, 'MANTER', '2026-11-18 16:30:00', '2026-11-18 16:30:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CEBN', 'CEJA', 'CEBN', 'CEJA', 'Handebol', 'Sub 17', 'FEMININO'),
  (5, 5, 'MANTER', '2026-11-18 17:10:00', '2026-11-18 17:10:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CEJA', 'CETI', 'CEJA', 'CETI', 'Baleado', 'Sub 17', 'MASCULINO'),
  (6, 6, 'MANTER', '2026-11-18 17:50:00', '2026-11-18 17:50:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CEJA', 'CEBC', 'CEJA', 'CEBC', 'Futsal', 'Aberto', 'MASCULINO'),
  (7, 7, 'MANTER', '2026-11-18 18:30:00', '2026-11-18 18:30:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'LUCIA ROCHA', 'VITORIA LIMA', 'LUCIA ROCHA', 'VITORIA LIMA', 'Futsal', 'Sub 17', 'MASCULINO'),
  (8, 8, 'MANTER', '2026-11-18 19:20:00', '2026-11-18 19:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CETI', 'CEBC', 'CETI', 'CEBC', 'Futsal', 'Sub 17', 'MASCULINO'),
  (9, 9, 'MANTER', '2026-11-18 20:00:00', '2026-11-18 20:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CEJA', 'LUCIA ROCHA', 'CEJA', 'LUCIA ROCHA', 'Futsal', 'Aberto', 'MASCULINO'),
  (10, 10, 'MANTER', '2026-11-18 20:40:00', '2026-11-18 20:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'MANOEL RAMOS', 'VITORIA LIMA', 'MANOEL RAMOS', 'VITORIA LIMA', 'Futsal', 'Aberto', 'MASCULINO'),
  (11, 11, 'MANTER', '2026-11-18 14:30:00', '2026-11-18 14:30:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'MANOEL RAMOS', 'ADELIETA RAMALHO', 'MANOEL RAMOS', 'ADELIETA RAMALHO', 'Baleado', 'Sub 11', 'MASCULINO'),
  (12, 12, 'MANTER', '2026-11-18 15:10:00', '2026-11-18 15:10:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'EMILIANO ZAPATA', 'MANOEL RAMOS', 'EMILIANO ZAPATA', 'MANOEL RAMOS', 'Baleado', 'Sub 13', 'MASCULINO'),
  (13, 13, 'MANTER', '2026-11-18 15:50:00', '2026-11-18 15:50:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'CEJA', 'ADELIETA RAMALHO', 'CEJA', 'ADELIETA RAMALHO', 'Handebol', 'Sub 11', 'MASCULINO'),
  (14, 14, 'MANTER', '2026-11-18 16:30:00', '2026-11-18 16:30:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'CEBC', 'JOSE DIAS', 'CEBC', 'JOSE DIAS', 'Handebol', 'Sub 11', 'MASCULINO'),
  (15, 15, 'MANTER', '2026-11-18 14:20:00', '2026-11-18 14:20:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'ADELIETA RAMALHO', 'MARLENE SANTANA', 'ADELIETA RAMALHO', 'MARLENE SANTANA', 'Baleado', 'Sub 9', 'MASCULINO'),
  (16, 16, 'MANTER', '2026-11-18 14:40:00', '2026-11-18 14:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'TEODULO LEITE', 'MARIA DA GLORIA', 'TEODULO LEITE', 'MARIA DA GLORIA', 'Baleado', 'Sub 9', 'MASCULINO'),
  (17, 17, 'MANTER', '2026-11-18 15:20:00', '2026-11-18 15:20:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'CEJA', 'MARIA DA GLORIA', 'CEJA', 'MARIA DA GLORIA', 'Baleado', 'Sub 13', 'FEMININO'),
  (18, 18, 'MANTER', '2026-11-18 15:40:00', '2026-11-18 15:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'EMILIANO ZAPATA', 'JOSE DIAS', 'EMILIANO ZAPATA', 'JOSE DIAS', 'Baleado', 'Sub 13', 'FEMININO'),
  (19, 19, 'MANTER', '2026-11-18 16:00:00', '2026-11-18 16:00:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'CEBN', 'Conveniada', 'CEBN', 'Conveniada', 'Baleado', 'Sub 13', 'FEMININO'),
  (20, 20, 'MANTER', '2026-11-18 16:20:00', '2026-11-18 16:20:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'JOSENILDO LEITE', 'CEBC', 'JOSENILDO LEITE', 'CEBC', 'Baleado', 'Sub 13', 'MASCULINO'),
  (21, 21, 'MANTER', '2026-11-18 16:40:00', '2026-11-18 16:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'CEJA', 'CEBC', 'CEJA', 'CEBC', 'Handebol', 'Sub 13', 'MASCULINO'),
  (22, 22, 'MANTER', '2026-11-18 14:30:00', '2026-11-18 14:30:00', 'Quadra do CEJA', 'Quadra do CEJA', 'CEJA', 'JOSE DIAS', 'CEJA', 'JOSE DIAS', 'Futsal', 'Sub 15', 'MASCULINO'),
  (23, 23, 'MANTER', '2026-11-18 15:10:00', '2026-11-18 15:10:00', 'Quadra do CEJA', 'Quadra do CEJA', 'CEBC', 'MANOEL RAMOS', 'CEBC', 'MANOEL RAMOS', 'Futsal', 'Sub 15', 'MASCULINO'),
  (24, 24, 'MANTER', '2026-11-18 15:50:00', '2026-11-18 15:50:00', 'Quadra do CEJA', 'Quadra do CEJA', 'CEJA', 'JOSE DIAS', 'CEJA', 'JOSE DIAS', 'Futsal', 'Sub 17', 'MASCULINO'),
  (25, 25, 'MANTER', '2026-11-18 16:30:00', '2026-11-18 16:30:00', 'Quadra do CEJA', 'Quadra do CEJA', 'EMILIANO ZAPATA', 'JOSENILDO LEITE', 'EMILIANO ZAPATA', 'JOSENILDO LEITE', 'Futsal', 'Sub 17', 'MASCULINO'),
  (26, 26, 'MANTER', '2026-11-18 14:30:00', '2026-11-18 14:30:00', 'Quadra do CETI', 'Quadra do CETI', 'JOSE DIAS', 'ACM', 'JOSE DIAS', 'ACM', 'Futsal', 'Sub 7', 'MASCULINO'),
  (27, 27, 'ALTERAR', '2026-11-18 16:30:00', '2026-11-18 15:10:00', 'Quadra do CETI', 'Quadra do CETI', 'EMILIANO ZAPATA', 'JOSE DIAS', 'EMILIANO ZAPATA', 'JOSE DIAS', 'Futsal', 'Sub 9', 'MASCULINO'),
  (28, 28, 'MANTER', '2026-11-18 15:50:00', '2026-11-18 15:50:00', 'Quadra do CETI', 'Quadra do CETI', 'MARLENE SANTANA', 'ADELIETA RAMALHO', 'MARLENE SANTANA', 'ADELIETA RAMALHO', 'Futsal', 'Sub 9', 'MASCULINO'),
  (29, 29, 'ALTERAR', '2026-11-18 15:10:00', '2026-11-18 16:30:00', 'Quadra do CETI', 'Quadra do CETI', 'ADELIETA RAMALHO', 'TEODULO LEITE', 'ADELIETA RAMALHO', 'TEODULO LEITE', 'Futsal', 'Sub 7', 'MASCULINO'),
  (30, 30, 'MANTER', '2026-11-18 14:30:00', '2026-11-18 14:30:00', 'Quadra do CEBC', 'Quadra do CEBC', 'MARLENE SANTANA', 'CEBC', 'MARLENE SANTANA', 'CEBC', 'Futsal', 'Sub 11', 'MASCULINO'),
  (31, 31, 'MANTER', '2026-11-18 15:10:00', '2026-11-18 15:10:00', 'Quadra do CEBC', 'Quadra do CEBC', 'JOSENILDO LEITE', 'MARIA DA GLORIA', 'JOSENILDO LEITE', 'MARIA DA GLORIA', 'Futsal', 'Sub 11', 'MASCULINO'),
  (32, 32, 'MANTER', '2026-11-18 15:50:00', '2026-11-18 15:50:00', 'Quadra do CEBC', 'Quadra do CEBC', 'EMILIANO ZAPATA', 'PORTAL DO SABER', 'EMILIANO ZAPATA', 'PORTAL DO SABER', 'Futsal', 'Sub 11', 'MASCULINO'),
  (33, 33, 'MANTER', '2026-11-18 16:30:00', '2026-11-18 16:30:00', 'Quadra do CEBC', 'Quadra do CEBC', 'ADELIETA RAMALHO', 'FRANCISCO AMORIM', 'ADELIETA RAMALHO', 'FRANCISCO AMORIM', 'Handebol', 'Sub 9', 'MASCULINO'),
  (34, 34, 'MANTER', '2026-11-18 17:10:00', '2026-11-18 17:10:00', 'Quadra do CEBC', 'Quadra do CEBC', 'CEBC', 'CEJA', 'CEBC', 'CEJA', 'Basquete', 'Sub 15', 'FEMININO'),
  (35, 35, 'MANTER', '2026-11-18 15:00:00', '2026-11-18 15:00:00', 'Campo Society Arena Social', 'Campo Society Arena Social', 'CEJA', 'JOSE DIAS', 'CEJA', 'JOSE DIAS', 'Futebol Society', 'Sub 15', 'MASCULINO'),
  (NULL, 36, 'INCLUIR', NULL, '2026-11-18 15:40:00', NULL, 'Campo Society Arena Social', NULL, NULL, 'CEBN', 'CEBC', 'Futebol Society', 'Sub 15', 'MASCULINO'),
  (NULL, 37, 'INCLUIR', NULL, '2026-11-18 16:20:00', NULL, 'Campo Society Arena Social', NULL, NULL, 'CEBC', 'VITORIA LIMA', 'Futebol Society', 'Sub 17', 'MASCULINO'),
  (38, 38, 'MANTER', '2026-11-19 08:00:00', '2026-11-19 08:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'FRANCISCO AMORIM', 'EMILIANO ZAPATA', 'FRANCISCO AMORIM', 'EMILIANO ZAPATA', 'Baleado', 'Sub 11', 'MASCULINO'),
  (39, 39, 'MANTER', '2026-11-19 08:40:00', '2026-11-19 08:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'MARLENE SANTANA', 'MANOEL RAMOS', 'MARLENE SANTANA', 'MANOEL RAMOS', 'Baleado', 'Sub 11', 'MASCULINO'),
  (40, 40, 'MANTER', '2026-11-19 09:20:00', '2026-11-19 09:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CEBC', 'CEJA', 'CEBC', 'CEJA', 'Baleado', 'Sub 13', 'MASCULINO'),
  (41, 41, 'MANTER', '2026-11-19 10:00:00', '2026-11-19 10:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CEBN', 'Conveniada', 'CEBN', 'Conveniada', 'Baleado', 'Sub 13', 'MASCULINO'),
  (42, 42, 'MANTER', '2026-11-19 10:40:00', '2026-11-19 10:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CETI', 'VITORIA LIMA', 'CETI', 'VITORIA LIMA', 'Futsal', 'Sub 17', 'FEMININO'),
  (NULL, 43, 'INCLUIR', NULL, '2026-11-19 11:20:00', NULL, 'Ginásio de Esportes', NULL, NULL, 'MANOEL RAMOS', 'EMILIANO ZAPATA', 'Futsal', 'Sub 15', 'MASCULINO'),
  (44, 44, 'MANTER', '2026-11-19 12:00:00', '2026-11-19 12:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'JOSENILDO LEITE', 'Conveniada', 'JOSENILDO LEITE', 'Conveniada', 'Futsal', 'Sub 15', 'MASCULINO'),
  (45, 45, 'MANTER', '2026-11-19 12:40:00', '2026-11-19 12:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CEBC', 'EMILIANO ZAPATA', 'CEBC', 'EMILIANO ZAPATA', 'Futsal', 'Sub 13', 'MASCULINO'),
  (46, 46, 'MANTER', '2026-11-19 13:20:00', '2026-11-19 13:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'JOSENILDO LEITE', 'CEJA', 'JOSENILDO LEITE', 'CEJA', 'Futsal', 'Sub 13', 'MASCULINO'),
  (47, 47, 'MANTER', '2026-11-19 14:00:00', '2026-11-19 14:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CEBN', 'Conveniada', 'CEBN', 'Conveniada', 'Futsal', 'Sub 13', 'MASCULINO'),
  (48, 48, 'MANTER', '2026-11-19 14:40:00', '2026-11-19 14:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'JOSE DIAS', 'ADELIETA RAMALHO', 'JOSE DIAS', 'ADELIETA RAMALHO', 'Baleado', 'Sub 11', 'MASCULINO'),
  (49, 49, 'MANTER', '2026-11-19 15:20:00', '2026-11-19 15:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CEJA', 'JOSENILDO LEITE', 'CEJA', 'JOSENILDO LEITE', 'Baleado', 'Sub 13', 'MASCULINO'),
  (50, 50, 'MANTER', '2026-11-19 16:00:00', '2026-11-19 16:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'ADELIETA RAMALHO', 'CEBN', 'ADELIETA RAMALHO', 'CEBN', 'Baleado', 'Sub 13', 'MASCULINO'),
  (51, 51, 'MANTER', '2026-11-19 16:40:00', '2026-11-19 16:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CETI', 'CEJA', 'CETI', 'CEJA', 'Baleado', 'Sub 17', 'FEMININO'),
  (52, 52, 'MANTER', '2026-11-19 17:20:00', '2026-11-19 17:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CETI', 'CEJA', 'CETI', 'CEJA', 'Handebol', 'Aberto', 'MASCULINO'),
  (53, 53, 'MANTER', '2026-11-19 18:00:00', '2026-11-19 18:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CETI', 'VITORIA LIMA', 'CETI', 'VITORIA LIMA', 'Futsal', 'Aberto', 'MASCULINO'),
  (54, 54, 'MANTER', '2026-11-19 18:40:00', '2026-11-19 18:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'LUCIA ROCHA', 'CETI', 'LUCIA ROCHA', 'CETI', 'Futsal', 'Aberto', 'FEMININO'),
  (55, 55, 'MANTER', '2026-11-19 19:20:00', '2026-11-19 19:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'JOSE DIAS', 'JOSENILDO LEITE', 'JOSE DIAS', 'JOSENILDO LEITE', 'Futsal', 'Sub 17', 'MASCULINO'),
  (56, 56, 'MANTER', '2026-11-19 20:00:00', '2026-11-19 20:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CETI', 'MANOEL RAMOS', 'CETI', 'MANOEL RAMOS', 'Futsal', 'Aberto', 'MASCULINO'),
  (57, 57, 'MANTER', '2026-11-19 20:40:00', '2026-11-19 20:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'LUCIA ROCHA', 'CEBC', 'LUCIA ROCHA', 'CEBC', 'Futsal', 'Aberto', 'MASCULINO'),
  (58, 58, 'MANTER', '2026-11-19 08:00:00', '2026-11-19 08:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'CEBN', 'ADELIETA RAMALHO', 'CEBN', 'ADELIETA RAMALHO', 'Baleado', 'Sub 13', 'FEMININO'),
  (59, 59, 'MANTER', '2026-11-19 08:40:00', '2026-11-19 08:40:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'CEBC', 'EMILIANO ZAPATA', 'CEBC', 'EMILIANO ZAPATA', 'Baleado', 'Sub 13', 'FEMININO'),
  (60, 60, 'MANTER', '2026-11-19 09:20:00', '2026-11-19 09:20:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'CEJA', 'MANOEL RAMOS', 'CEJA', 'MANOEL RAMOS', 'Baleado', 'Sub 13', 'FEMININO'),
  (61, 61, 'MANTER', '2026-11-19 10:00:00', '2026-11-19 10:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'JOSE DIAS', 'FRANCISCO AMORIM', 'JOSE DIAS', 'FRANCISCO AMORIM', 'Handebol', 'Sub 11', 'MASCULINO'),
  (62, 62, 'MANTER', '2026-11-19 10:40:00', '2026-11-19 10:40:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'ADELIETA RAMALHO', 'MARIA DA GLORIA', 'ADELIETA RAMALHO', 'MARIA DA GLORIA', 'Handebol', 'Sub 11', 'MASCULINO'),
  (63, 63, 'MANTER', '2026-11-19 11:20:00', '2026-11-19 11:20:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'CEJA', 'CEBN', 'CEJA', 'CEBN', 'Futsal', 'Sub 13', 'FEMININO'),
  (64, 64, 'MANTER', '2026-11-19 12:00:00', '2026-11-19 12:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'CEBN', 'EMILIANO ZAPATA', 'CEBN', 'EMILIANO ZAPATA', 'Futsal', 'Sub 15', 'FEMININO'),
  (65, 65, 'MANTER', '2026-11-19 12:40:00', '2026-11-19 12:40:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'CEBC', 'Conveniada', 'CEBC', 'Conveniada', 'Futsal', 'Sub 15', 'FEMININO'),
  (66, 66, 'MANTER', '2026-11-19 13:20:00', '2026-11-19 13:20:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'FRANCISCO AMORIM', 'MARIA DA GLORIA', 'FRANCISCO AMORIM', 'MARIA DA GLORIA', 'Futsal', 'Sub 11', 'MASCULINO'),
  (67, 67, 'MANTER', '2026-11-19 14:00:00', '2026-11-19 14:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'CEBN', 'Conveniada', 'CEBN', 'Conveniada', 'Handebol', 'Sub 13', 'MASCULINO'),
  (68, 68, 'MANTER', '2026-11-19 14:40:00', '2026-11-19 14:40:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'ACM', 'ADELIETA RAMALHO', 'ACM', 'ADELIETA RAMALHO', 'Handebol', 'Sub 8', 'MASCULINO'),
  (69, 69, 'MANTER', '2026-11-19 15:20:00', '2026-11-19 15:20:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'FRANCISCO AMORIM', 'MARIA DA GLORIA', 'FRANCISCO AMORIM', 'MARIA DA GLORIA', 'Handebol', 'Sub 11', 'FEMININO'),
  (70, 70, 'MANTER', '2026-11-19 16:00:00', '2026-11-19 16:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'JOSE DIAS', 'MARLENE SANTANA', 'JOSE DIAS', 'MARLENE SANTANA', 'Handebol', 'Sub 11', 'FEMININO'),
  (72, 71, 'RENUMERAR', '2026-11-19 08:00:00', '2026-11-19 08:00:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'MARIA DA GLORIA', 'TEODULO LEITE', 'MARIA DA GLORIA', 'TEODULO LEITE', 'Futsal', 'Sub 9', 'MASCULINO'),
  (73, 72, 'RENUMERAR', '2026-11-19 08:40:00', '2026-11-19 08:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'MARLENE SANTANA', 'PORTAL DO SABER', 'MARLENE SANTANA', 'PORTAL DO SABER', 'Futsal', 'Sub 9', 'MASCULINO'),
  (74, 73, 'RENUMERAR', '2026-11-19 09:20:00', '2026-11-19 09:20:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'CEBC', 'JOSENILDO LEITE', 'CEBC', 'JOSENILDO LEITE', 'Baleado', 'Sub 17', 'MASCULINO'),
  (75, 74, 'RENUMERAR', '2026-11-19 10:00:00', '2026-11-19 10:00:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'MARIA DA GLORIA', 'EMILIANO ZAPATA', 'MARIA DA GLORIA', 'EMILIANO ZAPATA', 'Baleado', 'Sub 13', 'MASCULINO'),
  (76, 75, 'RENUMERAR', '2026-11-19 10:40:00', '2026-11-19 10:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'Conveniada', 'MANOEL RAMOS', 'Conveniada', 'MANOEL RAMOS', 'Baleado', 'Sub 15', 'MASCULINO'),
  (77, 76, 'RENUMERAR', '2026-11-19 11:20:00', '2026-11-19 11:20:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'CEBC', 'CEBN', 'CEBC', 'CEBN', 'Baleado', 'Sub 15', 'MASCULINO'),
  (78, 77, 'RENUMERAR', '2026-11-19 12:00:00', '2026-11-19 12:00:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'MARIA DA GLORIA', 'FRANCISCO AMORIM', 'MARIA DA GLORIA', 'FRANCISCO AMORIM', 'Baleado', 'Sub 9', 'MASCULINO'),
  (79, 78, 'RENUMERAR', '2026-11-19 12:40:00', '2026-11-19 12:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'CEBC', 'CEJA', 'CEBC', 'CEJA', 'Futsal', 'Sub 17', 'FEMININO'),
  (80, 79, 'RENUMERAR', '2026-11-19 13:20:00', '2026-11-19 13:20:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'EMILIANO ZAPATA', 'CEJA', 'EMILIANO ZAPATA', 'CEJA', 'Futsal', 'Sub 13', 'FEMININO'),
  (81, 80, 'RENUMERAR', '2026-11-19 14:00:00', '2026-11-19 14:00:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'JOSE DIAS', 'MARIA DA GLORIA', 'JOSE DIAS', 'MARIA DA GLORIA', 'Futsal', 'Sub 9', 'MASCULINO'),
  (82, 81, 'RENUMERAR', '2026-11-19 14:40:00', '2026-11-19 14:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'FRANCISCO AMORIM', 'PORTAL DO SABER', 'FRANCISCO AMORIM', 'PORTAL DO SABER', 'Futsal', 'Sub 9', 'MASCULINO'),
  (83, 82, 'RENUMERAR', '2026-11-19 15:20:00', '2026-11-19 15:20:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'MARIA DA GLORIA', 'MANOEL RAMOS', 'MARIA DA GLORIA', 'MANOEL RAMOS', 'Baleado', 'Sub 13', 'FEMININO'),
  (84, 83, 'RENUMERAR', '2026-11-19 16:00:00', '2026-11-19 16:00:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'JOSE DIAS', 'CEBC', 'JOSE DIAS', 'CEBC', 'Baleado', 'Sub 13', 'FEMININO'),
  (85, 84, 'RENUMERAR', '2026-11-19 16:40:00', '2026-11-19 16:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'PORTAL DO SABER', 'Conveniada', 'PORTAL DO SABER', 'Conveniada', 'Baleado', 'Sub 13', 'FEMININO'),
  (86, 85, 'RENUMERAR', '2026-11-19 08:00:00', '2026-11-19 08:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 'ADELIETA RAMALHO', 'CEJA', 'ADELIETA RAMALHO', 'CEJA', 'Futsal', 'Sub 11', 'MASCULINO'),
  (87, 86, 'RENUMERAR', '2026-11-19 08:40:00', '2026-11-19 08:40:00', 'Quadra do CEJA', 'Quadra do CEJA', 'JOSE DIAS', 'MARLENE SANTANA', 'JOSE DIAS', 'MARLENE SANTANA', 'Futsal', 'Sub 11', 'MASCULINO'),
  (88, 87, 'RENUMERAR', '2026-11-19 09:20:00', '2026-11-19 09:20:00', 'Quadra do CEJA', 'Quadra do CEJA', 'EMILIANO ZAPATA', 'CEJA', 'EMILIANO ZAPATA', 'CEJA', 'Futsal', 'Sub 17', 'MASCULINO'),
  (89, 88, 'RENUMERAR', '2026-11-19 10:00:00', '2026-11-19 10:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 'VITORIA LIMA', 'CETI', 'VITORIA LIMA', 'CETI', 'Futsal', 'Sub 17', 'MASCULINO'),
  (90, 89, 'RENUMERAR', '2026-11-19 10:40:00', '2026-11-19 10:40:00', 'Quadra do CEJA', 'Quadra do CEJA', 'LUCIA ROCHA', 'CEBC', 'LUCIA ROCHA', 'CEBC', 'Futsal', 'Sub 17', 'MASCULINO'),
  (91, 90, 'RENUMERAR', '2026-11-19 11:20:00', '2026-11-19 11:20:00', 'Quadra do CEJA', 'Quadra do CEJA', 'Conveniada', 'EMILIANO ZAPATA', 'Conveniada', 'EMILIANO ZAPATA', 'Baleado', 'Sub 15', 'FEMININO'),
  (92, 91, 'RENUMERAR', '2026-11-19 12:00:00', '2026-11-19 12:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 'CEBN', 'JOSENILDO LEITE', 'CEBN', 'JOSENILDO LEITE', 'Baleado', 'Sub 15', 'FEMININO'),
  (93, 92, 'RENUMERAR', '2026-11-19 12:40:00', '2026-11-19 12:40:00', 'Quadra do CEJA', 'Quadra do CEJA', 'PORTAL DO SABER', 'ADELIETA RAMALHO', 'PORTAL DO SABER', 'ADELIETA RAMALHO', 'Baleado', 'Sub 11', 'FEMININO'),
  (94, 93, 'RENUMERAR', '2026-11-19 13:20:00', '2026-11-19 13:20:00', 'Quadra do CEJA', 'Quadra do CEJA', 'JOSENILDO LEITE', 'FRANCISCO AMORIM', 'JOSENILDO LEITE', 'FRANCISCO AMORIM', 'Baleado', 'Sub 11', 'FEMININO'),
  (95, 94, 'RENUMERAR', '2026-11-19 14:00:00', '2026-11-19 14:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 'JOSE DIAS', 'CEJA', 'JOSE DIAS', 'CEJA', 'Baleado', 'Sub 11', 'FEMININO'),
  (96, 95, 'RENUMERAR', '2026-11-19 14:40:00', '2026-11-19 14:40:00', 'Quadra do CEJA', 'Quadra do CEJA', 'EMILIANO ZAPATA', 'MARIA DA GLORIA', 'EMILIANO ZAPATA', 'MARIA DA GLORIA', 'Baleado', 'Sub 11', 'FEMININO'),
  (97, 96, 'RENUMERAR', '2026-11-19 15:20:00', '2026-11-19 15:20:00', 'Quadra do CEJA', 'Quadra do CEJA', 'CEBC', 'ADELIETA RAMALHO', 'CEBC', 'ADELIETA RAMALHO', 'Handebol', 'Sub 13', 'MASCULINO'),
  (98, 97, 'RENUMERAR', '2026-11-19 16:00:00', '2026-11-19 16:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 'CEJA', 'CEBN', 'CEJA', 'CEBN', 'Handebol', 'Sub 15', 'MASCULINO'),
  (99, 98, 'RENUMERAR', '2026-11-19 08:00:00', '2026-11-19 08:00:00', 'Quadra do CEBC', 'Quadra do CEBC', 'ADELIETA RAMALHO', 'FRANCISCO AMORIM', 'ADELIETA RAMALHO', 'FRANCISCO AMORIM', 'Handebol', 'Sub 9', 'FEMININO'),
  (100, 99, 'RENUMERAR', '2026-11-19 08:40:00', '2026-11-19 08:40:00', 'Quadra do CEBC', 'Quadra do CEBC', 'JOSE DIAS', 'JOSENILDO LEITE', 'JOSE DIAS', 'JOSENILDO LEITE', 'Futsal', 'Sub 15', 'MASCULINO'),
  (101, 100, 'RENUMERAR', '2026-11-19 09:20:00', '2026-11-19 09:20:00', 'Quadra do CEBC', 'Quadra do CEBC', 'Conveniada', 'CEBC', 'Conveniada', 'CEBC', 'Basquete', 'Sub 15', 'FEMININO'),
  (NULL, 101, 'INCLUIR', NULL, '2026-11-19 10:00:00', NULL, 'Quadra do CEBC', NULL, NULL, 'CETI', 'CEJA', 'Basquete', 'Sub 17', 'FEMININO'),
  (211, 102, 'ALTERAR', '2026-11-20 09:20:00', '2026-11-19 10:40:00', 'Quadra do CEBC', 'Quadra do CEBC', 'Conveniada', 'CEJA', 'CEJA', 'CONVENIADA', 'Basquete', 'Sub 15', 'MASCULINO'),
  (104, 103, 'RENUMERAR', '2026-11-19 11:20:00', '2026-11-19 11:20:00', 'Quadra do CEBC', 'Quadra do CEBC', 'CETI', 'CEBC', 'CETI', 'CEBC', 'Basquete', 'Sub 17', 'MASCULINO'),
  (105, 104, 'RENUMERAR', '2026-11-19 12:00:00', '2026-11-19 12:00:00', 'Quadra do CEBC', 'Quadra do CEBC', 'CEJA', 'EMILIANO ZAPATA', 'CEJA', 'EMILIANO ZAPATA', 'Futsal', 'Sub 11', 'MASCULINO'),
  (106, 105, 'RENUMERAR', '2026-11-19 12:40:00', '2026-11-19 12:40:00', 'Quadra do CEBC', 'Quadra do CEBC', 'CEBC', 'JOSE DIAS', 'CEBC', 'JOSE DIAS', 'Futsal', 'Sub 11', 'MASCULINO'),
  (107, 106, 'RENUMERAR', '2026-11-19 13:20:00', '2026-11-19 13:20:00', 'Quadra do CEBC', 'Quadra do CEBC', 'Conveniada', 'JOSE DIAS', 'Conveniada', 'JOSE DIAS', 'Handebol', 'Sub 13', 'MASCULINO'),
  (108, 107, 'RENUMERAR', '2026-11-19 14:00:00', '2026-11-19 14:00:00', 'Quadra do CEBC', 'Quadra do CEBC', 'CETI', 'CEBC', 'CETI', 'CEBC', 'Handebol', 'Sub 17', 'MASCULINO'),
  (109, 108, 'RENUMERAR', '2026-11-19 14:40:00', '2026-11-19 14:40:00', 'Quadra do CEBC', 'Quadra do CEBC', 'CEJA', 'Conveniada', 'CEJA', 'Conveniada', 'Handebol', 'Sub 17', 'MASCULINO'),
  (110, 109, 'RENUMERAR', '2026-11-19 15:20:00', '2026-11-19 15:20:00', 'Quadra do CEBC', 'Quadra do CEBC', 'CETI', 'CEBN', 'CETI', 'CEBN', 'Handebol', 'Sub 17', 'FEMININO'),
  (71, 110, 'ALTERAR', '2026-11-19 16:40:00', '2026-11-19 16:00:00', 'Quadra da Adelieta Ramalho', 'Quadra do CEBC', 'CEBC', 'CEBN', 'CEBC', 'CEBN', 'Handebol', 'Sub 13', 'FEMININO'),
  (111, 111, 'ALTERAR', '2026-11-19 16:00:00', '2026-11-19 16:40:00', 'Quadra do CEBC', 'Quadra do CEBC', 'CEBC', 'CEJA', 'CEBC', 'CEJA', 'Basquete', 'Sub 17', 'MASCULINO'),
  (113, 112, 'RENUMERAR', '2026-11-19 08:00:00', '2026-11-19 08:00:00', 'Quadra do CETI', 'Quadra do CETI', 'MARLENE SANTANA', 'JOSE DIAS', 'MARLENE SANTANA', 'JOSE DIAS', 'Futsal', 'Sub 9', 'FEMININO'),
  (114, 113, 'RENUMERAR', '2026-11-19 08:40:00', '2026-11-19 08:40:00', 'Quadra do CETI', 'Quadra do CETI', 'JOSE DIAS', 'ADELIETA RAMALHO', 'JOSE DIAS', 'ADELIETA RAMALHO', 'Futsal', 'Sub 7', 'MASCULINO'),
  (115, 114, 'RENUMERAR', '2026-11-19 09:20:00', '2026-11-19 09:20:00', 'Quadra do CETI', 'Quadra do CETI', 'TEODULO LEITE', 'ACM', 'TEODULO LEITE', 'ACM', 'Futsal', 'Sub 7', 'MASCULINO'),
  (116, 115, 'RENUMERAR', '2026-11-19 10:00:00', '2026-11-19 10:00:00', 'Quadra do CETI', 'Quadra do CETI', 'CEBN', 'EMILIANO ZAPATA', 'CEBN', 'EMILIANO ZAPATA', 'Vôlei', 'Sub 17', 'MISTO'),
  (117, 116, 'RENUMERAR', '2026-11-19 10:40:00', '2026-11-19 10:40:00', 'Quadra do CETI', 'Quadra do CETI', 'CEJA', 'CEBN', 'CEJA', 'CEBN', 'Vôlei', 'Sub 15', 'MISTO'),
  (118, 117, 'RENUMERAR', '2026-11-19 11:20:00', '2026-11-19 11:20:00', 'Quadra do CETI', 'Quadra do CETI', 'EMILIANO ZAPATA', 'CETI', 'EMILIANO ZAPATA', 'CETI', 'Vôlei', 'Sub 17', 'MISTO'),
  (119, 118, 'RENUMERAR', '2026-11-19 12:00:00', '2026-11-19 12:00:00', 'Quadra do CETI', 'Quadra do CETI', 'LUCIA ROCHA', 'CEBC', 'LUCIA ROCHA', 'CEBC', 'Vôlei', 'Sub 17', 'MISTO'),
  (120, 119, 'RENUMERAR', '2026-11-19 12:40:00', '2026-11-19 12:40:00', 'Quadra do CETI', 'Quadra do CETI', 'CETI', 'CEBC', 'CETI', 'CEBC', 'Vôlei', 'Aberto', 'MASCULINO'),
  (121, 120, 'RENUMERAR', '2026-11-19 13:20:00', '2026-11-19 13:20:00', 'Quadra do CETI', 'Quadra do CETI', 'EMILIANO ZAPATA', 'CEBC', 'EMILIANO ZAPATA', 'CEBC', 'Vôlei', 'Sub 15', 'MISTO'),
  (122, 121, 'RENUMERAR', '2026-11-19 14:00:00', '2026-11-19 14:00:00', 'Quadra do CETI', 'Quadra do CETI', 'ADELIETA RAMALHO', 'JOSE DIAS', 'ADELIETA RAMALHO', 'JOSE DIAS', 'Futsal', 'Sub 8', 'MASCULINO'),
  (123, 122, 'RENUMERAR', '2026-11-19 14:40:00', '2026-11-19 14:40:00', 'Quadra do CETI', 'Quadra do CETI', 'TEODULO LEITE', 'MARLENE SANTANA', 'TEODULO LEITE', 'MARLENE SANTANA', 'Futsal', 'Sub 8', 'MASCULINO'),
  (124, 123, 'RENUMERAR', '2026-11-19 15:20:00', '2026-11-19 15:20:00', 'Quadra do CETI', 'Quadra do CETI', 'JOSE DIAS', 'EMILIANO ZAPATA', 'JOSE DIAS', 'EMILIANO ZAPATA', 'Futsal', 'Sub 8', 'FEMININO'),
  (125, 124, 'RENUMERAR', '2026-11-19 16:00:00', '2026-11-19 16:00:00', 'Quadra do CETI', 'Quadra do CETI', 'JOSE DIAS', 'MARLENE SANTANA', 'JOSE DIAS', 'MARLENE SANTANA', 'Futsal', 'Sub 11', 'FEMININO'),
  (126, 125, 'ALTERAR', '2026-11-19 08:00:00', '2026-11-19 08:30:00', 'Campo Society Arena Social', 'Campo Society Arena Social', 'CEJA', 'CEBC', 'CEJA', 'CEBC', 'Futebol Society', 'Sub 13', 'MASCULINO'),
  (NULL, 126, 'INCLUIR', NULL, '2026-11-19 09:10:00', NULL, 'Campo Society Arena Social', NULL, NULL, 'CETI', 'CEBC', 'Futebol Society', 'Sub 17', 'MASCULINO'),
  (128, 127, 'ALTERAR', '2026-11-19 09:20:00', '2026-11-19 09:50:00', 'Campo Society Arena Social', 'Campo Society Arena Social', 'JOSE DIAS', 'Conveniada', 'JOSE DIAS', 'CONVENIADA', 'Futebol Society', 'Sub 15', 'MASCULINO'),
  (130, 128, 'RENUMERAR', '2026-11-19 14:00:00', '2026-11-19 14:00:00', 'Campo Society Arena Social', 'Campo Society Arena Social', 'CEBC', 'CEBN', 'CEBC', 'CEBN', 'Futebol Society', 'Sub 15', 'MASCULINO'),
  (131, 129, 'RENUMERAR', '2026-11-19 14:40:00', '2026-11-19 14:40:00', 'Campo Society Arena Social', 'Campo Society Arena Social', 'MARIA DA GLORIA', 'CEBN', 'MARIA DA GLORIA', 'CEBN', 'Futebol Society', 'Sub 13', 'MASCULINO'),
  (NULL, 130, 'INCLUIR', NULL, '2026-11-19 15:20:00', NULL, 'Campo Society Arena Social', NULL, NULL, 'CEJA', 'VITORIA LIMA', 'Futebol Society', 'Sub 17', 'MASCULINO'),
  (133, 131, 'RENUMERAR', '2026-11-20 08:00:00', '2026-11-20 08:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'EMILIANO ZAPATA', 'MARIA DA GLORIA', 'EMILIANO ZAPATA', 'MARIA DA GLORIA', 'Baleado', 'Sub 11', 'MASCULINO'),
  (134, 132, 'RENUMERAR', '2026-11-20 08:40:00', '2026-11-20 08:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'JOSE DIAS', 'MARLENE SANTANA', 'JOSE DIAS', 'MARLENE SANTANA', 'Baleado', 'Sub 11', 'MASCULINO'),
  (135, 133, 'RENUMERAR', '2026-11-20 09:20:00', '2026-11-20 09:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CEJA', 'MARIA DA GLORIA', 'CEJA', 'MARIA DA GLORIA', 'Handebol', 'Sub 11', 'MASCULINO'),
  (136, 134, 'RENUMERAR', '2026-11-20 10:00:00', '2026-11-20 10:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CEBC', 'FRANCISCO AMORIM', 'CEBC', 'FRANCISCO AMORIM', 'Handebol', 'Sub 11', 'MASCULINO'),
  (137, 135, 'RENUMERAR', '2026-11-20 10:40:00', '2026-11-20 10:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'EMILIANO ZAPATA', 'JOSENILDO LEITE', 'EMILIANO ZAPATA', 'JOSENILDO LEITE', 'Futsal', 'Sub 13', 'MASCULINO'),
  (138, 136, 'RENUMERAR', '2026-11-20 11:20:00', '2026-11-20 11:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CEBN', 'JOSE DIAS', 'CEBN', 'JOSE DIAS', 'Futsal', 'Sub 13', 'MASCULINO'),
  (139, 137, 'RENUMERAR', '2026-11-20 12:00:00', '2026-11-20 12:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CETI', 'CEJA', 'CETI', 'CEJA', 'Futsal', 'Sub 17', 'FEMININO'),
  (140, 138, 'RENUMERAR', '2026-11-20 12:40:00', '2026-11-20 12:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CEBC', 'VITORIA LIMA', 'CEBC', 'VITORIA LIMA', 'Futsal', 'Sub 17', 'FEMININO'),
  (141, 139, 'RENUMERAR', '2026-11-20 13:20:00', '2026-11-20 13:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CEBC', 'JOSENILDO LEITE', 'CEBC', 'JOSENILDO LEITE', 'Baleado', 'Sub 13', 'MASCULINO'),
  (146, 140, 'ALTERAR', '2026-11-20 17:20:00', '2026-11-20 14:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CETI', 'LUCIA ROCHA', 'CETI', 'LUCIA ROCHA', 'Handebol', 'Aberto', 'MASCULINO'),
  (142, 141, 'ALTERAR', '2026-11-20 14:40:00', '2026-11-20 15:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CEJA', 'Conveniada', 'CEJA', 'CONVENIADA', 'Baleado', 'Sub 15', 'FEMININO'),
  (143, 142, 'ALTERAR', '2026-11-20 15:20:00', '2026-11-20 16:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CEBN', 'CEBC', 'CEBN', 'CEBC', 'Baleado', 'Sub 15', 'FEMININO'),
  (144, 143, 'ALTERAR', '2026-11-20 16:00:00', '2026-11-20 16:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'Conveniada', 'CEBN', 'CONVENIADA', 'CEBN', 'Handebol', 'Sub 17', 'MASCULINO'),
  (145, 144, 'ALTERAR', '2026-11-20 16:40:00', '2026-11-20 17:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CEBC', 'CETI', 'CEBC', 'CETI', 'Handebol', 'Sub 17', 'MASCULINO'),
  (147, 145, 'RENUMERAR', '2026-11-20 18:00:00', '2026-11-20 18:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'VITORIA LIMA', 'CETI', 'VITORIA LIMA', 'CETI', 'Futsal', 'Aberto', 'FEMININO'),
  (152, 150, 'RENUMERAR', '2026-11-20 08:00:00', '2026-11-20 08:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'MARLENE SANTANA', 'ADELIETA RAMALHO', 'MARLENE SANTANA', 'ADELIETA RAMALHO', 'Handebol', 'Sub 11', 'FEMININO'),
  (153, 151, 'RENUMERAR', '2026-11-20 08:40:00', '2026-11-20 08:40:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'FRANCISCO AMORIM', 'JOSENILDO LEITE', 'FRANCISCO AMORIM', 'JOSENILDO LEITE', 'Futsal', 'Sub 11', 'MASCULINO'),
  (154, 152, 'RENUMERAR', '2026-11-20 09:20:00', '2026-11-20 09:20:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'EMILIANO ZAPATA', 'TEODULO LEITE', 'EMILIANO ZAPATA', 'TEODULO LEITE', 'Futsal', 'Sub 9', 'MASCULINO'),
  (155, 153, 'RENUMERAR', '2026-11-20 10:00:00', '2026-11-20 10:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'FRANCISCO AMORIM', 'ADELIETA RAMALHO', 'FRANCISCO AMORIM', 'ADELIETA RAMALHO', 'Futsal', 'Sub 9', 'MASCULINO'),
  (156, 154, 'RENUMERAR', '2026-11-20 10:40:00', '2026-11-20 10:40:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'ADELIETA RAMALHO', 'PORTAL DO SABER', 'ADELIETA RAMALHO', 'PORTAL DO SABER', 'Futsal', 'Sub 11', 'MASCULINO'),
  (157, 155, 'RENUMERAR', '2026-11-20 11:20:00', '2026-11-20 11:20:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'CEBN', 'EMILIANO ZAPATA', 'CEBN', 'EMILIANO ZAPATA', 'Futsal', 'Sub 13', 'FEMININO'),
  (158, 156, 'RENUMERAR', '2026-11-20 12:00:00', '2026-11-20 12:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'ADELIETA RAMALHO', 'JOSE DIAS', 'ADELIETA RAMALHO', 'JOSE DIAS', 'Handebol', 'Sub 8', 'MASCULINO'),
  (159, 157, 'ALTERAR', '2026-11-20 13:20:00', '2026-11-20 12:40:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'ADELIETA RAMALHO', 'CEJA', 'ADELIETA RAMALHO', 'CEJA', 'Handebol', 'Sub 13', 'MASCULINO'),
  (160, 158, 'ALTERAR', '2026-11-20 14:00:00', '2026-11-20 13:20:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'MANOEL RAMOS', 'MARIA DA GLORIA', 'MANOEL RAMOS', 'MARIA DA GLORIA', 'Baleado', 'Sub 13', 'MASCULINO'),
  (161, 159, 'ALTERAR', '2026-11-20 14:40:00', '2026-11-20 14:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'FRANCISCO AMORIM', 'CEBC', 'FRANCISCO AMORIM', 'CEBC', 'Handebol', 'Sub 11', 'MASCULINO'),
  (162, 160, 'ALTERAR', '2026-11-20 15:20:00', '2026-11-20 14:40:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'MARIA DA GLORIA', 'CEJA', 'MARIA DA GLORIA', 'CEJA', 'Handebol', 'Sub 11', 'FEMININO'),
  (163, 161, 'ALTERAR', '2026-11-20 16:00:00', '2026-11-20 15:20:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'CEBN', 'Conveniada', 'CEBN', 'CONVENIADA', 'Handebol', 'Sub 15', 'FEMININO'),
  (164, 162, 'ALTERAR', '2026-11-20 16:40:00', '2026-11-20 16:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'CEBC', 'CEJA', 'CEBC', 'CEJA', 'Handebol', 'Sub 15', 'FEMININO'),
  (165, 163, 'RENUMERAR', '2026-11-20 08:00:00', '2026-11-20 08:00:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'MARIA DA GLORIA', 'JOSE DIAS', 'MARIA DA GLORIA', 'JOSE DIAS', 'Baleado', 'Sub 11', 'FEMININO'),
  (166, 164, 'RENUMERAR', '2026-11-20 08:40:00', '2026-11-20 08:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'ACM', 'MARLENE SANTANA', 'ACM', 'MARLENE SANTANA', 'Baleado', 'Sub 8', 'MASCULINO'),
  (167, 165, 'RENUMERAR', '2026-11-20 09:20:00', '2026-11-20 09:20:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'ACM', 'JOSE DIAS', 'ACM', 'JOSE DIAS', 'Baleado', 'Sub 8', 'FEMININO'),
  (168, 166, 'RENUMERAR', '2026-11-20 10:00:00', '2026-11-20 10:00:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'MARIA DA GLORIA', 'PORTAL DO SABER', 'MARIA DA GLORIA', 'PORTAL DO SABER', 'Baleado', 'Sub 9', 'FEMININO'),
  (169, 167, 'RENUMERAR', '2026-11-20 10:40:00', '2026-11-20 10:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'MARLENE SANTANA', 'JOSE DIAS', 'MARLENE SANTANA', 'JOSE DIAS', 'Baleado', 'Sub 9', 'MASCULINO'),
  (170, 168, 'RENUMERAR', '2026-11-20 11:20:00', '2026-11-20 11:20:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'EMILIANO ZAPATA', 'ADELIETA RAMALHO', 'EMILIANO ZAPATA', 'ADELIETA RAMALHO', 'Baleado', 'Sub 9', 'FEMININO'),
  (171, 169, 'RENUMERAR', '2026-11-20 12:00:00', '2026-11-20 12:00:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'EMILIANO ZAPATA', 'CEJA', 'EMILIANO ZAPATA', 'CEJA', 'Vôlei', 'Sub 15', 'MISTO'),
  (172, 170, 'RENUMERAR', '2026-11-20 12:40:00', '2026-11-20 12:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'LUCIA ROCHA', 'CEBC', 'LUCIA ROCHA', 'CEBC', 'Vôlei', 'Aberto', 'MASCULINO'),
  (173, 171, 'RENUMERAR', '2026-11-20 13:20:00', '2026-11-20 13:20:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'CETI', 'CEBN', 'CETI', 'CEBN', 'Vôlei', 'Sub 17', 'MISTO'),
  (174, 172, 'RENUMERAR', '2026-11-20 14:00:00', '2026-11-20 14:00:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'CEBC', 'CEBN', 'CEBC', 'CEBN', 'Vôlei', 'Sub 15', 'MISTO'),
  (175, 173, 'RENUMERAR', '2026-11-20 14:40:00', '2026-11-20 14:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'FRANCISCO AMORIM', 'MARIA DA GLORIA', 'FRANCISCO AMORIM', 'MARIA DA GLORIA', 'Baleado', 'Sub 9', 'FEMININO'),
  (179, 177, 'RENUMERAR', '2026-11-20 08:00:00', '2026-11-20 08:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 'CEJA', 'CEBN', 'CEJA', 'CEBN', 'Futsal', 'Sub 15', 'FEMININO'),
  (180, 178, 'RENUMERAR', '2026-11-20 08:40:00', '2026-11-20 08:40:00', 'Quadra do CEJA', 'Quadra do CEJA', 'Conveniada', 'JOSE DIAS', 'Conveniada', 'JOSE DIAS', 'Futsal', 'Sub 15', 'FEMININO'),
  (181, 179, 'RENUMERAR', '2026-11-20 09:20:00', '2026-11-20 09:20:00', 'Quadra do CEJA', 'Quadra do CEJA', 'CEBC', 'EMILIANO ZAPATA', 'CEBC', 'EMILIANO ZAPATA', 'Futsal', 'Sub 15', 'MASCULINO'),
  (182, 180, 'RENUMERAR', '2026-11-20 10:00:00', '2026-11-20 10:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 'CEJA', 'Conveniada', 'CEJA', 'Conveniada', 'Futsal', 'Sub 15', 'MASCULINO'),
  (183, 181, 'RENUMERAR', '2026-11-20 10:40:00', '2026-11-20 10:40:00', 'Quadra do CEJA', 'Quadra do CEJA', 'CEJA', 'EMILIANO ZAPATA', 'CEJA', 'EMILIANO ZAPATA', 'Baleado', 'Sub 11', 'FEMININO'),
  (184, 182, 'RENUMERAR', '2026-11-20 11:20:00', '2026-11-20 11:20:00', 'Quadra do CEJA', 'Quadra do CEJA', 'CEJA', 'CEBC', 'CEJA', 'CEBC', 'Baleado', 'Sub 15', 'MASCULINO'),
  (185, 183, 'RENUMERAR', '2026-11-20 12:00:00', '2026-11-20 12:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 'CEBN', 'CEJA', 'CEBN', 'CEJA', 'Handebol', 'Sub 13', 'FEMININO'),
  (186, 184, 'RENUMERAR', '2026-11-20 12:40:00', '2026-11-20 12:40:00', 'Quadra do CEJA', 'Quadra do CEJA', 'CEBN', 'JOSE DIAS', 'CEBN', 'JOSE DIAS', 'Handebol', 'Sub 13', 'MASCULINO'),
  (187, 185, 'RENUMERAR', '2026-11-20 13:20:00', '2026-11-20 13:20:00', 'Quadra do CEJA', 'Quadra do CEJA', 'CEJA', 'CETI', 'CEJA', 'CETI', 'Handebol', 'Sub 17', 'FEMININO'),
  (188, 186, 'RENUMERAR', '2026-11-20 14:00:00', '2026-11-20 14:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 'CEBC', 'LUCIA ROCHA', 'CEBC', 'LUCIA ROCHA', 'Baleado', 'Sub 17', 'FEMININO'),
  (189, 187, 'RENUMERAR', '2026-11-20 14:40:00', '2026-11-20 14:40:00', 'Quadra do CEJA', 'Quadra do CEJA', 'JOSE DIAS', 'Conveniada', 'JOSE DIAS', 'Conveniada', 'Futsal', 'Sub 13', 'MASCULINO'),
  (190, 188, 'RENUMERAR', '2026-11-20 15:20:00', '2026-11-20 15:20:00', 'Quadra do CEJA', 'Quadra do CEJA', 'CEJA', 'CEBC', 'CEJA', 'CEBC', 'Futsal', 'Sub 13', 'MASCULINO'),
  (266, 189, 'ALTERAR', '2026-11-21 10:00:00', '2026-11-20 16:00:00', 'Quadra do CEBC', 'Quadra do CEJA', 'CEBN', 'CEBC', 'CEBN', 'CEBC', 'Handebol', 'Sub 17', 'FEMININO'),
  (192, 190, 'ALTERAR', '2026-11-20 08:00:00', '2026-11-20 08:40:00', 'Campo Society do CETI', 'Campo Society do CETI', 'Conveniada', 'CEJA', 'CONVENIADA', 'CEJA', 'Futebol Society', 'Sub 13', 'MASCULINO'),
  (193, 191, 'ALTERAR', '2026-11-20 08:40:00', '2026-11-20 09:20:00', 'Campo Society do CETI', 'Campo Society do CETI', 'Conveniada', 'CEJA', 'CONVENIADA', 'CEJA', 'Futebol Society', 'Sub 15', 'MASCULINO'),
  (NULL, 192, 'INCLUIR', NULL, '2026-11-20 10:00:00', NULL, 'Campo Society do CETI', NULL, NULL, 'CEJA', 'CETI', 'Futebol Society', 'Sub 17', 'MASCULINO'),
  (196, 193, 'ALTERAR', '2026-11-20 14:40:00', '2026-11-20 15:00:00', 'Campo Society do CETI', 'Campo Society do CETI', 'MARIA DA GLORIA', 'CEBN', 'MARIA DA GLORIA', 'CEBN', 'Futebol Society', 'Sub 13', 'MASCULINO'),
  (197, 194, 'ALTERAR', '2026-11-20 15:20:00', '2026-11-20 15:40:00', 'Campo Society do CETI', 'Campo Society do CETI', 'CEBC', 'Conveniada', 'CEBC', 'CONVENIADA', 'Futebol Society', 'Sub 13', 'MASCULINO'),
  (200, 195, 'RENUMERAR', '2026-11-20 08:00:00', '2026-11-20 08:00:00', 'Quadra do CETI', 'Quadra do CETI', 'MARLENE SANTANA', 'ACM', 'MARLENE SANTANA', 'ACM', 'Futsal', 'Sub 8', 'MASCULINO'),
  (201, 196, 'RENUMERAR', '2026-11-20 08:40:00', '2026-11-20 08:40:00', 'Quadra do CETI', 'Quadra do CETI', 'JOSE DIAS', 'ADELIETA RAMALHO', 'JOSE DIAS', 'ADELIETA RAMALHO', 'Futsal', 'Sub 8', 'MASCULINO'),
  (202, 197, 'ALTERAR', '2026-11-20 11:20:00', '2026-11-20 09:20:00', 'Quadra do CETI', 'Quadra do CETI', 'FRANCISCO AMORIM', 'PORTAL DO SABER', 'FRANCISCO AMORIM', 'PORTAL DO SABER', 'Baleado', 'Sub 11', 'FEMININO'),
  (204, 199, 'ALTERAR', '2026-11-20 12:40:00', '2026-11-20 10:40:00', 'Quadra do CETI', 'Quadra do CETI', 'ADELIETA RAMALHO', 'JOSENILDO LEITE', 'ADELIETA RAMALHO', 'JOSENILDO LEITE', 'Baleado', 'Sub 11', 'FEMININO'),
  (205, 200, 'ALTERAR', '2026-11-20 13:20:00', '2026-11-20 11:20:00', 'Quadra do CETI', 'Quadra do CETI', 'FRANCISCO AMORIM', 'MARIA DA GLORIA', 'FRANCISCO AMORIM', 'MARIA DA GLORIA', 'Handebol', 'Sub 9', 'FEMININO'),
  (206, 201, 'ALTERAR', '2026-11-20 14:40:00', '2026-11-20 12:00:00', 'Quadra do CETI', 'Quadra do CETI', 'ACM', 'TEODULO LEITE', 'ACM', 'TEODULO LEITE', 'Futsal', 'Sub 8', 'MASCULINO'),
  (207, 202, 'ALTERAR', '2026-11-20 15:20:00', '2026-11-20 12:40:00', 'Quadra do CETI', 'Quadra do CETI', 'LUCIA ROCHA', 'CEBC', 'LUCIA ROCHA', 'CEBC', 'Vôlei', 'Sub 17', 'MISTO'),
  (208, 203, 'ALTERAR', '2026-11-20 16:00:00', '2026-11-20 13:20:00', 'Quadra do CETI', 'Quadra do CETI', 'CETI', 'LUCIA ROCHA', 'CETI', 'LUCIA ROCHA', 'Vôlei', 'Aberto', 'MASCULINO'),
  (NULL, 204, 'INCLUIR', NULL, '2026-11-20 08:00:00', NULL, 'Quadra do CEBC', NULL, NULL, 'CEBC', 'CETI', 'Basquete', 'Sub 17', 'FEMININO'),
  (210, 205, 'RENUMERAR', '2026-11-20 08:40:00', '2026-11-20 08:40:00', 'Quadra do CEBC', 'Quadra do CEBC', 'CEJA', 'Conveniada', 'CEJA', 'Conveniada', 'Basquete', 'Sub 15', 'FEMININO'),
  (NULL, 206, 'INCLUIR', NULL, '2026-11-20 09:20:00', NULL, 'Quadra do CEBC', NULL, NULL, 'CONVENIADA', 'CEBC', 'Basquete', 'Sub 15', 'MASCULINO'),
  (212, 207, 'RENUMERAR', '2026-11-20 10:00:00', '2026-11-20 10:00:00', 'Quadra do CEBC', 'Quadra do CEBC', 'EMILIANO ZAPATA', 'CEJA', 'EMILIANO ZAPATA', 'CEJA', 'Futsal', 'Sub 15', 'FEMININO'),
  (213, 208, 'RENUMERAR', '2026-11-20 10:40:00', '2026-11-20 10:40:00', 'Quadra do CEBC', 'Quadra do CEBC', 'JOSE DIAS', 'CEBC', 'JOSE DIAS', 'CEBC', 'Futsal', 'Sub 15', 'FEMININO'),
  (214, 209, 'RENUMERAR', '2026-11-20 11:20:00', '2026-11-20 11:20:00', 'Quadra do CEBC', 'Quadra do CEBC', 'FRANCISCO AMORIM', 'CEJA', 'FRANCISCO AMORIM', 'CEJA', 'Handebol', 'Sub 11', 'FEMININO'),
  (215, 210, 'RENUMERAR', '2026-11-20 12:00:00', '2026-11-20 12:00:00', 'Quadra do CEBC', 'Quadra do CEBC', 'CEJA', 'CETI', 'CEJA', 'CETI', 'Basquete', 'Sub 17', 'MASCULINO'),
  (216, 211, 'RENUMERAR', '2026-11-20 12:40:00', '2026-11-20 12:40:00', 'Quadra do CEBC', 'Quadra do CEBC', 'CEJA', 'CEBC', 'CEJA', 'CEBC', 'Basquete', 'Sub 15', 'MASCULINO'),
  (102, 212, 'ALTERAR', '2026-11-19 10:00:00', '2026-11-20 13:20:00', 'Quadra do CEBC', 'Quadra do CEBC', 'CEJA', 'CEBC', 'CEJA', 'CEBC', 'Basquete', 'Sub 17', 'FEMININO'),
  (218, 213, 'RENUMERAR', '2026-11-20 14:00:00', '2026-11-20 14:00:00', 'Quadra do CEBC', 'Quadra do CEBC', 'FRANCISCO AMORIM', 'TEODULO LEITE', 'FRANCISCO AMORIM', 'TEODULO LEITE', 'Baleado', 'Sub 9', 'MASCULINO'),
  (219, 214, 'RENUMERAR', '2026-11-20 14:40:00', '2026-11-20 14:40:00', 'Quadra do CEBC', 'Quadra do CEBC', 'JOSE DIAS', 'ADELIETA RAMALHO', 'JOSE DIAS', 'ADELIETA RAMALHO', 'Baleado', 'Sub 9', 'MASCULINO'),
  (221, 216, 'RENUMERAR', '2026-11-20 16:00:00', '2026-11-20 16:00:00', 'Quadra do CEBC', 'Quadra do CEBC', 'Conveniada', 'CEBN', 'Conveniada', 'CEBN', 'Handebol', 'Sub 15', 'MASCULINO'),
  (222, 217, 'RENUMERAR', '2026-11-20 16:40:00', '2026-11-20 16:40:00', 'Quadra do CEBC', 'Quadra do CEBC', 'CEJA', 'CEBC', 'CEJA', 'CEBC', 'Handebol', 'Sub 15', 'MASCULINO'),
  (223, 218, 'ALTERAR', '2026-11-20 18:00:00', '2026-11-20 17:20:00', 'Quadra do CEBC', 'Quadra do CEBC', 'CEJA', 'LUCIA ROCHA', 'CEJA', 'LUCIA ROCHA', 'Handebol', 'Aberto', 'MASCULINO'),
  (224, 219, 'RENUMERAR', '2026-11-21 08:00:00', '2026-11-21 08:00:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'Conveniada', 'CEBC', 'Conveniada', 'CEBC', 'Handebol', 'Sub 15', 'MASCULINO'),
  (225, 220, 'RENUMERAR', '2026-11-21 08:40:00', '2026-11-21 08:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 'CEJA', 'CEBN', 'CEJA', 'CEBN', 'Handebol', 'Sub 17', 'MASCULINO'),
  (236, 231, 'ALTERAR', '2026-11-21 09:20:00', '2026-11-21 08:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'ADELIETA RAMALHO', 'JOSE DIAS', 'ADELIETA RAMALHO', 'JOSE DIAS', 'Handebol', 'Sub 11', 'FEMININO'),
  (237, 232, 'ALTERAR', '2026-11-21 10:00:00', '2026-11-21 08:40:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'Conveniada', 'MANOEL RAMOS', 'CONVENIADA', 'MANOEL RAMOS', 'Baleado', 'Sub 15', 'MASCULINO'),
  (238, 233, 'ALTERAR', '2026-11-21 10:40:00', '2026-11-21 09:20:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'CEBN', 'CEJA', 'CEBN', 'CEJA', 'Baleado', 'Sub 15', 'MASCULINO'),
  (239, 234, 'ALTERAR', '2026-11-21 11:20:00', '2026-11-21 10:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'JOSENILDO LEITE', 'CEJA', 'JOSENILDO LEITE', 'CEJA', 'Baleado', 'Sub 17', 'MASCULINO'),
  (240, 235, 'ALTERAR', '2026-11-21 12:00:00', '2026-11-21 10:40:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 'CEBC', 'CETI', 'CEBC', 'CETI', 'Baleado', 'Sub 17', 'MASCULINO'),
  (249, 244, 'RENUMERAR', '2026-11-21 08:00:00', '2026-11-21 08:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 'EMILIANO ZAPATA', 'CEJA', 'EMILIANO ZAPATA', 'CEJA', 'Baleado', 'Sub 15', 'FEMININO'),
  (250, 245, 'RENUMERAR', '2026-11-21 08:40:00', '2026-11-21 08:40:00', 'Quadra do CEJA', 'Quadra do CEJA', 'CEBC', 'JOSENILDO LEITE', 'CEBC', 'JOSENILDO LEITE', 'Baleado', 'Sub 15', 'FEMININO'),
  (251, 246, 'RENUMERAR', '2026-11-21 09:20:00', '2026-11-21 09:20:00', 'Quadra do CEJA', 'Quadra do CEJA', 'CEJA', 'CEBC', 'CEJA', 'CEBC', 'Baleado', 'Sub 17', 'FEMININO'),
  (252, 247, 'RENUMERAR', '2026-11-21 10:00:00', '2026-11-21 10:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 'LUCIA ROCHA', 'CETI', 'LUCIA ROCHA', 'CETI', 'Baleado', 'Sub 17', 'FEMININO'),
  (254, 249, 'RENUMERAR', '2026-11-21 11:20:00', '2026-11-21 11:20:00', 'Quadra do CEJA', 'Quadra do CEJA', 'LUCIA ROCHA', 'VITORIA LIMA', 'LUCIA ROCHA', 'VITORIA LIMA', 'Futsal', 'Aberto', 'FEMININO'),
  (278, 272, 'RENUMERAR', '2026-11-21 08:00:00', '2026-11-21 08:00:00', 'Quadra do CETI', 'Quadra do CETI', 'MARIA DA GLORIA', 'ADELIETA RAMALHO', 'MARIA DA GLORIA', 'ADELIETA RAMALHO', 'Handebol', 'Sub 9', 'FEMININO'),
  (279, 273, 'RENUMERAR', '2026-11-21 08:40:00', '2026-11-21 08:40:00', 'Quadra do CETI', 'Quadra do CETI', 'JOSE DIAS', 'ACM', 'JOSE DIAS', 'ACM', 'Handebol', 'Sub 8', 'MASCULINO'),
  (280, 274, 'RENUMERAR', '2026-11-21 09:20:00', '2026-11-21 09:20:00', 'Quadra do CETI', 'Quadra do CETI', 'PORTAL DO SABER', 'FRANCISCO AMORIM', 'PORTAL DO SABER', 'FRANCISCO AMORIM', 'Baleado', 'Sub 9', 'FEMININO'),
  (281, 275, 'RENUMERAR', '2026-11-21 10:00:00', '2026-11-21 10:00:00', 'Quadra do CETI', 'Quadra do CETI', 'ADELIETA RAMALHO', 'EMILIANO ZAPATA', 'ADELIETA RAMALHO', 'EMILIANO ZAPATA', 'Baleado', 'Sub 9', 'FEMININO'),
  (282, 276, 'RENUMERAR', '2026-11-21 10:40:00', '2026-11-21 10:40:00', 'Quadra do CETI', 'Quadra do CETI', 'JOSE DIAS', 'ACM', 'JOSE DIAS', 'ACM', 'Baleado', 'Sub 8', 'FEMININO'),
  (283, 277, 'RENUMERAR', '2026-11-21 11:20:00', '2026-11-21 11:20:00', 'Quadra do CETI', 'Quadra do CETI', 'EMILIANO ZAPATA', 'JOSE DIAS', 'EMILIANO ZAPATA', 'JOSE DIAS', 'Futsal', 'Sub 8', 'FEMININO'),
  (284, 278, 'RENUMERAR', '2026-11-21 12:00:00', '2026-11-21 12:00:00', 'Quadra do CETI', 'Quadra do CETI', 'JOSE DIAS', 'MARLENE SANTANA', 'JOSE DIAS', 'MARLENE SANTANA', 'Futsal', 'Sub 11', 'FEMININO'),
  (285, 279, 'RENUMERAR', '2026-11-21 12:40:00', '2026-11-21 12:40:00', 'Quadra do CETI', 'Quadra do CETI', 'JOSE DIAS', 'MARLENE SANTANA', 'JOSE DIAS', 'MARLENE SANTANA', 'Futsal', 'Sub 9', 'FEMININO'),
  (288, 282, 'RENUMERAR', '2026-11-21 14:40:00', '2026-11-21 14:40:00', 'Quadra do CETI', 'Quadra do CETI', 'ACM', 'JOSE DIAS', 'ACM', 'JOSE DIAS', 'Handebol', 'Sub 8', 'FEMININO'),
  (NULL, 286, 'INCLUIR', NULL, '2026-11-21 16:40:00', NULL, 'Quadra do CETI', NULL, NULL, 'ACM', 'MARLENE SANTANA', 'Baleado', 'Sub 8', 'MASCULINO'),
  (293, 287, 'RENUMERAR', '2026-11-21 08:00:00', '2026-11-21 08:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CEJA', 'CEBC', 'CEJA', 'CEBC', 'Handebol', 'Sub 13', 'FEMININO'),
  (294, 288, 'RENUMERAR', '2026-11-21 08:40:00', '2026-11-21 08:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'Conveniada', 'CEJA', 'Conveniada', 'CEJA', 'Handebol', 'Sub 15', 'FEMININO'),
  (295, 289, 'RENUMERAR', '2026-11-21 09:20:00', '2026-11-21 09:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 'CEBC', 'CEBN', 'CEBC', 'CEBN', 'Handebol', 'Sub 15', 'FEMININO'),
  (36, NULL, 'REMOVER', '2026-11-18 15:40:00', NULL, 'Campo Society Arena Social', NULL, 'CEBN', 'CETI', NULL, NULL, 'Futebol Society', 'Sub 15', 'MASCULINO'),
  (37, NULL, 'REMOVER', '2026-11-18 16:20:00', NULL, 'Campo Society Arena Social', NULL, 'CETI', 'VITORIA LIMA', NULL, NULL, 'Futebol Society', 'Sub 17', 'MASCULINO'),
  (43, NULL, 'REMOVER', '2026-11-19 11:20:00', NULL, 'Ginásio de Esportes', NULL, 'CETI', 'EMILIANO ZAPATA', NULL, NULL, 'Futsal', 'Sub 15', 'MASCULINO'),
  (129, NULL, 'REMOVER', '2026-11-19 10:00:00', NULL, 'Campo Society Arena Social', NULL, 'CETI', 'VITORIA LIMA', NULL, NULL, 'Futebol Society', 'Sub 17', 'MASCULINO'),
  (132, NULL, 'REMOVER', '2026-11-19 15:20:00', NULL, 'Campo Society Arena Social', NULL, 'CEBC', 'CEJA', NULL, NULL, 'Futebol Society', 'Sub 17', 'MASCULINO'),
  (191, NULL, 'REMOVER', '2026-11-20 16:40:00', NULL, 'Quadra do CEJA', NULL, 'CETI', 'MANOEL RAMOS', NULL, NULL, 'Futsal', 'Sub 15', 'MASCULINO'),
  (194, NULL, 'REMOVER', '2026-11-20 09:20:00', NULL, 'Campo Society do CETI', NULL, 'CETI', 'CEBC', NULL, NULL, 'Futebol Society', 'Sub 15', 'MASCULINO'),
  (209, NULL, 'REMOVER', '2026-11-20 08:00:00', NULL, 'Quadra do CEBC', NULL, 'CEBC', 'CEJA', NULL, NULL, 'Basquete', 'Sub 17', 'FEMININO');

-- ---------------------------------------------------------------------
-- O que o banco tem hoje
-- ---------------------------------------------------------------------
SET @jogos_total  := (SELECT COUNT(*) FROM jogos);
SET @jogos_grupos := (SELECT COUNT(*) FROM jogos WHERE fase = 'GRUPOS');

-- Jogos do banco que casam com o "nº atual" do mapa (esperado 232 no estado original)
SET @casam_atual := (
  SELECT COUNT(*) FROM mapa_db26 m
    INNER JOIN jogos j ON j.numero_tabela = m.tab_atual
    INNER JOIN competicoes c ON c.id = j.competicao_id AND c.genero = m.genero
    INNER JOIN modalidades mo ON mo.id = c.modalidade_id AND mo.nome = m.modalidade
    INNER JOIN categorias ca ON ca.id = c.categoria_id AND ca.nome = m.categoria
    INNER JOIN locais_disputa l ON l.id = j.local_id AND l.nome = m.local_atual
    INNER JOIN equipes e1 ON e1.id = j.equipe_1_id
    INNER JOIN escolas s1 ON s1.id = e1.escola_id AND s1.nome = m.eq1_atual
    INNER JOIN equipes e2 ON e2.id = j.equipe_2_id
    INNER JOIN escolas s2 ON s2.id = e2.escola_id AND s2.nome = m.eq2_atual
   WHERE m.tab_atual IS NOT NULL AND j.data_hora = m.data_atual);

-- Jogos do banco que casam com o "nº novo" do mapa (esperado 234 no estado já feito)
SET @casam_novo := (
  SELECT COUNT(*) FROM mapa_db26 m
    INNER JOIN jogos j ON j.numero_tabela = m.tab_novo
    INNER JOIN competicoes c ON c.id = j.competicao_id AND c.genero = m.genero
    INNER JOIN modalidades mo ON mo.id = c.modalidade_id AND mo.nome = m.modalidade
    INNER JOIN categorias ca ON ca.id = c.categoria_id AND ca.nome = m.categoria
    INNER JOIN locais_disputa l ON l.id = j.local_id AND l.nome = m.local_novo
    INNER JOIN equipes e1 ON e1.id = j.equipe_1_id
    INNER JOIN escolas s1 ON s1.id = e1.escola_id AND s1.nome = m.eq1_novo
    INNER JOIN equipes e2 ON e2.id = j.equipe_2_id
    INNER JOIN escolas s2 ON s2.id = e2.escola_id AND s2.nome = m.eq2_novo
   WHERE m.tab_novo IS NOT NULL AND j.data_hora = m.data_nova);

-- Dos jogos que MUDAM ou SAEM (167), quantos estão "limpos": AGENDADO, sem
-- placar, pênaltis nem vencedor, sem súmula e sem set (esperado 167)
SET @limpos := (
  SELECT COUNT(*) FROM mapa_db26 m
    INNER JOIN jogos j ON j.numero_tabela = m.tab_atual
   WHERE m.tab_atual IS NOT NULL AND m.acao <> 'MANTER'
     AND j.status = 'AGENDADO' AND j.placar_1 IS NULL AND j.placar_2 IS NULL
     AND j.penaltis_1 IS NULL AND j.penaltis_2 IS NULL AND j.vencedor_equipe_id IS NULL
     AND NOT EXISTS (SELECT 1 FROM sumula_equipes x WHERE x.jogo_id = j.id)
     AND NOT EXISTS (SELECT 1 FROM sumula_atletas x WHERE x.jogo_id = j.id)
     AND NOT EXISTS (SELECT 1 FROM jogo_sets x WHERE x.jogo_id = j.id));

-- Competições e equipes que o roteiro mexe
SET @soc15 := (SELECT c.id FROM competicoes c INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.slug = 'futebol-society'
                INNER JOIN categorias k ON k.id = c.categoria_id AND k.nome = 'Sub 15' WHERE c.genero = 'MASCULINO');
SET @fut15 := (SELECT c.id FROM competicoes c INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.slug = 'futsal'
                INNER JOIN categorias k ON k.id = c.categoria_id AND k.nome = 'Sub 15' WHERE c.genero = 'MASCULINO');
SET @bq17f := (SELECT c.id FROM competicoes c INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.slug = 'basquete'
                INNER JOIN categorias k ON k.id = c.categoria_id AND k.nome = 'Sub 17' WHERE c.genero = 'FEMININO');
SET @soc17 := (SELECT c.id FROM competicoes c INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.slug = 'futebol-society'
                INNER JOIN categorias k ON k.id = c.categoria_id AND k.nome = 'Sub 17' WHERE c.genero = 'MASCULINO');
SET @ceti  := (SELECT id FROM escolas WHERE nome = 'CETI');

SET @eq_ceti_soc15 := (SELECT id FROM equipes WHERE competicao_id = @soc15 AND escola_id = @ceti);
SET @eq_ceti_fut15 := (SELECT id FROM equipes WHERE competicao_id = @fut15 AND escola_id = @ceti);
SET @ceti_bq17f    := (SELECT COUNT(*) FROM equipes WHERE competicao_id = @bq17f AND escola_id = @ceti);
SET @grupo_a_bq17f := (SELECT id FROM grupos WHERE competicao_id = @bq17f AND nome = 'A');

-- A CETI das duas Sub 15: sem atleta, súmula nem colocação, e com jogo só nos
-- 2 que saem (esperado 2)
SET @ceti_limpas := (
  SELECT COUNT(*) FROM equipes e
   WHERE e.id IN (COALESCE(@eq_ceti_soc15, 0), COALESCE(@eq_ceti_fut15, 0))
     AND NOT EXISTS (SELECT 1 FROM inscricoes_atletas x WHERE x.equipe_id = e.id)
     AND NOT EXISTS (SELECT 1 FROM sumula_equipes x WHERE x.equipe_id = e.id)
     AND NOT EXISTS (SELECT 1 FROM sumula_atletas x WHERE x.equipe_id = e.id)
     AND NOT EXISTS (SELECT 1 FROM colocacoes_finais x WHERE x.equipe_id = e.id)
     AND (SELECT COUNT(*) FROM jogos g WHERE g.equipe_1_id = e.id OR g.equipe_2_id = e.id) = 2
     AND (SELECT COUNT(*) FROM jogos g WHERE (g.equipe_1_id = e.id OR g.equipe_2_id = e.id)
              AND g.numero_tabela IN (36, 43, 191, 194)) = 2);

-- Os dois estados aceitos
SET @estado := CASE
  WHEN @casam_atual = 232 AND @jogos_total = 232 AND @limpos = 167 AND @ceti_limpas = 2
       AND @soc15 IS NOT NULL AND @fut15 IS NOT NULL AND @bq17f IS NOT NULL AND @soc17 IS NOT NULL
       AND @ceti IS NOT NULL AND @ceti_bq17f = 0 AND @grupo_a_bq17f IS NOT NULL THEN 'original: aplica'
  WHEN @casam_novo = 234 AND @jogos_grupos = 234 AND @eq_ceti_soc15 IS NULL AND @eq_ceti_fut15 IS NULL
       AND @ceti_bq17f = 1 THEN 'já feito: nada a fazer'
  ELSE 'não bate' END;

-- O que foi achado (antes da trava, para ver o motivo se ela parar)
SELECT @jogos_total AS jogos, @casam_atual AS casam_atual, @casam_novo AS casam_novo, @limpos AS limpos,
       @ceti_limpas AS ceti_limpas, @ceti_bq17f AS ceti_no_basquete, @estado AS estado;

-- ---------------------------------------------------------------------
-- Trava 1: só o estado original ou o já feito. Qualquer outra coisa para aqui.
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS trava_tabela_db26;
CREATE TEMPORARY TABLE trava_tabela_db26 (
  estado VARCHAR(40) NOT NULL,
  ok     TINYINT     NOT NULL,
  CONSTRAINT tabela_20264_nao_bate_com_o_banco CHECK (ok = 1)
);
INSERT INTO trava_tabela_db26 (estado, ok)
VALUES (@estado, CASE WHEN @estado = 'não bate' THEN 0 ELSE 1 END);

SELECT @estado AS db26;
DROP TEMPORARY TABLE trava_tabela_db26;

-- ---------------------------------------------------------------------
-- As mudanças, só no estado original (no "já feito" nenhuma linha casa)
-- ---------------------------------------------------------------------

-- 0) Liga cada linha do mapa ao jogo que existe hoje
UPDATE mapa_db26 m
  INNER JOIN jogos j ON j.numero_tabela = m.tab_atual
   SET m.jogo_id = j.id
 WHERE m.tab_atual IS NOT NULL AND @estado = 'original: aplica';

-- 1) Saem os 8 jogos
DELETE j FROM jogos j
  INNER JOIN mapa_db26 m ON m.jogo_id = j.id
 WHERE m.acao = 'REMOVER' AND @estado = 'original: aplica';

-- 2) Sai a CETI das duas Sub 15 (já sem jogo, sem atleta, sem súmula, sem colocação)
DELETE FROM equipes
 WHERE id IN (COALESCE(@eq_ceti_soc15, 0), COALESCE(@eq_ceti_fut15, 0)) AND @estado = 'original: aplica';

-- 3) Renumeração, fase 1: o número novo + 10000 (só quem muda de número)
UPDATE jogos j
  INNER JOIN mapa_db26 m ON m.jogo_id = j.id
   SET j.numero_tabela = m.tab_novo + 10000
 WHERE m.acao IN ('RENUMERAR', 'ALTERAR') AND m.tab_novo <> m.tab_atual AND @estado = 'original: aplica';

-- 3) Renumeração, fase 2: tira os 10000
UPDATE jogos
   SET numero_tabela = numero_tabela - 10000
 WHERE numero_tabela >= 10000 AND @estado = 'original: aplica';

-- 4) Os jogos que ALTERAM dia, hora, local ou mando
UPDATE jogos j
  INNER JOIN mapa_db26 m ON m.jogo_id = j.id
  INNER JOIN locais_disputa l ON l.nome = m.local_novo
  INNER JOIN escolas s1 ON s1.nome = m.eq1_novo
  INNER JOIN equipes e1 ON e1.escola_id = s1.id AND e1.competicao_id = j.competicao_id
  INNER JOIN escolas s2 ON s2.nome = m.eq2_novo
  INNER JOIN equipes e2 ON e2.escola_id = s2.id AND e2.competicao_id = j.competicao_id
   SET j.data_hora = m.data_nova, j.local_id = l.id, j.equipe_1_id = e1.id, j.equipe_2_id = e2.id
 WHERE m.acao = 'ALTERAR' AND @estado = 'original: aplica';

-- 5) A CETI volta ao Basquete Sub 17 F, no grupo A
INSERT INTO equipes (competicao_id, escola_id, grupo_id)
SELECT @bq17f, @ceti, @grupo_a_bq17f
 FROM escolas
WHERE id = @ceti AND @estado = 'original: aplica';

-- 6) Entram os 10 jogos (AGENDADOS, na fase de grupos; o numero_jogo é o maior da
--    competição + 1; grupo_id só quando as duas equipes são do mesmo grupo)
-- nº 36: CEBN x CEBC (Futebol Society Sub 15 MASCULINO, 2026-11-18 15:40)
INSERT INTO jogos (competicao_id, numero_jogo, numero_tabela, fase, rodada, grupo_id, local_id, data_hora,
                   equipe_1_id, equipe_2_id, status)
SELECT c.id,
       (SELECT COALESCE(MAX(x.numero_jogo), 0) + 1 FROM jogos x WHERE x.competicao_id = c.id),
       m.tab_novo, 'GRUPOS', NULL,
       CASE WHEN e1.grupo_id = e2.grupo_id THEN e1.grupo_id ELSE NULL END,
       l.id, m.data_nova, e1.id, e2.id, 'AGENDADO'
  FROM mapa_db26 m
  INNER JOIN modalidades mo ON mo.nome = m.modalidade
  INNER JOIN categorias ca ON ca.nome = m.categoria
  INNER JOIN competicoes c ON c.modalidade_id = mo.id AND c.categoria_id = ca.id AND c.genero = m.genero
  INNER JOIN locais_disputa l ON l.nome = m.local_novo
  INNER JOIN escolas s1 ON s1.nome = m.eq1_novo
  INNER JOIN equipes e1 ON e1.escola_id = s1.id AND e1.competicao_id = c.id
  INNER JOIN escolas s2 ON s2.nome = m.eq2_novo
  INNER JOIN equipes e2 ON e2.escola_id = s2.id AND e2.competicao_id = c.id
 WHERE m.acao = 'INCLUIR' AND m.tab_novo = 36 AND @estado = 'original: aplica';

-- nº 37: CEBC x VITORIA LIMA (Futebol Society Sub 17 MASCULINO, 2026-11-18 16:20)
INSERT INTO jogos (competicao_id, numero_jogo, numero_tabela, fase, rodada, grupo_id, local_id, data_hora,
                   equipe_1_id, equipe_2_id, status)
SELECT c.id,
       (SELECT COALESCE(MAX(x.numero_jogo), 0) + 1 FROM jogos x WHERE x.competicao_id = c.id),
       m.tab_novo, 'GRUPOS', NULL,
       CASE WHEN e1.grupo_id = e2.grupo_id THEN e1.grupo_id ELSE NULL END,
       l.id, m.data_nova, e1.id, e2.id, 'AGENDADO'
  FROM mapa_db26 m
  INNER JOIN modalidades mo ON mo.nome = m.modalidade
  INNER JOIN categorias ca ON ca.nome = m.categoria
  INNER JOIN competicoes c ON c.modalidade_id = mo.id AND c.categoria_id = ca.id AND c.genero = m.genero
  INNER JOIN locais_disputa l ON l.nome = m.local_novo
  INNER JOIN escolas s1 ON s1.nome = m.eq1_novo
  INNER JOIN equipes e1 ON e1.escola_id = s1.id AND e1.competicao_id = c.id
  INNER JOIN escolas s2 ON s2.nome = m.eq2_novo
  INNER JOIN equipes e2 ON e2.escola_id = s2.id AND e2.competicao_id = c.id
 WHERE m.acao = 'INCLUIR' AND m.tab_novo = 37 AND @estado = 'original: aplica';

-- nº 43: MANOEL RAMOS x EMILIANO ZAPATA (Futsal Sub 15 MASCULINO, 2026-11-19 11:20)
INSERT INTO jogos (competicao_id, numero_jogo, numero_tabela, fase, rodada, grupo_id, local_id, data_hora,
                   equipe_1_id, equipe_2_id, status)
SELECT c.id,
       (SELECT COALESCE(MAX(x.numero_jogo), 0) + 1 FROM jogos x WHERE x.competicao_id = c.id),
       m.tab_novo, 'GRUPOS', NULL,
       CASE WHEN e1.grupo_id = e2.grupo_id THEN e1.grupo_id ELSE NULL END,
       l.id, m.data_nova, e1.id, e2.id, 'AGENDADO'
  FROM mapa_db26 m
  INNER JOIN modalidades mo ON mo.nome = m.modalidade
  INNER JOIN categorias ca ON ca.nome = m.categoria
  INNER JOIN competicoes c ON c.modalidade_id = mo.id AND c.categoria_id = ca.id AND c.genero = m.genero
  INNER JOIN locais_disputa l ON l.nome = m.local_novo
  INNER JOIN escolas s1 ON s1.nome = m.eq1_novo
  INNER JOIN equipes e1 ON e1.escola_id = s1.id AND e1.competicao_id = c.id
  INNER JOIN escolas s2 ON s2.nome = m.eq2_novo
  INNER JOIN equipes e2 ON e2.escola_id = s2.id AND e2.competicao_id = c.id
 WHERE m.acao = 'INCLUIR' AND m.tab_novo = 43 AND @estado = 'original: aplica';

-- nº 101: CETI x CEJA (Basquete Sub 17 FEMININO, 2026-11-19 10:00)
INSERT INTO jogos (competicao_id, numero_jogo, numero_tabela, fase, rodada, grupo_id, local_id, data_hora,
                   equipe_1_id, equipe_2_id, status)
SELECT c.id,
       (SELECT COALESCE(MAX(x.numero_jogo), 0) + 1 FROM jogos x WHERE x.competicao_id = c.id),
       m.tab_novo, 'GRUPOS', NULL,
       CASE WHEN e1.grupo_id = e2.grupo_id THEN e1.grupo_id ELSE NULL END,
       l.id, m.data_nova, e1.id, e2.id, 'AGENDADO'
  FROM mapa_db26 m
  INNER JOIN modalidades mo ON mo.nome = m.modalidade
  INNER JOIN categorias ca ON ca.nome = m.categoria
  INNER JOIN competicoes c ON c.modalidade_id = mo.id AND c.categoria_id = ca.id AND c.genero = m.genero
  INNER JOIN locais_disputa l ON l.nome = m.local_novo
  INNER JOIN escolas s1 ON s1.nome = m.eq1_novo
  INNER JOIN equipes e1 ON e1.escola_id = s1.id AND e1.competicao_id = c.id
  INNER JOIN escolas s2 ON s2.nome = m.eq2_novo
  INNER JOIN equipes e2 ON e2.escola_id = s2.id AND e2.competicao_id = c.id
 WHERE m.acao = 'INCLUIR' AND m.tab_novo = 101 AND @estado = 'original: aplica';

-- nº 126: CETI x CEBC (Futebol Society Sub 17 MASCULINO, 2026-11-19 09:10)
INSERT INTO jogos (competicao_id, numero_jogo, numero_tabela, fase, rodada, grupo_id, local_id, data_hora,
                   equipe_1_id, equipe_2_id, status)
SELECT c.id,
       (SELECT COALESCE(MAX(x.numero_jogo), 0) + 1 FROM jogos x WHERE x.competicao_id = c.id),
       m.tab_novo, 'GRUPOS', NULL,
       CASE WHEN e1.grupo_id = e2.grupo_id THEN e1.grupo_id ELSE NULL END,
       l.id, m.data_nova, e1.id, e2.id, 'AGENDADO'
  FROM mapa_db26 m
  INNER JOIN modalidades mo ON mo.nome = m.modalidade
  INNER JOIN categorias ca ON ca.nome = m.categoria
  INNER JOIN competicoes c ON c.modalidade_id = mo.id AND c.categoria_id = ca.id AND c.genero = m.genero
  INNER JOIN locais_disputa l ON l.nome = m.local_novo
  INNER JOIN escolas s1 ON s1.nome = m.eq1_novo
  INNER JOIN equipes e1 ON e1.escola_id = s1.id AND e1.competicao_id = c.id
  INNER JOIN escolas s2 ON s2.nome = m.eq2_novo
  INNER JOIN equipes e2 ON e2.escola_id = s2.id AND e2.competicao_id = c.id
 WHERE m.acao = 'INCLUIR' AND m.tab_novo = 126 AND @estado = 'original: aplica';

-- nº 130: CEJA x VITORIA LIMA (Futebol Society Sub 17 MASCULINO, 2026-11-19 15:20)
INSERT INTO jogos (competicao_id, numero_jogo, numero_tabela, fase, rodada, grupo_id, local_id, data_hora,
                   equipe_1_id, equipe_2_id, status)
SELECT c.id,
       (SELECT COALESCE(MAX(x.numero_jogo), 0) + 1 FROM jogos x WHERE x.competicao_id = c.id),
       m.tab_novo, 'GRUPOS', NULL,
       CASE WHEN e1.grupo_id = e2.grupo_id THEN e1.grupo_id ELSE NULL END,
       l.id, m.data_nova, e1.id, e2.id, 'AGENDADO'
  FROM mapa_db26 m
  INNER JOIN modalidades mo ON mo.nome = m.modalidade
  INNER JOIN categorias ca ON ca.nome = m.categoria
  INNER JOIN competicoes c ON c.modalidade_id = mo.id AND c.categoria_id = ca.id AND c.genero = m.genero
  INNER JOIN locais_disputa l ON l.nome = m.local_novo
  INNER JOIN escolas s1 ON s1.nome = m.eq1_novo
  INNER JOIN equipes e1 ON e1.escola_id = s1.id AND e1.competicao_id = c.id
  INNER JOIN escolas s2 ON s2.nome = m.eq2_novo
  INNER JOIN equipes e2 ON e2.escola_id = s2.id AND e2.competicao_id = c.id
 WHERE m.acao = 'INCLUIR' AND m.tab_novo = 130 AND @estado = 'original: aplica';

-- nº 192: CEJA x CETI (Futebol Society Sub 17 MASCULINO, 2026-11-20 10:00)
INSERT INTO jogos (competicao_id, numero_jogo, numero_tabela, fase, rodada, grupo_id, local_id, data_hora,
                   equipe_1_id, equipe_2_id, status)
SELECT c.id,
       (SELECT COALESCE(MAX(x.numero_jogo), 0) + 1 FROM jogos x WHERE x.competicao_id = c.id),
       m.tab_novo, 'GRUPOS', NULL,
       CASE WHEN e1.grupo_id = e2.grupo_id THEN e1.grupo_id ELSE NULL END,
       l.id, m.data_nova, e1.id, e2.id, 'AGENDADO'
  FROM mapa_db26 m
  INNER JOIN modalidades mo ON mo.nome = m.modalidade
  INNER JOIN categorias ca ON ca.nome = m.categoria
  INNER JOIN competicoes c ON c.modalidade_id = mo.id AND c.categoria_id = ca.id AND c.genero = m.genero
  INNER JOIN locais_disputa l ON l.nome = m.local_novo
  INNER JOIN escolas s1 ON s1.nome = m.eq1_novo
  INNER JOIN equipes e1 ON e1.escola_id = s1.id AND e1.competicao_id = c.id
  INNER JOIN escolas s2 ON s2.nome = m.eq2_novo
  INNER JOIN equipes e2 ON e2.escola_id = s2.id AND e2.competicao_id = c.id
 WHERE m.acao = 'INCLUIR' AND m.tab_novo = 192 AND @estado = 'original: aplica';

-- nº 204: CEBC x CETI (Basquete Sub 17 FEMININO, 2026-11-20 08:00)
INSERT INTO jogos (competicao_id, numero_jogo, numero_tabela, fase, rodada, grupo_id, local_id, data_hora,
                   equipe_1_id, equipe_2_id, status)
SELECT c.id,
       (SELECT COALESCE(MAX(x.numero_jogo), 0) + 1 FROM jogos x WHERE x.competicao_id = c.id),
       m.tab_novo, 'GRUPOS', NULL,
       CASE WHEN e1.grupo_id = e2.grupo_id THEN e1.grupo_id ELSE NULL END,
       l.id, m.data_nova, e1.id, e2.id, 'AGENDADO'
  FROM mapa_db26 m
  INNER JOIN modalidades mo ON mo.nome = m.modalidade
  INNER JOIN categorias ca ON ca.nome = m.categoria
  INNER JOIN competicoes c ON c.modalidade_id = mo.id AND c.categoria_id = ca.id AND c.genero = m.genero
  INNER JOIN locais_disputa l ON l.nome = m.local_novo
  INNER JOIN escolas s1 ON s1.nome = m.eq1_novo
  INNER JOIN equipes e1 ON e1.escola_id = s1.id AND e1.competicao_id = c.id
  INNER JOIN escolas s2 ON s2.nome = m.eq2_novo
  INNER JOIN equipes e2 ON e2.escola_id = s2.id AND e2.competicao_id = c.id
 WHERE m.acao = 'INCLUIR' AND m.tab_novo = 204 AND @estado = 'original: aplica';

-- nº 206: CONVENIADA x CEBC (Basquete Sub 15 MASCULINO, 2026-11-20 09:20)
INSERT INTO jogos (competicao_id, numero_jogo, numero_tabela, fase, rodada, grupo_id, local_id, data_hora,
                   equipe_1_id, equipe_2_id, status)
SELECT c.id,
       (SELECT COALESCE(MAX(x.numero_jogo), 0) + 1 FROM jogos x WHERE x.competicao_id = c.id),
       m.tab_novo, 'GRUPOS', NULL,
       CASE WHEN e1.grupo_id = e2.grupo_id THEN e1.grupo_id ELSE NULL END,
       l.id, m.data_nova, e1.id, e2.id, 'AGENDADO'
  FROM mapa_db26 m
  INNER JOIN modalidades mo ON mo.nome = m.modalidade
  INNER JOIN categorias ca ON ca.nome = m.categoria
  INNER JOIN competicoes c ON c.modalidade_id = mo.id AND c.categoria_id = ca.id AND c.genero = m.genero
  INNER JOIN locais_disputa l ON l.nome = m.local_novo
  INNER JOIN escolas s1 ON s1.nome = m.eq1_novo
  INNER JOIN equipes e1 ON e1.escola_id = s1.id AND e1.competicao_id = c.id
  INNER JOIN escolas s2 ON s2.nome = m.eq2_novo
  INNER JOIN equipes e2 ON e2.escola_id = s2.id AND e2.competicao_id = c.id
 WHERE m.acao = 'INCLUIR' AND m.tab_novo = 206 AND @estado = 'original: aplica';

-- nº 286: ACM x MARLENE SANTANA (Baleado Sub 8 MASCULINO, 2026-11-21 16:40)
INSERT INTO jogos (competicao_id, numero_jogo, numero_tabela, fase, rodada, grupo_id, local_id, data_hora,
                   equipe_1_id, equipe_2_id, status)
SELECT c.id,
       (SELECT COALESCE(MAX(x.numero_jogo), 0) + 1 FROM jogos x WHERE x.competicao_id = c.id),
       m.tab_novo, 'GRUPOS', NULL,
       CASE WHEN e1.grupo_id = e2.grupo_id THEN e1.grupo_id ELSE NULL END,
       l.id, m.data_nova, e1.id, e2.id, 'AGENDADO'
  FROM mapa_db26 m
  INNER JOIN modalidades mo ON mo.nome = m.modalidade
  INNER JOIN categorias ca ON ca.nome = m.categoria
  INNER JOIN competicoes c ON c.modalidade_id = mo.id AND c.categoria_id = ca.id AND c.genero = m.genero
  INNER JOIN locais_disputa l ON l.nome = m.local_novo
  INNER JOIN escolas s1 ON s1.nome = m.eq1_novo
  INNER JOIN equipes e1 ON e1.escola_id = s1.id AND e1.competicao_id = c.id
  INNER JOIN escolas s2 ON s2.nome = m.eq2_novo
  INNER JOIN equipes e2 ON e2.escola_id = s2.id AND e2.competicao_id = c.id
 WHERE m.acao = 'INCLUIR' AND m.tab_novo = 286 AND @estado = 'original: aplica';


-- ---------------------------------------------------------------------
-- Conferências. A tabela mostra o esperado e o encontrado; a trava logo
-- depois desfaz tudo se alguma divergir.
-- ---------------------------------------------------------------------
-- (cada consulta do mapa fica numa variável: tabela temporária não pode
-- aparecer mais de uma vez na mesma consulta)
SET @casam_novo_final := (
  SELECT COUNT(*) FROM mapa_db26 m
    INNER JOIN jogos j ON j.numero_tabela = m.tab_novo
    INNER JOIN competicoes c ON c.id = j.competicao_id AND c.genero = m.genero
    INNER JOIN modalidades mo ON mo.id = c.modalidade_id AND mo.nome = m.modalidade
    INNER JOIN categorias ca ON ca.id = c.categoria_id AND ca.nome = m.categoria
    INNER JOIN locais_disputa l ON l.id = j.local_id AND l.nome = m.local_novo
    INNER JOIN equipes e1 ON e1.id = j.equipe_1_id
    INNER JOIN escolas s1 ON s1.id = e1.escola_id AND s1.nome = m.eq1_novo
    INNER JOIN equipes e2 ON e2.id = j.equipe_2_id
    INNER JOIN escolas s2 ON s2.id = e2.escola_id AND s2.nome = m.eq2_novo
   WHERE m.tab_novo IS NOT NULL AND j.data_hora = m.data_nova);
SET @linhas_novo := (SELECT COUNT(*) FROM mapa_db26 WHERE tab_novo IS NOT NULL);

DROP TEMPORARY TABLE IF EXISTS conferencia_db26;
CREATE TEMPORARY TABLE conferencia_db26 (
  item       VARCHAR(90) NOT NULL,
  esperado   INT         NOT NULL,
  encontrado INT         NOT NULL
);

INSERT INTO conferencia_db26 (item, esperado, encontrado)
SELECT 'jogos de grupo no total', 234, COUNT(*) FROM jogos WHERE fase = 'GRUPOS'
UNION ALL SELECT 'jogos que casam com o "nº novo" do mapa (número, competição, dia e hora, local, equipes)', 234, @casam_novo_final
UNION ALL SELECT 'linhas do mapa com número novo', 234, @linhas_novo
UNION ALL SELECT 'números da tabela repetidos', 0, COUNT(*) - COUNT(DISTINCT numero_tabela) FROM jogos
           WHERE numero_tabela IS NOT NULL
UNION ALL SELECT 'jogos de grupo sem número da tabela', 0, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND numero_tabela IS NULL
UNION ALL SELECT 'números da tabela acima de 10000 (renumeração pela metade)', 0, COUNT(*) FROM jogos WHERE numero_tabela >= 10000
UNION ALL SELECT 'jogos de grupo em 18/11', 37, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-18'
UNION ALL SELECT 'jogos de grupo em 19/11', 93, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-19'
UNION ALL SELECT 'jogos de grupo em 20/11', 79, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-20'
UNION ALL SELECT 'jogos de grupo em 21/11', 25, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-21'
UNION ALL SELECT 'jogos de grupo fora de 18 a 21/11 ou sem data', 0, COUNT(*) FROM jogos
           WHERE fase = 'GRUPOS' AND (data_hora IS NULL OR DATE(data_hora) NOT BETWEEN '2026-11-18' AND '2026-11-21')
UNION ALL SELECT 'jogos de uma equipe contra ela mesma', 0, COUNT(*) FROM jogos WHERE equipe_1_id = equipe_2_id
UNION ALL SELECT 'equipes em dois jogos de grupo no mesmo dia e hora', 0, COUNT(*) FROM (
             SELECT t.equipe_id FROM (
               SELECT equipe_1_id AS equipe_id, data_hora FROM jogos WHERE fase = 'GRUPOS'
               UNION ALL
               SELECT equipe_2_id, data_hora FROM jogos WHERE fase = 'GRUPOS') t
              GROUP BY t.equipe_id, t.data_hora HAVING COUNT(*) > 1) repetidas
UNION ALL SELECT 'equipes da CETI no Futebol Society Sub 15 M e no Futsal Sub 15 M', 0, COUNT(*) FROM equipes
           WHERE escola_id = @ceti AND competicao_id IN (COALESCE(@soc15, 0), COALESCE(@fut15, 0))
UNION ALL SELECT 'equipes do Basquete Sub 17 F (CETI, CEJA e CEBC)', 3, COUNT(*) FROM equipes WHERE competicao_id = @bq17f
UNION ALL SELECT 'jogos do Basquete Sub 17 F', 3, COUNT(*) FROM jogos WHERE competicao_id = @bq17f
UNION ALL SELECT 'jogos do Futebol Society Sub 17 M (os 4 novos)', 4, COUNT(*) FROM jogos WHERE competicao_id = @soc17
UNION ALL SELECT 'equipes do Futebol Society Sub 15 M e do Futsal Sub 15 M sem nenhum jogo', 0, COUNT(*) FROM equipes e
           WHERE e.competicao_id IN (COALESCE(@soc15, 0), COALESCE(@fut15, 0))
             AND NOT EXISTS (SELECT 1 FROM jogos g WHERE g.equipe_1_id = e.id OR g.equipe_2_id = e.id);

SELECT item, esperado, encontrado,
       CASE WHEN esperado = encontrado THEN 'ok' ELSE 'DIVERGE' END AS situacao
  FROM conferencia_db26;

-- Trava 2: qualquer divergência para aqui, antes do COMMIT
DROP TEMPORARY TABLE IF EXISTS trava_conferencia_db26;
CREATE TEMPORARY TABLE trava_conferencia_db26 (
  item VARCHAR(90) NOT NULL,
  ok   TINYINT     NOT NULL,
  CONSTRAINT conferencia_do_db26_divergiu CHECK (ok = 1)
);
INSERT INTO trava_conferencia_db26 (item, ok)
SELECT item, CASE WHEN esperado = encontrado THEN 1 ELSE 0 END FROM conferencia_db26;

DROP TEMPORARY TABLE trava_conferencia_db26;
DROP TEMPORARY TABLE conferencia_db26;
DROP TEMPORARY TABLE mapa_db26;

COMMIT;

-- ---------------------------------------------------------------------
-- Depois do COMMIT, só leitura
-- ---------------------------------------------------------------------

-- A Lucia Rocha (a ESCOLA, em qualquer competição) com dois jogos de grupo no mesmo dia e hora.
-- INFORMATIVO, não trava: a tabela do chefe tem vários casos de escola em dois lugares ao mesmo
-- tempo (86 antes do db/26), em categorias e quadras diferentes. Se esta consulta trouxer linhas,
-- a Lucia Rocha ainda tem dois jogos no mesmo horário.
SELECT s.nome AS escola, j.data_hora, GROUP_CONCAT(j.numero_tabela ORDER BY j.numero_tabela) AS jogos
  FROM (SELECT equipe_1_id AS equipe_id, numero_tabela, data_hora FROM jogos WHERE fase = 'GRUPOS'
        UNION ALL SELECT equipe_2_id, numero_tabela, data_hora FROM jogos WHERE fase = 'GRUPOS') j
  INNER JOIN equipes e ON e.id = j.equipe_id
  INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'LUCIA ROCHA'
 GROUP BY s.nome, j.data_hora HAVING COUNT(*) > 1;

-- Os jogos do Society Sub 17 M (sem grupo, até o db/27) e as equipes das competições que o roteiro mexeu
SELECT j.numero_tabela, j.numero_jogo, j.grupo_id, j.data_hora, s1.nome AS equipe_1, s2.nome AS equipe_2
  FROM jogos j
  INNER JOIN equipes e1 ON e1.id = j.equipe_1_id INNER JOIN escolas s1 ON s1.id = e1.escola_id
  INNER JOIN equipes e2 ON e2.id = j.equipe_2_id INNER JOIN escolas s2 ON s2.id = e2.escola_id
 WHERE j.competicao_id = @soc17
 ORDER BY j.numero_jogo;

SELECT c.id AS competicao_id, m.nome AS modalidade, k.nome AS categoria, c.genero,
       (SELECT COUNT(*) FROM equipes e WHERE e.competicao_id = c.id) AS equipes,
       (SELECT COUNT(*) FROM jogos g WHERE g.competicao_id = c.id) AS jogos
  FROM competicoes c
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias k ON k.id = c.categoria_id
 WHERE c.id IN (COALESCE(@soc15, 0), COALESCE(@fut15, 0), COALESCE(@bq17f, 0), COALESCE(@soc17, 0));
