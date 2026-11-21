-- =====================================================================
-- MIGRAÇÃO 43 — Tabela de jogos 20269 do chefe (16/11/2026)
--
-- Aplica a TABELA DE JOGOS 20269 sobre a 20268 (estado da produção depois do
-- db/41 e do db/42: 302 jogos, 229 de grupo e 73 de mata-mata; ver
-- docs/importacao/contexto_tabela_20269.md, fora do git). A comparação foi feita
-- PELO CONTEÚDO (competição + equipes; no mata-mata, competição + fase + ordem),
-- conferida pelo usuário contra o docx, e está escrita aqui jogo a jogo: o
-- script não lê arquivo nenhum.
--
--   302 jogos viram 299 (228 de grupo e 71 de mata-mata):
--   199 IGUAIS, 100 ALTERAR (82 só de número, 16 de número e hora, 1 de equipes
--   e 1 só de grupo, o 166; o 265 muda de número e de grupo) e 3 REMOVER. Nenhum jogo entra; nenhum muda de dia nem de local.
--   Por dia, grupo/mata-mata: 18/11 36/0, 19/11 92/0, 20/11 75/9, 21/11 25/62.
--   numero_tabela de 1 a 299, sem repetir nem faltar.
--
-- 1) Handebol Sub 11 F: o CEJA sai. Saem o jogo Francisco Amorim x CEJA (205) e
--    as semifinais 230 e 231; o 158 passa de Maria da Glória x CEJA a Maria da
--    Glória x Francisco Amorim; a final 235 vira o 232, às 21/11 13:20 (Quadra da
--    Adelieta), "1º do Grupo A x 1º do Grupo B" (2 grupos, 1 classificado,
--    FINAL). A equipe do CEJA sai da competição com as inscrições dela (os atletas
--    continuam cadastrados), só se não tiver súmula nem colocação. O numero_jogo
--    desta competição é renumerado de 1 a N por data e hora.
-- 2) Baleado Sub 9 F: volta a 2 grupos (o grupo B é criado). A = Maria da
--    Glória, Portal do Saber e Francisco Amorim; B = José Dias e Adelieta (jogos
--    166 e 265, o antigo 268). Final 275 (o antigo 278) = "1º do Grupo A x 1º do
--    Grupo B" (2 grupos, 1 classificado, FINAL). O Baleado Sub 9 M (274) e o
--    Vôlei Sub 17 (284) continuam grupo único, 1º colocado x 2º colocado.
-- 3) Horários novos (dia e local iguais): 19/11 Quadra do CEJA (94 -> 92 às
--    13:20, 92 -> 93 às 14:00, 93 -> 94 às 14:40); 20/11 Quadra do CEBC (206..213
--    -> 205..212, mais cedo); 21/11 Quadra da Adelieta (232..236 -> 229..233).
-- 4) Renumeração (tira o 205, o 230 e o 231 e o resto desce; a troca do 19/11
--    no CEJA à parte), em 2 FASES por causa do índice único de numero_tabela
--    (provisório = 10000 + número novo). Handebol F Sub 8: o 102 fica e o 275
--    vira 272. O rótulo "Vencedor do jogo N" de todas as vagas é regravado com o
--    número novo do jogo de origem (o jogo_origem_id não muda).
--
-- COMO O JOGO É ACHADO: competição (modalidade + categoria + gênero, nunca por
-- id) + fase + par de equipes (em qualquer ordem) + a ocorrência do par na
-- competição, por data e hora; no mata-mata, competição + fase + ordem por data
-- e hora. Nunca pelo numero_tabela nem pelo id. Cada linha do plano fica
-- APLICAR (como na 20268), FEITO (como na 20269) ou vazia (nenhum dos dois:
-- para o script). Todo jogo do banco tem de cair em exatamente uma linha.
--
-- IDEMPOTENTE: rodado de novo, cai tudo em FEITO e não grava nada.
--
-- SEGURANÇA: uma transação só. Cinco travas (CHECK em tabela temporária, erro
-- 3819 no MySQL e 4025 no MariaDB) param o script sem gravar nada:
--   db43_jogo_nao_bate        (antes de escrever: linha do plano sem estado ou
--        que achou mais de um jogo; jogo do banco fora do plano ou em duas linhas)
--   db43_estado_misto         (antes de escrever: parte APLICAR e parte FEITO)
--   db43_jogo_ja_mexido       (antes de escrever: jogo que muda ou sai, ou das
--        duas competições, com placar, vencedor, cobranças, prorrogação, súmula,
--        set, suspensão ou status diferente de AGENDADO; mata-mata com equipe
--        preenchida pelo automático; vaga de outro jogo vinda de jogo que sai)
--   db43_competicao_nao_bate  (antes de escrever: competição ou grupos não
--        achados; regra diferente da de antes e da de depois; equipe do CEJA no
--        Handebol Sub 11 F com súmula ou colocação; equipes a achar)
--   db43_conferencia_divergiu (antes do COMMIT: 299 jogos, 228 de grupo e 71 de
--        mata-mata, 36/92/75/25 e 0/0/9/62 por dia, numero_tabela de 1 a 299,
--        nenhuma equipe nem local com dois jogos no mesmo dia e hora, os 299 jogos
--        como na 20269, as duas competições como acima)
-- No cliente mysql o erro encerra a sessão e a transação é desfeita. No
-- DBeaver, se um comando falhar, rode ROLLBACK antes de qualquer outra coisa.
--
-- A final do Basquete F Sub 17 (288 -> 285) tem CEJA x CEBC em vagas MANUAIS
-- (db/34): só muda de número, e a vaga manual não conta como "preenchida".
--
-- Avisos que NÃO abortam (depois do COMMIT, só leitura): ESCOLA em dois jogos no
-- mesmo dia e hora envolvendo jogos que mudam de hora ou de equipe (equipes e
-- quadras diferentes) e, na tabela inteira, ATLETA inscrito em duas equipes que
-- jogam no mesmo dia e hora (marca se um dos jogos foi mexido por este script).
--
-- Só dados. Rode depois do 42. MySQL 8.0.16+ ou MariaDB 10.2+. Faça o dump
-- antes, na produção. Não entra no banco de fumaça. Sem dado de aluno.
-- NÃO repita o db/34, o db/39 nem o db/41 depois deste. Próximo script: o 44.
-- =====================================================================

SET NAMES utf8mb4;

START TRANSACTION;

-- Trava os jogos e as vagas: nada muda no meio do script
SELECT COUNT(*) AS jogos_travados FROM jogos FOR UPDATE;
SELECT COUNT(*) AS vagas_travadas FROM jogo_vagas FOR UPDATE;

-- ---------------------------------------------------------------------
-- O plano: os 299 jogos da 20269 e os 3 que saem
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS alvo_db43;
CREATE TEMPORARY TABLE alvo_db43 (
  ordem        INT          NOT NULL PRIMARY KEY,
  acao         VARCHAR(8)   NOT NULL,   -- IGUAL, ALTERAR ou REMOVER
  a            INT          NOT NULL,   -- numero_tabela na 20268
  b            INT          NULL,       -- numero_tabela na 20269
  modalidade   VARCHAR(60)  NOT NULL,
  categoria    VARCHAR(20)  NOT NULL,
  genero       VARCHAR(10)  NOT NULL,
  fase         VARCHAR(10)  NOT NULL,
  local_nome   VARCHAR(80)  NOT NULL,   -- nenhum jogo muda de local
  -- como na 20268
  g_antes      VARCHAR(2)   NULL,
  e1_antes     VARCHAR(100) NULL,       -- só na fase de grupos
  e2_antes     VARCHAR(100) NULL,
  occ_antes    INT          NOT NULL,   -- ocorrência do par (ou ordem no mata-mata) na competição
  dh_antes     DATETIME     NOT NULL,
  -- como na 20269
  g_novo       VARCHAR(2)   NULL,
  e1_novo      VARCHAR(100) NULL,
  e2_novo      VARCHAR(100) NULL,
  occ_novo     INT          NULL,
  dh_novo      DATETIME     NULL,
  -- o que foi achado
  comp_id      INT          NULL,
  n_antes      INT          NOT NULL DEFAULT 0,
  id_antes     INT          NULL,
  n_novo       INT          NOT NULL DEFAULT 0,
  id_novo      INT          NULL,
  jogo_id      INT          NULL,
  g_novo_id    INT          NULL,
  e1_novo_id   INT          NULL,       -- equipes do jogo que troca de equipe
  e2_novo_id   INT          NULL,
  -- o jogo achado como na 20268 (bate_antes) e como na 20269 (bate_novo):
  -- número, dia, hora, local e grupo iguais aos do plano
  bate_antes   TINYINT      NOT NULL DEFAULT 0,
  bate_novo    TINYINT      NOT NULL DEFAULT 0,
  estado       VARCHAR(10)  NOT NULL DEFAULT ''
);

INSERT INTO alvo_db43 (ordem, acao, a, b, modalidade, categoria, genero, fase, local_nome,
                       g_antes, e1_antes, e2_antes, occ_antes, dh_antes, g_novo, e1_novo, e2_novo, occ_novo, dh_novo) VALUES
  (  1, 'IGUAL', 1, 1, 'Baleado', 'Sub 11', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'B', 'MARIA DA GLORIA', 'FRANCISCO AMORIM', 1, '2026-11-18 14:30:00', 'B', 'MARIA DA GLORIA', 'FRANCISCO AMORIM', 1, '2026-11-18 14:30:00'),
  (  2, 'IGUAL', 2, 2, 'Baleado', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'B', 'Conveniada', 'ADELIETA RAMALHO', 1, '2026-11-18 15:10:00', 'B', 'Conveniada', 'ADELIETA RAMALHO', 1, '2026-11-18 15:10:00'),
  (  3, 'IGUAL', 3, 3, 'Baleado', 'Sub 13', 'FEMININO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'ADELIETA RAMALHO', 'PORTAL DO SABER', 1, '2026-11-18 15:50:00', 'A', 'ADELIETA RAMALHO', 'PORTAL DO SABER', 1, '2026-11-18 15:50:00'),
  (  4, 'IGUAL', 4, 4, 'Handebol', 'Sub 17', 'FEMININO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'CEBN', 'CEJA', 1, '2026-11-18 16:30:00', 'A', 'CEBN', 'CEJA', 1, '2026-11-18 16:30:00'),
  (  5, 'IGUAL', 5, 5, 'Baleado', 'Sub 17', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'CEJA', 'CETI', 1, '2026-11-18 17:10:00', 'A', 'CEJA', 'CETI', 1, '2026-11-18 17:10:00'),
  (  6, 'IGUAL', 6, 6, 'Futsal', 'Aberto', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'B', 'CEJA', 'CEBC', 1, '2026-11-18 18:50:00', 'B', 'CEJA', 'CEBC', 1, '2026-11-18 18:50:00'),
  (  7, 'IGUAL', 7, 7, 'Futsal', 'Sub 17', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'B', 'LUCIA ROCHA', 'VITORIA LIMA', 1, '2026-11-18 18:30:00', 'B', 'LUCIA ROCHA', 'VITORIA LIMA', 1, '2026-11-18 18:30:00'),
  (  8, 'IGUAL', 8, 8, 'Futsal', 'Sub 17', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'B', 'CETI', 'CEBC', 1, '2026-11-18 19:20:00', 'B', 'CETI', 'CEBC', 1, '2026-11-18 19:20:00'),
  (  9, 'IGUAL', 9, 9, 'Futsal', 'Aberto', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'B', 'CEJA', 'LUCIA ROCHA', 1, '2026-11-18 20:00:00', 'B', 'CEJA', 'LUCIA ROCHA', 1, '2026-11-18 20:00:00'),
  ( 10, 'IGUAL', 10, 10, 'Futsal', 'Aberto', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'MANOEL RAMOS', 'VITORIA LIMA', 1, '2026-11-18 20:40:00', 'A', 'MANOEL RAMOS', 'VITORIA LIMA', 1, '2026-11-18 20:40:00'),
  ( 11, 'IGUAL', 11, 11, 'Baleado', 'Sub 11', 'MASCULINO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'A', 'MANOEL RAMOS', 'ADELIETA RAMALHO', 1, '2026-11-18 14:30:00', 'A', 'MANOEL RAMOS', 'ADELIETA RAMALHO', 1, '2026-11-18 14:30:00'),
  ( 12, 'IGUAL', 12, 12, 'Baleado', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'C', 'EMILIANO ZAPATA', 'MANOEL RAMOS', 1, '2026-11-18 15:10:00', 'C', 'EMILIANO ZAPATA', 'MANOEL RAMOS', 1, '2026-11-18 15:10:00'),
  ( 13, 'IGUAL', 13, 13, 'Handebol', 'Sub 11', 'MASCULINO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'B', 'CEBC', 'JOSE DIAS', 1, '2026-11-18 15:50:00', 'B', 'CEBC', 'JOSE DIAS', 1, '2026-11-18 15:50:00'),
  ( 14, 'IGUAL', 14, 14, 'Handebol', 'Sub 11', 'MASCULINO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'A', 'CEJA', 'ADELIETA RAMALHO', 1, '2026-11-18 16:30:00', 'A', 'CEJA', 'ADELIETA RAMALHO', 1, '2026-11-18 16:30:00'),
  ( 15, 'IGUAL', 15, 15, 'Baleado', 'Sub 9', 'MASCULINO', 'GRUPOS', 'Quadra do Maria da Glória', 'A', 'ADELIETA RAMALHO', 'MARLENE SANTANA', 1, '2026-11-18 14:20:00', 'A', 'ADELIETA RAMALHO', 'MARLENE SANTANA', 1, '2026-11-18 14:20:00'),
  ( 16, 'IGUAL', 16, 16, 'Baleado', 'Sub 9', 'MASCULINO', 'GRUPOS', 'Quadra do Maria da Glória', 'A', 'TEODULO LEITE', 'MARIA DA GLORIA', 1, '2026-11-18 14:40:00', 'A', 'TEODULO LEITE', 'MARIA DA GLORIA', 1, '2026-11-18 14:40:00'),
  ( 17, 'IGUAL', 17, 17, 'Baleado', 'Sub 13', 'FEMININO', 'GRUPOS', 'Quadra do Maria da Glória', 'C', 'CEJA', 'MARIA DA GLORIA', 1, '2026-11-18 15:20:00', 'C', 'CEJA', 'MARIA DA GLORIA', 1, '2026-11-18 15:20:00'),
  ( 18, 'IGUAL', 18, 18, 'Baleado', 'Sub 13', 'FEMININO', 'GRUPOS', 'Quadra do Maria da Glória', 'B', 'EMILIANO ZAPATA', 'JOSE DIAS', 1, '2026-11-18 15:40:00', 'B', 'EMILIANO ZAPATA', 'JOSE DIAS', 1, '2026-11-18 15:40:00'),
  ( 19, 'IGUAL', 19, 19, 'Baleado', 'Sub 13', 'FEMININO', 'GRUPOS', 'Quadra do Maria da Glória', 'A', 'CEBN', 'Conveniada', 1, '2026-11-18 16:00:00', 'A', 'CEBN', 'Conveniada', 1, '2026-11-18 16:00:00'),
  ( 20, 'IGUAL', 20, 20, 'Baleado', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Quadra do Maria da Glória', 'A', 'JOSENILDO LEITE', 'CEBC', 1, '2026-11-18 16:20:00', 'A', 'JOSENILDO LEITE', 'CEBC', 1, '2026-11-18 16:20:00'),
  ( 21, 'IGUAL', 21, 21, 'Handebol', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Quadra do Maria da Glória', 'B', 'CEJA', 'CEBC', 1, '2026-11-18 16:40:00', 'B', 'CEJA', 'CEBC', 1, '2026-11-18 16:40:00'),
  ( 22, 'IGUAL', 22, 22, 'Futsal', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Quadra do CEJA', 'B', 'CEJA', 'JOSE DIAS', 1, '2026-11-18 14:00:00', 'B', 'CEJA', 'JOSE DIAS', 1, '2026-11-18 14:00:00'),
  ( 23, 'IGUAL', 23, 23, 'Futsal', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Quadra do CEJA', 'A', 'CEBC', 'MANOEL RAMOS', 1, '2026-11-18 14:40:00', 'A', 'CEBC', 'MANOEL RAMOS', 1, '2026-11-18 14:40:00'),
  ( 24, 'IGUAL', 24, 24, 'Futsal', 'Sub 17', 'MASCULINO', 'GRUPOS', 'Quadra do CEJA', 'A', 'CEJA', 'JOSE DIAS', 1, '2026-11-18 15:30:00', 'A', 'CEJA', 'JOSE DIAS', 1, '2026-11-18 15:30:00'),
  ( 25, 'IGUAL', 25, 25, 'Futsal', 'Sub 17', 'MASCULINO', 'GRUPOS', 'Quadra do CEJA', 'A', 'EMILIANO ZAPATA', 'JOSENILDO LEITE', 1, '2026-11-18 16:10:00', 'A', 'EMILIANO ZAPATA', 'JOSENILDO LEITE', 1, '2026-11-18 16:10:00'),
  ( 26, 'IGUAL', 26, 26, 'Futsal', 'Sub 7', 'MASCULINO', 'GRUPOS', 'Quadra do CETI', 'A', 'JOSE DIAS', 'ACM', 1, '2026-11-18 14:30:00', 'A', 'JOSE DIAS', 'ACM', 1, '2026-11-18 14:30:00'),
  ( 27, 'IGUAL', 27, 27, 'Futsal', 'Sub 9', 'MASCULINO', 'GRUPOS', 'Quadra do CETI', 'B', 'EMILIANO ZAPATA', 'JOSE DIAS', 1, '2026-11-18 15:10:00', 'B', 'EMILIANO ZAPATA', 'JOSE DIAS', 1, '2026-11-18 15:10:00'),
  ( 28, 'IGUAL', 28, 28, 'Futsal', 'Sub 9', 'MASCULINO', 'GRUPOS', 'Quadra do CETI', 'A', 'MARLENE SANTANA', 'ADELIETA RAMALHO', 1, '2026-11-18 15:50:00', 'A', 'MARLENE SANTANA', 'ADELIETA RAMALHO', 1, '2026-11-18 15:50:00'),
  ( 29, 'IGUAL', 29, 29, 'Futsal', 'Sub 7', 'MASCULINO', 'GRUPOS', 'Quadra do CETI', 'A', 'ADELIETA RAMALHO', 'TEODULO LEITE', 1, '2026-11-18 16:30:00', 'A', 'ADELIETA RAMALHO', 'TEODULO LEITE', 1, '2026-11-18 16:30:00'),
  ( 30, 'IGUAL', 30, 30, 'Futsal', 'Sub 11', 'MASCULINO', 'GRUPOS', 'Quadra do CEBC', 'C', 'MARLENE SANTANA', 'CEBC', 1, '2026-11-18 14:30:00', 'C', 'MARLENE SANTANA', 'CEBC', 1, '2026-11-18 14:30:00'),
  ( 31, 'IGUAL', 31, 31, 'Futsal', 'Sub 11', 'MASCULINO', 'GRUPOS', 'Quadra do CEBC', 'B', 'JOSENILDO LEITE', 'MARIA DA GLORIA', 1, '2026-11-18 15:10:00', 'B', 'JOSENILDO LEITE', 'MARIA DA GLORIA', 1, '2026-11-18 15:10:00'),
  ( 32, 'IGUAL', 32, 32, 'Futsal', 'Sub 11', 'MASCULINO', 'GRUPOS', 'Quadra do CEBC', 'A', 'EMILIANO ZAPATA', 'PORTAL DO SABER', 1, '2026-11-18 15:50:00', 'A', 'EMILIANO ZAPATA', 'PORTAL DO SABER', 1, '2026-11-18 15:50:00'),
  ( 33, 'IGUAL', 33, 33, 'Basquete', 'Sub 15', 'FEMININO', 'GRUPOS', 'Quadra do CEBC', 'A', 'CEBC', 'CEJA', 1, '2026-11-18 16:30:00', 'A', 'CEBC', 'CEJA', 1, '2026-11-18 16:30:00'),
  ( 34, 'IGUAL', 34, 34, 'Futebol Society', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Campo Society Arena Social', 'A', 'CEJA', 'JOSE DIAS', 1, '2026-11-18 15:00:00', 'A', 'CEJA', 'JOSE DIAS', 1, '2026-11-18 15:00:00'),
  ( 35, 'IGUAL', 35, 35, 'Futebol Society', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Campo Society Arena Social', 'B', 'CEBN', 'CEBC', 1, '2026-11-18 15:40:00', 'B', 'CEBN', 'CEBC', 1, '2026-11-18 15:40:00'),
  ( 36, 'IGUAL', 36, 36, 'Futebol Society', 'Sub 17', 'MASCULINO', 'GRUPOS', 'Campo Society Arena Social', 'A', 'CEBC', 'VITORIA LIMA', 1, '2026-11-18 16:20:00', 'A', 'CEBC', 'VITORIA LIMA', 1, '2026-11-18 16:20:00'),
  ( 37, 'IGUAL', 37, 37, 'Baleado', 'Sub 11', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'B', 'FRANCISCO AMORIM', 'EMILIANO ZAPATA', 1, '2026-11-19 08:00:00', 'B', 'FRANCISCO AMORIM', 'EMILIANO ZAPATA', 1, '2026-11-19 08:00:00'),
  ( 38, 'IGUAL', 38, 38, 'Baleado', 'Sub 11', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'MARLENE SANTANA', 'MANOEL RAMOS', 1, '2026-11-19 08:40:00', 'A', 'MARLENE SANTANA', 'MANOEL RAMOS', 1, '2026-11-19 08:40:00'),
  ( 39, 'IGUAL', 39, 39, 'Baleado', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'CEBC', 'CEJA', 1, '2026-11-19 09:20:00', 'A', 'CEBC', 'CEJA', 1, '2026-11-19 09:20:00'),
  ( 40, 'IGUAL', 40, 40, 'Baleado', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'B', 'CEBN', 'Conveniada', 1, '2026-11-19 10:00:00', 'B', 'CEBN', 'Conveniada', 1, '2026-11-19 10:00:00'),
  ( 41, 'IGUAL', 41, 41, 'Futsal', 'Sub 17', 'FEMININO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'CETI', 'VITORIA LIMA', 1, '2026-11-19 10:40:00', 'A', 'CETI', 'VITORIA LIMA', 1, '2026-11-19 10:40:00'),
  ( 42, 'IGUAL', 42, 42, 'Futsal', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'MANOEL RAMOS', 'EMILIANO ZAPATA', 1, '2026-11-19 11:20:00', 'A', 'MANOEL RAMOS', 'EMILIANO ZAPATA', 1, '2026-11-19 11:20:00'),
  ( 43, 'IGUAL', 43, 43, 'Futsal', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'B', 'JOSENILDO LEITE', 'Conveniada', 1, '2026-11-19 12:00:00', 'B', 'JOSENILDO LEITE', 'Conveniada', 1, '2026-11-19 12:00:00'),
  ( 44, 'IGUAL', 44, 44, 'Futsal', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'CEBC', 'EMILIANO ZAPATA', 1, '2026-11-19 12:40:00', 'A', 'CEBC', 'EMILIANO ZAPATA', 1, '2026-11-19 12:40:00'),
  ( 45, 'IGUAL', 45, 45, 'Futsal', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'JOSENILDO LEITE', 'CEJA', 1, '2026-11-19 13:20:00', 'A', 'JOSENILDO LEITE', 'CEJA', 1, '2026-11-19 13:20:00'),
  ( 46, 'IGUAL', 46, 46, 'Futsal', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'B', 'CEBN', 'Conveniada', 1, '2026-11-19 14:00:00', 'B', 'CEBN', 'Conveniada', 1, '2026-11-19 14:00:00'),
  ( 47, 'IGUAL', 47, 47, 'Baleado', 'Sub 11', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'JOSE DIAS', 'ADELIETA RAMALHO', 1, '2026-11-19 14:40:00', 'A', 'JOSE DIAS', 'ADELIETA RAMALHO', 1, '2026-11-19 14:40:00'),
  ( 48, 'IGUAL', 48, 48, 'Baleado', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'CEJA', 'JOSENILDO LEITE', 1, '2026-11-19 15:20:00', 'A', 'CEJA', 'JOSENILDO LEITE', 1, '2026-11-19 15:20:00'),
  ( 49, 'IGUAL', 49, 49, 'Baleado', 'Sub 17', 'FEMININO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'CETI', 'CEJA', 1, '2026-11-19 16:00:00', 'A', 'CETI', 'CEJA', 1, '2026-11-19 16:00:00'),
  ( 50, 'IGUAL', 50, 50, 'Handebol', 'Aberto', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'CETI', 'CEJA', 1, '2026-11-19 16:40:00', 'A', 'CETI', 'CEJA', 1, '2026-11-19 16:40:00'),
  ( 51, 'IGUAL', 51, 51, 'Baleado', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'B', 'ADELIETA RAMALHO', 'CEBN', 1, '2026-11-19 17:20:00', 'B', 'ADELIETA RAMALHO', 'CEBN', 1, '2026-11-19 17:20:00'),
  ( 52, 'IGUAL', 52, 52, 'Futsal', 'Aberto', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'CETI', 'VITORIA LIMA', 1, '2026-11-19 18:00:00', 'A', 'CETI', 'VITORIA LIMA', 1, '2026-11-19 18:00:00'),
  ( 53, 'IGUAL', 53, 53, 'Futsal', 'Aberto', 'FEMININO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'LUCIA ROCHA', 'CETI', 1, '2026-11-19 18:40:00', 'A', 'LUCIA ROCHA', 'CETI', 1, '2026-11-19 18:40:00'),
  ( 54, 'IGUAL', 54, 54, 'Futsal', 'Sub 17', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'JOSE DIAS', 'JOSENILDO LEITE', 1, '2026-11-19 19:20:00', 'A', 'JOSE DIAS', 'JOSENILDO LEITE', 1, '2026-11-19 19:20:00'),
  ( 55, 'IGUAL', 55, 55, 'Futsal', 'Aberto', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'CETI', 'MANOEL RAMOS', 1, '2026-11-19 20:00:00', 'A', 'CETI', 'MANOEL RAMOS', 1, '2026-11-19 20:00:00'),
  ( 56, 'IGUAL', 56, 56, 'Futsal', 'Aberto', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'B', 'LUCIA ROCHA', 'CEBC', 1, '2026-11-19 20:40:00', 'B', 'LUCIA ROCHA', 'CEBC', 1, '2026-11-19 20:40:00'),
  ( 57, 'IGUAL', 57, 57, 'Baleado', 'Sub 13', 'FEMININO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'A', 'CEBN', 'ADELIETA RAMALHO', 1, '2026-11-19 08:00:00', 'A', 'CEBN', 'ADELIETA RAMALHO', 1, '2026-11-19 08:00:00'),
  ( 58, 'IGUAL', 58, 58, 'Baleado', 'Sub 13', 'FEMININO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'B', 'CEBC', 'EMILIANO ZAPATA', 1, '2026-11-19 08:40:00', 'B', 'CEBC', 'EMILIANO ZAPATA', 1, '2026-11-19 08:40:00'),
  ( 59, 'IGUAL', 59, 59, 'Baleado', 'Sub 13', 'FEMININO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'C', 'CEJA', 'MANOEL RAMOS', 1, '2026-11-19 09:20:00', 'C', 'CEJA', 'MANOEL RAMOS', 1, '2026-11-19 09:20:00'),
  ( 60, 'IGUAL', 60, 60, 'Handebol', 'Sub 11', 'MASCULINO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'B', 'JOSE DIAS', 'FRANCISCO AMORIM', 1, '2026-11-19 10:00:00', 'B', 'JOSE DIAS', 'FRANCISCO AMORIM', 1, '2026-11-19 10:00:00'),
  ( 61, 'IGUAL', 61, 61, 'Handebol', 'Sub 11', 'MASCULINO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'A', 'ADELIETA RAMALHO', 'MARIA DA GLORIA', 1, '2026-11-19 10:40:00', 'A', 'ADELIETA RAMALHO', 'MARIA DA GLORIA', 1, '2026-11-19 10:40:00'),
  ( 62, 'IGUAL', 62, 62, 'Futsal', 'Sub 13', 'FEMININO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'A', 'CEJA', 'CEBN', 1, '2026-11-19 11:20:00', 'A', 'CEJA', 'CEBN', 1, '2026-11-19 11:20:00'),
  ( 63, 'IGUAL', 63, 63, 'Futsal', 'Sub 15', 'FEMININO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'A', 'CEBN', 'EMILIANO ZAPATA', 1, '2026-11-19 12:00:00', 'A', 'CEBN', 'EMILIANO ZAPATA', 1, '2026-11-19 12:00:00'),
  ( 64, 'IGUAL', 64, 64, 'Futsal', 'Sub 15', 'FEMININO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'B', 'CEBC', 'Conveniada', 1, '2026-11-19 12:40:00', 'B', 'CEBC', 'Conveniada', 1, '2026-11-19 12:40:00'),
  ( 65, 'IGUAL', 65, 65, 'Futsal', 'Sub 11', 'MASCULINO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'B', 'FRANCISCO AMORIM', 'MARIA DA GLORIA', 1, '2026-11-19 13:20:00', 'B', 'FRANCISCO AMORIM', 'MARIA DA GLORIA', 1, '2026-11-19 13:20:00'),
  ( 66, 'IGUAL', 66, 66, 'Handebol', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'A', 'CEBN', 'Conveniada', 1, '2026-11-19 14:00:00', 'A', 'CEBN', 'Conveniada', 1, '2026-11-19 14:00:00'),
  ( 67, 'IGUAL', 67, 67, 'Handebol', 'Sub 11', 'FEMININO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'A', 'FRANCISCO AMORIM', 'MARIA DA GLORIA', 1, '2026-11-19 14:40:00', 'A', 'FRANCISCO AMORIM', 'MARIA DA GLORIA', 1, '2026-11-19 14:40:00'),
  ( 68, 'IGUAL', 68, 68, 'Handebol', 'Sub 11', 'FEMININO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'B', 'JOSE DIAS', 'MARLENE SANTANA', 1, '2026-11-19 15:20:00', 'B', 'JOSE DIAS', 'MARLENE SANTANA', 1, '2026-11-19 15:20:00'),
  ( 69, 'IGUAL', 69, 69, 'Handebol', 'Sub 8', 'MASCULINO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'A', 'ACM', 'ADELIETA RAMALHO', 1, '2026-11-19 16:00:00', 'A', 'ACM', 'ADELIETA RAMALHO', 1, '2026-11-19 16:00:00'),
  ( 70, 'IGUAL', 70, 70, 'Futsal', 'Sub 9', 'MASCULINO', 'GRUPOS', 'Quadra do Maria da Glória', 'B', 'MARIA DA GLORIA', 'TEODULO LEITE', 1, '2026-11-19 08:00:00', 'B', 'MARIA DA GLORIA', 'TEODULO LEITE', 1, '2026-11-19 08:00:00'),
  ( 71, 'IGUAL', 71, 71, 'Futsal', 'Sub 9', 'MASCULINO', 'GRUPOS', 'Quadra do Maria da Glória', 'A', 'MARLENE SANTANA', 'PORTAL DO SABER', 1, '2026-11-19 08:40:00', 'A', 'MARLENE SANTANA', 'PORTAL DO SABER', 1, '2026-11-19 08:40:00'),
  ( 72, 'IGUAL', 72, 72, 'Baleado', 'Sub 17', 'MASCULINO', 'GRUPOS', 'Quadra do Maria da Glória', 'A', 'CEBC', 'JOSENILDO LEITE', 1, '2026-11-19 09:20:00', 'A', 'CEBC', 'JOSENILDO LEITE', 1, '2026-11-19 09:20:00'),
  ( 73, 'IGUAL', 73, 73, 'Baleado', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Quadra do Maria da Glória', 'C', 'MARIA DA GLORIA', 'EMILIANO ZAPATA', 1, '2026-11-19 10:00:00', 'C', 'MARIA DA GLORIA', 'EMILIANO ZAPATA', 1, '2026-11-19 10:00:00'),
  ( 74, 'IGUAL', 74, 74, 'Baleado', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Quadra do Maria da Glória', 'B', 'Conveniada', 'MANOEL RAMOS', 1, '2026-11-19 10:40:00', 'B', 'Conveniada', 'MANOEL RAMOS', 1, '2026-11-19 10:40:00'),
  ( 75, 'IGUAL', 75, 75, 'Baleado', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Quadra do Maria da Glória', 'A', 'CEBC', 'CEBN', 1, '2026-11-19 11:20:00', 'A', 'CEBC', 'CEBN', 1, '2026-11-19 11:20:00'),
  ( 76, 'IGUAL', 76, 76, 'Baleado', 'Sub 9', 'MASCULINO', 'GRUPOS', 'Quadra do Maria da Glória', 'A', 'MARIA DA GLORIA', 'FRANCISCO AMORIM', 1, '2026-11-19 12:00:00', 'A', 'MARIA DA GLORIA', 'FRANCISCO AMORIM', 1, '2026-11-19 12:00:00'),
  ( 77, 'IGUAL', 77, 77, 'Futsal', 'Sub 17', 'FEMININO', 'GRUPOS', 'Quadra do Maria da Glória', 'A', 'CEBC', 'CEJA', 1, '2026-11-19 12:40:00', 'A', 'CEBC', 'CEJA', 1, '2026-11-19 12:40:00'),
  ( 78, 'IGUAL', 78, 78, 'Futsal', 'Sub 13', 'FEMININO', 'GRUPOS', 'Quadra do Maria da Glória', 'A', 'EMILIANO ZAPATA', 'CEJA', 1, '2026-11-19 13:20:00', 'A', 'EMILIANO ZAPATA', 'CEJA', 1, '2026-11-19 13:20:00'),
  ( 79, 'IGUAL', 79, 79, 'Futsal', 'Sub 9', 'MASCULINO', 'GRUPOS', 'Quadra do Maria da Glória', 'B', 'JOSE DIAS', 'MARIA DA GLORIA', 1, '2026-11-19 14:00:00', 'B', 'JOSE DIAS', 'MARIA DA GLORIA', 1, '2026-11-19 14:00:00'),
  ( 80, 'IGUAL', 80, 80, 'Futsal', 'Sub 9', 'MASCULINO', 'GRUPOS', 'Quadra do Maria da Glória', 'A', 'FRANCISCO AMORIM', 'PORTAL DO SABER', 1, '2026-11-19 14:40:00', 'A', 'FRANCISCO AMORIM', 'PORTAL DO SABER', 1, '2026-11-19 14:40:00'),
  ( 81, 'IGUAL', 81, 81, 'Baleado', 'Sub 13', 'FEMININO', 'GRUPOS', 'Quadra do Maria da Glória', 'C', 'MARIA DA GLORIA', 'MANOEL RAMOS', 1, '2026-11-19 15:20:00', 'C', 'MARIA DA GLORIA', 'MANOEL RAMOS', 1, '2026-11-19 15:20:00'),
  ( 82, 'IGUAL', 82, 82, 'Baleado', 'Sub 13', 'FEMININO', 'GRUPOS', 'Quadra do Maria da Glória', 'B', 'JOSE DIAS', 'CEBC', 1, '2026-11-19 16:00:00', 'B', 'JOSE DIAS', 'CEBC', 1, '2026-11-19 16:00:00'),
  ( 83, 'IGUAL', 83, 83, 'Baleado', 'Sub 13', 'FEMININO', 'GRUPOS', 'Quadra do Maria da Glória', 'A', 'PORTAL DO SABER', 'Conveniada', 1, '2026-11-19 16:40:00', 'A', 'PORTAL DO SABER', 'Conveniada', 1, '2026-11-19 16:40:00'),
  ( 84, 'IGUAL', 84, 84, 'Futsal', 'Sub 11', 'MASCULINO', 'GRUPOS', 'Quadra do CEJA', 'A', 'ADELIETA RAMALHO', 'CEJA', 1, '2026-11-19 08:00:00', 'A', 'ADELIETA RAMALHO', 'CEJA', 1, '2026-11-19 08:00:00'),
  ( 85, 'IGUAL', 85, 85, 'Futsal', 'Sub 11', 'MASCULINO', 'GRUPOS', 'Quadra do CEJA', 'C', 'JOSE DIAS', 'MARLENE SANTANA', 1, '2026-11-19 08:40:00', 'C', 'JOSE DIAS', 'MARLENE SANTANA', 1, '2026-11-19 08:40:00'),
  ( 86, 'IGUAL', 86, 86, 'Futsal', 'Sub 17', 'MASCULINO', 'GRUPOS', 'Quadra do CEJA', 'A', 'EMILIANO ZAPATA', 'CEJA', 1, '2026-11-19 09:20:00', 'A', 'EMILIANO ZAPATA', 'CEJA', 1, '2026-11-19 09:20:00'),
  ( 87, 'IGUAL', 87, 87, 'Baleado', 'Sub 11', 'FEMININO', 'GRUPOS', 'Quadra do CEJA', 'B', 'JOSE DIAS', 'CEJA', 1, '2026-11-19 10:00:00', 'B', 'JOSE DIAS', 'CEJA', 1, '2026-11-19 10:00:00'),
  ( 88, 'IGUAL', 88, 88, 'Futsal', 'Sub 17', 'MASCULINO', 'GRUPOS', 'Quadra do CEJA', 'B', 'VITORIA LIMA', 'CETI', 1, '2026-11-19 10:40:00', 'B', 'VITORIA LIMA', 'CETI', 1, '2026-11-19 10:40:00'),
  ( 89, 'IGUAL', 89, 89, 'Futsal', 'Sub 17', 'MASCULINO', 'GRUPOS', 'Quadra do CEJA', 'B', 'LUCIA ROCHA', 'CEBC', 1, '2026-11-19 11:20:00', 'B', 'LUCIA ROCHA', 'CEBC', 1, '2026-11-19 11:20:00'),
  ( 90, 'IGUAL', 90, 90, 'Baleado', 'Sub 15', 'FEMININO', 'GRUPOS', 'Quadra do CEJA', 'B', 'Conveniada', 'EMILIANO ZAPATA', 1, '2026-11-19 12:00:00', 'B', 'Conveniada', 'EMILIANO ZAPATA', 1, '2026-11-19 12:00:00'),
  ( 91, 'IGUAL', 91, 91, 'Baleado', 'Sub 15', 'FEMININO', 'GRUPOS', 'Quadra do CEJA', 'A', 'CEBN', 'JOSENILDO LEITE', 1, '2026-11-19 12:40:00', 'A', 'CEBN', 'JOSENILDO LEITE', 1, '2026-11-19 12:40:00'),
  ( 92, 'ALTERAR', 94, 92, 'Baleado', 'Sub 11', 'FEMININO', 'GRUPOS', 'Quadra do CEJA', 'B', 'EMILIANO ZAPATA', 'MARIA DA GLORIA', 1, '2026-11-19 14:40:00', 'B', 'EMILIANO ZAPATA', 'MARIA DA GLORIA', 1, '2026-11-19 13:20:00'),
  ( 93, 'ALTERAR', 92, 93, 'Baleado', 'Sub 11', 'FEMININO', 'GRUPOS', 'Quadra do CEJA', 'A', 'PORTAL DO SABER', 'ADELIETA RAMALHO', 1, '2026-11-19 13:20:00', 'A', 'PORTAL DO SABER', 'ADELIETA RAMALHO', 1, '2026-11-19 14:00:00'),
  ( 94, 'ALTERAR', 93, 94, 'Baleado', 'Sub 11', 'FEMININO', 'GRUPOS', 'Quadra do CEJA', 'A', 'JOSENILDO LEITE', 'FRANCISCO AMORIM', 1, '2026-11-19 14:00:00', 'A', 'JOSENILDO LEITE', 'FRANCISCO AMORIM', 1, '2026-11-19 14:40:00'),
  ( 95, 'IGUAL', 95, 95, 'Handebol', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Quadra do CEJA', 'B', 'CEBC', 'ADELIETA RAMALHO', 1, '2026-11-19 15:20:00', 'B', 'CEBC', 'ADELIETA RAMALHO', 1, '2026-11-19 15:20:00'),
  ( 96, 'IGUAL', 96, 96, 'Handebol', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Quadra do CEJA', 'A', 'CEJA', 'CEBN', 1, '2026-11-19 16:00:00', 'A', 'CEJA', 'CEBN', 1, '2026-11-19 16:00:00'),
  ( 97, 'IGUAL', 97, 97, 'Handebol', 'Sub 17', 'FEMININO', 'GRUPOS', 'Quadra do CEBC', 'A', 'CETI', 'CEBN', 1, '2026-11-19 08:00:00', 'A', 'CETI', 'CEBN', 1, '2026-11-19 08:00:00'),
  ( 98, 'IGUAL', 98, 98, 'Handebol', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Quadra do CEBC', 'A', 'Conveniada', 'JOSE DIAS', 1, '2026-11-19 08:40:00', 'A', 'Conveniada', 'JOSE DIAS', 1, '2026-11-19 08:40:00'),
  ( 99, 'IGUAL', 99, 99, 'Handebol', 'Sub 9', 'FEMININO', 'GRUPOS', 'Quadra do CEBC', 'A', 'ADELIETA RAMALHO', 'FRANCISCO AMORIM', 1, '2026-11-19 09:20:00', 'A', 'ADELIETA RAMALHO', 'FRANCISCO AMORIM', 1, '2026-11-19 09:20:00'),
  (100, 'IGUAL', 100, 100, 'Futsal', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Quadra do CEBC', 'B', 'JOSE DIAS', 'JOSENILDO LEITE', 1, '2026-11-19 10:00:00', 'B', 'JOSE DIAS', 'JOSENILDO LEITE', 1, '2026-11-19 10:00:00'),
  (101, 'IGUAL', 101, 101, 'Basquete', 'Sub 15', 'FEMININO', 'GRUPOS', 'Quadra do CEBC', 'A', 'Conveniada', 'CEBC', 1, '2026-11-19 10:40:00', 'A', 'Conveniada', 'CEBC', 1, '2026-11-19 10:40:00'),
  (102, 'IGUAL', 102, 102, 'Handebol', 'Sub 8', 'FEMININO', 'GRUPOS', 'Quadra do CEBC', 'A', 'ACM', 'JOSE DIAS', 1, '2026-11-19 11:20:00', 'A', 'ACM', 'JOSE DIAS', 1, '2026-11-19 11:20:00'),
  (103, 'IGUAL', 103, 103, 'Basquete', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Quadra do CEBC', 'A', 'CEJA', 'Conveniada', 1, '2026-11-19 12:00:00', 'A', 'CEJA', 'Conveniada', 1, '2026-11-19 12:00:00'),
  (104, 'IGUAL', 104, 104, 'Basquete', 'Sub 17', 'MASCULINO', 'GRUPOS', 'Quadra do CEBC', 'A', 'CETI', 'CEBC', 1, '2026-11-19 12:40:00', 'A', 'CETI', 'CEBC', 1, '2026-11-19 12:40:00'),
  (105, 'IGUAL', 105, 105, 'Futsal', 'Sub 11', 'MASCULINO', 'GRUPOS', 'Quadra do CEBC', 'A', 'CEJA', 'EMILIANO ZAPATA', 1, '2026-11-19 13:20:00', 'A', 'CEJA', 'EMILIANO ZAPATA', 1, '2026-11-19 13:20:00'),
  (106, 'IGUAL', 106, 106, 'Futsal', 'Sub 11', 'MASCULINO', 'GRUPOS', 'Quadra do CEBC', 'C', 'CEBC', 'JOSE DIAS', 1, '2026-11-19 14:00:00', 'C', 'CEBC', 'JOSE DIAS', 1, '2026-11-19 14:00:00'),
  (107, 'IGUAL', 107, 107, 'Handebol', 'Sub 17', 'MASCULINO', 'GRUPOS', 'Quadra do CEBC', 'B', 'CETI', 'CEBC', 1, '2026-11-19 14:40:00', 'B', 'CETI', 'CEBC', 1, '2026-11-19 14:40:00'),
  (108, 'IGUAL', 108, 108, 'Handebol', 'Sub 17', 'MASCULINO', 'GRUPOS', 'Quadra do CEBC', 'A', 'CEJA', 'Conveniada', 1, '2026-11-19 15:20:00', 'A', 'CEJA', 'Conveniada', 1, '2026-11-19 15:20:00'),
  (109, 'IGUAL', 109, 109, 'Handebol', 'Sub 13', 'FEMININO', 'GRUPOS', 'Quadra do CEBC', 'A', 'CEBC', 'CEBN', 1, '2026-11-19 16:00:00', 'A', 'CEBC', 'CEBN', 1, '2026-11-19 16:00:00'),
  (110, 'IGUAL', 110, 110, 'Basquete', 'Sub 17', 'MASCULINO', 'GRUPOS', 'Quadra do CEBC', 'A', 'CEBC', 'CEJA', 1, '2026-11-19 16:40:00', 'A', 'CEBC', 'CEJA', 1, '2026-11-19 16:40:00'),
  (111, 'IGUAL', 111, 111, 'Futsal', 'Sub 9', 'FEMININO', 'GRUPOS', 'Quadra do CETI', 'A', 'MARLENE SANTANA', 'JOSE DIAS', 1, '2026-11-19 08:00:00', 'A', 'MARLENE SANTANA', 'JOSE DIAS', 1, '2026-11-19 08:00:00'),
  (112, 'IGUAL', 112, 112, 'Futsal', 'Sub 7', 'MASCULINO', 'GRUPOS', 'Quadra do CETI', 'A', 'JOSE DIAS', 'ADELIETA RAMALHO', 1, '2026-11-19 08:40:00', 'A', 'JOSE DIAS', 'ADELIETA RAMALHO', 1, '2026-11-19 08:40:00'),
  (113, 'IGUAL', 113, 113, 'Futsal', 'Sub 7', 'MASCULINO', 'GRUPOS', 'Quadra do CETI', 'A', 'TEODULO LEITE', 'ACM', 1, '2026-11-19 09:20:00', 'A', 'TEODULO LEITE', 'ACM', 1, '2026-11-19 09:20:00'),
  (114, 'IGUAL', 114, 114, 'Vôlei', 'Aberto', 'MISTO', 'GRUPOS', 'Quadra do CETI', 'A', 'CETI', 'CEBC', 1, '2026-11-19 10:00:00', 'A', 'CETI', 'CEBC', 1, '2026-11-19 10:00:00'),
  (115, 'IGUAL', 115, 115, 'Vôlei', 'Sub 15', 'MISTO', 'GRUPOS', 'Quadra do CETI', 'A', 'EMILIANO ZAPATA', 'CEBC', 1, '2026-11-19 10:40:00', 'A', 'EMILIANO ZAPATA', 'CEBC', 1, '2026-11-19 10:40:00'),
  (116, 'IGUAL', 116, 116, 'Futsal', 'Sub 8', 'MASCULINO', 'GRUPOS', 'Quadra do CETI', 'A', 'ADELIETA RAMALHO', 'JOSE DIAS', 1, '2026-11-19 11:20:00', 'A', 'ADELIETA RAMALHO', 'JOSE DIAS', 1, '2026-11-19 11:20:00'),
  (117, 'IGUAL', 117, 117, 'Futsal', 'Sub 8', 'MASCULINO', 'GRUPOS', 'Quadra do CETI', 'B', 'TEODULO LEITE', 'MARLENE SANTANA', 1, '2026-11-19 12:00:00', 'B', 'TEODULO LEITE', 'MARLENE SANTANA', 1, '2026-11-19 12:00:00'),
  (118, 'IGUAL', 118, 118, 'Futsal', 'Sub 8', 'FEMININO', 'GRUPOS', 'Quadra do CETI', 'A', 'JOSE DIAS', 'EMILIANO ZAPATA', 1, '2026-11-19 12:40:00', 'A', 'JOSE DIAS', 'EMILIANO ZAPATA', 1, '2026-11-19 12:40:00'),
  (119, 'IGUAL', 119, 119, 'Futsal', 'Sub 11', 'FEMININO', 'GRUPOS', 'Quadra do CETI', 'A', 'JOSE DIAS', 'MARLENE SANTANA', 1, '2026-11-19 13:20:00', 'A', 'JOSE DIAS', 'MARLENE SANTANA', 1, '2026-11-19 13:20:00'),
  (120, 'IGUAL', 120, 120, 'Vôlei', 'Sub 15', 'MISTO', 'GRUPOS', 'Quadra do CETI', 'A', 'CEJA', 'CEBN', 1, '2026-11-19 14:00:00', 'A', 'CEJA', 'CEBN', 1, '2026-11-19 14:00:00'),
  (121, 'IGUAL', 121, 121, 'Vôlei', 'Sub 17', 'MISTO', 'GRUPOS', 'Quadra do CETI', 'A', 'CEBC', 'CETI', 1, '2026-11-19 14:40:00', 'A', 'CEBC', 'CETI', 1, '2026-11-19 14:40:00'),
  (122, 'IGUAL', 122, 122, 'Vôlei', 'Sub 17', 'MISTO', 'GRUPOS', 'Quadra do CETI', 'A', 'LUCIA ROCHA', 'CEBN', 1, '2026-11-19 15:20:00', 'A', 'LUCIA ROCHA', 'CEBN', 1, '2026-11-19 15:20:00'),
  (123, 'IGUAL', 123, 123, 'Futebol Society', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Campo Society Arena Social', 'A', 'CEJA', 'CEBC', 1, '2026-11-19 08:30:00', 'A', 'CEJA', 'CEBC', 1, '2026-11-19 08:30:00'),
  (124, 'IGUAL', 124, 124, 'Futebol Society', 'Sub 17', 'MASCULINO', 'GRUPOS', 'Campo Society Arena Social', 'A', 'CETI', 'CEBC', 1, '2026-11-19 09:10:00', 'A', 'CETI', 'CEBC', 1, '2026-11-19 09:10:00'),
  (125, 'IGUAL', 125, 125, 'Futebol Society', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Campo Society Arena Social', 'A', 'JOSE DIAS', 'Conveniada', 1, '2026-11-19 09:50:00', 'A', 'JOSE DIAS', 'Conveniada', 1, '2026-11-19 09:50:00'),
  (126, 'IGUAL', 126, 126, 'Futebol Society', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Campo Society Arena Social', 'B', 'CEBC', 'CEBN', 2, '2026-11-19 14:00:00', 'B', 'CEBC', 'CEBN', 2, '2026-11-19 14:00:00'),
  (127, 'IGUAL', 127, 127, 'Futebol Society', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Campo Society Arena Social', 'B', 'MARIA DA GLORIA', 'CEBN', 1, '2026-11-19 14:40:00', 'B', 'MARIA DA GLORIA', 'CEBN', 1, '2026-11-19 14:40:00'),
  (128, 'IGUAL', 128, 128, 'Futebol Society', 'Sub 17', 'MASCULINO', 'GRUPOS', 'Campo Society Arena Social', 'A', 'CEJA', 'VITORIA LIMA', 1, '2026-11-19 15:20:00', 'A', 'CEJA', 'VITORIA LIMA', 1, '2026-11-19 15:20:00'),
  (129, 'IGUAL', 129, 129, 'Baleado', 'Sub 11', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'B', 'EMILIANO ZAPATA', 'MARIA DA GLORIA', 1, '2026-11-20 08:00:00', 'B', 'EMILIANO ZAPATA', 'MARIA DA GLORIA', 1, '2026-11-20 08:00:00'),
  (130, 'IGUAL', 130, 130, 'Baleado', 'Sub 11', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'JOSE DIAS', 'MARLENE SANTANA', 1, '2026-11-20 08:40:00', 'A', 'JOSE DIAS', 'MARLENE SANTANA', 1, '2026-11-20 08:40:00'),
  (131, 'IGUAL', 131, 131, 'Handebol', 'Sub 11', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'CEJA', 'MARIA DA GLORIA', 1, '2026-11-20 09:20:00', 'A', 'CEJA', 'MARIA DA GLORIA', 1, '2026-11-20 09:20:00'),
  (132, 'IGUAL', 132, 132, 'Handebol', 'Sub 11', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'B', 'CEBC', 'FRANCISCO AMORIM', 1, '2026-11-20 10:00:00', 'B', 'CEBC', 'FRANCISCO AMORIM', 1, '2026-11-20 10:00:00'),
  (133, 'IGUAL', 133, 133, 'Futsal', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'EMILIANO ZAPATA', 'JOSENILDO LEITE', 1, '2026-11-20 10:40:00', 'A', 'EMILIANO ZAPATA', 'JOSENILDO LEITE', 1, '2026-11-20 10:40:00'),
  (134, 'IGUAL', 134, 134, 'Futsal', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'B', 'CEBN', 'JOSE DIAS', 1, '2026-11-20 11:20:00', 'B', 'CEBN', 'JOSE DIAS', 1, '2026-11-20 11:20:00'),
  (135, 'IGUAL', 135, 135, 'Futsal', 'Sub 17', 'FEMININO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'CETI', 'CEJA', 1, '2026-11-20 12:00:00', 'A', 'CETI', 'CEJA', 1, '2026-11-20 12:00:00'),
  (136, 'IGUAL', 136, 136, 'Futsal', 'Sub 17', 'FEMININO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'CEBC', 'VITORIA LIMA', 1, '2026-11-20 12:40:00', 'A', 'CEBC', 'VITORIA LIMA', 1, '2026-11-20 12:40:00'),
  (137, 'IGUAL', 137, 137, 'Baleado', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'CEBC', 'JOSENILDO LEITE', 2, '2026-11-20 13:20:00', 'A', 'CEBC', 'JOSENILDO LEITE', 2, '2026-11-20 13:20:00'),
  (138, 'IGUAL', 138, 138, 'Handebol', 'Aberto', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'CETI', 'LUCIA ROCHA', 1, '2026-11-20 14:40:00', 'A', 'CETI', 'LUCIA ROCHA', 1, '2026-11-20 14:40:00'),
  (139, 'IGUAL', 139, 139, 'Baleado', 'Sub 15', 'FEMININO', 'GRUPOS', 'Ginásio de Esportes', 'B', 'CEJA', 'Conveniada', 1, '2026-11-20 15:20:00', 'B', 'CEJA', 'Conveniada', 1, '2026-11-20 15:20:00'),
  (140, 'IGUAL', 140, 140, 'Baleado', 'Sub 15', 'FEMININO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'CEBN', 'CEBC', 1, '2026-11-20 16:00:00', 'A', 'CEBN', 'CEBC', 1, '2026-11-20 16:00:00'),
  (141, 'IGUAL', 141, 141, 'Handebol', 'Sub 17', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'Conveniada', 'CEBN', 1, '2026-11-20 16:40:00', 'A', 'Conveniada', 'CEBN', 1, '2026-11-20 16:40:00'),
  (142, 'IGUAL', 142, 142, 'Handebol', 'Sub 17', 'MASCULINO', 'GRUPOS', 'Ginásio de Esportes', 'B', 'CEBC', 'CETI', 2, '2026-11-20 17:20:00', 'B', 'CEBC', 'CETI', 2, '2026-11-20 17:20:00'),
  (143, 'IGUAL', 143, 143, 'Futsal', 'Aberto', 'FEMININO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'VITORIA LIMA', 'CETI', 1, '2026-11-20 18:00:00', 'A', 'VITORIA LIMA', 'CETI', 1, '2026-11-20 18:00:00'),
  (144, 'IGUAL', 144, 144, 'Futsal', 'Sub 17', 'MASCULINO', 'SEMIFINAL', 'Ginásio de Esportes', NULL, NULL, NULL, 1, '2026-11-20 18:40:00', NULL, NULL, NULL, 1, '2026-11-20 18:40:00'),
  (145, 'IGUAL', 145, 145, 'Futsal', 'Sub 17', 'MASCULINO', 'SEMIFINAL', 'Ginásio de Esportes', NULL, NULL, NULL, 2, '2026-11-20 19:20:00', NULL, NULL, NULL, 2, '2026-11-20 19:20:00'),
  (146, 'IGUAL', 146, 146, 'Futsal', 'Aberto', 'MASCULINO', 'SEMIFINAL', 'Ginásio de Esportes', NULL, NULL, NULL, 1, '2026-11-20 20:00:00', NULL, NULL, NULL, 1, '2026-11-20 20:00:00'),
  (147, 'IGUAL', 147, 147, 'Futsal', 'Aberto', 'MASCULINO', 'SEMIFINAL', 'Ginásio de Esportes', NULL, NULL, NULL, 2, '2026-11-20 20:40:00', NULL, NULL, NULL, 2, '2026-11-20 20:40:00'),
  (148, 'IGUAL', 148, 148, 'Handebol', 'Sub 11', 'FEMININO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'B', 'MARLENE SANTANA', 'ADELIETA RAMALHO', 1, '2026-11-20 08:00:00', 'B', 'MARLENE SANTANA', 'ADELIETA RAMALHO', 1, '2026-11-20 08:00:00'),
  (149, 'IGUAL', 149, 149, 'Futsal', 'Sub 11', 'MASCULINO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'B', 'FRANCISCO AMORIM', 'JOSENILDO LEITE', 1, '2026-11-20 08:40:00', 'B', 'FRANCISCO AMORIM', 'JOSENILDO LEITE', 1, '2026-11-20 08:40:00'),
  (150, 'IGUAL', 150, 150, 'Futsal', 'Sub 9', 'MASCULINO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'B', 'EMILIANO ZAPATA', 'TEODULO LEITE', 1, '2026-11-20 09:20:00', 'B', 'EMILIANO ZAPATA', 'TEODULO LEITE', 1, '2026-11-20 09:20:00'),
  (151, 'IGUAL', 151, 151, 'Futsal', 'Sub 9', 'MASCULINO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'A', 'FRANCISCO AMORIM', 'ADELIETA RAMALHO', 1, '2026-11-20 10:00:00', 'A', 'FRANCISCO AMORIM', 'ADELIETA RAMALHO', 1, '2026-11-20 10:00:00'),
  (152, 'IGUAL', 152, 152, 'Futsal', 'Sub 11', 'MASCULINO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'A', 'ADELIETA RAMALHO', 'PORTAL DO SABER', 1, '2026-11-20 10:40:00', 'A', 'ADELIETA RAMALHO', 'PORTAL DO SABER', 1, '2026-11-20 10:40:00'),
  (153, 'IGUAL', 153, 153, 'Futsal', 'Sub 13', 'FEMININO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'A', 'CEBN', 'EMILIANO ZAPATA', 1, '2026-11-20 11:20:00', 'A', 'CEBN', 'EMILIANO ZAPATA', 1, '2026-11-20 11:20:00'),
  (154, 'IGUAL', 154, 154, 'Handebol', 'Sub 8', 'MASCULINO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'A', 'ADELIETA RAMALHO', 'JOSE DIAS', 1, '2026-11-20 12:00:00', 'A', 'ADELIETA RAMALHO', 'JOSE DIAS', 1, '2026-11-20 12:00:00'),
  (155, 'IGUAL', 155, 155, 'Handebol', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'B', 'ADELIETA RAMALHO', 'CEJA', 1, '2026-11-20 12:40:00', 'B', 'ADELIETA RAMALHO', 'CEJA', 1, '2026-11-20 12:40:00'),
  (156, 'IGUAL', 156, 156, 'Baleado', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'C', 'MANOEL RAMOS', 'MARIA DA GLORIA', 1, '2026-11-20 13:20:00', 'C', 'MANOEL RAMOS', 'MARIA DA GLORIA', 1, '2026-11-20 13:20:00'),
  (157, 'IGUAL', 157, 157, 'Handebol', 'Sub 11', 'MASCULINO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'B', 'FRANCISCO AMORIM', 'CEBC', 2, '2026-11-20 14:00:00', 'B', 'FRANCISCO AMORIM', 'CEBC', 2, '2026-11-20 14:00:00'),
  (158, 'ALTERAR', 158, 158, 'Handebol', 'Sub 11', 'FEMININO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'A', 'MARIA DA GLORIA', 'CEJA', 1, '2026-11-20 14:40:00', 'A', 'MARIA DA GLORIA', 'FRANCISCO AMORIM', 2, '2026-11-20 14:40:00'),
  (159, 'IGUAL', 159, 159, 'Handebol', 'Sub 15', 'FEMININO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'A', 'CEBN', 'Conveniada', 1, '2026-11-20 15:20:00', 'A', 'CEBN', 'Conveniada', 1, '2026-11-20 15:20:00'),
  (160, 'IGUAL', 160, 160, 'Handebol', 'Sub 15', 'FEMININO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'A', 'CEBC', 'CEJA', 1, '2026-11-20 16:00:00', 'A', 'CEBC', 'CEJA', 1, '2026-11-20 16:00:00'),
  (161, 'IGUAL', 161, 161, 'Baleado', 'Sub 11', 'FEMININO', 'GRUPOS', 'Quadra do Maria da Glória', 'B', 'MARIA DA GLORIA', 'JOSE DIAS', 1, '2026-11-20 08:00:00', 'B', 'MARIA DA GLORIA', 'JOSE DIAS', 1, '2026-11-20 08:00:00'),
  (162, 'IGUAL', 162, 162, 'Baleado', 'Sub 8', 'MASCULINO', 'GRUPOS', 'Quadra do Maria da Glória', 'A', 'ACM', 'MARLENE SANTANA', 1, '2026-11-20 08:40:00', 'A', 'ACM', 'MARLENE SANTANA', 1, '2026-11-20 08:40:00'),
  (163, 'IGUAL', 163, 163, 'Baleado', 'Sub 8', 'FEMININO', 'GRUPOS', 'Quadra do Maria da Glória', 'A', 'ACM', 'JOSE DIAS', 1, '2026-11-20 09:20:00', 'A', 'ACM', 'JOSE DIAS', 1, '2026-11-20 09:20:00'),
  (164, 'IGUAL', 164, 164, 'Baleado', 'Sub 9', 'FEMININO', 'GRUPOS', 'Quadra do Maria da Glória', 'A', 'MARIA DA GLORIA', 'PORTAL DO SABER', 1, '2026-11-20 10:00:00', 'A', 'MARIA DA GLORIA', 'PORTAL DO SABER', 1, '2026-11-20 10:00:00'),
  (165, 'IGUAL', 165, 165, 'Baleado', 'Sub 9', 'MASCULINO', 'GRUPOS', 'Quadra do Maria da Glória', 'A', 'MARLENE SANTANA', 'ADELIETA RAMALHO', 2, '2026-11-20 10:40:00', 'A', 'MARLENE SANTANA', 'ADELIETA RAMALHO', 2, '2026-11-20 10:40:00'),
  (166, 'ALTERAR', 166, 166, 'Baleado', 'Sub 9', 'FEMININO', 'GRUPOS', 'Quadra do Maria da Glória', 'A', 'JOSE DIAS', 'ADELIETA RAMALHO', 1, '2026-11-20 11:20:00', 'B', 'JOSE DIAS', 'ADELIETA RAMALHO', 1, '2026-11-20 11:20:00'),
  (167, 'IGUAL', 167, 167, 'Vôlei', 'Sub 15', 'MISTO', 'GRUPOS', 'Quadra do Maria da Glória', 'A', 'EMILIANO ZAPATA', 'CEJA', 1, '2026-11-20 12:00:00', 'A', 'EMILIANO ZAPATA', 'CEJA', 1, '2026-11-20 12:00:00'),
  (168, 'IGUAL', 168, 168, 'Vôlei', 'Aberto', 'MISTO', 'GRUPOS', 'Quadra do Maria da Glória', 'A', 'LUCIA ROCHA', 'CEBC', 1, '2026-11-20 12:40:00', 'A', 'LUCIA ROCHA', 'CEBC', 1, '2026-11-20 12:40:00'),
  (169, 'IGUAL', 169, 169, 'Vôlei', 'Sub 17', 'MISTO', 'GRUPOS', 'Quadra do Maria da Glória', 'A', 'CETI', 'LUCIA ROCHA', 1, '2026-11-20 13:20:00', 'A', 'CETI', 'LUCIA ROCHA', 1, '2026-11-20 13:20:00'),
  (170, 'IGUAL', 170, 170, 'Vôlei', 'Sub 15', 'MISTO', 'GRUPOS', 'Quadra do Maria da Glória', 'A', 'CEBC', 'CEBN', 1, '2026-11-20 14:00:00', 'A', 'CEBC', 'CEBN', 1, '2026-11-20 14:00:00'),
  (171, 'IGUAL', 171, 171, 'Handebol', 'Sub 11', 'MASCULINO', 'SEMIFINAL', 'Quadra do Maria da Glória', NULL, NULL, NULL, 1, '2026-11-20 14:40:00', NULL, NULL, NULL, 1, '2026-11-20 14:40:00'),
  (172, 'IGUAL', 172, 172, 'Handebol', 'Sub 11', 'MASCULINO', 'SEMIFINAL', 'Quadra do Maria da Glória', NULL, NULL, NULL, 2, '2026-11-20 15:20:00', NULL, NULL, NULL, 2, '2026-11-20 15:20:00'),
  (173, 'IGUAL', 173, 173, 'Handebol', 'Sub 13', 'MASCULINO', 'SEMIFINAL', 'Quadra do Maria da Glória', NULL, NULL, NULL, 1, '2026-11-20 16:00:00', NULL, NULL, NULL, 1, '2026-11-20 16:00:00'),
  (174, 'IGUAL', 174, 174, 'Futsal', 'Sub 15', 'FEMININO', 'GRUPOS', 'Quadra do CEJA', 'A', 'CEJA', 'CEBN', 1, '2026-11-20 08:00:00', 'A', 'CEJA', 'CEBN', 1, '2026-11-20 08:00:00'),
  (175, 'IGUAL', 175, 175, 'Futsal', 'Sub 15', 'FEMININO', 'GRUPOS', 'Quadra do CEJA', 'B', 'Conveniada', 'JOSE DIAS', 1, '2026-11-20 08:40:00', 'B', 'Conveniada', 'JOSE DIAS', 1, '2026-11-20 08:40:00'),
  (176, 'IGUAL', 176, 176, 'Futsal', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Quadra do CEJA', 'A', 'CEBC', 'EMILIANO ZAPATA', 1, '2026-11-20 09:20:00', 'A', 'CEBC', 'EMILIANO ZAPATA', 1, '2026-11-20 09:20:00'),
  (177, 'IGUAL', 177, 177, 'Futsal', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Quadra do CEJA', 'B', 'CEJA', 'Conveniada', 1, '2026-11-20 10:00:00', 'B', 'CEJA', 'Conveniada', 1, '2026-11-20 10:00:00'),
  (178, 'IGUAL', 178, 178, 'Baleado', 'Sub 11', 'FEMININO', 'GRUPOS', 'Quadra do CEJA', 'B', 'CEJA', 'EMILIANO ZAPATA', 1, '2026-11-20 10:40:00', 'B', 'CEJA', 'EMILIANO ZAPATA', 1, '2026-11-20 10:40:00'),
  (179, 'IGUAL', 179, 179, 'Baleado', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Quadra do CEJA', 'A', 'CEJA', 'CEBC', 1, '2026-11-20 11:20:00', 'A', 'CEJA', 'CEBC', 1, '2026-11-20 11:20:00'),
  (180, 'IGUAL', 180, 180, 'Handebol', 'Sub 13', 'FEMININO', 'GRUPOS', 'Quadra do CEJA', 'A', 'CEBN', 'CEJA', 1, '2026-11-20 12:00:00', 'A', 'CEBN', 'CEJA', 1, '2026-11-20 12:00:00'),
  (181, 'IGUAL', 181, 181, 'Handebol', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Quadra do CEJA', 'A', 'CEBN', 'JOSE DIAS', 1, '2026-11-20 12:40:00', 'A', 'CEBN', 'JOSE DIAS', 1, '2026-11-20 12:40:00'),
  (182, 'IGUAL', 182, 182, 'Handebol', 'Sub 17', 'FEMININO', 'GRUPOS', 'Quadra do CEJA', 'A', 'CEJA', 'CETI', 1, '2026-11-20 13:20:00', 'A', 'CEJA', 'CETI', 1, '2026-11-20 13:20:00'),
  (183, 'IGUAL', 183, 183, 'Baleado', 'Sub 17', 'FEMININO', 'GRUPOS', 'Quadra do CEJA', 'A', 'CEBC', 'LUCIA ROCHA', 1, '2026-11-20 14:00:00', 'A', 'CEBC', 'LUCIA ROCHA', 1, '2026-11-20 14:00:00'),
  (184, 'IGUAL', 184, 184, 'Baleado', 'Sub 9', 'FEMININO', 'GRUPOS', 'Quadra do CEJA', 'A', 'FRANCISCO AMORIM', 'MARIA DA GLORIA', 1, '2026-11-20 14:40:00', 'A', 'FRANCISCO AMORIM', 'MARIA DA GLORIA', 1, '2026-11-20 14:40:00'),
  (185, 'IGUAL', 185, 185, 'Futsal', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Quadra do CEJA', 'B', 'JOSE DIAS', 'Conveniada', 1, '2026-11-20 15:20:00', 'B', 'JOSE DIAS', 'Conveniada', 1, '2026-11-20 15:20:00'),
  (186, 'IGUAL', 186, 186, 'Futsal', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Quadra do CEJA', 'A', 'CEJA', 'CEBC', 1, '2026-11-20 16:00:00', 'A', 'CEJA', 'CEBC', 1, '2026-11-20 16:00:00'),
  (187, 'IGUAL', 187, 187, 'Futebol Society', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Campo Society do CETI', 'A', 'Conveniada', 'CEJA', 1, '2026-11-20 08:40:00', 'A', 'Conveniada', 'CEJA', 1, '2026-11-20 08:40:00'),
  (188, 'IGUAL', 188, 188, 'Futebol Society', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Campo Society do CETI', 'A', 'Conveniada', 'CEJA', 1, '2026-11-20 09:20:00', 'A', 'Conveniada', 'CEJA', 1, '2026-11-20 09:20:00'),
  (189, 'IGUAL', 189, 189, 'Futebol Society', 'Sub 17', 'MASCULINO', 'GRUPOS', 'Campo Society do CETI', 'A', 'CEJA', 'CETI', 1, '2026-11-20 10:00:00', 'A', 'CEJA', 'CETI', 1, '2026-11-20 10:00:00'),
  (190, 'IGUAL', 190, 190, 'Futebol Society', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Campo Society do CETI', 'B', 'MARIA DA GLORIA', 'CEBN', 2, '2026-11-20 15:00:00', 'B', 'MARIA DA GLORIA', 'CEBN', 2, '2026-11-20 15:00:00'),
  (191, 'IGUAL', 191, 191, 'Futebol Society', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Campo Society do CETI', 'A', 'CEBC', 'Conveniada', 1, '2026-11-20 15:40:00', 'A', 'CEBC', 'Conveniada', 1, '2026-11-20 15:40:00'),
  (192, 'IGUAL', 192, 192, 'Vôlei', 'Sub 17', 'MISTO', 'GRUPOS', 'Quadra do CETI', 'A', 'CEBN', 'CEBC', 1, '2026-11-20 08:00:00', 'A', 'CEBN', 'CEBC', 1, '2026-11-20 08:00:00'),
  (193, 'IGUAL', 193, 193, 'Vôlei', 'Aberto', 'MISTO', 'GRUPOS', 'Quadra do CETI', 'A', 'CETI', 'LUCIA ROCHA', 1, '2026-11-20 08:40:00', 'A', 'CETI', 'LUCIA ROCHA', 1, '2026-11-20 08:40:00'),
  (194, 'IGUAL', 194, 194, 'Futsal', 'Sub 8', 'MASCULINO', 'GRUPOS', 'Quadra do CETI', 'B', 'MARLENE SANTANA', 'ACM', 1, '2026-11-20 09:20:00', 'B', 'MARLENE SANTANA', 'ACM', 1, '2026-11-20 09:20:00'),
  (195, 'IGUAL', 195, 195, 'Futsal', 'Sub 8', 'MASCULINO', 'GRUPOS', 'Quadra do CETI', 'A', 'JOSE DIAS', 'ADELIETA RAMALHO', 2, '2026-11-20 10:00:00', 'A', 'JOSE DIAS', 'ADELIETA RAMALHO', 2, '2026-11-20 10:00:00'),
  (196, 'IGUAL', 196, 196, 'Baleado', 'Sub 11', 'FEMININO', 'GRUPOS', 'Quadra do CETI', 'A', 'FRANCISCO AMORIM', 'PORTAL DO SABER', 1, '2026-11-20 10:40:00', 'A', 'FRANCISCO AMORIM', 'PORTAL DO SABER', 1, '2026-11-20 10:40:00'),
  (197, 'IGUAL', 197, 197, 'Baleado', 'Sub 13', 'MASCULINO', 'SEMIFINAL', 'Quadra do CETI', NULL, NULL, NULL, 1, '2026-11-20 11:20:00', NULL, NULL, NULL, 1, '2026-11-20 11:20:00'),
  (198, 'IGUAL', 198, 198, 'Baleado', 'Sub 11', 'FEMININO', 'GRUPOS', 'Quadra do CETI', 'A', 'ADELIETA RAMALHO', 'JOSENILDO LEITE', 1, '2026-11-20 12:00:00', 'A', 'ADELIETA RAMALHO', 'JOSENILDO LEITE', 1, '2026-11-20 12:00:00'),
  (199, 'IGUAL', 199, 199, 'Handebol', 'Sub 9', 'FEMININO', 'GRUPOS', 'Quadra do CETI', 'A', 'FRANCISCO AMORIM', 'MARIA DA GLORIA', 1, '2026-11-20 12:40:00', 'A', 'FRANCISCO AMORIM', 'MARIA DA GLORIA', 1, '2026-11-20 12:40:00'),
  (200, 'IGUAL', 200, 200, 'Futsal', 'Sub 8', 'MASCULINO', 'GRUPOS', 'Quadra do CETI', 'B', 'ACM', 'TEODULO LEITE', 1, '2026-11-20 13:20:00', 'B', 'ACM', 'TEODULO LEITE', 1, '2026-11-20 13:20:00'),
  (201, 'IGUAL', 201, 201, 'Basquete', 'Sub 15', 'FEMININO', 'GRUPOS', 'Quadra do CEBC', 'A', 'CEJA', 'Conveniada', 1, '2026-11-20 08:00:00', 'A', 'CEJA', 'Conveniada', 1, '2026-11-20 08:00:00'),
  (202, 'IGUAL', 202, 202, 'Basquete', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Quadra do CEBC', 'A', 'Conveniada', 'CEBC', 1, '2026-11-20 08:40:00', 'A', 'Conveniada', 'CEBC', 1, '2026-11-20 08:40:00'),
  (203, 'IGUAL', 203, 203, 'Futsal', 'Sub 15', 'FEMININO', 'GRUPOS', 'Quadra do CEBC', 'A', 'EMILIANO ZAPATA', 'CEJA', 1, '2026-11-20 09:20:00', 'A', 'EMILIANO ZAPATA', 'CEJA', 1, '2026-11-20 09:20:00'),
  (204, 'IGUAL', 204, 204, 'Futsal', 'Sub 15', 'FEMININO', 'GRUPOS', 'Quadra do CEBC', 'B', 'JOSE DIAS', 'CEBC', 1, '2026-11-20 10:00:00', 'B', 'JOSE DIAS', 'CEBC', 1, '2026-11-20 10:00:00'),
  (205, 'ALTERAR', 206, 205, 'Basquete', 'Sub 17', 'MASCULINO', 'GRUPOS', 'Quadra do CEBC', 'A', 'CEJA', 'CETI', 1, '2026-11-20 11:20:00', 'A', 'CEJA', 'CETI', 1, '2026-11-20 10:40:00'),
  (206, 'ALTERAR', 207, 206, 'Basquete', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Quadra do CEBC', 'A', 'CEJA', 'CEBC', 1, '2026-11-20 12:00:00', 'A', 'CEJA', 'CEBC', 1, '2026-11-20 11:20:00'),
  (207, 'ALTERAR', 208, 207, 'Basquete', 'Sub 17', 'FEMININO', 'GRUPOS', 'Quadra do CEBC', 'A', 'CEJA', 'CEBC', 1, '2026-11-20 12:40:00', 'A', 'CEJA', 'CEBC', 1, '2026-11-20 12:00:00'),
  (208, 'ALTERAR', 209, 208, 'Baleado', 'Sub 9', 'MASCULINO', 'GRUPOS', 'Quadra do CEBC', 'A', 'FRANCISCO AMORIM', 'TEODULO LEITE', 1, '2026-11-20 13:20:00', 'A', 'FRANCISCO AMORIM', 'TEODULO LEITE', 1, '2026-11-20 12:40:00'),
  (209, 'ALTERAR', 210, 209, 'Baleado', 'Sub 11', 'MASCULINO', 'SEMIFINAL', 'Quadra do CEBC', NULL, NULL, NULL, 1, '2026-11-20 14:40:00', NULL, NULL, NULL, 1, '2026-11-20 13:20:00'),
  (210, 'ALTERAR', 211, 210, 'Handebol', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Quadra do CEBC', 'A', 'Conveniada', 'CEBN', 1, '2026-11-20 15:20:00', 'A', 'Conveniada', 'CEBN', 1, '2026-11-20 14:00:00'),
  (211, 'ALTERAR', 212, 211, 'Handebol', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Quadra do CEBC', 'A', 'CEJA', 'CEBC', 1, '2026-11-20 16:00:00', 'A', 'CEJA', 'CEBC', 1, '2026-11-20 14:40:00'),
  (212, 'ALTERAR', 213, 212, 'Handebol', 'Aberto', 'MASCULINO', 'GRUPOS', 'Quadra do CEBC', 'A', 'CEJA', 'LUCIA ROCHA', 1, '2026-11-20 16:40:00', 'A', 'CEJA', 'LUCIA ROCHA', 1, '2026-11-20 15:20:00'),
  (213, 'ALTERAR', 214, 213, 'Handebol', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Quadra do Maria da Glória', 'A', 'Conveniada', 'CEBC', 1, '2026-11-21 08:40:00', 'A', 'Conveniada', 'CEBC', 1, '2026-11-21 08:40:00'),
  (214, 'ALTERAR', 215, 214, 'Handebol', 'Sub 17', 'MASCULINO', 'GRUPOS', 'Quadra do Maria da Glória', 'A', 'CEJA', 'CEBN', 1, '2026-11-21 09:20:00', 'A', 'CEJA', 'CEBN', 1, '2026-11-21 09:20:00'),
  (215, 'ALTERAR', 216, 215, 'Baleado', 'Sub 15', 'FEMININO', 'SEMIFINAL', 'Quadra do Maria da Glória', NULL, NULL, NULL, 1, '2026-11-21 10:00:00', NULL, NULL, NULL, 1, '2026-11-21 10:00:00'),
  (216, 'ALTERAR', 217, 216, 'Baleado', 'Sub 15', 'FEMININO', 'SEMIFINAL', 'Quadra do Maria da Glória', NULL, NULL, NULL, 2, '2026-11-21 10:40:00', NULL, NULL, NULL, 2, '2026-11-21 10:40:00'),
  (217, 'ALTERAR', 218, 217, 'Futsal', 'Sub 9', 'MASCULINO', 'SEMIFINAL', 'Quadra do Maria da Glória', NULL, NULL, NULL, 1, '2026-11-21 11:20:00', NULL, NULL, NULL, 1, '2026-11-21 11:20:00'),
  (218, 'ALTERAR', 219, 218, 'Futsal', 'Sub 9', 'MASCULINO', 'SEMIFINAL', 'Quadra do Maria da Glória', NULL, NULL, NULL, 2, '2026-11-21 12:00:00', NULL, NULL, NULL, 2, '2026-11-21 12:00:00'),
  (219, 'ALTERAR', 220, 219, 'Baleado', 'Sub 11', 'MASCULINO', 'SEMIFINAL', 'Quadra do Maria da Glória', NULL, NULL, NULL, 2, '2026-11-21 12:40:00', NULL, NULL, NULL, 2, '2026-11-21 12:40:00'),
  (220, 'ALTERAR', 221, 220, 'Handebol', 'Sub 13', 'MASCULINO', 'FINAL', 'Quadra do Maria da Glória', NULL, NULL, NULL, 1, '2026-11-21 13:20:00', NULL, NULL, NULL, 1, '2026-11-21 13:20:00'),
  (221, 'ALTERAR', 222, 221, 'Handebol', 'Sub 13', 'FEMININO', 'FINAL', 'Quadra do Maria da Glória', NULL, NULL, NULL, 1, '2026-11-21 14:00:00', NULL, NULL, NULL, 1, '2026-11-21 14:00:00'),
  (222, 'ALTERAR', 223, 222, 'Handebol', 'Sub 11', 'MASCULINO', 'FINAL', 'Quadra do Maria da Glória', NULL, NULL, NULL, 1, '2026-11-21 14:40:00', NULL, NULL, NULL, 1, '2026-11-21 14:40:00'),
  (223, 'ALTERAR', 224, 223, 'Handebol', 'Sub 15', 'MASCULINO', 'FINAL', 'Quadra do Maria da Glória', NULL, NULL, NULL, 1, '2026-11-21 15:20:00', NULL, NULL, NULL, 1, '2026-11-21 15:20:00'),
  (224, 'ALTERAR', 225, 224, 'Handebol', 'Sub 11', 'FEMININO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'B', 'ADELIETA RAMALHO', 'JOSE DIAS', 1, '2026-11-21 08:00:00', 'B', 'ADELIETA RAMALHO', 'JOSE DIAS', 1, '2026-11-21 08:00:00'),
  (225, 'ALTERAR', 226, 225, 'Baleado', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'B', 'Conveniada', 'MANOEL RAMOS', 2, '2026-11-21 08:40:00', 'B', 'Conveniada', 'MANOEL RAMOS', 2, '2026-11-21 08:40:00'),
  (226, 'ALTERAR', 227, 226, 'Baleado', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'A', 'CEBN', 'CEJA', 1, '2026-11-21 09:20:00', 'A', 'CEBN', 'CEJA', 1, '2026-11-21 09:20:00'),
  (227, 'ALTERAR', 228, 227, 'Baleado', 'Sub 17', 'MASCULINO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'A', 'JOSENILDO LEITE', 'CEJA', 1, '2026-11-21 10:00:00', 'A', 'JOSENILDO LEITE', 'CEJA', 1, '2026-11-21 10:00:00'),
  (228, 'ALTERAR', 229, 228, 'Baleado', 'Sub 17', 'MASCULINO', 'GRUPOS', 'Quadra da Adelieta Ramalho', 'A', 'CEBC', 'CETI', 1, '2026-11-21 10:40:00', 'A', 'CEBC', 'CETI', 1, '2026-11-21 10:40:00'),
  (229, 'ALTERAR', 232, 229, 'Baleado', 'Sub 13', 'MASCULINO', 'SEMIFINAL', 'Quadra da Adelieta Ramalho', NULL, NULL, NULL, 2, '2026-11-21 12:40:00', NULL, NULL, NULL, 2, '2026-11-21 11:20:00'),
  (230, 'ALTERAR', 233, 230, 'Baleado', 'Sub 15', 'FEMININO', 'FINAL', 'Quadra da Adelieta Ramalho', NULL, NULL, NULL, 1, '2026-11-21 13:20:00', NULL, NULL, NULL, 1, '2026-11-21 12:00:00'),
  (231, 'ALTERAR', 234, 231, 'Baleado', 'Sub 13', 'FEMININO', 'FINAL', 'Quadra da Adelieta Ramalho', NULL, NULL, NULL, 1, '2026-11-21 14:00:00', NULL, NULL, NULL, 1, '2026-11-21 12:40:00'),
  (232, 'ALTERAR', 235, 232, 'Handebol', 'Sub 11', 'FEMININO', 'FINAL', 'Quadra da Adelieta Ramalho', NULL, NULL, NULL, 1, '2026-11-21 14:40:00', NULL, NULL, NULL, 1, '2026-11-21 13:20:00'),
  (233, 'ALTERAR', 236, 233, 'Baleado', 'Sub 11', 'MASCULINO', 'FINAL', 'Quadra da Adelieta Ramalho', NULL, NULL, NULL, 1, '2026-11-21 15:20:00', NULL, NULL, NULL, 1, '2026-11-21 14:00:00'),
  (234, 'ALTERAR', 237, 234, 'Baleado', 'Sub 15', 'FEMININO', 'GRUPOS', 'Quadra do CEJA', 'B', 'EMILIANO ZAPATA', 'CEJA', 1, '2026-11-21 08:00:00', 'B', 'EMILIANO ZAPATA', 'CEJA', 1, '2026-11-21 08:00:00'),
  (235, 'ALTERAR', 238, 235, 'Baleado', 'Sub 15', 'FEMININO', 'GRUPOS', 'Quadra do CEJA', 'A', 'CEBC', 'JOSENILDO LEITE', 1, '2026-11-21 08:40:00', 'A', 'CEBC', 'JOSENILDO LEITE', 1, '2026-11-21 08:40:00'),
  (236, 'ALTERAR', 239, 236, 'Baleado', 'Sub 17', 'FEMININO', 'GRUPOS', 'Quadra do CEJA', 'A', 'CEJA', 'CEBC', 1, '2026-11-21 09:20:00', 'A', 'CEJA', 'CEBC', 1, '2026-11-21 09:20:00'),
  (237, 'ALTERAR', 240, 237, 'Baleado', 'Sub 17', 'FEMININO', 'GRUPOS', 'Quadra do CEJA', 'A', 'LUCIA ROCHA', 'CETI', 1, '2026-11-21 10:00:00', 'A', 'LUCIA ROCHA', 'CETI', 1, '2026-11-21 10:00:00'),
  (238, 'ALTERAR', 241, 238, 'Handebol', 'Sub 13', 'MASCULINO', 'SEMIFINAL', 'Quadra do CEJA', NULL, NULL, NULL, 2, '2026-11-21 10:40:00', NULL, NULL, NULL, 2, '2026-11-21 10:40:00'),
  (239, 'ALTERAR', 242, 239, 'Futsal', 'Aberto', 'FEMININO', 'GRUPOS', 'Quadra do CEJA', 'A', 'LUCIA ROCHA', 'VITORIA LIMA', 1, '2026-11-21 11:20:00', 'A', 'LUCIA ROCHA', 'VITORIA LIMA', 1, '2026-11-21 11:20:00'),
  (240, 'ALTERAR', 243, 240, 'Futsal', 'Sub 13', 'MASCULINO', 'SEMIFINAL', 'Quadra do CEJA', NULL, NULL, NULL, 1, '2026-11-21 12:00:00', NULL, NULL, NULL, 1, '2026-11-21 12:00:00'),
  (241, 'ALTERAR', 244, 241, 'Futsal', 'Sub 13', 'MASCULINO', 'SEMIFINAL', 'Quadra do CEJA', NULL, NULL, NULL, 2, '2026-11-21 12:40:00', NULL, NULL, NULL, 2, '2026-11-21 12:40:00'),
  (242, 'ALTERAR', 245, 242, 'Futsal', 'Sub 11', 'MASCULINO', 'SEMIFINAL', 'Quadra do CEJA', NULL, NULL, NULL, 1, '2026-11-21 13:20:00', NULL, NULL, NULL, 1, '2026-11-21 13:20:00'),
  (243, 'ALTERAR', 246, 243, 'Futsal', 'Sub 11', 'MASCULINO', 'SEMIFINAL', 'Quadra do CEJA', NULL, NULL, NULL, 2, '2026-11-21 14:00:00', NULL, NULL, NULL, 2, '2026-11-21 14:00:00'),
  (244, 'ALTERAR', 247, 244, 'Baleado', 'Sub 17', 'MASCULINO', 'FINAL', 'Quadra do CEJA', NULL, NULL, NULL, 1, '2026-11-21 14:40:00', NULL, NULL, NULL, 1, '2026-11-21 14:40:00'),
  (245, 'ALTERAR', 248, 245, 'Baleado', 'Sub 15', 'MASCULINO', 'FINAL', 'Quadra do CEJA', NULL, NULL, NULL, 1, '2026-11-21 15:20:00', NULL, NULL, NULL, 1, '2026-11-21 15:20:00'),
  (246, 'ALTERAR', 249, 246, 'Baleado', 'Sub 13', 'MASCULINO', 'FINAL', 'Quadra do CEJA', NULL, NULL, NULL, 1, '2026-11-21 16:00:00', NULL, NULL, NULL, 1, '2026-11-21 16:00:00'),
  (247, 'ALTERAR', 250, 247, 'Baleado', 'Sub 17', 'FEMININO', 'FINAL', 'Quadra do CEJA', NULL, NULL, NULL, 1, '2026-11-21 16:40:00', NULL, NULL, NULL, 1, '2026-11-21 16:40:00'),
  (248, 'ALTERAR', 251, 248, 'Baleado', 'Sub 13', 'FEMININO', 'SEMIFINAL', 'Quadra do CEBC', NULL, NULL, NULL, 1, '2026-11-21 08:00:00', NULL, NULL, NULL, 1, '2026-11-21 08:00:00'),
  (249, 'ALTERAR', 252, 249, 'Baleado', 'Sub 13', 'FEMININO', 'SEMIFINAL', 'Quadra do CEBC', NULL, NULL, NULL, 2, '2026-11-21 08:40:00', NULL, NULL, NULL, 2, '2026-11-21 08:40:00'),
  (250, 'ALTERAR', 253, 250, 'Baleado', 'Sub 11', 'FEMININO', 'SEMIFINAL', 'Quadra do CEBC', NULL, NULL, NULL, 1, '2026-11-21 09:20:00', NULL, NULL, NULL, 1, '2026-11-21 09:20:00'),
  (251, 'ALTERAR', 254, 251, 'Basquete', 'Sub 15', 'FEMININO', 'FINAL', 'Quadra do CEBC', NULL, NULL, NULL, 1, '2026-11-21 10:00:00', NULL, NULL, NULL, 1, '2026-11-21 10:00:00'),
  (252, 'ALTERAR', 255, 252, 'Futsal', 'Sub 15', 'MASCULINO', 'SEMIFINAL', 'Quadra do CEBC', NULL, NULL, NULL, 1, '2026-11-21 10:40:00', NULL, NULL, NULL, 1, '2026-11-21 10:40:00'),
  (253, 'ALTERAR', 256, 253, 'Futsal', 'Sub 15', 'MASCULINO', 'SEMIFINAL', 'Quadra do CEBC', NULL, NULL, NULL, 2, '2026-11-21 11:00:00', NULL, NULL, NULL, 2, '2026-11-21 11:00:00'),
  (254, 'ALTERAR', 257, 254, 'Futsal', 'Sub 15', 'FEMININO', 'SEMIFINAL', 'Quadra do CEBC', NULL, NULL, NULL, 1, '2026-11-21 11:40:00', NULL, NULL, NULL, 1, '2026-11-21 11:40:00'),
  (255, 'ALTERAR', 258, 255, 'Futsal', 'Sub 15', 'FEMININO', 'SEMIFINAL', 'Quadra do CEBC', NULL, NULL, NULL, 2, '2026-11-21 12:20:00', NULL, NULL, NULL, 2, '2026-11-21 12:20:00'),
  (256, 'ALTERAR', 259, 256, 'Handebol', 'Sub 15', 'FEMININO', 'FINAL', 'Quadra do CEBC', NULL, NULL, NULL, 1, '2026-11-21 13:00:00', NULL, NULL, NULL, 1, '2026-11-21 13:00:00'),
  (257, 'ALTERAR', 260, 257, 'Futsal', 'Sub 13', 'FEMININO', 'FINAL', 'Quadra do CEBC', NULL, NULL, NULL, 1, '2026-11-21 13:40:00', NULL, NULL, NULL, 1, '2026-11-21 13:40:00'),
  (258, 'ALTERAR', 261, 258, 'Futsal', 'Sub 9', 'MASCULINO', 'FINAL', 'Quadra do CEBC', NULL, NULL, NULL, 1, '2026-11-21 14:20:00', NULL, NULL, NULL, 1, '2026-11-21 14:20:00'),
  (259, 'ALTERAR', 262, 259, 'Futsal', 'Sub 17', 'FEMININO', 'FINAL', 'Quadra do CEBC', NULL, NULL, NULL, 1, '2026-11-21 15:00:00', NULL, NULL, NULL, 1, '2026-11-21 15:00:00'),
  (260, 'ALTERAR', 263, 260, 'Futsal', 'Sub 15', 'FEMININO', 'FINAL', 'Quadra do CEBC', NULL, NULL, NULL, 1, '2026-11-21 15:40:00', NULL, NULL, NULL, 1, '2026-11-21 15:40:00'),
  (261, 'ALTERAR', 264, 261, 'Futsal', 'Sub 11', 'MASCULINO', 'FINAL', 'Quadra do CEBC', NULL, NULL, NULL, 1, '2026-11-21 16:20:00', NULL, NULL, NULL, 1, '2026-11-21 16:20:00'),
  (262, 'ALTERAR', 265, 262, 'Handebol', 'Sub 9', 'FEMININO', 'GRUPOS', 'Quadra do CETI', 'A', 'MARIA DA GLORIA', 'ADELIETA RAMALHO', 1, '2026-11-21 08:00:00', 'A', 'MARIA DA GLORIA', 'ADELIETA RAMALHO', 1, '2026-11-21 08:00:00'),
  (263, 'ALTERAR', 266, 263, 'Handebol', 'Sub 8', 'MASCULINO', 'GRUPOS', 'Quadra do CETI', 'A', 'JOSE DIAS', 'ACM', 1, '2026-11-21 08:40:00', 'A', 'JOSE DIAS', 'ACM', 1, '2026-11-21 08:40:00'),
  (264, 'ALTERAR', 267, 264, 'Baleado', 'Sub 9', 'FEMININO', 'GRUPOS', 'Quadra do CETI', 'A', 'PORTAL DO SABER', 'FRANCISCO AMORIM', 1, '2026-11-21 09:20:00', 'A', 'PORTAL DO SABER', 'FRANCISCO AMORIM', 1, '2026-11-21 09:20:00'),
  (265, 'ALTERAR', 268, 265, 'Baleado', 'Sub 9', 'FEMININO', 'GRUPOS', 'Quadra do CETI', 'A', 'JOSE DIAS', 'ADELIETA RAMALHO', 2, '2026-11-21 10:00:00', 'B', 'JOSE DIAS', 'ADELIETA RAMALHO', 2, '2026-11-21 10:00:00'),
  (266, 'ALTERAR', 269, 266, 'Baleado', 'Sub 8', 'FEMININO', 'GRUPOS', 'Quadra do CETI', 'A', 'JOSE DIAS', 'ACM', 2, '2026-11-21 10:40:00', 'A', 'JOSE DIAS', 'ACM', 2, '2026-11-21 10:40:00'),
  (267, 'ALTERAR', 270, 267, 'Futsal', 'Sub 8', 'FEMININO', 'GRUPOS', 'Quadra do CETI', 'A', 'EMILIANO ZAPATA', 'JOSE DIAS', 2, '2026-11-21 11:20:00', 'A', 'EMILIANO ZAPATA', 'JOSE DIAS', 2, '2026-11-21 11:20:00'),
  (268, 'ALTERAR', 271, 268, 'Futsal', 'Sub 11', 'FEMININO', 'GRUPOS', 'Quadra do CETI', 'A', 'JOSE DIAS', 'MARLENE SANTANA', 2, '2026-11-21 12:00:00', 'A', 'JOSE DIAS', 'MARLENE SANTANA', 2, '2026-11-21 12:00:00'),
  (269, 'ALTERAR', 272, 269, 'Futsal', 'Sub 9', 'FEMININO', 'GRUPOS', 'Quadra do CETI', 'A', 'JOSE DIAS', 'MARLENE SANTANA', 2, '2026-11-21 12:40:00', 'A', 'JOSE DIAS', 'MARLENE SANTANA', 2, '2026-11-21 12:40:00'),
  (270, 'ALTERAR', 273, 270, 'Futsal', 'Sub 8', 'MASCULINO', 'FINAL', 'Quadra do CETI', NULL, NULL, NULL, 1, '2026-11-21 13:20:00', NULL, NULL, NULL, 1, '2026-11-21 13:20:00'),
  (271, 'ALTERAR', 274, 271, 'Handebol', 'Sub 8', 'MASCULINO', 'FINAL', 'Quadra do CETI', NULL, NULL, NULL, 1, '2026-11-21 14:00:00', NULL, NULL, NULL, 1, '2026-11-21 14:00:00'),
  (272, 'ALTERAR', 275, 272, 'Handebol', 'Sub 8', 'FEMININO', 'GRUPOS', 'Quadra do CETI', 'A', 'ACM', 'JOSE DIAS', 2, '2026-11-21 14:40:00', 'A', 'ACM', 'JOSE DIAS', 2, '2026-11-21 14:40:00'),
  (273, 'ALTERAR', 276, 273, 'Handebol', 'Sub 9', 'FEMININO', 'FINAL', 'Quadra do CETI', NULL, NULL, NULL, 1, '2026-11-21 15:20:00', NULL, NULL, NULL, 1, '2026-11-21 15:20:00'),
  (274, 'ALTERAR', 277, 274, 'Baleado', 'Sub 9', 'MASCULINO', 'FINAL', 'Quadra do CETI', NULL, NULL, NULL, 1, '2026-11-21 16:00:00', NULL, NULL, NULL, 1, '2026-11-21 16:00:00'),
  (275, 'ALTERAR', 278, 275, 'Baleado', 'Sub 9', 'FEMININO', 'FINAL', 'Quadra do CETI', NULL, NULL, NULL, 1, '2026-11-21 16:20:00', NULL, NULL, NULL, 1, '2026-11-21 16:20:00'),
  (276, 'ALTERAR', 279, 276, 'Baleado', 'Sub 8', 'MASCULINO', 'GRUPOS', 'Quadra do CETI', 'A', 'ACM', 'MARLENE SANTANA', 2, '2026-11-21 16:40:00', 'A', 'ACM', 'MARLENE SANTANA', 2, '2026-11-21 16:40:00'),
  (277, 'ALTERAR', 280, 277, 'Handebol', 'Sub 13', 'FEMININO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'CEJA', 'CEBC', 1, '2026-11-21 08:00:00', 'A', 'CEJA', 'CEBC', 1, '2026-11-21 08:00:00'),
  (278, 'ALTERAR', 281, 278, 'Handebol', 'Sub 15', 'FEMININO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'Conveniada', 'CEJA', 1, '2026-11-21 08:40:00', 'A', 'Conveniada', 'CEJA', 1, '2026-11-21 08:40:00'),
  (279, 'ALTERAR', 282, 279, 'Handebol', 'Sub 15', 'FEMININO', 'GRUPOS', 'Ginásio de Esportes', 'A', 'CEBC', 'CEBN', 1, '2026-11-21 09:20:00', 'A', 'CEBC', 'CEBN', 1, '2026-11-21 09:20:00'),
  (280, 'ALTERAR', 283, 280, 'Baleado', 'Sub 11', 'FEMININO', 'SEMIFINAL', 'Ginásio de Esportes', NULL, NULL, NULL, 2, '2026-11-21 10:00:00', NULL, NULL, NULL, 2, '2026-11-21 10:00:00'),
  (281, 'ALTERAR', 284, 281, 'Futsal', 'Sub 7', 'MASCULINO', 'FINAL', 'Ginásio de Esportes', NULL, NULL, NULL, 1, '2026-11-21 10:40:00', NULL, NULL, NULL, 1, '2026-11-21 10:40:00'),
  (282, 'ALTERAR', 285, 282, 'Vôlei', 'Aberto', 'MISTO', 'FINAL', 'Ginásio de Esportes', NULL, NULL, NULL, 1, '2026-11-21 11:20:00', NULL, NULL, NULL, 1, '2026-11-21 11:20:00'),
  (283, 'ALTERAR', 286, 283, 'Vôlei', 'Sub 15', 'MISTO', 'FINAL', 'Ginásio de Esportes', NULL, NULL, NULL, 1, '2026-11-21 12:00:00', NULL, NULL, NULL, 1, '2026-11-21 12:00:00'),
  (284, 'ALTERAR', 287, 284, 'Vôlei', 'Sub 17', 'MISTO', 'FINAL', 'Ginásio de Esportes', NULL, NULL, NULL, 1, '2026-11-21 12:40:00', NULL, NULL, NULL, 1, '2026-11-21 12:40:00'),
  (285, 'ALTERAR', 288, 285, 'Basquete', 'Sub 17', 'FEMININO', 'FINAL', 'Ginásio de Esportes', NULL, 'CEJA', 'CEBC', 1, '2026-11-21 13:20:00', NULL, 'CEJA', 'CEBC', 1, '2026-11-21 13:20:00'),
  (286, 'ALTERAR', 289, 286, 'Basquete', 'Sub 15', 'MASCULINO', 'FINAL', 'Ginásio de Esportes', NULL, NULL, NULL, 1, '2026-11-21 14:00:00', NULL, NULL, NULL, 1, '2026-11-21 14:00:00'),
  (287, 'ALTERAR', 290, 287, 'Basquete', 'Sub 17', 'MASCULINO', 'FINAL', 'Ginásio de Esportes', NULL, NULL, NULL, 1, '2026-11-21 14:40:00', NULL, NULL, NULL, 1, '2026-11-21 14:40:00'),
  (288, 'ALTERAR', 291, 288, 'Baleado', 'Sub 11', 'FEMININO', 'FINAL', 'Ginásio de Esportes', NULL, NULL, NULL, 1, '2026-11-21 15:20:00', NULL, NULL, NULL, 1, '2026-11-21 15:20:00'),
  (289, 'ALTERAR', 292, 289, 'Handebol', 'Sub 17', 'FEMININO', 'FINAL', 'Ginásio de Esportes', NULL, NULL, NULL, 1, '2026-11-21 16:00:00', NULL, NULL, NULL, 1, '2026-11-21 16:00:00'),
  (290, 'ALTERAR', 293, 290, 'Handebol', 'Sub 17', 'MASCULINO', 'FINAL', 'Ginásio de Esportes', NULL, NULL, NULL, 1, '2026-11-21 16:40:00', NULL, NULL, NULL, 1, '2026-11-21 16:40:00'),
  (291, 'ALTERAR', 294, 291, 'Handebol', 'Aberto', 'MASCULINO', 'FINAL', 'Ginásio de Esportes', NULL, NULL, NULL, 1, '2026-11-21 17:20:00', NULL, NULL, NULL, 1, '2026-11-21 17:20:00'),
  (292, 'ALTERAR', 295, 292, 'Futsal', 'Sub 13', 'MASCULINO', 'FINAL', 'Ginásio de Esportes', NULL, NULL, NULL, 1, '2026-11-21 18:00:00', NULL, NULL, NULL, 1, '2026-11-21 18:00:00'),
  (293, 'ALTERAR', 296, 293, 'Futsal', 'Sub 15', 'MASCULINO', 'FINAL', 'Ginásio de Esportes', NULL, NULL, NULL, 1, '2026-11-21 18:40:00', NULL, NULL, NULL, 1, '2026-11-21 18:40:00'),
  (294, 'ALTERAR', 297, 294, 'Futsal', 'Aberto', 'FEMININO', 'FINAL', 'Ginásio de Esportes', NULL, NULL, NULL, 1, '2026-11-21 19:20:00', NULL, NULL, NULL, 1, '2026-11-21 19:20:00'),
  (295, 'ALTERAR', 298, 295, 'Futsal', 'Sub 17', 'MASCULINO', 'FINAL', 'Ginásio de Esportes', NULL, NULL, NULL, 1, '2026-11-21 20:00:00', NULL, NULL, NULL, 1, '2026-11-21 20:00:00'),
  (296, 'ALTERAR', 299, 296, 'Futsal', 'Aberto', 'MASCULINO', 'FINAL', 'Ginásio de Esportes', NULL, NULL, NULL, 1, '2026-11-21 20:40:00', NULL, NULL, NULL, 1, '2026-11-21 20:40:00'),
  (297, 'ALTERAR', 300, 297, 'Futebol Society', 'Sub 13', 'MASCULINO', 'FINAL', 'Campo Society do CETI', NULL, NULL, NULL, 1, '2026-11-21 08:40:00', NULL, NULL, NULL, 1, '2026-11-21 08:40:00'),
  (298, 'ALTERAR', 301, 298, 'Futebol Society', 'Sub 15', 'MASCULINO', 'FINAL', 'Campo Society do CETI', NULL, NULL, NULL, 1, '2026-11-21 09:20:00', NULL, NULL, NULL, 1, '2026-11-21 09:20:00'),
  (299, 'ALTERAR', 302, 299, 'Futebol Society', 'Sub 17', 'MASCULINO', 'FINAL', 'Campo Society do CETI', NULL, NULL, NULL, 1, '2026-11-21 10:00:00', NULL, NULL, NULL, 1, '2026-11-21 10:00:00'),
  (300, 'REMOVER', 205, NULL, 'Handebol', 'Sub 11', 'FEMININO', 'GRUPOS', 'Quadra do CEBC', 'A', 'FRANCISCO AMORIM', 'CEJA', 1, '2026-11-20 10:40:00', NULL, NULL, NULL, NULL, NULL),
  (301, 'REMOVER', 230, NULL, 'Handebol', 'Sub 11', 'FEMININO', 'SEMIFINAL', 'Quadra da Adelieta Ramalho', NULL, NULL, NULL, 1, '2026-11-21 11:20:00', NULL, NULL, NULL, NULL, NULL),
  (302, 'REMOVER', 231, NULL, 'Handebol', 'Sub 11', 'FEMININO', 'SEMIFINAL', 'Quadra da Adelieta Ramalho', NULL, NULL, NULL, 2, '2026-11-21 12:00:00', NULL, NULL, NULL, NULL, NULL);

-- A competição de cada linha (modalidade + categoria + gênero)
UPDATE alvo_db43 t
   SET t.comp_id = (SELECT MAX(c.id) FROM competicoes c
                      INNER JOIN modalidades m ON m.id = c.modalidade_id
                      INNER JOIN categorias cat ON cat.id = c.categoria_id
                     WHERE m.nome = t.modalidade AND cat.nome = t.categoria AND c.genero = t.genero);

-- ---------------------------------------------------------------------
-- Os jogos do banco: par de equipes, ocorrência do par na competição (ou ordem
-- no mata-mata) e se já foram mexidos
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS jogo_db43;
CREATE TEMPORARY TABLE jogo_db43 (
  id          INT          NOT NULL PRIMARY KEY,
  comp        INT          NOT NULL,
  fase        VARCHAR(10)  NOT NULL,
  gnome       VARCHAR(10)  NULL,
  e1n         VARCHAR(100) NULL,
  e2n         VARCHAR(100) NULL,
  occ         INT          NOT NULL,
  nt          INT          NULL,
  dh          DATETIME     NULL,
  local_nome  VARCHAR(80)  NULL,
  sujo        INT          NOT NULL DEFAULT 0,   -- status, placar, cobranças, súmula, set, suspensão
  vaga_cheia  INT          NOT NULL DEFAULT 0,   -- mata-mata com equipe posta pelo automático
  plano       INT          NOT NULL DEFAULT 0    -- em quantas linhas do plano o jogo caiu
);
INSERT INTO jogo_db43 (id, comp, fase, gnome, e1n, e2n, occ, nt, dh, local_nome)
SELECT d.id, d.competicao_id, d.fase, d.gnome, d.e1n, d.e2n,
       ROW_NUMBER() OVER (PARTITION BY d.competicao_id, d.fase, d.chave ORDER BY d.data_hora, d.numero_tabela),
       d.numero_tabela, d.data_hora, d.local_nome
  FROM (SELECT j.id, j.competicao_id, j.fase, j.data_hora, j.numero_tabela, l.nome AS local_nome, g.nome AS gnome,
               s1.nome AS e1n, s2.nome AS e2n,
               CASE WHEN j.fase = 'GRUPOS' THEN CONCAT(LEAST(s1.nome, s2.nome), '|', GREATEST(s1.nome, s2.nome)) ELSE '' END AS chave
          FROM jogos j
          LEFT JOIN grupos g ON g.id = j.grupo_id
          LEFT JOIN locais_disputa l ON l.id = j.local_id
          LEFT JOIN equipes q1 ON q1.id = j.equipe_1_id LEFT JOIN escolas s1 ON s1.id = q1.escola_id
          LEFT JOIN equipes q2 ON q2.id = j.equipe_2_id LEFT JOIN escolas s2 ON s2.id = q2.escola_id) d;

UPDATE jogo_db43 x
  INNER JOIN jogos j ON j.id = x.id
   SET x.sujo = (j.status <> 'AGENDADO') + (j.placar_1 IS NOT NULL) + (j.placar_2 IS NOT NULL)
              + (j.vencedor_equipe_id IS NOT NULL) + (j.penaltis_1 IS NOT NULL) + (j.penaltis_2 IS NOT NULL)
              + (j.prorrogacao <> 0) + (j.baleou_primeiro_equipe_id IS NOT NULL)
              + (SELECT COUNT(*) FROM sumula_atletas sa WHERE sa.jogo_id = j.id)
              + (SELECT COUNT(*) FROM sumula_equipes se WHERE se.jogo_id = j.id)
              + (SELECT COUNT(*) FROM jogo_sets js WHERE js.jogo_id = j.id)
              + (SELECT COUNT(*) FROM suspensoes su WHERE su.jogo_origem_id = j.id),
       -- lado com equipe e sem vaga manual (a vaga manual do ADMIN não depende da tabela)
       x.vaga_cheia = CASE WHEN j.fase = 'GRUPOS' THEN 0 ELSE
            (j.equipe_1_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM jogo_vagas v WHERE v.jogo_id = j.id AND v.lado = 1 AND v.manual = 1))
          + (j.equipe_2_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM jogo_vagas v WHERE v.jogo_id = j.id AND v.lado = 2 AND v.manual = 1)) END;

-- Cada linha do plano no banco, como na 20268 e como na 20269 (uma consulta por
-- coluna: a tabela temporária só pode ser lida uma vez em cada comando, erro 1137)
UPDATE alvo_db43 t
   SET t.n_antes = (SELECT COUNT(*) FROM jogo_db43 x
                     WHERE x.comp = t.comp_id AND x.fase = t.fase AND x.occ = t.occ_antes
                       AND (t.fase <> 'GRUPOS' OR (x.e1n = t.e1_antes AND x.e2n = t.e2_antes) OR (x.e1n = t.e2_antes AND x.e2n = t.e1_antes)));
UPDATE alvo_db43 t
   SET t.id_antes = (SELECT MAX(x.id) FROM jogo_db43 x
                      WHERE x.comp = t.comp_id AND x.fase = t.fase AND x.occ = t.occ_antes
                        AND (t.fase <> 'GRUPOS' OR (x.e1n = t.e1_antes AND x.e2n = t.e2_antes) OR (x.e1n = t.e2_antes AND x.e2n = t.e1_antes)));
UPDATE alvo_db43 t
   SET t.n_novo = (SELECT COUNT(*) FROM jogo_db43 x
                    WHERE t.acao <> 'REMOVER' AND x.comp = t.comp_id AND x.fase = t.fase AND x.occ = t.occ_novo
                      AND (t.fase <> 'GRUPOS' OR (x.e1n = t.e1_novo AND x.e2n = t.e2_novo) OR (x.e1n = t.e2_novo AND x.e2n = t.e1_novo)));
UPDATE alvo_db43 t
   SET t.id_novo = (SELECT MAX(x.id) FROM jogo_db43 x
                     WHERE t.acao <> 'REMOVER' AND x.comp = t.comp_id AND x.fase = t.fase AND x.occ = t.occ_novo
                       AND (t.fase <> 'GRUPOS' OR (x.e1n = t.e1_novo AND x.e2n = t.e2_novo) OR (x.e1n = t.e2_novo AND x.e2n = t.e1_novo)));

-- O estado: FEITO se o jogo já está como na 20269 (número, dia, hora, local e
-- grupo); APLICAR se está como na 20268; senão vazio, e a trava 1 para
-- (uma leitura de jogo_db43 por comando: erro 1137)
UPDATE alvo_db43 t
  INNER JOIN jogo_db43 xa ON xa.id = t.id_antes
   SET t.bate_antes = (xa.nt = t.a AND xa.dh = t.dh_antes AND xa.local_nome <=> t.local_nome
                       AND (t.acao = 'REMOVER' OR xa.gnome <=> t.g_antes));
UPDATE alvo_db43 t
  INNER JOIN jogo_db43 xn ON xn.id = t.id_novo
   SET t.bate_novo = (xn.nt = t.b AND xn.dh = t.dh_novo AND xn.local_nome <=> t.local_nome AND xn.gnome <=> t.g_novo);
UPDATE alvo_db43 t
   SET t.estado = CASE
         WHEN t.comp_id IS NULL OR t.n_antes > 1 OR t.n_novo > 1 THEN ''
         WHEN t.acao = 'REMOVER' AND t.n_antes = 0 THEN 'FEITO'
         WHEN t.acao = 'REMOVER' AND t.n_antes = 1 AND t.bate_antes = 1 THEN 'APLICAR'
         WHEN t.acao = 'REMOVER' THEN ''
         WHEN t.n_novo = 1 AND t.bate_novo = 1 THEN 'FEITO'
         WHEN t.n_antes = 1 AND t.bate_antes = 1 THEN 'APLICAR'
         ELSE '' END;
UPDATE alvo_db43 t
   SET t.jogo_id = CASE t.estado WHEN 'FEITO' THEN t.id_novo WHEN 'APLICAR' THEN t.id_antes ELSE NULL END;

-- Em quantas linhas cada jogo do banco caiu (tem de ser 1)
UPDATE jogo_db43 x SET x.plano = (SELECT COUNT(*) FROM alvo_db43 t WHERE t.jogo_id = x.id);

-- Os jogos que saem (para as vagas)
DROP TEMPORARY TABLE IF EXISTS sai_db43;
CREATE TEMPORARY TABLE sai_db43 (jogo_id INT NOT NULL PRIMARY KEY);
INSERT INTO sai_db43 (jogo_id)
SELECT jogo_id FROM alvo_db43 WHERE acao = 'REMOVER' AND estado = 'APLICAR' AND jogo_id IS NOT NULL;

SELECT acao, estado, COUNT(*) AS linhas FROM alvo_db43 GROUP BY acao, estado ORDER BY acao, estado;

-- O que muda de hora ou de equipe, e o que sai
SELECT t.acao, t.a AS de, t.b AS para, CONCAT(t.modalidade, ' ', t.categoria, ' ', IF(t.genero = 'MISTO', 'Misto', LEFT(t.genero, 1))) AS competicao, t.fase,
       CONCAT(COALESCE(t.e1_antes, '-'), ' x ', COALESCE(t.e2_antes, '-')) AS jogo_antes,
       CONCAT(COALESCE(t.e1_novo, '-'), ' x ', COALESCE(t.e2_novo, '-')) AS jogo_depois,
       DATE_FORMAT(t.dh_antes, '%d/%m %H:%i') AS antes, DATE_FORMAT(t.dh_novo, '%H:%i') AS depois, t.local_nome,
       t.n_antes, t.n_novo, t.estado
  FROM alvo_db43 t
 WHERE t.acao = 'REMOVER' OR NOT (t.dh_antes <=> t.dh_novo) OR NOT (t.e1_antes <=> t.e1_novo AND t.e2_antes <=> t.e2_novo)
    OR NOT (t.g_antes <=> t.g_novo)
 ORDER BY t.acao, COALESCE(t.b, t.a);

-- ---------------------------------------------------------------------
-- As duas competições que mudam de formato
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS comp_db43;
CREATE TEMPORARY TABLE comp_db43 (
  modalidade   VARCHAR(60) NOT NULL,
  categoria    VARCHAR(20) NOT NULL,
  genero       VARCHAR(10) NOT NULL,
  qtd_antes    INT NOT NULL,
  classif_antes INT NOT NULL,
  fase_antes   VARCHAR(20) NOT NULL,
  grupos_antes INT NOT NULL,
  equipes_fim  INT NOT NULL,
  comp_id      INT NULL,
  achadas      INT NOT NULL DEFAULT 0,
  grupo_a      INT NULL,
  grupo_b      INT NULL,
  grupos       INT NOT NULL DEFAULT 0,
  qtd          INT NULL,
  classif      INT NULL,
  fase         VARCHAR(20) NULL,
  melhores     INT NULL,
  turno        VARCHAR(20) NULL,
  final_id     INT NULL,
  estado       VARCHAR(10) NOT NULL DEFAULT ''
);
-- Depois, nas duas: 2 grupos (A e B), 1 classificado por grupo, FINAL, turno único
INSERT INTO comp_db43 (modalidade, categoria, genero, qtd_antes, classif_antes, fase_antes, grupos_antes, equipes_fim) VALUES
  ('Handebol', 'Sub 11', 'FEMININO', 2, 2, 'SEMIFINAL', 2, 5),
  ('Baleado',  'Sub 9',  'FEMININO', 1, 2, 'FINAL',     1, 5);
UPDATE comp_db43 x
   SET x.achadas = (SELECT COUNT(*) FROM competicoes c
                      INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.nome = x.modalidade
                      INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = x.categoria
                     WHERE c.genero = x.genero),
       x.comp_id = (SELECT MAX(c.id) FROM competicoes c
                      INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.nome = x.modalidade
                      INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = x.categoria
                     WHERE c.genero = x.genero);
UPDATE comp_db43 x
  INNER JOIN competicoes c ON c.id = x.comp_id
   SET x.qtd = c.qtd_grupos, x.classif = c.classificados_por_grupo, x.fase = c.proxima_fase,
       x.melhores = c.melhores_segundos, x.turno = c.turno,
       x.grupo_a = (SELECT MAX(g.id) FROM grupos g WHERE g.competicao_id = x.comp_id AND g.nome = 'A'),
       x.grupo_b = (SELECT MAX(g.id) FROM grupos g WHERE g.competicao_id = x.comp_id AND g.nome = 'B'),
       x.grupos  = (SELECT COUNT(*) FROM grupos g WHERE g.competicao_id = x.comp_id),
       x.final_id = (SELECT MAX(j.id) FROM jogos j WHERE j.competicao_id = x.comp_id AND j.fase = 'FINAL');
UPDATE comp_db43 x
   SET x.estado = CASE
         WHEN x.achadas <> 1 OR x.melhores <> 0 OR x.turno <> 'UNICO' OR x.grupo_a IS NULL OR x.final_id IS NULL THEN ''
         WHEN x.qtd = 2 AND x.classif = 1 AND x.fase = 'FINAL' AND x.grupos = 2 AND x.grupo_b IS NOT NULL THEN 'FEITO'
         WHEN x.qtd = x.qtd_antes AND x.classif = x.classif_antes AND x.fase = x.fase_antes AND x.grupos = x.grupos_antes THEN 'APLICAR'
         ELSE '' END;

SET @hf_db43  = (SELECT comp_id FROM comp_db43 WHERE modalidade = 'Handebol');
SET @bf_db43  = (SELECT comp_id FROM comp_db43 WHERE modalidade = 'Baleado');
SET @hfa_db43 = (SELECT grupo_a FROM comp_db43 WHERE modalidade = 'Handebol');
SET @hfb_db43 = (SELECT grupo_b FROM comp_db43 WHERE modalidade = 'Handebol');
SET @bfa_db43 = (SELECT grupo_a FROM comp_db43 WHERE modalidade = 'Baleado');
SET @hf_final_db43 = (SELECT final_id FROM comp_db43 WHERE modalidade = 'Handebol');
SET @bf_final_db43 = (SELECT final_id FROM comp_db43 WHERE modalidade = 'Baleado');

SELECT modalidade, categoria, genero, achadas, grupos, CONCAT(qtd, ' grupo(s), ', classif, ' classificado(s), ', fase) AS regra_hoje,
       '2 grupos, 1 classificado, FINAL' AS regra_depois, estado
  FROM comp_db43;

-- A equipe do CEJA no Handebol Sub 11 F (sai com as inscrições; súmula ou colocação = para)
DROP TEMPORARY TABLE IF EXISTS equipe_db43;
CREATE TEMPORARY TABLE equipe_db43 (
  achadas     INT NOT NULL DEFAULT 0,
  equipe_id   INT NULL,
  inscricoes  INT NOT NULL DEFAULT 0,
  sumulas     INT NOT NULL DEFAULT 0,
  colocacoes  INT NOT NULL DEFAULT 0,
  estado      VARCHAR(10) NOT NULL DEFAULT ''
);
INSERT INTO equipe_db43 (achadas, equipe_id)
SELECT COUNT(*), MAX(e.id) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'CEJA'
 WHERE e.competicao_id = @hf_db43;
UPDATE equipe_db43 x
   SET x.inscricoes = (SELECT COUNT(*) FROM inscricoes_atletas i WHERE i.equipe_id = x.equipe_id),
       x.sumulas = (SELECT COUNT(*) FROM sumula_atletas sa WHERE sa.equipe_id = x.equipe_id)
                 + (SELECT COUNT(*) FROM sumula_equipes se WHERE se.equipe_id = x.equipe_id),
       x.colocacoes = (SELECT COUNT(*) FROM colocacoes_finais cf WHERE cf.equipe_id = x.equipe_id);
UPDATE equipe_db43 x
   SET x.estado = CASE WHEN x.achadas = 1 AND x.sumulas = 0 AND x.colocacoes = 0 THEN 'APLICAR'
                       WHEN x.achadas = 0 THEN 'FEITO' ELSE '' END;
SELECT 'CEJA no Handebol Sub 11 F' AS equipe, achadas, inscricoes AS inscricoes_que_saem, sumulas, colocacoes, estado FROM equipe_db43;

-- As equipes do jogo que troca de equipe (158: Francisco Amorim no lugar do CEJA), na competição do jogo
UPDATE alvo_db43 t
   SET t.e1_novo_id = (SELECT MAX(e.id) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id
                        WHERE e.competicao_id = t.comp_id AND s.nome = t.e1_novo),
       t.e2_novo_id = (SELECT MAX(e.id) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id
                        WHERE e.competicao_id = t.comp_id AND s.nome = t.e2_novo)
 WHERE t.fase = 'GRUPOS' AND t.acao <> 'REMOVER' AND NOT (t.e1_antes <=> t.e1_novo AND t.e2_antes <=> t.e2_novo);

-- Contagem de itens: as linhas que mudam ou saem, as duas competições e a equipe do CEJA
SET @aplicar_db43 = (SELECT COUNT(*) FROM alvo_db43 WHERE acao <> 'IGUAL' AND estado = 'APLICAR')
                  + (SELECT COUNT(*) FROM comp_db43 WHERE estado = 'APLICAR')
                  + (SELECT COUNT(*) FROM equipe_db43 WHERE estado = 'APLICAR');
SET @feito_db43   = (SELECT COUNT(*) FROM alvo_db43 WHERE acao <> 'IGUAL' AND estado = 'FEITO')
                  + (SELECT COUNT(*) FROM comp_db43 WHERE estado = 'FEITO')
                  + (SELECT COUNT(*) FROM equipe_db43 WHERE estado = 'FEITO');
SET @jogos_db43 = (SELECT COUNT(*) FROM jogos);
SELECT @aplicar_db43 AS itens_a_aplicar, @feito_db43 AS itens_ja_feitos, @jogos_db43 AS jogos_no_banco;

-- ---------------------------------------------------------------------
-- Trava 1: o plano bate com o banco
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS trava_jogo_db43;
CREATE TEMPORARY TABLE trava_jogo_db43 (
  item VARCHAR(80) NOT NULL,
  ok   TINYINT     NOT NULL,
  CONSTRAINT db43_jogo_nao_bate CHECK (ok = 1)
);
INSERT INTO trava_jogo_db43 (item, ok)
SELECT CONCAT('linha ', ordem, ' (', acao, ' ', a, ' -> ', COALESCE(b, '-'), ')'),
       CASE WHEN estado <> '' AND (acao <> 'IGUAL' OR estado = 'FEITO') THEN 1 ELSE 0 END
  FROM alvo_db43;
INSERT INTO trava_jogo_db43 (item, ok)
SELECT CONCAT('jogo do banco nº ', COALESCE(nt, '?'), ' em ', plano, ' linhas do plano'), 0
  FROM jogo_db43 WHERE plano <> 1;
DROP TEMPORARY TABLE trava_jogo_db43;

-- Trava 2: estado misto (parte como na 20268, parte como na 20269)
DROP TEMPORARY TABLE IF EXISTS trava_misto_db43;
CREATE TEMPORARY TABLE trava_misto_db43 (
  item VARCHAR(80) NOT NULL,
  ok   TINYINT     NOT NULL,
  CONSTRAINT db43_estado_misto CHECK (ok = 1)
);
INSERT INTO trava_misto_db43 (item, ok)
SELECT 'tudo APLICAR ou tudo FEITO', CASE WHEN @aplicar_db43 = 0 OR @feito_db43 = 0 THEN 1 ELSE 0 END;
DROP TEMPORARY TABLE trava_misto_db43;

-- Trava 3: nada que muda ou sai pode ter sido jogado (só quando há o que aplicar)
DROP TEMPORARY TABLE IF EXISTS trava_mexido_db43;
CREATE TEMPORARY TABLE trava_mexido_db43 (
  item VARCHAR(80) NOT NULL,
  ok   TINYINT     NOT NULL,
  CONSTRAINT db43_jogo_ja_mexido CHECK (ok = 1)
);
INSERT INTO trava_mexido_db43 (item, ok)
SELECT CONCAT('jogo nº ', x.nt), CASE WHEN x.sujo = 0 AND x.vaga_cheia = 0 THEN 1 ELSE 0 END
  FROM jogo_db43 x
  INNER JOIN alvo_db43 t ON t.jogo_id = x.id
 WHERE @aplicar_db43 > 0
   AND (t.acao IN ('ALTERAR', 'REMOVER') OR x.comp IN (@hf_db43, @bf_db43));
INSERT INTO trava_mexido_db43 (item, ok)
SELECT 'vaga de outro jogo vinda de jogo que sai', CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END
  FROM jogo_vagas v
 WHERE v.jogo_origem_id IN (SELECT s.jogo_id FROM sai_db43 s)
   AND v.jogo_id <> COALESCE(@hf_final_db43, 0);
DROP TEMPORARY TABLE trava_mexido_db43;

-- Trava 4: as duas competições, as equipes e a equipe do CEJA
DROP TEMPORARY TABLE IF EXISTS trava_comp_db43;
CREATE TEMPORARY TABLE trava_comp_db43 (
  item VARCHAR(80) NOT NULL,
  ok   TINYINT     NOT NULL,
  CONSTRAINT db43_competicao_nao_bate CHECK (ok = 1)
);
INSERT INTO trava_comp_db43 (item, ok)
SELECT CONCAT(modalidade, ' ', categoria, ' ', genero), CASE WHEN estado <> '' THEN 1 ELSE 0 END FROM comp_db43;
INSERT INTO trava_comp_db43 (item, ok)
SELECT 'CEJA no Handebol Sub 11 F (súmula ou colocação)', CASE WHEN estado <> '' THEN 1 ELSE 0 END FROM equipe_db43;
INSERT INTO trava_comp_db43 (item, ok)
SELECT CONCAT('equipes do jogo ', a, ' -> ', b), CASE WHEN estado = 'FEITO' OR (e1_novo_id IS NOT NULL AND e2_novo_id IS NOT NULL) THEN 1 ELSE 0 END
  FROM alvo_db43 WHERE fase = 'GRUPOS' AND acao <> 'REMOVER' AND NOT (e1_antes <=> e1_novo AND e2_antes <=> e2_novo);
INSERT INTO trava_comp_db43 (item, ok)
SELECT 'José Dias e Adelieta no Baleado Sub 9 F (2)',
       CASE WHEN COUNT(*) = 2 THEN 1 ELSE 0 END
  FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id AND s.nome IN ('JOSE DIAS', 'ADELIETA RAMALHO')
 WHERE e.competicao_id = @bf_db43;
DROP TEMPORARY TABLE trava_comp_db43;

-- Contagens de antes
SET @vagas_antes_db43   = (SELECT COUNT(*) FROM jogo_vagas);
SET @equipes_antes_db43 = (SELECT COUNT(*) FROM equipes);
SET @grupos_antes_db43  = (SELECT COUNT(*) FROM grupos);
SET @insc_antes_db43    = (SELECT COUNT(*) FROM inscricoes_atletas);
SET @insc_ceja_db43     = (SELECT COALESCE(SUM(CASE WHEN estado = 'APLICAR' THEN inscricoes ELSE 0 END), 0) FROM equipe_db43);
SET @vagas_saem_db43    = (SELECT COUNT(*) FROM jogo_vagas v INNER JOIN sai_db43 s ON s.jogo_id = v.jogo_id);
SET @faz_db43 = (@aplicar_db43 > 0);

-- ---------------------------------------------------------------------
-- As escritas (só no que é APLICAR)
-- ---------------------------------------------------------------------
-- 1) Baleado Sub 9 F: o grupo B volta
INSERT INTO grupos (competicao_id, nome)
SELECT x.comp_id, 'B' FROM comp_db43 x
 WHERE x.modalidade = 'Baleado' AND x.estado = 'APLICAR' AND x.grupo_b IS NULL;
SET @grupos_criados_db43 = ROW_COUNT();
SET @bfb_db43 = (SELECT MAX(g.id) FROM grupos g WHERE g.competicao_id = @bf_db43 AND g.nome = 'B');

-- O grupo novo de cada jogo de grupo (pelo nome, na competição do jogo)
UPDATE alvo_db43 t
   SET t.g_novo_id = (SELECT MAX(g.id) FROM grupos g WHERE g.competicao_id = t.comp_id AND g.nome = t.g_novo)
 WHERE t.fase = 'GRUPOS' AND t.acao <> 'REMOVER';

-- 2) As finais das duas competições: 1º do Grupo A x 1º do Grupo B (antes de
--    apagar as semifinais do Handebol Sub 11 F, de onde vinham as vagas da final)
UPDATE jogo_vagas v
   SET v.tipo = 'GRUPO', v.grupo_id = CASE v.lado WHEN 1 THEN @hfa_db43 ELSE @hfb_db43 END, v.posicao = 1,
       v.jogo_origem_id = NULL, v.rotulo = CASE v.lado WHEN 1 THEN '1º do Grupo A' ELSE '1º do Grupo B' END
 WHERE v.jogo_id = @hf_final_db43 AND @faz_db43
   AND (SELECT estado FROM comp_db43 WHERE modalidade = 'Handebol') = 'APLICAR';
SET @vagas_finais_db43 = ROW_COUNT();
UPDATE jogo_vagas v
   SET v.tipo = 'GRUPO', v.grupo_id = CASE v.lado WHEN 1 THEN @bfa_db43 ELSE @bfb_db43 END, v.posicao = 1,
       v.jogo_origem_id = NULL, v.rotulo = CASE v.lado WHEN 1 THEN '1º do Grupo A' ELSE '1º do Grupo B' END
 WHERE v.jogo_id = @bf_final_db43 AND @faz_db43
   AND (SELECT estado FROM comp_db43 WHERE modalidade = 'Baleado') = 'APLICAR';
SET @vagas_finais_db43 = @vagas_finais_db43 + ROW_COUNT();

-- 3) O jogo que troca de equipe (158: Maria da Glória x Francisco Amorim)
UPDATE jogos j
  INNER JOIN alvo_db43 t ON t.jogo_id = j.id AND t.estado = 'APLICAR' AND t.e1_novo_id IS NOT NULL
   SET j.equipe_1_id = t.e1_novo_id, j.equipe_2_id = t.e2_novo_id;
SET @jogos_equipes_db43 = ROW_COUNT();

-- 4) Os jogos que saem (as vagas das semifinais vão junto: ON DELETE CASCADE)
DELETE j FROM jogos j INNER JOIN sai_db43 s ON s.jogo_id = j.id;
SET @jogos_removidos_db43 = ROW_COUNT();

-- 5) A equipe do CEJA sai do Handebol Sub 11 F, com as inscrições (os atletas ficam)
DELETE i FROM inscricoes_atletas i
  INNER JOIN equipe_db43 x ON x.equipe_id = i.equipe_id AND x.estado = 'APLICAR';
SET @inscricoes_removidas_db43 = ROW_COUNT();
DELETE e FROM equipes e
  INNER JOIN equipe_db43 x ON x.equipe_id = e.id AND x.estado = 'APLICAR';
SET @equipes_removidas_db43 = ROW_COUNT();

-- 6) Baleado Sub 9 F: José Dias e Adelieta vão para o grupo B, com os jogos delas
UPDATE equipes e
  INNER JOIN escolas s ON s.id = e.escola_id AND s.nome IN ('JOSE DIAS', 'ADELIETA RAMALHO')
   SET e.grupo_id = @bfb_db43
 WHERE e.competicao_id = @bf_db43 AND @bfb_db43 IS NOT NULL AND NOT (e.grupo_id <=> @bfb_db43);
SET @equipes_movidas_db43 = ROW_COUNT();
UPDATE jogos j
  INNER JOIN alvo_db43 t ON t.jogo_id = j.id AND t.estado = 'APLICAR'
   SET j.grupo_id = t.g_novo_id
 WHERE t.fase = 'GRUPOS' AND NOT (t.g_antes <=> t.g_novo);
SET @jogos_movidos_db43 = ROW_COUNT();

-- 7) A regra das duas: 2 grupos, 1 classificado por grupo, FINAL
UPDATE competicoes c
  INNER JOIN comp_db43 x ON x.comp_id = c.id AND x.estado = 'APLICAR'
   SET c.qtd_grupos = 2, c.classificados_por_grupo = 1, c.proxima_fase = 'FINAL';
SET @regras_mudadas_db43 = ROW_COUNT();

-- 8) numero_tabela, fase 1: tira do caminho todos os que mudam de número
UPDATE jogos j
  INNER JOIN alvo_db43 t ON t.jogo_id = j.id AND t.estado = 'APLICAR' AND t.acao = 'ALTERAR' AND t.a <> t.b
   SET j.numero_tabela = 10000 + t.b;

-- 9) Os jogos que ficam: número e hora da 20269 (dia e local não mudam)
UPDATE jogos j
  INNER JOIN alvo_db43 t ON t.jogo_id = j.id AND t.estado = 'APLICAR' AND t.acao = 'ALTERAR'
   SET j.numero_tabela = t.b, j.data_hora = t.dh_novo;
SET @jogos_alterados_db43 = ROW_COUNT();

-- 10) numero_jogo do Handebol Sub 11 F: de 1 a N por data e hora, em 2 fases
--     (o índice único é por competição)
UPDATE jogos j SET j.numero_jogo = 10000 + j.numero_tabela
 WHERE j.competicao_id = @hf_db43 AND @faz_db43;
DROP TEMPORARY TABLE IF EXISTS ordem_db43;
CREATE TEMPORARY TABLE ordem_db43 (id INT NOT NULL PRIMARY KEY, nj INT NOT NULL);
INSERT INTO ordem_db43 (id, nj)
SELECT j.id, ROW_NUMBER() OVER (ORDER BY j.data_hora, j.numero_tabela)
  FROM jogos j WHERE j.competicao_id = @hf_db43 AND @faz_db43;
UPDATE jogos j INNER JOIN ordem_db43 o ON o.id = j.id SET j.numero_jogo = o.nj;
SET @jogos_renumerados_db43 = ROW_COUNT();

-- 11) Rótulo "Vencedor do jogo N" com o número novo do jogo de origem
UPDATE jogo_vagas v
  INNER JOIN jogos jo ON jo.id = v.jogo_origem_id
   SET v.rotulo = CONCAT('Vencedor do jogo ', jo.numero_tabela)
 WHERE v.tipo = 'VENCEDOR' AND NOT (v.rotulo <=> CONCAT('Vencedor do jogo ', jo.numero_tabela));
SET @rotulos_db43 = ROW_COUNT();

-- ---------------------------------------------------------------------
-- Conferências
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS conferencia_db43;
CREATE TEMPORARY TABLE conferencia_db43 (
  item       VARCHAR(140) NOT NULL,
  esperado   INT          NOT NULL,
  encontrado INT          NOT NULL
);

INSERT INTO conferencia_db43 SELECT 'jogos no banco (299)', 299, COUNT(*) FROM jogos;
INSERT INTO conferencia_db43 SELECT 'jogos de grupo (228)', 228, COUNT(*) FROM jogos WHERE fase = 'GRUPOS';
INSERT INTO conferencia_db43 SELECT 'jogos de mata-mata (71)', 71, COUNT(*) FROM jogos WHERE fase <> 'GRUPOS';
INSERT INTO conferencia_db43 SELECT '18/11: grupo (36)', 36, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-18';
INSERT INTO conferencia_db43 SELECT '18/11: mata-mata (0)', 0, COUNT(*) FROM jogos WHERE fase <> 'GRUPOS' AND DATE(data_hora) = '2026-11-18';
INSERT INTO conferencia_db43 SELECT '19/11: grupo (92)', 92, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-19';
INSERT INTO conferencia_db43 SELECT '19/11: mata-mata (0)', 0, COUNT(*) FROM jogos WHERE fase <> 'GRUPOS' AND DATE(data_hora) = '2026-11-19';
INSERT INTO conferencia_db43 SELECT '20/11: grupo (75)', 75, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-20';
INSERT INTO conferencia_db43 SELECT '20/11: mata-mata (9)', 9, COUNT(*) FROM jogos WHERE fase <> 'GRUPOS' AND DATE(data_hora) = '2026-11-20';
INSERT INTO conferencia_db43 SELECT '21/11: grupo (25)', 25, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-21';
INSERT INTO conferencia_db43 SELECT '21/11: mata-mata (62)', 62, COUNT(*) FROM jogos WHERE fase <> 'GRUPOS' AND DATE(data_hora) = '2026-11-21';
INSERT INTO conferencia_db43
SELECT 'jogo sem data ou fora de 18 a 21/11 (0)', 0, COUNT(*) FROM jogos
 WHERE data_hora IS NULL OR data_hora < '2026-11-18 00:00:00' OR data_hora >= '2026-11-22 00:00:00';
INSERT INTO conferencia_db43
SELECT 'numero_tabela de 1 a 299, sem repetir nem faltar (299)', 299, COUNT(DISTINCT numero_tabela) FROM jogos
 WHERE numero_tabela BETWEEN 1 AND 299;
INSERT INTO conferencia_db43
SELECT 'numero_tabela vazio, fora de 1 a 299 ou provisório (0)', 0, COUNT(*) FROM jogos
 WHERE numero_tabela IS NULL OR numero_tabela < 1 OR numero_tabela > 299;
INSERT INTO conferencia_db43
SELECT 'numero_jogo provisório que ficou (0)', 0, COUNT(*) FROM jogos WHERE numero_jogo >= 10000;
INSERT INTO conferencia_db43
SELECT 'equipe em dois jogos no mesmo dia e hora (0)', 0, COUNT(*)
  FROM (SELECT x.data_hora, x.equipe_id
          FROM (SELECT data_hora, equipe_1_id AS equipe_id FROM jogos
                UNION ALL SELECT data_hora, equipe_2_id FROM jogos) x
         WHERE x.equipe_id IS NOT NULL AND x.data_hora IS NOT NULL
         GROUP BY x.data_hora, x.equipe_id
        HAVING COUNT(*) > 1) d;
INSERT INTO conferencia_db43
SELECT 'local com dois jogos no mesmo dia e hora (0)', 0, COUNT(*)
  FROM (SELECT local_id, data_hora FROM jogos
         WHERE local_id IS NOT NULL AND data_hora IS NOT NULL
         GROUP BY local_id, data_hora HAVING COUNT(*) > 1) d;
INSERT INTO conferencia_db43
SELECT 'jogos da 20269 no banco com número, dia, hora, local, grupo e equipes (299)', 299, COUNT(*)
  FROM alvo_db43 t
 WHERE t.acao <> 'REMOVER'
   AND (SELECT COUNT(*) FROM jogos j
          LEFT JOIN locais_disputa l ON l.id = j.local_id
          LEFT JOIN grupos g ON g.id = j.grupo_id
          LEFT JOIN equipes q1 ON q1.id = j.equipe_1_id LEFT JOIN escolas s1 ON s1.id = q1.escola_id
          LEFT JOIN equipes q2 ON q2.id = j.equipe_2_id LEFT JOIN escolas s2 ON s2.id = q2.escola_id
         WHERE j.competicao_id = t.comp_id AND j.fase = t.fase AND j.numero_tabela = t.b
           AND j.data_hora = t.dh_novo AND l.nome = t.local_nome AND g.nome <=> t.g_novo
           AND (t.fase <> 'GRUPOS' OR (s1.nome = t.e1_novo AND s2.nome = t.e2_novo) OR (s1.nome = t.e2_novo AND s2.nome = t.e1_novo))) = 1;
INSERT INTO conferencia_db43
SELECT 'jogos que saem ainda no banco (0)', 0, COUNT(*) FROM jogos j INNER JOIN sai_db43 s ON s.jogo_id = j.id;
INSERT INTO conferencia_db43
SELECT 'vagas = antes - as das semifinais que saem', @vagas_antes_db43 - @vagas_saem_db43, COUNT(*) FROM jogo_vagas;
INSERT INTO conferencia_db43
SELECT 'equipes = antes - a do CEJA', @equipes_antes_db43 - (SELECT COUNT(*) FROM equipe_db43 WHERE estado = 'APLICAR'), COUNT(*) FROM equipes;
INSERT INTO conferencia_db43
SELECT 'inscrições = antes - as do CEJA no Handebol Sub 11 F', @insc_antes_db43 - @insc_ceja_db43, COUNT(*) FROM inscricoes_atletas;
INSERT INTO conferencia_db43
SELECT 'grupos = antes + o grupo B do Baleado Sub 9 F', @grupos_antes_db43 + @grupos_criados_db43, COUNT(*) FROM grupos;
INSERT INTO conferencia_db43
SELECT 'rótulo "Vencedor do jogo N" com número antigo (0)', 0, COUNT(*)
  FROM jogo_vagas v INNER JOIN jogos jo ON jo.id = v.jogo_origem_id
 WHERE v.tipo = 'VENCEDOR' AND NOT (v.rotulo <=> CONCAT('Vencedor do jogo ', jo.numero_tabela));
INSERT INTO conferencia_db43
SELECT 'vaga de grupo apontando para grupo de outra competição (0)', 0, COUNT(*)
  FROM jogo_vagas v INNER JOIN jogos j ON j.id = v.jogo_id INNER JOIN grupos g ON g.id = v.grupo_id
 WHERE v.tipo = 'GRUPO' AND g.competicao_id <> j.competicao_id;
-- As duas competições
INSERT INTO conferencia_db43
SELECT CONCAT(x.modalidade, ' ', x.categoria, ' F: 2 grupos (A e B), 1 classificado, FINAL (1)'), 1,
       (SELECT COUNT(*) FROM competicoes c WHERE c.id = x.comp_id AND c.qtd_grupos = 2 AND c.classificados_por_grupo = 1
           AND c.proxima_fase = 'FINAL' AND c.melhores_segundos = 0 AND c.turno = 'UNICO')
     * (SELECT CASE WHEN COUNT(*) = 2 AND MIN(g.nome) = 'A' AND MAX(g.nome) = 'B' THEN 1 ELSE 0 END FROM grupos g WHERE g.competicao_id = x.comp_id)
  FROM comp_db43 x;
INSERT INTO conferencia_db43
SELECT CONCAT(x.modalidade, ' ', x.categoria, ' F: equipes (', x.equipes_fim, ')'), x.equipes_fim,
       (SELECT COUNT(*) FROM equipes e WHERE e.competicao_id = x.comp_id)
  FROM comp_db43 x;
INSERT INTO conferencia_db43
SELECT 'Handebol Sub 11 F: grupo A = Francisco Amorim e Maria da Glória (2)', 2, COUNT(*)
  FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id AND s.nome IN ('FRANCISCO AMORIM', 'MARIA DA GLORIA')
 WHERE e.competicao_id = @hf_db43 AND e.grupo_id = @hfa_db43;
INSERT INTO conferencia_db43
SELECT 'Handebol Sub 11 F: grupo A com 2 e grupo B com 3 equipes (23)', 23,
       10 * (SELECT COUNT(*) FROM equipes WHERE competicao_id = @hf_db43 AND grupo_id = @hfa_db43)
     + (SELECT COUNT(*) FROM equipes WHERE competicao_id = @hf_db43 AND grupo_id = @hfb_db43);
INSERT INTO conferencia_db43
SELECT 'Handebol Sub 11 F: equipe do CEJA (0)', 0, COUNT(*)
  FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'CEJA' WHERE e.competicao_id = @hf_db43;
INSERT INTO conferencia_db43
SELECT 'Handebol Sub 11 F: 5 jogos de grupo, 0 semifinal e 1 final (501)', 501,
       100 * (SELECT COUNT(*) FROM jogos WHERE competicao_id = @hf_db43 AND fase = 'GRUPOS')
     + 10 * (SELECT COUNT(*) FROM jogos WHERE competicao_id = @hf_db43 AND fase = 'SEMIFINAL')
     + (SELECT COUNT(*) FROM jogos WHERE competicao_id = @hf_db43 AND fase = 'FINAL');
INSERT INTO conferencia_db43
SELECT 'Handebol Sub 11 F: numero_jogo de 1 a 6, por data e hora (6)', 6, COUNT(*)
  FROM (SELECT j.numero_jogo, ROW_NUMBER() OVER (ORDER BY j.data_hora, j.numero_tabela) AS ordem
          FROM jogos j WHERE j.competicao_id = @hf_db43) d
 WHERE d.numero_jogo = d.ordem;
INSERT INTO conferencia_db43
SELECT 'Baleado Sub 9 F: grupo A com 3 e grupo B com 2 equipes (32)', 32,
       10 * (SELECT COUNT(*) FROM equipes WHERE competicao_id = @bf_db43 AND grupo_id = @bfa_db43)
     + (SELECT COUNT(*) FROM equipes WHERE competicao_id = @bf_db43 AND grupo_id = @bfb_db43);
INSERT INTO conferencia_db43
SELECT 'Baleado Sub 9 F: grupo B = José Dias e Adelieta (2)', 2, COUNT(*)
  FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id AND s.nome IN ('JOSE DIAS', 'ADELIETA RAMALHO')
 WHERE e.competicao_id = @bf_db43 AND e.grupo_id = @bfb_db43;
INSERT INTO conferencia_db43
SELECT 'Baleado Sub 9 F: 5 jogos de grupo e 1 final (51)', 51,
       10 * (SELECT COUNT(*) FROM jogos WHERE competicao_id = @bf_db43 AND fase = 'GRUPOS')
     + (SELECT COUNT(*) FROM jogos WHERE competicao_id = @bf_db43 AND fase <> 'GRUPOS');
INSERT INTO conferencia_db43
SELECT 'jogo de grupo das duas competições com equipe de outro grupo (0)', 0, COUNT(*)
  FROM jogos j
  INNER JOIN equipes e1 ON e1.id = j.equipe_1_id
  INNER JOIN equipes e2 ON e2.id = j.equipe_2_id
 WHERE j.competicao_id IN (@hf_db43, @bf_db43) AND j.fase = 'GRUPOS'
   AND NOT (e1.grupo_id <=> j.grupo_id AND e2.grupo_id <=> j.grupo_id);
INSERT INTO conferencia_db43
SELECT 'finais das duas: 1º do Grupo A x 1º do Grupo B, automáticas (4)', 4, COUNT(*)
  FROM jogo_vagas v
  INNER JOIN jogos j ON j.id = v.jogo_id AND j.fase = 'FINAL' AND j.competicao_id IN (@hf_db43, @bf_db43)
  INNER JOIN grupos g ON g.id = v.grupo_id AND g.competicao_id = j.competicao_id
 WHERE v.tipo = 'GRUPO' AND v.posicao = 1 AND v.manual = 0 AND v.jogo_origem_id IS NULL
   AND ((v.lado = 1 AND g.nome = 'A' AND v.rotulo = '1º do Grupo A') OR (v.lado = 2 AND g.nome = 'B' AND v.rotulo = '1º do Grupo B'));
INSERT INTO conferencia_db43
SELECT 'finais das duas: nº 232 (Handebol) e nº 275 (Baleado) (2)', 2, COUNT(*)
  FROM jogos j
 WHERE (j.competicao_id = @hf_db43 AND j.fase = 'FINAL' AND j.numero_tabela = 232 AND j.data_hora = '2026-11-21 13:20:00')
    OR (j.competicao_id = @bf_db43 AND j.fase = 'FINAL' AND j.numero_tabela = 275);

SELECT item, esperado, encontrado, CASE WHEN esperado = encontrado THEN 'ok' ELSE 'DIVERGE' END AS situacao
  FROM conferencia_db43;

-- Trava 5: qualquer divergência para aqui, antes do COMMIT
DROP TEMPORARY TABLE IF EXISTS trava_conferencia_db43;
CREATE TEMPORARY TABLE trava_conferencia_db43 (
  item VARCHAR(140) NOT NULL,
  ok   TINYINT      NOT NULL,
  CONSTRAINT db43_conferencia_divergiu CHECK (ok = 1)
);
INSERT INTO trava_conferencia_db43 (item, ok)
SELECT item, CASE WHEN esperado = encontrado THEN 1 ELSE 0 END FROM conferencia_db43;
DROP TEMPORARY TABLE trava_conferencia_db43;
DROP TEMPORARY TABLE conferencia_db43;
DROP TEMPORARY TABLE ordem_db43;
DROP TEMPORARY TABLE equipe_db43;
DROP TEMPORARY TABLE sai_db43;
DROP TEMPORARY TABLE jogo_db43;

COMMIT;

-- ---------------------------------------------------------------------
-- Depois do COMMIT, só leitura
-- ---------------------------------------------------------------------
SELECT @grupos_criados_db43 AS grupos_criados, @vagas_finais_db43 AS vagas_das_finais,
       @jogos_equipes_db43 AS jogos_com_equipe_nova, @jogos_removidos_db43 AS jogos_removidos,
       @inscricoes_removidas_db43 AS inscricoes_removidas, @equipes_removidas_db43 AS equipes_removidas,
       @equipes_movidas_db43 AS equipes_para_o_grupo_B, @jogos_movidos_db43 AS jogos_para_o_grupo_B,
       @regras_mudadas_db43 AS regras_mudadas, @jogos_alterados_db43 AS jogos_alterados,
       @jogos_renumerados_db43 AS numero_jogo_regravados, @rotulos_db43 AS rotulos_regravados;

-- As duas competições: regra, equipes e jogos
SELECT CONCAT(m.nome, ' ', cat.nome, ' ', c.genero) AS competicao, c.qtd_grupos, c.classificados_por_grupo, c.proxima_fase
  FROM comp_db43 x
  INNER JOIN competicoes c ON c.id = x.comp_id
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id;
SELECT CONCAT(x.modalidade, ' ', x.categoria, ' ', x.genero) AS competicao, g.nome AS grupo, s.nome AS escola,
       (SELECT COUNT(*) FROM inscricoes_atletas i WHERE i.equipe_id = e.id) AS inscritos
  FROM comp_db43 x
  INNER JOIN equipes e ON e.competicao_id = x.comp_id
  INNER JOIN escolas s ON s.id = e.escola_id
  LEFT JOIN grupos g ON g.id = e.grupo_id
 ORDER BY x.modalidade DESC, g.nome, s.nome;
SELECT CONCAT(x.modalidade, ' ', x.categoria, ' ', x.genero) AS competicao, j.numero_jogo, j.numero_tabela, j.fase, g.nome AS grupo,
       DATE_FORMAT(j.data_hora, '%d/%m %H:%i') AS quando, l.nome AS local_,
       COALESCE(s1.nome, (SELECT v.rotulo FROM jogo_vagas v WHERE v.jogo_id = j.id AND v.lado = 1)) AS equipe_1,
       COALESCE(s2.nome, (SELECT v.rotulo FROM jogo_vagas v WHERE v.jogo_id = j.id AND v.lado = 2)) AS equipe_2
  FROM comp_db43 x
  INNER JOIN jogos j ON j.competicao_id = x.comp_id
  LEFT JOIN grupos g ON g.id = j.grupo_id
  LEFT JOIN locais_disputa l ON l.id = j.local_id
  LEFT JOIN equipes e1 ON e1.id = j.equipe_1_id LEFT JOIN escolas s1 ON s1.id = e1.escola_id
  LEFT JOIN equipes e2 ON e2.id = j.equipe_2_id LEFT JOIN escolas s2 ON s2.id = e2.escola_id
 ORDER BY x.modalidade DESC, j.numero_jogo;

-- Aviso (não aborta): ESCOLA em dois jogos no mesmo dia e hora, envolvendo jogos que mudam de hora ou de equipe
SELECT DATE_FORMAT(x.data_hora, '%d/%m %H:%i') AS quando, s.nome AS escola,
       GROUP_CONCAT(CONCAT('nº ', j.numero_tabela, ' ', m.nome, ' ', cat.nome, ' ', IF(c.genero = 'MISTO', 'Misto', LEFT(c.genero, 1)))
                    ORDER BY j.numero_tabela SEPARATOR ' | ') AS jogos
  FROM (SELECT id, data_hora, equipe_1_id AS equipe_id FROM jogos UNION ALL SELECT id, data_hora, equipe_2_id FROM jogos) x
  INNER JOIN jogos j ON j.id = x.id
  INNER JOIN equipes e ON e.id = x.equipe_id
  INNER JOIN escolas s ON s.id = e.escola_id
  INNER JOIN competicoes c ON c.id = j.competicao_id
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
 WHERE (x.data_hora, s.id) IN (
         SELECT j2.data_hora, e2.escola_id
           FROM alvo_db43 t
           INNER JOIN jogos j2 ON j2.numero_tabela = t.b
           INNER JOIN equipes e2 ON e2.id IN (j2.equipe_1_id, j2.equipe_2_id)
          WHERE NOT (t.dh_antes <=> t.dh_novo) OR NOT (t.e1_antes <=> t.e1_novo AND t.e2_antes <=> t.e2_novo))
 GROUP BY x.data_hora, s.id, s.nome
HAVING COUNT(*) > 1
 ORDER BY x.data_hora, s.nome;

-- Aviso (não aborta): ATLETA em dois jogos no mesmo dia e hora (inscrito nas
-- duas equipes), em toda a tabela. "mexido_pelo_db43" = um dos dois jogos mudou
-- de hora ou de equipe neste script. Só leitura: mostra nomes na tela, não grava.
DROP TEMPORARY TABLE IF EXISTS atleta_conflito_db43;
CREATE TEMPORARY TABLE atleta_conflito_db43 (
  atleta     VARCHAR(150) NOT NULL,
  escola     VARCHAR(100) NOT NULL,
  quando     DATETIME     NOT NULL,
  nt_1       INT          NOT NULL,
  comp_1     VARCHAR(80)  NOT NULL,
  local_1    VARCHAR(80)  NULL,
  nt_2       INT          NOT NULL,
  comp_2     VARCHAR(80)  NOT NULL,
  local_2    VARCHAR(80)  NULL,
  mexido     TINYINT      NOT NULL DEFAULT 0
);
INSERT INTO atleta_conflito_db43 (atleta, escola, quando, nt_1, comp_1, local_1, nt_2, comp_2, local_2)
SELECT a.nome, s.nome, j1.data_hora,
       j1.numero_tabela, CONCAT(m1.nome, ' ', k1.nome, ' ', IF(c1.genero = 'MISTO', 'Misto', LEFT(c1.genero, 1))), l1.nome,
       j2.numero_tabela, CONCAT(m2.nome, ' ', k2.nome, ' ', IF(c2.genero = 'MISTO', 'Misto', LEFT(c2.genero, 1))), l2.nome
  FROM inscricoes_atletas i1
  INNER JOIN jogos j1 ON i1.equipe_id IN (j1.equipe_1_id, j1.equipe_2_id)
  INNER JOIN inscricoes_atletas i2 ON i2.atleta_id = i1.atleta_id AND i2.id <> i1.id
  INNER JOIN jogos j2 ON i2.equipe_id IN (j2.equipe_1_id, j2.equipe_2_id)
                     AND j2.data_hora = j1.data_hora AND j2.numero_tabela > j1.numero_tabela
  INNER JOIN atletas a ON a.id = i1.atleta_id
  INNER JOIN escolas s ON s.id = a.escola_id
  INNER JOIN competicoes c1 ON c1.id = j1.competicao_id
  INNER JOIN modalidades m1 ON m1.id = c1.modalidade_id
  INNER JOIN categorias k1 ON k1.id = c1.categoria_id
  INNER JOIN competicoes c2 ON c2.id = j2.competicao_id
  INNER JOIN modalidades m2 ON m2.id = c2.modalidade_id
  INNER JOIN categorias k2 ON k2.id = c2.categoria_id
  LEFT JOIN locais_disputa l1 ON l1.id = j1.local_id
  LEFT JOIN locais_disputa l2 ON l2.id = j2.local_id
 WHERE j1.data_hora IS NOT NULL;
-- (a temporária só pode ser lida uma vez por comando: um UPDATE para cada jogo)
UPDATE atleta_conflito_db43 x SET x.mexido = 1
 WHERE x.nt_1 IN (SELECT t.b FROM alvo_db43 t WHERE NOT (t.dh_antes <=> t.dh_novo) OR NOT (t.e1_antes <=> t.e1_novo AND t.e2_antes <=> t.e2_novo));
UPDATE atleta_conflito_db43 x SET x.mexido = 1
 WHERE x.nt_2 IN (SELECT t.b FROM alvo_db43 t WHERE NOT (t.dh_antes <=> t.dh_novo) OR NOT (t.e1_antes <=> t.e1_novo AND t.e2_antes <=> t.e2_novo));

SELECT COUNT(*) AS atleta_em_dois_jogos_no_mesmo_horario, COALESCE(SUM(mexido), 0) AS mexido_pelo_db43
  FROM atleta_conflito_db43;
SELECT atleta, escola, DATE_FORMAT(quando, '%d/%m %H:%i') AS quando,
       CONCAT('nº ', nt_1, ' ', comp_1, ' (', COALESCE(local_1, 'sem local'), ')') AS jogo_1,
       CONCAT('nº ', nt_2, ' ', comp_2, ' (', COALESCE(local_2, 'sem local'), ')') AS jogo_2,
       IF(mexido = 1, 'sim', 'não') AS mexido_pelo_db43
  FROM atleta_conflito_db43
 ORDER BY quando, escola, atleta;
DROP TEMPORARY TABLE atleta_conflito_db43;

SELECT DATE_FORMAT(data_hora, '%d/%m') AS dia, SUM(fase = 'GRUPOS') AS grupo, SUM(fase <> 'GRUPOS') AS mata_mata, COUNT(*) AS total
  FROM jogos GROUP BY DATE_FORMAT(data_hora, '%d/%m') ORDER BY dia;

DROP TEMPORARY TABLE comp_db43;
DROP TEMPORARY TABLE alvo_db43;
