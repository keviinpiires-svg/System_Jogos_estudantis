-- =====================================================================
-- MIGRAÇÃO 41 — Tabela de jogos 20268 do chefe (14/11/2026)
--
-- Aplica a TABELA DE JOGOS 20268 sobre a 20267 (estado da produção depois do
-- db/34, db/35 e db/39; ver docs/importacao/contexto_tabela_20268.md, fora do
-- git). A comparação foi feita PELO CONTEÚDO (competição + equipes; no
-- mata-mata, competição + fase + ordem), não pelo número, e está escrita aqui
-- jogo a jogo: o script não lê arquivo nenhum.
--
--   304 jogos (229 de grupo e 75 de mata-mata) viram 300 (227 e 73):
--   112 IGUAIS, 183 ALTERAR (163 só de número e 20 de dia, hora ou local),
--   5 INCLUIR e 9 REMOVER.
--   Por dia, grupo/mata-mata: 18/11 36/0, 19/11 91/0, 20/11 76/9, 21/11 24/64.
--   numero_tabela de 1 a 302, sem o 102 e o 275 (Handebol F Sub 8, ACM x José
--   Dias: estão na tabela do chefe, mas saíram do sistema pelo db/35 e NÃO entram).
--
-- 1) A Emiliano Zapata sai do Baleado Sub 9 F e do Vôlei Sub 17 Misto: saem os
--    jogos dela (167, 272, 114 e 122) e a equipe dela nas duas competições (só
--    se não tiver inscrição, súmula nem colocação).
-- 2) Baleado Sub 9 F: saem as semifinais 218 e 233; o 211 vira o 166 (20/11
--    11:20, Quadra do Maria da Glória); entra o 268 (José Dias x Adelieta, 21/11
--    10:00, Quadra do CETI); GRUPO ÚNICO com 5 equipes; final 278 = 1º colocado
--    x 2º colocado.
-- 3) Baleado Sub 9 M: GRUPO ÚNICO com 5 equipes (jogos 15, 16, 76, 165 e 209);
--    final 277 = 1º colocado x 2º colocado.
-- 4) Vôlei Sub 17 Misto: saem 123, 193 e 170; entram 121 (CEBC x CETI, 19/11
--    14:40, CETI), 122 (Lucia Rocha x CEBN, 19/11 15:20, CETI), 169 (CETI x
--    Lucia Rocha, 20/11 13:20, Maria da Glória) e 192 (CEBN x CEBC, 20/11 08:00,
--    CETI); GRUPO ÚNICO com 4 equipes; final 287 = 1º colocado x 2º colocado.
--    Grupo único nas três = qtd_grupos 1, 2 classificados, próxima fase FINAL;
--    as equipes e os jogos do grupo B passam para o A e o grupo B é apagado.
--    O numero_jogo dessas três competições é renumerado de 1 a N por data e
--    hora (nas outras não muda).
-- 5) Horários e locais da 20268: 19/11 no CETI (115..121 -> 114..120, 40 min
--    mais cedo), 21/11 216/217 -> 214/215 (40 min mais tarde), mata-mata
--    234..240 -> 230..236 (40 min mais cedo) e as finais do Society 304..306 ->
--    300..302, que passam da Quadra do CETI para o Campo Society do CETI (a
--    tabela diz "SOCIETY: CETI" desde a 20267).
-- 6) Renumeração de toda a tabela, mata-mata incluído, em 2 FASES por causa do
--    índice único de numero_tabela (provisório = 10000 + número novo).
-- 7) O rótulo "Vencedor do jogo N" de todas as vagas é regravado com o número
--    novo do jogo de origem (o jogo_origem_id não muda).
--
-- COMO O JOGO É ACHADO: competição (modalidade + categoria + gênero, nunca por
-- id) + fase + par de equipes (em qualquer ordem) + a ocorrência do par na
-- competição, por data e hora; no mata-mata, competição + fase + ordem por data
-- e hora. Cada linha do plano fica APLICAR (como na 20267), FEITO (como na
-- 20268) ou vazia (nenhum dos dois: para o script). Todo jogo do banco tem de
-- cair em exatamente uma linha do plano.
--
-- IDEMPOTENTE: rodado de novo, cai tudo em FEITO e não grava nada.
--
-- SEGURANÇA: uma transação só. Cinco travas (CHECK em tabela temporária, erro
-- 3819 no MySQL e 4025 no MariaDB) param o script sem gravar nada:
--   db41_jogo_nao_bate        (antes de escrever: linha do plano sem estado;
--        jogo do banco fora do plano ou em duas linhas; local fora do cadastro;
--        equipe de jogo novo não achada)
--   db41_estado_misto         (antes de escrever: parte APLICAR e parte FEITO)
--   db41_jogo_ja_mexido       (antes de escrever: jogo que muda ou sai, ou das
--        três competições, com placar, vencedor, cobranças, prorrogação, súmula,
--        set, suspensão ou status diferente de AGENDADO; mata-mata com equipe
--        preenchida pelo automático; vaga de outro jogo vinda de jogo que sai)
--   db41_competicao_nao_bate  (antes de escrever: competição ou grupos não
--        achados; regra diferente da de antes e da de depois; equipe da Emiliano
--        com inscrição, súmula ou colocação)
--   db41_conferencia_divergiu (antes do COMMIT)
-- No cliente mysql o erro encerra a sessão e a transação é desfeita. No
-- DBeaver, se um comando falhar, rode ROLLBACK antes de qualquer outra coisa.
--
-- A final do Basquete F Sub 17 (292 -> 288) tem CEJA x CEBC em vagas MANUAIS
-- (db/34): só muda de número, e a vaga manual não conta como "preenchida".
--
-- Avisos que NÃO abortam (depois do COMMIT, só leitura): ESCOLA em dois jogos
-- no mesmo dia e hora envolvendo jogos que mudam ou entram (equipes e quadras
-- diferentes) e, na tabela inteira, ATLETA inscrito em duas equipes que jogam
-- no mesmo dia e hora (atleta, escola e os dois jogos: numero_tabela,
-- competição, hora e local; marca se um dos jogos foi mexido por este script).
--
-- Só dados. Rode depois do 40. MySQL 8.0.16+ ou MariaDB 10.2+. Faça o dump
-- antes, na produção. Não entra no banco de fumaça. Sem dado de aluno.
-- NÃO repita o db/34 nem o db/39 depois deste.
-- =====================================================================

SET NAMES utf8mb4;

START TRANSACTION;

-- Trava os jogos e as vagas: nada muda no meio do script
SELECT COUNT(*) AS jogos_travados FROM jogos FOR UPDATE;
SELECT COUNT(*) AS vagas_travadas FROM jogo_vagas FOR UPDATE;

-- ---------------------------------------------------------------------
-- O plano: 300 jogos da 20268 (sem o 102 e o 275) e os 9 que saem
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS alvo_db41;
CREATE TEMPORARY TABLE alvo_db41 (
  ordem        INT          NOT NULL PRIMARY KEY,
  acao         VARCHAR(8)   NOT NULL,   -- IGUAL, ALTERAR, INCLUIR ou REMOVER
  a            INT          NULL,       -- numero_tabela na 20267
  b            INT          NULL,       -- numero_tabela na 20268
  modalidade   VARCHAR(60)  NOT NULL,
  categoria    VARCHAR(20)  NOT NULL,
  genero       VARCHAR(10)  NOT NULL,
  fase         VARCHAR(10)  NOT NULL,
  e1           VARCHAR(100) NULL,       -- só na fase de grupos
  e2           VARCHAR(100) NULL,
  occ          INT          NOT NULL,   -- ocorrência do par (ou ordem no mata-mata) na competição
  dh_antes     DATETIME     NULL,
  local_antes  VARCHAR(80)  NULL,
  dh_novo      DATETIME     NULL,
  local_novo   VARCHAR(80)  NULL,
  -- o que foi achado
  comp_id      INT          NULL,
  achados      INT          NOT NULL DEFAULT 0,
  jogo_id      INT          NULL,
  local_novo_id INT         NULL,
  e1_id        INT          NULL,       -- equipes do jogo novo
  e2_id        INT          NULL,
  estado       VARCHAR(10)  NOT NULL DEFAULT ''
);

INSERT INTO alvo_db41 (ordem, acao, a, b, modalidade, categoria, genero, fase, e1, e2, occ, dh_antes, local_antes, dh_novo, local_novo) VALUES
  (  1, 'IGUAL', 1, 1, 'Baleado', 'Sub 11', 'MASCULINO', 'GRUPOS', 'MARIA DA GLORIA', 'FRANCISCO AMORIM', 1, '2026-11-18 14:30:00', 'Ginásio de Esportes', '2026-11-18 14:30:00', 'Ginásio de Esportes'),
  (  2, 'IGUAL', 2, 2, 'Baleado', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Conveniada', 'ADELIETA RAMALHO', 1, '2026-11-18 15:10:00', 'Ginásio de Esportes', '2026-11-18 15:10:00', 'Ginásio de Esportes'),
  (  3, 'IGUAL', 3, 3, 'Baleado', 'Sub 13', 'FEMININO', 'GRUPOS', 'ADELIETA RAMALHO', 'PORTAL DO SABER', 1, '2026-11-18 15:50:00', 'Ginásio de Esportes', '2026-11-18 15:50:00', 'Ginásio de Esportes'),
  (  4, 'IGUAL', 4, 4, 'Handebol', 'Sub 17', 'FEMININO', 'GRUPOS', 'CEBN', 'CEJA', 1, '2026-11-18 16:30:00', 'Ginásio de Esportes', '2026-11-18 16:30:00', 'Ginásio de Esportes'),
  (  5, 'IGUAL', 5, 5, 'Baleado', 'Sub 17', 'MASCULINO', 'GRUPOS', 'CEJA', 'CETI', 1, '2026-11-18 17:10:00', 'Ginásio de Esportes', '2026-11-18 17:10:00', 'Ginásio de Esportes'),
  (  6, 'IGUAL', 6, 6, 'Futsal', 'Aberto', 'MASCULINO', 'GRUPOS', 'CEJA', 'CEBC', 1, '2026-11-18 18:50:00', 'Ginásio de Esportes', '2026-11-18 18:50:00', 'Ginásio de Esportes'),
  (  7, 'IGUAL', 7, 7, 'Futsal', 'Sub 17', 'MASCULINO', 'GRUPOS', 'LUCIA ROCHA', 'VITORIA LIMA', 1, '2026-11-18 18:30:00', 'Ginásio de Esportes', '2026-11-18 18:30:00', 'Ginásio de Esportes'),
  (  8, 'IGUAL', 8, 8, 'Futsal', 'Sub 17', 'MASCULINO', 'GRUPOS', 'CETI', 'CEBC', 1, '2026-11-18 19:20:00', 'Ginásio de Esportes', '2026-11-18 19:20:00', 'Ginásio de Esportes'),
  (  9, 'IGUAL', 9, 9, 'Futsal', 'Aberto', 'MASCULINO', 'GRUPOS', 'CEJA', 'LUCIA ROCHA', 1, '2026-11-18 20:00:00', 'Ginásio de Esportes', '2026-11-18 20:00:00', 'Ginásio de Esportes'),
  ( 10, 'IGUAL', 10, 10, 'Futsal', 'Aberto', 'MASCULINO', 'GRUPOS', 'MANOEL RAMOS', 'VITORIA LIMA', 1, '2026-11-18 20:40:00', 'Ginásio de Esportes', '2026-11-18 20:40:00', 'Ginásio de Esportes'),
  ( 11, 'IGUAL', 11, 11, 'Baleado', 'Sub 11', 'MASCULINO', 'GRUPOS', 'MANOEL RAMOS', 'ADELIETA RAMALHO', 1, '2026-11-18 14:30:00', 'Quadra da Adelieta Ramalho', '2026-11-18 14:30:00', 'Quadra da Adelieta Ramalho'),
  ( 12, 'IGUAL', 12, 12, 'Baleado', 'Sub 13', 'MASCULINO', 'GRUPOS', 'EMILIANO ZAPATA', 'MANOEL RAMOS', 1, '2026-11-18 15:10:00', 'Quadra da Adelieta Ramalho', '2026-11-18 15:10:00', 'Quadra da Adelieta Ramalho'),
  ( 13, 'IGUAL', 13, 13, 'Handebol', 'Sub 11', 'MASCULINO', 'GRUPOS', 'CEBC', 'JOSE DIAS', 1, '2026-11-18 15:50:00', 'Quadra da Adelieta Ramalho', '2026-11-18 15:50:00', 'Quadra da Adelieta Ramalho'),
  ( 14, 'IGUAL', 14, 14, 'Handebol', 'Sub 11', 'MASCULINO', 'GRUPOS', 'CEJA', 'ADELIETA RAMALHO', 1, '2026-11-18 16:30:00', 'Quadra da Adelieta Ramalho', '2026-11-18 16:30:00', 'Quadra da Adelieta Ramalho'),
  ( 15, 'IGUAL', 15, 15, 'Baleado', 'Sub 9', 'MASCULINO', 'GRUPOS', 'ADELIETA RAMALHO', 'MARLENE SANTANA', 1, '2026-11-18 14:20:00', 'Quadra do Maria da Glória', '2026-11-18 14:20:00', 'Quadra do Maria da Glória'),
  ( 16, 'IGUAL', 16, 16, 'Baleado', 'Sub 9', 'MASCULINO', 'GRUPOS', 'TEODULO LEITE', 'MARIA DA GLORIA', 1, '2026-11-18 14:40:00', 'Quadra do Maria da Glória', '2026-11-18 14:40:00', 'Quadra do Maria da Glória'),
  ( 17, 'IGUAL', 17, 17, 'Baleado', 'Sub 13', 'FEMININO', 'GRUPOS', 'CEJA', 'MARIA DA GLORIA', 1, '2026-11-18 15:20:00', 'Quadra do Maria da Glória', '2026-11-18 15:20:00', 'Quadra do Maria da Glória'),
  ( 18, 'IGUAL', 18, 18, 'Baleado', 'Sub 13', 'FEMININO', 'GRUPOS', 'EMILIANO ZAPATA', 'JOSE DIAS', 1, '2026-11-18 15:40:00', 'Quadra do Maria da Glória', '2026-11-18 15:40:00', 'Quadra do Maria da Glória'),
  ( 19, 'IGUAL', 19, 19, 'Baleado', 'Sub 13', 'FEMININO', 'GRUPOS', 'CEBN', 'Conveniada', 1, '2026-11-18 16:00:00', 'Quadra do Maria da Glória', '2026-11-18 16:00:00', 'Quadra do Maria da Glória'),
  ( 20, 'IGUAL', 20, 20, 'Baleado', 'Sub 13', 'MASCULINO', 'GRUPOS', 'JOSENILDO LEITE', 'CEBC', 1, '2026-11-18 16:20:00', 'Quadra do Maria da Glória', '2026-11-18 16:20:00', 'Quadra do Maria da Glória'),
  ( 21, 'IGUAL', 21, 21, 'Handebol', 'Sub 13', 'MASCULINO', 'GRUPOS', 'CEJA', 'CEBC', 1, '2026-11-18 16:40:00', 'Quadra do Maria da Glória', '2026-11-18 16:40:00', 'Quadra do Maria da Glória'),
  ( 22, 'IGUAL', 22, 22, 'Futsal', 'Sub 15', 'MASCULINO', 'GRUPOS', 'CEJA', 'JOSE DIAS', 1, '2026-11-18 14:00:00', 'Quadra do CEJA', '2026-11-18 14:00:00', 'Quadra do CEJA'),
  ( 23, 'IGUAL', 23, 23, 'Futsal', 'Sub 15', 'MASCULINO', 'GRUPOS', 'CEBC', 'MANOEL RAMOS', 1, '2026-11-18 14:40:00', 'Quadra do CEJA', '2026-11-18 14:40:00', 'Quadra do CEJA'),
  ( 24, 'IGUAL', 24, 24, 'Futsal', 'Sub 17', 'MASCULINO', 'GRUPOS', 'CEJA', 'JOSE DIAS', 1, '2026-11-18 15:30:00', 'Quadra do CEJA', '2026-11-18 15:30:00', 'Quadra do CEJA'),
  ( 25, 'IGUAL', 25, 25, 'Futsal', 'Sub 17', 'MASCULINO', 'GRUPOS', 'EMILIANO ZAPATA', 'JOSENILDO LEITE', 1, '2026-11-18 16:10:00', 'Quadra do CEJA', '2026-11-18 16:10:00', 'Quadra do CEJA'),
  ( 26, 'IGUAL', 26, 26, 'Futsal', 'Sub 7', 'MASCULINO', 'GRUPOS', 'JOSE DIAS', 'ACM', 1, '2026-11-18 14:30:00', 'Quadra do CETI', '2026-11-18 14:30:00', 'Quadra do CETI'),
  ( 27, 'IGUAL', 27, 27, 'Futsal', 'Sub 9', 'MASCULINO', 'GRUPOS', 'EMILIANO ZAPATA', 'JOSE DIAS', 1, '2026-11-18 15:10:00', 'Quadra do CETI', '2026-11-18 15:10:00', 'Quadra do CETI'),
  ( 28, 'IGUAL', 28, 28, 'Futsal', 'Sub 9', 'MASCULINO', 'GRUPOS', 'MARLENE SANTANA', 'ADELIETA RAMALHO', 1, '2026-11-18 15:50:00', 'Quadra do CETI', '2026-11-18 15:50:00', 'Quadra do CETI'),
  ( 29, 'IGUAL', 29, 29, 'Futsal', 'Sub 7', 'MASCULINO', 'GRUPOS', 'ADELIETA RAMALHO', 'TEODULO LEITE', 1, '2026-11-18 16:30:00', 'Quadra do CETI', '2026-11-18 16:30:00', 'Quadra do CETI'),
  ( 30, 'IGUAL', 30, 30, 'Futsal', 'Sub 11', 'MASCULINO', 'GRUPOS', 'MARLENE SANTANA', 'CEBC', 1, '2026-11-18 14:30:00', 'Quadra do CEBC', '2026-11-18 14:30:00', 'Quadra do CEBC'),
  ( 31, 'IGUAL', 31, 31, 'Futsal', 'Sub 11', 'MASCULINO', 'GRUPOS', 'JOSENILDO LEITE', 'MARIA DA GLORIA', 1, '2026-11-18 15:10:00', 'Quadra do CEBC', '2026-11-18 15:10:00', 'Quadra do CEBC'),
  ( 32, 'IGUAL', 32, 32, 'Futsal', 'Sub 11', 'MASCULINO', 'GRUPOS', 'EMILIANO ZAPATA', 'PORTAL DO SABER', 1, '2026-11-18 15:50:00', 'Quadra do CEBC', '2026-11-18 15:50:00', 'Quadra do CEBC'),
  ( 33, 'IGUAL', 33, 33, 'Basquete', 'Sub 15', 'FEMININO', 'GRUPOS', 'CEBC', 'CEJA', 1, '2026-11-18 16:30:00', 'Quadra do CEBC', '2026-11-18 16:30:00', 'Quadra do CEBC'),
  ( 34, 'IGUAL', 34, 34, 'Futebol Society', 'Sub 15', 'MASCULINO', 'GRUPOS', 'CEJA', 'JOSE DIAS', 1, '2026-11-18 15:00:00', 'Campo Society Arena Social', '2026-11-18 15:00:00', 'Campo Society Arena Social'),
  ( 35, 'IGUAL', 35, 35, 'Futebol Society', 'Sub 15', 'MASCULINO', 'GRUPOS', 'CEBN', 'CEBC', 1, '2026-11-18 15:40:00', 'Campo Society Arena Social', '2026-11-18 15:40:00', 'Campo Society Arena Social'),
  ( 36, 'IGUAL', 36, 36, 'Futebol Society', 'Sub 17', 'MASCULINO', 'GRUPOS', 'CEBC', 'VITORIA LIMA', 1, '2026-11-18 16:20:00', 'Campo Society Arena Social', '2026-11-18 16:20:00', 'Campo Society Arena Social'),
  ( 37, 'IGUAL', 37, 37, 'Baleado', 'Sub 11', 'MASCULINO', 'GRUPOS', 'FRANCISCO AMORIM', 'EMILIANO ZAPATA', 1, '2026-11-19 08:00:00', 'Ginásio de Esportes', '2026-11-19 08:00:00', 'Ginásio de Esportes'),
  ( 38, 'IGUAL', 38, 38, 'Baleado', 'Sub 11', 'MASCULINO', 'GRUPOS', 'MARLENE SANTANA', 'MANOEL RAMOS', 1, '2026-11-19 08:40:00', 'Ginásio de Esportes', '2026-11-19 08:40:00', 'Ginásio de Esportes'),
  ( 39, 'IGUAL', 39, 39, 'Baleado', 'Sub 13', 'MASCULINO', 'GRUPOS', 'CEBC', 'CEJA', 1, '2026-11-19 09:20:00', 'Ginásio de Esportes', '2026-11-19 09:20:00', 'Ginásio de Esportes'),
  ( 40, 'IGUAL', 40, 40, 'Baleado', 'Sub 13', 'MASCULINO', 'GRUPOS', 'CEBN', 'Conveniada', 1, '2026-11-19 10:00:00', 'Ginásio de Esportes', '2026-11-19 10:00:00', 'Ginásio de Esportes'),
  ( 41, 'IGUAL', 41, 41, 'Futsal', 'Sub 17', 'FEMININO', 'GRUPOS', 'CETI', 'VITORIA LIMA', 1, '2026-11-19 10:40:00', 'Ginásio de Esportes', '2026-11-19 10:40:00', 'Ginásio de Esportes'),
  ( 42, 'IGUAL', 42, 42, 'Futsal', 'Sub 15', 'MASCULINO', 'GRUPOS', 'MANOEL RAMOS', 'EMILIANO ZAPATA', 1, '2026-11-19 11:20:00', 'Ginásio de Esportes', '2026-11-19 11:20:00', 'Ginásio de Esportes'),
  ( 43, 'IGUAL', 43, 43, 'Futsal', 'Sub 15', 'MASCULINO', 'GRUPOS', 'JOSENILDO LEITE', 'Conveniada', 1, '2026-11-19 12:00:00', 'Ginásio de Esportes', '2026-11-19 12:00:00', 'Ginásio de Esportes'),
  ( 44, 'IGUAL', 44, 44, 'Futsal', 'Sub 13', 'MASCULINO', 'GRUPOS', 'CEBC', 'EMILIANO ZAPATA', 1, '2026-11-19 12:40:00', 'Ginásio de Esportes', '2026-11-19 12:40:00', 'Ginásio de Esportes'),
  ( 45, 'IGUAL', 45, 45, 'Futsal', 'Sub 13', 'MASCULINO', 'GRUPOS', 'JOSENILDO LEITE', 'CEJA', 1, '2026-11-19 13:20:00', 'Ginásio de Esportes', '2026-11-19 13:20:00', 'Ginásio de Esportes'),
  ( 46, 'IGUAL', 46, 46, 'Futsal', 'Sub 13', 'MASCULINO', 'GRUPOS', 'CEBN', 'Conveniada', 1, '2026-11-19 14:00:00', 'Ginásio de Esportes', '2026-11-19 14:00:00', 'Ginásio de Esportes'),
  ( 47, 'IGUAL', 47, 47, 'Baleado', 'Sub 11', 'MASCULINO', 'GRUPOS', 'JOSE DIAS', 'ADELIETA RAMALHO', 1, '2026-11-19 14:40:00', 'Ginásio de Esportes', '2026-11-19 14:40:00', 'Ginásio de Esportes'),
  ( 48, 'IGUAL', 48, 48, 'Baleado', 'Sub 13', 'MASCULINO', 'GRUPOS', 'CEJA', 'JOSENILDO LEITE', 1, '2026-11-19 15:20:00', 'Ginásio de Esportes', '2026-11-19 15:20:00', 'Ginásio de Esportes'),
  ( 49, 'IGUAL', 49, 49, 'Baleado', 'Sub 17', 'FEMININO', 'GRUPOS', 'CETI', 'CEJA', 1, '2026-11-19 16:00:00', 'Ginásio de Esportes', '2026-11-19 16:00:00', 'Ginásio de Esportes'),
  ( 50, 'IGUAL', 50, 50, 'Handebol', 'Aberto', 'MASCULINO', 'GRUPOS', 'CETI', 'CEJA', 1, '2026-11-19 16:40:00', 'Ginásio de Esportes', '2026-11-19 16:40:00', 'Ginásio de Esportes'),
  ( 51, 'IGUAL', 51, 51, 'Baleado', 'Sub 13', 'MASCULINO', 'GRUPOS', 'ADELIETA RAMALHO', 'CEBN', 1, '2026-11-19 17:20:00', 'Ginásio de Esportes', '2026-11-19 17:20:00', 'Ginásio de Esportes'),
  ( 52, 'IGUAL', 52, 52, 'Futsal', 'Aberto', 'MASCULINO', 'GRUPOS', 'CETI', 'VITORIA LIMA', 1, '2026-11-19 18:00:00', 'Ginásio de Esportes', '2026-11-19 18:00:00', 'Ginásio de Esportes'),
  ( 53, 'IGUAL', 53, 53, 'Futsal', 'Aberto', 'FEMININO', 'GRUPOS', 'LUCIA ROCHA', 'CETI', 1, '2026-11-19 18:40:00', 'Ginásio de Esportes', '2026-11-19 18:40:00', 'Ginásio de Esportes'),
  ( 54, 'IGUAL', 54, 54, 'Futsal', 'Sub 17', 'MASCULINO', 'GRUPOS', 'JOSE DIAS', 'JOSENILDO LEITE', 1, '2026-11-19 19:20:00', 'Ginásio de Esportes', '2026-11-19 19:20:00', 'Ginásio de Esportes'),
  ( 55, 'IGUAL', 55, 55, 'Futsal', 'Aberto', 'MASCULINO', 'GRUPOS', 'CETI', 'MANOEL RAMOS', 1, '2026-11-19 20:00:00', 'Ginásio de Esportes', '2026-11-19 20:00:00', 'Ginásio de Esportes'),
  ( 56, 'IGUAL', 56, 56, 'Futsal', 'Aberto', 'MASCULINO', 'GRUPOS', 'LUCIA ROCHA', 'CEBC', 1, '2026-11-19 20:40:00', 'Ginásio de Esportes', '2026-11-19 20:40:00', 'Ginásio de Esportes'),
  ( 57, 'IGUAL', 57, 57, 'Baleado', 'Sub 13', 'FEMININO', 'GRUPOS', 'CEBN', 'ADELIETA RAMALHO', 1, '2026-11-19 08:00:00', 'Quadra da Adelieta Ramalho', '2026-11-19 08:00:00', 'Quadra da Adelieta Ramalho'),
  ( 58, 'IGUAL', 58, 58, 'Baleado', 'Sub 13', 'FEMININO', 'GRUPOS', 'CEBC', 'EMILIANO ZAPATA', 1, '2026-11-19 08:40:00', 'Quadra da Adelieta Ramalho', '2026-11-19 08:40:00', 'Quadra da Adelieta Ramalho'),
  ( 59, 'IGUAL', 59, 59, 'Baleado', 'Sub 13', 'FEMININO', 'GRUPOS', 'CEJA', 'MANOEL RAMOS', 1, '2026-11-19 09:20:00', 'Quadra da Adelieta Ramalho', '2026-11-19 09:20:00', 'Quadra da Adelieta Ramalho'),
  ( 60, 'IGUAL', 60, 60, 'Handebol', 'Sub 11', 'MASCULINO', 'GRUPOS', 'JOSE DIAS', 'FRANCISCO AMORIM', 1, '2026-11-19 10:00:00', 'Quadra da Adelieta Ramalho', '2026-11-19 10:00:00', 'Quadra da Adelieta Ramalho'),
  ( 61, 'IGUAL', 61, 61, 'Handebol', 'Sub 11', 'MASCULINO', 'GRUPOS', 'ADELIETA RAMALHO', 'MARIA DA GLORIA', 1, '2026-11-19 10:40:00', 'Quadra da Adelieta Ramalho', '2026-11-19 10:40:00', 'Quadra da Adelieta Ramalho'),
  ( 62, 'IGUAL', 62, 62, 'Futsal', 'Sub 13', 'FEMININO', 'GRUPOS', 'CEJA', 'CEBN', 1, '2026-11-19 11:20:00', 'Quadra da Adelieta Ramalho', '2026-11-19 11:20:00', 'Quadra da Adelieta Ramalho'),
  ( 63, 'IGUAL', 63, 63, 'Futsal', 'Sub 15', 'FEMININO', 'GRUPOS', 'CEBN', 'EMILIANO ZAPATA', 1, '2026-11-19 12:00:00', 'Quadra da Adelieta Ramalho', '2026-11-19 12:00:00', 'Quadra da Adelieta Ramalho'),
  ( 64, 'IGUAL', 64, 64, 'Futsal', 'Sub 15', 'FEMININO', 'GRUPOS', 'CEBC', 'Conveniada', 1, '2026-11-19 12:40:00', 'Quadra da Adelieta Ramalho', '2026-11-19 12:40:00', 'Quadra da Adelieta Ramalho'),
  ( 65, 'IGUAL', 65, 65, 'Futsal', 'Sub 11', 'MASCULINO', 'GRUPOS', 'FRANCISCO AMORIM', 'MARIA DA GLORIA', 1, '2026-11-19 13:20:00', 'Quadra da Adelieta Ramalho', '2026-11-19 13:20:00', 'Quadra da Adelieta Ramalho'),
  ( 66, 'IGUAL', 66, 66, 'Handebol', 'Sub 13', 'MASCULINO', 'GRUPOS', 'CEBN', 'Conveniada', 1, '2026-11-19 14:00:00', 'Quadra da Adelieta Ramalho', '2026-11-19 14:00:00', 'Quadra da Adelieta Ramalho'),
  ( 67, 'IGUAL', 67, 67, 'Handebol', 'Sub 11', 'FEMININO', 'GRUPOS', 'FRANCISCO AMORIM', 'MARIA DA GLORIA', 1, '2026-11-19 14:40:00', 'Quadra da Adelieta Ramalho', '2026-11-19 14:40:00', 'Quadra da Adelieta Ramalho'),
  ( 68, 'IGUAL', 68, 68, 'Handebol', 'Sub 11', 'FEMININO', 'GRUPOS', 'JOSE DIAS', 'MARLENE SANTANA', 1, '2026-11-19 15:20:00', 'Quadra da Adelieta Ramalho', '2026-11-19 15:20:00', 'Quadra da Adelieta Ramalho'),
  ( 69, 'IGUAL', 69, 69, 'Handebol', 'Sub 8', 'MASCULINO', 'GRUPOS', 'ACM', 'ADELIETA RAMALHO', 1, '2026-11-19 16:00:00', 'Quadra da Adelieta Ramalho', '2026-11-19 16:00:00', 'Quadra da Adelieta Ramalho'),
  ( 70, 'IGUAL', 70, 70, 'Futsal', 'Sub 9', 'MASCULINO', 'GRUPOS', 'MARIA DA GLORIA', 'TEODULO LEITE', 1, '2026-11-19 08:00:00', 'Quadra do Maria da Glória', '2026-11-19 08:00:00', 'Quadra do Maria da Glória'),
  ( 71, 'IGUAL', 71, 71, 'Futsal', 'Sub 9', 'MASCULINO', 'GRUPOS', 'MARLENE SANTANA', 'PORTAL DO SABER', 1, '2026-11-19 08:40:00', 'Quadra do Maria da Glória', '2026-11-19 08:40:00', 'Quadra do Maria da Glória'),
  ( 72, 'IGUAL', 72, 72, 'Baleado', 'Sub 17', 'MASCULINO', 'GRUPOS', 'CEBC', 'JOSENILDO LEITE', 1, '2026-11-19 09:20:00', 'Quadra do Maria da Glória', '2026-11-19 09:20:00', 'Quadra do Maria da Glória'),
  ( 73, 'IGUAL', 73, 73, 'Baleado', 'Sub 13', 'MASCULINO', 'GRUPOS', 'MARIA DA GLORIA', 'EMILIANO ZAPATA', 1, '2026-11-19 10:00:00', 'Quadra do Maria da Glória', '2026-11-19 10:00:00', 'Quadra do Maria da Glória'),
  ( 74, 'IGUAL', 74, 74, 'Baleado', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Conveniada', 'MANOEL RAMOS', 1, '2026-11-19 10:40:00', 'Quadra do Maria da Glória', '2026-11-19 10:40:00', 'Quadra do Maria da Glória'),
  ( 75, 'IGUAL', 75, 75, 'Baleado', 'Sub 15', 'MASCULINO', 'GRUPOS', 'CEBC', 'CEBN', 1, '2026-11-19 11:20:00', 'Quadra do Maria da Glória', '2026-11-19 11:20:00', 'Quadra do Maria da Glória'),
  ( 76, 'IGUAL', 76, 76, 'Baleado', 'Sub 9', 'MASCULINO', 'GRUPOS', 'MARIA DA GLORIA', 'FRANCISCO AMORIM', 1, '2026-11-19 12:00:00', 'Quadra do Maria da Glória', '2026-11-19 12:00:00', 'Quadra do Maria da Glória'),
  ( 77, 'IGUAL', 77, 77, 'Futsal', 'Sub 17', 'FEMININO', 'GRUPOS', 'CEBC', 'CEJA', 1, '2026-11-19 12:40:00', 'Quadra do Maria da Glória', '2026-11-19 12:40:00', 'Quadra do Maria da Glória'),
  ( 78, 'IGUAL', 78, 78, 'Futsal', 'Sub 13', 'FEMININO', 'GRUPOS', 'EMILIANO ZAPATA', 'CEJA', 1, '2026-11-19 13:20:00', 'Quadra do Maria da Glória', '2026-11-19 13:20:00', 'Quadra do Maria da Glória'),
  ( 79, 'IGUAL', 79, 79, 'Futsal', 'Sub 9', 'MASCULINO', 'GRUPOS', 'JOSE DIAS', 'MARIA DA GLORIA', 1, '2026-11-19 14:00:00', 'Quadra do Maria da Glória', '2026-11-19 14:00:00', 'Quadra do Maria da Glória'),
  ( 80, 'IGUAL', 80, 80, 'Futsal', 'Sub 9', 'MASCULINO', 'GRUPOS', 'FRANCISCO AMORIM', 'PORTAL DO SABER', 1, '2026-11-19 14:40:00', 'Quadra do Maria da Glória', '2026-11-19 14:40:00', 'Quadra do Maria da Glória'),
  ( 81, 'IGUAL', 81, 81, 'Baleado', 'Sub 13', 'FEMININO', 'GRUPOS', 'MARIA DA GLORIA', 'MANOEL RAMOS', 1, '2026-11-19 15:20:00', 'Quadra do Maria da Glória', '2026-11-19 15:20:00', 'Quadra do Maria da Glória'),
  ( 82, 'IGUAL', 82, 82, 'Baleado', 'Sub 13', 'FEMININO', 'GRUPOS', 'JOSE DIAS', 'CEBC', 1, '2026-11-19 16:00:00', 'Quadra do Maria da Glória', '2026-11-19 16:00:00', 'Quadra do Maria da Glória'),
  ( 83, 'IGUAL', 83, 83, 'Baleado', 'Sub 13', 'FEMININO', 'GRUPOS', 'PORTAL DO SABER', 'Conveniada', 1, '2026-11-19 16:40:00', 'Quadra do Maria da Glória', '2026-11-19 16:40:00', 'Quadra do Maria da Glória'),
  ( 84, 'IGUAL', 84, 84, 'Futsal', 'Sub 11', 'MASCULINO', 'GRUPOS', 'ADELIETA RAMALHO', 'CEJA', 1, '2026-11-19 08:00:00', 'Quadra do CEJA', '2026-11-19 08:00:00', 'Quadra do CEJA'),
  ( 85, 'IGUAL', 85, 85, 'Futsal', 'Sub 11', 'MASCULINO', 'GRUPOS', 'JOSE DIAS', 'MARLENE SANTANA', 1, '2026-11-19 08:40:00', 'Quadra do CEJA', '2026-11-19 08:40:00', 'Quadra do CEJA'),
  ( 86, 'IGUAL', 86, 86, 'Futsal', 'Sub 17', 'MASCULINO', 'GRUPOS', 'EMILIANO ZAPATA', 'CEJA', 1, '2026-11-19 09:20:00', 'Quadra do CEJA', '2026-11-19 09:20:00', 'Quadra do CEJA'),
  ( 87, 'IGUAL', 87, 87, 'Baleado', 'Sub 11', 'FEMININO', 'GRUPOS', 'JOSE DIAS', 'CEJA', 1, '2026-11-19 10:00:00', 'Quadra do CEJA', '2026-11-19 10:00:00', 'Quadra do CEJA'),
  ( 88, 'IGUAL', 88, 88, 'Futsal', 'Sub 17', 'MASCULINO', 'GRUPOS', 'VITORIA LIMA', 'CETI', 1, '2026-11-19 10:40:00', 'Quadra do CEJA', '2026-11-19 10:40:00', 'Quadra do CEJA'),
  ( 89, 'IGUAL', 89, 89, 'Futsal', 'Sub 17', 'MASCULINO', 'GRUPOS', 'LUCIA ROCHA', 'CEBC', 1, '2026-11-19 11:20:00', 'Quadra do CEJA', '2026-11-19 11:20:00', 'Quadra do CEJA'),
  ( 90, 'IGUAL', 90, 90, 'Baleado', 'Sub 15', 'FEMININO', 'GRUPOS', 'Conveniada', 'EMILIANO ZAPATA', 1, '2026-11-19 12:00:00', 'Quadra do CEJA', '2026-11-19 12:00:00', 'Quadra do CEJA'),
  ( 91, 'IGUAL', 91, 91, 'Baleado', 'Sub 15', 'FEMININO', 'GRUPOS', 'CEBN', 'JOSENILDO LEITE', 1, '2026-11-19 12:40:00', 'Quadra do CEJA', '2026-11-19 12:40:00', 'Quadra do CEJA'),
  ( 92, 'IGUAL', 92, 92, 'Baleado', 'Sub 11', 'FEMININO', 'GRUPOS', 'PORTAL DO SABER', 'ADELIETA RAMALHO', 1, '2026-11-19 13:20:00', 'Quadra do CEJA', '2026-11-19 13:20:00', 'Quadra do CEJA'),
  ( 93, 'IGUAL', 93, 93, 'Baleado', 'Sub 11', 'FEMININO', 'GRUPOS', 'JOSENILDO LEITE', 'FRANCISCO AMORIM', 1, '2026-11-19 14:00:00', 'Quadra do CEJA', '2026-11-19 14:00:00', 'Quadra do CEJA'),
  ( 94, 'IGUAL', 94, 94, 'Baleado', 'Sub 11', 'FEMININO', 'GRUPOS', 'EMILIANO ZAPATA', 'MARIA DA GLORIA', 1, '2026-11-19 14:40:00', 'Quadra do CEJA', '2026-11-19 14:40:00', 'Quadra do CEJA'),
  ( 95, 'IGUAL', 95, 95, 'Handebol', 'Sub 13', 'MASCULINO', 'GRUPOS', 'CEBC', 'ADELIETA RAMALHO', 1, '2026-11-19 15:20:00', 'Quadra do CEJA', '2026-11-19 15:20:00', 'Quadra do CEJA'),
  ( 96, 'IGUAL', 96, 96, 'Handebol', 'Sub 15', 'MASCULINO', 'GRUPOS', 'CEJA', 'CEBN', 1, '2026-11-19 16:00:00', 'Quadra do CEJA', '2026-11-19 16:00:00', 'Quadra do CEJA'),
  ( 97, 'IGUAL', 97, 97, 'Handebol', 'Sub 17', 'FEMININO', 'GRUPOS', 'CETI', 'CEBN', 1, '2026-11-19 08:00:00', 'Quadra do CEBC', '2026-11-19 08:00:00', 'Quadra do CEBC'),
  ( 98, 'IGUAL', 98, 98, 'Handebol', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Conveniada', 'JOSE DIAS', 1, '2026-11-19 08:40:00', 'Quadra do CEBC', '2026-11-19 08:40:00', 'Quadra do CEBC'),
  ( 99, 'IGUAL', 99, 99, 'Handebol', 'Sub 9', 'FEMININO', 'GRUPOS', 'ADELIETA RAMALHO', 'FRANCISCO AMORIM', 1, '2026-11-19 09:20:00', 'Quadra do CEBC', '2026-11-19 09:20:00', 'Quadra do CEBC'),
  (100, 'IGUAL', 100, 100, 'Futsal', 'Sub 15', 'MASCULINO', 'GRUPOS', 'JOSE DIAS', 'JOSENILDO LEITE', 1, '2026-11-19 10:00:00', 'Quadra do CEBC', '2026-11-19 10:00:00', 'Quadra do CEBC'),
  (101, 'IGUAL', 101, 101, 'Basquete', 'Sub 15', 'FEMININO', 'GRUPOS', 'Conveniada', 'CEBC', 1, '2026-11-19 10:40:00', 'Quadra do CEBC', '2026-11-19 10:40:00', 'Quadra do CEBC'),
  (102, 'IGUAL', 103, 103, 'Basquete', 'Sub 15', 'MASCULINO', 'GRUPOS', 'CEJA', 'Conveniada', 1, '2026-11-19 12:00:00', 'Quadra do CEBC', '2026-11-19 12:00:00', 'Quadra do CEBC'),
  (103, 'IGUAL', 104, 104, 'Basquete', 'Sub 17', 'MASCULINO', 'GRUPOS', 'CETI', 'CEBC', 1, '2026-11-19 12:40:00', 'Quadra do CEBC', '2026-11-19 12:40:00', 'Quadra do CEBC'),
  (104, 'IGUAL', 105, 105, 'Futsal', 'Sub 11', 'MASCULINO', 'GRUPOS', 'CEJA', 'EMILIANO ZAPATA', 1, '2026-11-19 13:20:00', 'Quadra do CEBC', '2026-11-19 13:20:00', 'Quadra do CEBC'),
  (105, 'IGUAL', 106, 106, 'Futsal', 'Sub 11', 'MASCULINO', 'GRUPOS', 'CEBC', 'JOSE DIAS', 1, '2026-11-19 14:00:00', 'Quadra do CEBC', '2026-11-19 14:00:00', 'Quadra do CEBC'),
  (106, 'IGUAL', 107, 107, 'Handebol', 'Sub 17', 'MASCULINO', 'GRUPOS', 'CETI', 'CEBC', 1, '2026-11-19 14:40:00', 'Quadra do CEBC', '2026-11-19 14:40:00', 'Quadra do CEBC'),
  (107, 'IGUAL', 108, 108, 'Handebol', 'Sub 17', 'MASCULINO', 'GRUPOS', 'CEJA', 'Conveniada', 1, '2026-11-19 15:20:00', 'Quadra do CEBC', '2026-11-19 15:20:00', 'Quadra do CEBC'),
  (108, 'IGUAL', 109, 109, 'Handebol', 'Sub 13', 'FEMININO', 'GRUPOS', 'CEBC', 'CEBN', 1, '2026-11-19 16:00:00', 'Quadra do CEBC', '2026-11-19 16:00:00', 'Quadra do CEBC'),
  (109, 'IGUAL', 110, 110, 'Basquete', 'Sub 17', 'MASCULINO', 'GRUPOS', 'CEBC', 'CEJA', 1, '2026-11-19 16:40:00', 'Quadra do CEBC', '2026-11-19 16:40:00', 'Quadra do CEBC'),
  (110, 'IGUAL', 111, 111, 'Futsal', 'Sub 9', 'FEMININO', 'GRUPOS', 'MARLENE SANTANA', 'JOSE DIAS', 1, '2026-11-19 08:00:00', 'Quadra do CETI', '2026-11-19 08:00:00', 'Quadra do CETI'),
  (111, 'IGUAL', 112, 112, 'Futsal', 'Sub 7', 'MASCULINO', 'GRUPOS', 'JOSE DIAS', 'ADELIETA RAMALHO', 1, '2026-11-19 08:40:00', 'Quadra do CETI', '2026-11-19 08:40:00', 'Quadra do CETI'),
  (112, 'IGUAL', 113, 113, 'Futsal', 'Sub 7', 'MASCULINO', 'GRUPOS', 'TEODULO LEITE', 'ACM', 1, '2026-11-19 09:20:00', 'Quadra do CETI', '2026-11-19 09:20:00', 'Quadra do CETI'),
  (113, 'ALTERAR', 115, 114, 'Vôlei', 'Aberto', 'MISTO', 'GRUPOS', 'CETI', 'CEBC', 1, '2026-11-19 10:40:00', 'Quadra do CETI', '2026-11-19 10:00:00', 'Quadra do CETI'),
  (114, 'ALTERAR', 116, 115, 'Vôlei', 'Sub 15', 'MISTO', 'GRUPOS', 'EMILIANO ZAPATA', 'CEBC', 1, '2026-11-19 11:20:00', 'Quadra do CETI', '2026-11-19 10:40:00', 'Quadra do CETI'),
  (115, 'ALTERAR', 117, 116, 'Futsal', 'Sub 8', 'MASCULINO', 'GRUPOS', 'ADELIETA RAMALHO', 'JOSE DIAS', 1, '2026-11-19 12:00:00', 'Quadra do CETI', '2026-11-19 11:20:00', 'Quadra do CETI'),
  (116, 'ALTERAR', 118, 117, 'Futsal', 'Sub 8', 'MASCULINO', 'GRUPOS', 'TEODULO LEITE', 'MARLENE SANTANA', 1, '2026-11-19 12:40:00', 'Quadra do CETI', '2026-11-19 12:00:00', 'Quadra do CETI'),
  (117, 'ALTERAR', 119, 118, 'Futsal', 'Sub 8', 'FEMININO', 'GRUPOS', 'JOSE DIAS', 'EMILIANO ZAPATA', 1, '2026-11-19 13:20:00', 'Quadra do CETI', '2026-11-19 12:40:00', 'Quadra do CETI'),
  (118, 'ALTERAR', 120, 119, 'Futsal', 'Sub 11', 'FEMININO', 'GRUPOS', 'JOSE DIAS', 'MARLENE SANTANA', 1, '2026-11-19 14:00:00', 'Quadra do CETI', '2026-11-19 13:20:00', 'Quadra do CETI'),
  (119, 'ALTERAR', 121, 120, 'Vôlei', 'Sub 15', 'MISTO', 'GRUPOS', 'CEJA', 'CEBN', 1, '2026-11-19 14:40:00', 'Quadra do CETI', '2026-11-19 14:00:00', 'Quadra do CETI'),
  (120, 'INCLUIR', NULL, 121, 'Vôlei', 'Sub 17', 'MISTO', 'GRUPOS', 'CEBC', 'CETI', 1, NULL, NULL, '2026-11-19 14:40:00', 'Quadra do CETI'),
  (121, 'INCLUIR', NULL, 122, 'Vôlei', 'Sub 17', 'MISTO', 'GRUPOS', 'LUCIA ROCHA', 'CEBN', 1, NULL, NULL, '2026-11-19 15:20:00', 'Quadra do CETI'),
  (122, 'ALTERAR', 124, 123, 'Futebol Society', 'Sub 13', 'MASCULINO', 'GRUPOS', 'CEJA', 'CEBC', 1, '2026-11-19 08:30:00', 'Campo Society Arena Social', '2026-11-19 08:30:00', 'Campo Society Arena Social'),
  (123, 'ALTERAR', 125, 124, 'Futebol Society', 'Sub 17', 'MASCULINO', 'GRUPOS', 'CETI', 'CEBC', 1, '2026-11-19 09:10:00', 'Campo Society Arena Social', '2026-11-19 09:10:00', 'Campo Society Arena Social'),
  (124, 'ALTERAR', 126, 125, 'Futebol Society', 'Sub 15', 'MASCULINO', 'GRUPOS', 'JOSE DIAS', 'Conveniada', 1, '2026-11-19 09:50:00', 'Campo Society Arena Social', '2026-11-19 09:50:00', 'Campo Society Arena Social'),
  (125, 'ALTERAR', 127, 126, 'Futebol Society', 'Sub 15', 'MASCULINO', 'GRUPOS', 'CEBC', 'CEBN', 2, '2026-11-19 14:00:00', 'Campo Society Arena Social', '2026-11-19 14:00:00', 'Campo Society Arena Social'),
  (126, 'ALTERAR', 128, 127, 'Futebol Society', 'Sub 13', 'MASCULINO', 'GRUPOS', 'MARIA DA GLORIA', 'CEBN', 1, '2026-11-19 14:40:00', 'Campo Society Arena Social', '2026-11-19 14:40:00', 'Campo Society Arena Social'),
  (127, 'ALTERAR', 129, 128, 'Futebol Society', 'Sub 17', 'MASCULINO', 'GRUPOS', 'CEJA', 'VITORIA LIMA', 1, '2026-11-19 15:20:00', 'Campo Society Arena Social', '2026-11-19 15:20:00', 'Campo Society Arena Social'),
  (128, 'ALTERAR', 130, 129, 'Baleado', 'Sub 11', 'MASCULINO', 'GRUPOS', 'EMILIANO ZAPATA', 'MARIA DA GLORIA', 1, '2026-11-20 08:00:00', 'Ginásio de Esportes', '2026-11-20 08:00:00', 'Ginásio de Esportes'),
  (129, 'ALTERAR', 131, 130, 'Baleado', 'Sub 11', 'MASCULINO', 'GRUPOS', 'JOSE DIAS', 'MARLENE SANTANA', 1, '2026-11-20 08:40:00', 'Ginásio de Esportes', '2026-11-20 08:40:00', 'Ginásio de Esportes'),
  (130, 'ALTERAR', 132, 131, 'Handebol', 'Sub 11', 'MASCULINO', 'GRUPOS', 'CEJA', 'MARIA DA GLORIA', 1, '2026-11-20 09:20:00', 'Ginásio de Esportes', '2026-11-20 09:20:00', 'Ginásio de Esportes'),
  (131, 'ALTERAR', 133, 132, 'Handebol', 'Sub 11', 'MASCULINO', 'GRUPOS', 'CEBC', 'FRANCISCO AMORIM', 1, '2026-11-20 10:00:00', 'Ginásio de Esportes', '2026-11-20 10:00:00', 'Ginásio de Esportes'),
  (132, 'ALTERAR', 134, 133, 'Futsal', 'Sub 13', 'MASCULINO', 'GRUPOS', 'EMILIANO ZAPATA', 'JOSENILDO LEITE', 1, '2026-11-20 10:40:00', 'Ginásio de Esportes', '2026-11-20 10:40:00', 'Ginásio de Esportes'),
  (133, 'ALTERAR', 135, 134, 'Futsal', 'Sub 13', 'MASCULINO', 'GRUPOS', 'CEBN', 'JOSE DIAS', 1, '2026-11-20 11:20:00', 'Ginásio de Esportes', '2026-11-20 11:20:00', 'Ginásio de Esportes'),
  (134, 'ALTERAR', 136, 135, 'Futsal', 'Sub 17', 'FEMININO', 'GRUPOS', 'CETI', 'CEJA', 1, '2026-11-20 12:00:00', 'Ginásio de Esportes', '2026-11-20 12:00:00', 'Ginásio de Esportes'),
  (135, 'ALTERAR', 137, 136, 'Futsal', 'Sub 17', 'FEMININO', 'GRUPOS', 'CEBC', 'VITORIA LIMA', 1, '2026-11-20 12:40:00', 'Ginásio de Esportes', '2026-11-20 12:40:00', 'Ginásio de Esportes'),
  (136, 'ALTERAR', 138, 137, 'Baleado', 'Sub 13', 'MASCULINO', 'GRUPOS', 'CEBC', 'JOSENILDO LEITE', 2, '2026-11-20 13:20:00', 'Ginásio de Esportes', '2026-11-20 13:20:00', 'Ginásio de Esportes'),
  (137, 'ALTERAR', 139, 138, 'Handebol', 'Aberto', 'MASCULINO', 'GRUPOS', 'CETI', 'LUCIA ROCHA', 1, '2026-11-20 14:40:00', 'Ginásio de Esportes', '2026-11-20 14:40:00', 'Ginásio de Esportes'),
  (138, 'ALTERAR', 140, 139, 'Baleado', 'Sub 15', 'FEMININO', 'GRUPOS', 'CEJA', 'Conveniada', 1, '2026-11-20 15:20:00', 'Ginásio de Esportes', '2026-11-20 15:20:00', 'Ginásio de Esportes'),
  (139, 'ALTERAR', 141, 140, 'Baleado', 'Sub 15', 'FEMININO', 'GRUPOS', 'CEBN', 'CEBC', 1, '2026-11-20 16:00:00', 'Ginásio de Esportes', '2026-11-20 16:00:00', 'Ginásio de Esportes'),
  (140, 'ALTERAR', 142, 141, 'Handebol', 'Sub 17', 'MASCULINO', 'GRUPOS', 'Conveniada', 'CEBN', 1, '2026-11-20 16:40:00', 'Ginásio de Esportes', '2026-11-20 16:40:00', 'Ginásio de Esportes'),
  (141, 'ALTERAR', 143, 142, 'Handebol', 'Sub 17', 'MASCULINO', 'GRUPOS', 'CEBC', 'CETI', 2, '2026-11-20 17:20:00', 'Ginásio de Esportes', '2026-11-20 17:20:00', 'Ginásio de Esportes'),
  (142, 'ALTERAR', 144, 143, 'Futsal', 'Aberto', 'FEMININO', 'GRUPOS', 'VITORIA LIMA', 'CETI', 1, '2026-11-20 18:00:00', 'Ginásio de Esportes', '2026-11-20 18:00:00', 'Ginásio de Esportes'),
  (143, 'ALTERAR', 145, 144, 'Futsal', 'Sub 17', 'MASCULINO', 'SEMIFINAL', NULL, NULL, 1, '2026-11-20 18:40:00', 'Ginásio de Esportes', '2026-11-20 18:40:00', 'Ginásio de Esportes'),
  (144, 'ALTERAR', 146, 145, 'Futsal', 'Sub 17', 'MASCULINO', 'SEMIFINAL', NULL, NULL, 2, '2026-11-20 19:20:00', 'Ginásio de Esportes', '2026-11-20 19:20:00', 'Ginásio de Esportes'),
  (145, 'ALTERAR', 147, 146, 'Futsal', 'Aberto', 'MASCULINO', 'SEMIFINAL', NULL, NULL, 1, '2026-11-20 20:00:00', 'Ginásio de Esportes', '2026-11-20 20:00:00', 'Ginásio de Esportes'),
  (146, 'ALTERAR', 148, 147, 'Futsal', 'Aberto', 'MASCULINO', 'SEMIFINAL', NULL, NULL, 2, '2026-11-20 20:40:00', 'Ginásio de Esportes', '2026-11-20 20:40:00', 'Ginásio de Esportes'),
  (147, 'ALTERAR', 149, 148, 'Handebol', 'Sub 11', 'FEMININO', 'GRUPOS', 'MARLENE SANTANA', 'ADELIETA RAMALHO', 1, '2026-11-20 08:00:00', 'Quadra da Adelieta Ramalho', '2026-11-20 08:00:00', 'Quadra da Adelieta Ramalho'),
  (148, 'ALTERAR', 150, 149, 'Futsal', 'Sub 11', 'MASCULINO', 'GRUPOS', 'FRANCISCO AMORIM', 'JOSENILDO LEITE', 1, '2026-11-20 08:40:00', 'Quadra da Adelieta Ramalho', '2026-11-20 08:40:00', 'Quadra da Adelieta Ramalho'),
  (149, 'ALTERAR', 151, 150, 'Futsal', 'Sub 9', 'MASCULINO', 'GRUPOS', 'EMILIANO ZAPATA', 'TEODULO LEITE', 1, '2026-11-20 09:20:00', 'Quadra da Adelieta Ramalho', '2026-11-20 09:20:00', 'Quadra da Adelieta Ramalho'),
  (150, 'ALTERAR', 152, 151, 'Futsal', 'Sub 9', 'MASCULINO', 'GRUPOS', 'FRANCISCO AMORIM', 'ADELIETA RAMALHO', 1, '2026-11-20 10:00:00', 'Quadra da Adelieta Ramalho', '2026-11-20 10:00:00', 'Quadra da Adelieta Ramalho'),
  (151, 'ALTERAR', 153, 152, 'Futsal', 'Sub 11', 'MASCULINO', 'GRUPOS', 'ADELIETA RAMALHO', 'PORTAL DO SABER', 1, '2026-11-20 10:40:00', 'Quadra da Adelieta Ramalho', '2026-11-20 10:40:00', 'Quadra da Adelieta Ramalho'),
  (152, 'ALTERAR', 154, 153, 'Futsal', 'Sub 13', 'FEMININO', 'GRUPOS', 'CEBN', 'EMILIANO ZAPATA', 1, '2026-11-20 11:20:00', 'Quadra da Adelieta Ramalho', '2026-11-20 11:20:00', 'Quadra da Adelieta Ramalho'),
  (153, 'ALTERAR', 155, 154, 'Handebol', 'Sub 8', 'MASCULINO', 'GRUPOS', 'ADELIETA RAMALHO', 'JOSE DIAS', 1, '2026-11-20 12:00:00', 'Quadra da Adelieta Ramalho', '2026-11-20 12:00:00', 'Quadra da Adelieta Ramalho'),
  (154, 'ALTERAR', 156, 155, 'Handebol', 'Sub 13', 'MASCULINO', 'GRUPOS', 'ADELIETA RAMALHO', 'CEJA', 1, '2026-11-20 12:40:00', 'Quadra da Adelieta Ramalho', '2026-11-20 12:40:00', 'Quadra da Adelieta Ramalho'),
  (155, 'ALTERAR', 157, 156, 'Baleado', 'Sub 13', 'MASCULINO', 'GRUPOS', 'MANOEL RAMOS', 'MARIA DA GLORIA', 1, '2026-11-20 13:20:00', 'Quadra da Adelieta Ramalho', '2026-11-20 13:20:00', 'Quadra da Adelieta Ramalho'),
  (156, 'ALTERAR', 158, 157, 'Handebol', 'Sub 11', 'MASCULINO', 'GRUPOS', 'FRANCISCO AMORIM', 'CEBC', 2, '2026-11-20 14:00:00', 'Quadra da Adelieta Ramalho', '2026-11-20 14:00:00', 'Quadra da Adelieta Ramalho'),
  (157, 'ALTERAR', 159, 158, 'Handebol', 'Sub 11', 'FEMININO', 'GRUPOS', 'MARIA DA GLORIA', 'CEJA', 1, '2026-11-20 14:40:00', 'Quadra da Adelieta Ramalho', '2026-11-20 14:40:00', 'Quadra da Adelieta Ramalho'),
  (158, 'ALTERAR', 160, 159, 'Handebol', 'Sub 15', 'FEMININO', 'GRUPOS', 'CEBN', 'Conveniada', 1, '2026-11-20 15:20:00', 'Quadra da Adelieta Ramalho', '2026-11-20 15:20:00', 'Quadra da Adelieta Ramalho'),
  (159, 'ALTERAR', 161, 160, 'Handebol', 'Sub 15', 'FEMININO', 'GRUPOS', 'CEBC', 'CEJA', 1, '2026-11-20 16:00:00', 'Quadra da Adelieta Ramalho', '2026-11-20 16:00:00', 'Quadra da Adelieta Ramalho'),
  (160, 'ALTERAR', 162, 161, 'Baleado', 'Sub 11', 'FEMININO', 'GRUPOS', 'MARIA DA GLORIA', 'JOSE DIAS', 1, '2026-11-20 08:00:00', 'Quadra do Maria da Glória', '2026-11-20 08:00:00', 'Quadra do Maria da Glória'),
  (161, 'ALTERAR', 163, 162, 'Baleado', 'Sub 8', 'MASCULINO', 'GRUPOS', 'ACM', 'MARLENE SANTANA', 1, '2026-11-20 08:40:00', 'Quadra do Maria da Glória', '2026-11-20 08:40:00', 'Quadra do Maria da Glória'),
  (162, 'ALTERAR', 164, 163, 'Baleado', 'Sub 8', 'FEMININO', 'GRUPOS', 'ACM', 'JOSE DIAS', 1, '2026-11-20 09:20:00', 'Quadra do Maria da Glória', '2026-11-20 09:20:00', 'Quadra do Maria da Glória'),
  (163, 'ALTERAR', 165, 164, 'Baleado', 'Sub 9', 'FEMININO', 'GRUPOS', 'MARIA DA GLORIA', 'PORTAL DO SABER', 1, '2026-11-20 10:00:00', 'Quadra do Maria da Glória', '2026-11-20 10:00:00', 'Quadra do Maria da Glória'),
  (164, 'ALTERAR', 166, 165, 'Baleado', 'Sub 9', 'MASCULINO', 'GRUPOS', 'MARLENE SANTANA', 'ADELIETA RAMALHO', 2, '2026-11-20 10:40:00', 'Quadra do Maria da Glória', '2026-11-20 10:40:00', 'Quadra do Maria da Glória'),
  (165, 'ALTERAR', 211, 166, 'Baleado', 'Sub 9', 'FEMININO', 'GRUPOS', 'JOSE DIAS', 'ADELIETA RAMALHO', 1, '2026-11-20 14:00:00', 'Quadra do CEBC', '2026-11-20 11:20:00', 'Quadra do Maria da Glória'),
  (166, 'ALTERAR', 168, 167, 'Vôlei', 'Sub 15', 'MISTO', 'GRUPOS', 'EMILIANO ZAPATA', 'CEJA', 1, '2026-11-20 12:00:00', 'Quadra do Maria da Glória', '2026-11-20 12:00:00', 'Quadra do Maria da Glória'),
  (167, 'ALTERAR', 169, 168, 'Vôlei', 'Aberto', 'MISTO', 'GRUPOS', 'LUCIA ROCHA', 'CEBC', 1, '2026-11-20 12:40:00', 'Quadra do Maria da Glória', '2026-11-20 12:40:00', 'Quadra do Maria da Glória'),
  (168, 'INCLUIR', NULL, 169, 'Vôlei', 'Sub 17', 'MISTO', 'GRUPOS', 'CETI', 'LUCIA ROCHA', 1, NULL, NULL, '2026-11-20 13:20:00', 'Quadra do Maria da Glória'),
  (169, 'ALTERAR', 171, 170, 'Vôlei', 'Sub 15', 'MISTO', 'GRUPOS', 'CEBC', 'CEBN', 1, '2026-11-20 14:00:00', 'Quadra do Maria da Glória', '2026-11-20 14:00:00', 'Quadra do Maria da Glória'),
  (170, 'ALTERAR', 172, 171, 'Handebol', 'Sub 11', 'MASCULINO', 'SEMIFINAL', NULL, NULL, 1, '2026-11-20 14:40:00', 'Quadra do Maria da Glória', '2026-11-20 14:40:00', 'Quadra do Maria da Glória'),
  (171, 'ALTERAR', 173, 172, 'Handebol', 'Sub 11', 'MASCULINO', 'SEMIFINAL', NULL, NULL, 2, '2026-11-20 15:20:00', 'Quadra do Maria da Glória', '2026-11-20 15:20:00', 'Quadra do Maria da Glória'),
  (172, 'ALTERAR', 174, 173, 'Handebol', 'Sub 13', 'MASCULINO', 'SEMIFINAL', NULL, NULL, 1, '2026-11-20 16:00:00', 'Quadra do Maria da Glória', '2026-11-20 16:00:00', 'Quadra do Maria da Glória'),
  (173, 'ALTERAR', 175, 174, 'Futsal', 'Sub 15', 'FEMININO', 'GRUPOS', 'CEJA', 'CEBN', 1, '2026-11-20 08:00:00', 'Quadra do CEJA', '2026-11-20 08:00:00', 'Quadra do CEJA'),
  (174, 'ALTERAR', 176, 175, 'Futsal', 'Sub 15', 'FEMININO', 'GRUPOS', 'Conveniada', 'JOSE DIAS', 1, '2026-11-20 08:40:00', 'Quadra do CEJA', '2026-11-20 08:40:00', 'Quadra do CEJA'),
  (175, 'ALTERAR', 177, 176, 'Futsal', 'Sub 15', 'MASCULINO', 'GRUPOS', 'CEBC', 'EMILIANO ZAPATA', 1, '2026-11-20 09:20:00', 'Quadra do CEJA', '2026-11-20 09:20:00', 'Quadra do CEJA'),
  (176, 'ALTERAR', 178, 177, 'Futsal', 'Sub 15', 'MASCULINO', 'GRUPOS', 'CEJA', 'Conveniada', 1, '2026-11-20 10:00:00', 'Quadra do CEJA', '2026-11-20 10:00:00', 'Quadra do CEJA'),
  (177, 'ALTERAR', 179, 178, 'Baleado', 'Sub 11', 'FEMININO', 'GRUPOS', 'CEJA', 'EMILIANO ZAPATA', 1, '2026-11-20 10:40:00', 'Quadra do CEJA', '2026-11-20 10:40:00', 'Quadra do CEJA'),
  (178, 'ALTERAR', 180, 179, 'Baleado', 'Sub 15', 'MASCULINO', 'GRUPOS', 'CEJA', 'CEBC', 1, '2026-11-20 11:20:00', 'Quadra do CEJA', '2026-11-20 11:20:00', 'Quadra do CEJA'),
  (179, 'ALTERAR', 181, 180, 'Handebol', 'Sub 13', 'FEMININO', 'GRUPOS', 'CEBN', 'CEJA', 1, '2026-11-20 12:00:00', 'Quadra do CEJA', '2026-11-20 12:00:00', 'Quadra do CEJA'),
  (180, 'ALTERAR', 182, 181, 'Handebol', 'Sub 13', 'MASCULINO', 'GRUPOS', 'CEBN', 'JOSE DIAS', 1, '2026-11-20 12:40:00', 'Quadra do CEJA', '2026-11-20 12:40:00', 'Quadra do CEJA'),
  (181, 'ALTERAR', 183, 182, 'Handebol', 'Sub 17', 'FEMININO', 'GRUPOS', 'CEJA', 'CETI', 1, '2026-11-20 13:20:00', 'Quadra do CEJA', '2026-11-20 13:20:00', 'Quadra do CEJA'),
  (182, 'ALTERAR', 184, 183, 'Baleado', 'Sub 17', 'FEMININO', 'GRUPOS', 'CEBC', 'LUCIA ROCHA', 1, '2026-11-20 14:00:00', 'Quadra do CEJA', '2026-11-20 14:00:00', 'Quadra do CEJA'),
  (183, 'ALTERAR', 185, 184, 'Baleado', 'Sub 9', 'FEMININO', 'GRUPOS', 'FRANCISCO AMORIM', 'MARIA DA GLORIA', 1, '2026-11-20 14:40:00', 'Quadra do CEJA', '2026-11-20 14:40:00', 'Quadra do CEJA'),
  (184, 'ALTERAR', 186, 185, 'Futsal', 'Sub 13', 'MASCULINO', 'GRUPOS', 'JOSE DIAS', 'Conveniada', 1, '2026-11-20 15:20:00', 'Quadra do CEJA', '2026-11-20 15:20:00', 'Quadra do CEJA'),
  (185, 'ALTERAR', 187, 186, 'Futsal', 'Sub 13', 'MASCULINO', 'GRUPOS', 'CEJA', 'CEBC', 1, '2026-11-20 16:00:00', 'Quadra do CEJA', '2026-11-20 16:00:00', 'Quadra do CEJA'),
  (186, 'ALTERAR', 188, 187, 'Futebol Society', 'Sub 13', 'MASCULINO', 'GRUPOS', 'Conveniada', 'CEJA', 1, '2026-11-20 08:40:00', 'Campo Society do CETI', '2026-11-20 08:40:00', 'Campo Society do CETI'),
  (187, 'ALTERAR', 189, 188, 'Futebol Society', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Conveniada', 'CEJA', 1, '2026-11-20 09:20:00', 'Campo Society do CETI', '2026-11-20 09:20:00', 'Campo Society do CETI'),
  (188, 'ALTERAR', 190, 189, 'Futebol Society', 'Sub 17', 'MASCULINO', 'GRUPOS', 'CEJA', 'CETI', 1, '2026-11-20 10:00:00', 'Campo Society do CETI', '2026-11-20 10:00:00', 'Campo Society do CETI'),
  (189, 'ALTERAR', 191, 190, 'Futebol Society', 'Sub 13', 'MASCULINO', 'GRUPOS', 'MARIA DA GLORIA', 'CEBN', 2, '2026-11-20 15:00:00', 'Campo Society do CETI', '2026-11-20 15:00:00', 'Campo Society do CETI'),
  (190, 'ALTERAR', 192, 191, 'Futebol Society', 'Sub 13', 'MASCULINO', 'GRUPOS', 'CEBC', 'Conveniada', 1, '2026-11-20 15:40:00', 'Campo Society do CETI', '2026-11-20 15:40:00', 'Campo Society do CETI'),
  (191, 'INCLUIR', NULL, 192, 'Vôlei', 'Sub 17', 'MISTO', 'GRUPOS', 'CEBN', 'CEBC', 1, NULL, NULL, '2026-11-20 08:00:00', 'Quadra do CETI'),
  (192, 'ALTERAR', 194, 193, 'Vôlei', 'Aberto', 'MISTO', 'GRUPOS', 'CETI', 'LUCIA ROCHA', 1, '2026-11-20 08:40:00', 'Quadra do CETI', '2026-11-20 08:40:00', 'Quadra do CETI'),
  (193, 'ALTERAR', 195, 194, 'Futsal', 'Sub 8', 'MASCULINO', 'GRUPOS', 'MARLENE SANTANA', 'ACM', 1, '2026-11-20 09:20:00', 'Quadra do CETI', '2026-11-20 09:20:00', 'Quadra do CETI'),
  (194, 'ALTERAR', 196, 195, 'Futsal', 'Sub 8', 'MASCULINO', 'GRUPOS', 'JOSE DIAS', 'ADELIETA RAMALHO', 2, '2026-11-20 10:00:00', 'Quadra do CETI', '2026-11-20 10:00:00', 'Quadra do CETI'),
  (195, 'ALTERAR', 197, 196, 'Baleado', 'Sub 11', 'FEMININO', 'GRUPOS', 'FRANCISCO AMORIM', 'PORTAL DO SABER', 1, '2026-11-20 10:40:00', 'Quadra do CETI', '2026-11-20 10:40:00', 'Quadra do CETI'),
  (196, 'ALTERAR', 198, 197, 'Baleado', 'Sub 13', 'MASCULINO', 'SEMIFINAL', NULL, NULL, 1, '2026-11-20 11:20:00', 'Quadra do CETI', '2026-11-20 11:20:00', 'Quadra do CETI'),
  (197, 'ALTERAR', 199, 198, 'Baleado', 'Sub 11', 'FEMININO', 'GRUPOS', 'ADELIETA RAMALHO', 'JOSENILDO LEITE', 1, '2026-11-20 12:00:00', 'Quadra do CETI', '2026-11-20 12:00:00', 'Quadra do CETI'),
  (198, 'ALTERAR', 200, 199, 'Handebol', 'Sub 9', 'FEMININO', 'GRUPOS', 'FRANCISCO AMORIM', 'MARIA DA GLORIA', 1, '2026-11-20 12:40:00', 'Quadra do CETI', '2026-11-20 12:40:00', 'Quadra do CETI'),
  (199, 'ALTERAR', 201, 200, 'Futsal', 'Sub 8', 'MASCULINO', 'GRUPOS', 'ACM', 'TEODULO LEITE', 1, '2026-11-20 13:20:00', 'Quadra do CETI', '2026-11-20 13:20:00', 'Quadra do CETI'),
  (200, 'ALTERAR', 202, 201, 'Basquete', 'Sub 15', 'FEMININO', 'GRUPOS', 'CEJA', 'Conveniada', 1, '2026-11-20 08:00:00', 'Quadra do CEBC', '2026-11-20 08:00:00', 'Quadra do CEBC'),
  (201, 'ALTERAR', 203, 202, 'Basquete', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Conveniada', 'CEBC', 1, '2026-11-20 08:40:00', 'Quadra do CEBC', '2026-11-20 08:40:00', 'Quadra do CEBC'),
  (202, 'ALTERAR', 204, 203, 'Futsal', 'Sub 15', 'FEMININO', 'GRUPOS', 'EMILIANO ZAPATA', 'CEJA', 1, '2026-11-20 09:20:00', 'Quadra do CEBC', '2026-11-20 09:20:00', 'Quadra do CEBC'),
  (203, 'ALTERAR', 205, 204, 'Futsal', 'Sub 15', 'FEMININO', 'GRUPOS', 'JOSE DIAS', 'CEBC', 1, '2026-11-20 10:00:00', 'Quadra do CEBC', '2026-11-20 10:00:00', 'Quadra do CEBC'),
  (204, 'ALTERAR', 206, 205, 'Handebol', 'Sub 11', 'FEMININO', 'GRUPOS', 'FRANCISCO AMORIM', 'CEJA', 1, '2026-11-20 10:40:00', 'Quadra do CEBC', '2026-11-20 10:40:00', 'Quadra do CEBC'),
  (205, 'ALTERAR', 207, 206, 'Basquete', 'Sub 17', 'MASCULINO', 'GRUPOS', 'CEJA', 'CETI', 1, '2026-11-20 11:20:00', 'Quadra do CEBC', '2026-11-20 11:20:00', 'Quadra do CEBC'),
  (206, 'ALTERAR', 208, 207, 'Basquete', 'Sub 15', 'MASCULINO', 'GRUPOS', 'CEJA', 'CEBC', 1, '2026-11-20 12:00:00', 'Quadra do CEBC', '2026-11-20 12:00:00', 'Quadra do CEBC'),
  (207, 'ALTERAR', 209, 208, 'Basquete', 'Sub 17', 'FEMININO', 'GRUPOS', 'CEJA', 'CEBC', 1, '2026-11-20 12:40:00', 'Quadra do CEBC', '2026-11-20 12:40:00', 'Quadra do CEBC'),
  (208, 'ALTERAR', 210, 209, 'Baleado', 'Sub 9', 'MASCULINO', 'GRUPOS', 'FRANCISCO AMORIM', 'TEODULO LEITE', 1, '2026-11-20 13:20:00', 'Quadra do CEBC', '2026-11-20 13:20:00', 'Quadra do CEBC'),
  (209, 'ALTERAR', 212, 210, 'Baleado', 'Sub 11', 'MASCULINO', 'SEMIFINAL', NULL, NULL, 1, '2026-11-20 14:40:00', 'Quadra do CEBC', '2026-11-20 14:40:00', 'Quadra do CEBC'),
  (210, 'ALTERAR', 213, 211, 'Handebol', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Conveniada', 'CEBN', 1, '2026-11-20 15:20:00', 'Quadra do CEBC', '2026-11-20 15:20:00', 'Quadra do CEBC'),
  (211, 'ALTERAR', 214, 212, 'Handebol', 'Sub 15', 'MASCULINO', 'GRUPOS', 'CEJA', 'CEBC', 1, '2026-11-20 16:00:00', 'Quadra do CEBC', '2026-11-20 16:00:00', 'Quadra do CEBC'),
  (212, 'ALTERAR', 215, 213, 'Handebol', 'Aberto', 'MASCULINO', 'GRUPOS', 'CEJA', 'LUCIA ROCHA', 1, '2026-11-20 16:40:00', 'Quadra do CEBC', '2026-11-20 16:40:00', 'Quadra do CEBC'),
  (213, 'ALTERAR', 216, 214, 'Handebol', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Conveniada', 'CEBC', 1, '2026-11-21 08:00:00', 'Quadra do Maria da Glória', '2026-11-21 08:40:00', 'Quadra do Maria da Glória'),
  (214, 'ALTERAR', 217, 215, 'Handebol', 'Sub 17', 'MASCULINO', 'GRUPOS', 'CEJA', 'CEBN', 1, '2026-11-21 08:40:00', 'Quadra do Maria da Glória', '2026-11-21 09:20:00', 'Quadra do Maria da Glória'),
  (215, 'ALTERAR', 219, 216, 'Baleado', 'Sub 15', 'FEMININO', 'SEMIFINAL', NULL, NULL, 1, '2026-11-21 10:00:00', 'Quadra do Maria da Glória', '2026-11-21 10:00:00', 'Quadra do Maria da Glória'),
  (216, 'ALTERAR', 220, 217, 'Baleado', 'Sub 15', 'FEMININO', 'SEMIFINAL', NULL, NULL, 2, '2026-11-21 10:40:00', 'Quadra do Maria da Glória', '2026-11-21 10:40:00', 'Quadra do Maria da Glória'),
  (217, 'ALTERAR', 221, 218, 'Futsal', 'Sub 9', 'MASCULINO', 'SEMIFINAL', NULL, NULL, 1, '2026-11-21 11:20:00', 'Quadra do Maria da Glória', '2026-11-21 11:20:00', 'Quadra do Maria da Glória'),
  (218, 'ALTERAR', 222, 219, 'Futsal', 'Sub 9', 'MASCULINO', 'SEMIFINAL', NULL, NULL, 2, '2026-11-21 12:00:00', 'Quadra do Maria da Glória', '2026-11-21 12:00:00', 'Quadra do Maria da Glória'),
  (219, 'ALTERAR', 223, 220, 'Baleado', 'Sub 11', 'MASCULINO', 'SEMIFINAL', NULL, NULL, 2, '2026-11-21 12:40:00', 'Quadra do Maria da Glória', '2026-11-21 12:40:00', 'Quadra do Maria da Glória'),
  (220, 'ALTERAR', 224, 221, 'Handebol', 'Sub 13', 'MASCULINO', 'FINAL', NULL, NULL, 1, '2026-11-21 13:20:00', 'Quadra do Maria da Glória', '2026-11-21 13:20:00', 'Quadra do Maria da Glória'),
  (221, 'ALTERAR', 225, 222, 'Handebol', 'Sub 13', 'FEMININO', 'FINAL', NULL, NULL, 1, '2026-11-21 14:00:00', 'Quadra do Maria da Glória', '2026-11-21 14:00:00', 'Quadra do Maria da Glória'),
  (222, 'ALTERAR', 226, 223, 'Handebol', 'Sub 11', 'MASCULINO', 'FINAL', NULL, NULL, 1, '2026-11-21 14:40:00', 'Quadra do Maria da Glória', '2026-11-21 14:40:00', 'Quadra do Maria da Glória'),
  (223, 'ALTERAR', 227, 224, 'Handebol', 'Sub 15', 'MASCULINO', 'FINAL', NULL, NULL, 1, '2026-11-21 15:20:00', 'Quadra do Maria da Glória', '2026-11-21 15:20:00', 'Quadra do Maria da Glória'),
  (224, 'ALTERAR', 228, 225, 'Handebol', 'Sub 11', 'FEMININO', 'GRUPOS', 'ADELIETA RAMALHO', 'JOSE DIAS', 1, '2026-11-21 08:00:00', 'Quadra da Adelieta Ramalho', '2026-11-21 08:00:00', 'Quadra da Adelieta Ramalho'),
  (225, 'ALTERAR', 229, 226, 'Baleado', 'Sub 15', 'MASCULINO', 'GRUPOS', 'Conveniada', 'MANOEL RAMOS', 2, '2026-11-21 08:40:00', 'Quadra da Adelieta Ramalho', '2026-11-21 08:40:00', 'Quadra da Adelieta Ramalho'),
  (226, 'ALTERAR', 230, 227, 'Baleado', 'Sub 15', 'MASCULINO', 'GRUPOS', 'CEBN', 'CEJA', 1, '2026-11-21 09:20:00', 'Quadra da Adelieta Ramalho', '2026-11-21 09:20:00', 'Quadra da Adelieta Ramalho'),
  (227, 'ALTERAR', 231, 228, 'Baleado', 'Sub 17', 'MASCULINO', 'GRUPOS', 'JOSENILDO LEITE', 'CEJA', 1, '2026-11-21 10:00:00', 'Quadra da Adelieta Ramalho', '2026-11-21 10:00:00', 'Quadra da Adelieta Ramalho'),
  (228, 'ALTERAR', 232, 229, 'Baleado', 'Sub 17', 'MASCULINO', 'GRUPOS', 'CEBC', 'CETI', 1, '2026-11-21 10:40:00', 'Quadra da Adelieta Ramalho', '2026-11-21 10:40:00', 'Quadra da Adelieta Ramalho'),
  (229, 'ALTERAR', 234, 230, 'Handebol', 'Sub 11', 'FEMININO', 'SEMIFINAL', NULL, NULL, 1, '2026-11-21 12:00:00', 'Quadra da Adelieta Ramalho', '2026-11-21 11:20:00', 'Quadra da Adelieta Ramalho'),
  (230, 'ALTERAR', 235, 231, 'Handebol', 'Sub 11', 'FEMININO', 'SEMIFINAL', NULL, NULL, 2, '2026-11-21 12:40:00', 'Quadra da Adelieta Ramalho', '2026-11-21 12:00:00', 'Quadra da Adelieta Ramalho'),
  (231, 'ALTERAR', 236, 232, 'Baleado', 'Sub 13', 'MASCULINO', 'SEMIFINAL', NULL, NULL, 2, '2026-11-21 13:20:00', 'Quadra da Adelieta Ramalho', '2026-11-21 12:40:00', 'Quadra da Adelieta Ramalho'),
  (232, 'ALTERAR', 237, 233, 'Baleado', 'Sub 15', 'FEMININO', 'FINAL', NULL, NULL, 1, '2026-11-21 14:00:00', 'Quadra da Adelieta Ramalho', '2026-11-21 13:20:00', 'Quadra da Adelieta Ramalho'),
  (233, 'ALTERAR', 238, 234, 'Baleado', 'Sub 13', 'FEMININO', 'FINAL', NULL, NULL, 1, '2026-11-21 14:40:00', 'Quadra da Adelieta Ramalho', '2026-11-21 14:00:00', 'Quadra da Adelieta Ramalho'),
  (234, 'ALTERAR', 239, 235, 'Handebol', 'Sub 11', 'FEMININO', 'FINAL', NULL, NULL, 1, '2026-11-21 15:20:00', 'Quadra da Adelieta Ramalho', '2026-11-21 14:40:00', 'Quadra da Adelieta Ramalho'),
  (235, 'ALTERAR', 240, 236, 'Baleado', 'Sub 11', 'MASCULINO', 'FINAL', NULL, NULL, 1, '2026-11-21 16:00:00', 'Quadra da Adelieta Ramalho', '2026-11-21 15:20:00', 'Quadra da Adelieta Ramalho'),
  (236, 'ALTERAR', 241, 237, 'Baleado', 'Sub 15', 'FEMININO', 'GRUPOS', 'EMILIANO ZAPATA', 'CEJA', 1, '2026-11-21 08:00:00', 'Quadra do CEJA', '2026-11-21 08:00:00', 'Quadra do CEJA'),
  (237, 'ALTERAR', 242, 238, 'Baleado', 'Sub 15', 'FEMININO', 'GRUPOS', 'CEBC', 'JOSENILDO LEITE', 1, '2026-11-21 08:40:00', 'Quadra do CEJA', '2026-11-21 08:40:00', 'Quadra do CEJA'),
  (238, 'ALTERAR', 243, 239, 'Baleado', 'Sub 17', 'FEMININO', 'GRUPOS', 'CEJA', 'CEBC', 1, '2026-11-21 09:20:00', 'Quadra do CEJA', '2026-11-21 09:20:00', 'Quadra do CEJA'),
  (239, 'ALTERAR', 244, 240, 'Baleado', 'Sub 17', 'FEMININO', 'GRUPOS', 'LUCIA ROCHA', 'CETI', 1, '2026-11-21 10:00:00', 'Quadra do CEJA', '2026-11-21 10:00:00', 'Quadra do CEJA'),
  (240, 'ALTERAR', 245, 241, 'Handebol', 'Sub 13', 'MASCULINO', 'SEMIFINAL', NULL, NULL, 2, '2026-11-21 10:40:00', 'Quadra do CEJA', '2026-11-21 10:40:00', 'Quadra do CEJA'),
  (241, 'ALTERAR', 246, 242, 'Futsal', 'Aberto', 'FEMININO', 'GRUPOS', 'LUCIA ROCHA', 'VITORIA LIMA', 1, '2026-11-21 11:20:00', 'Quadra do CEJA', '2026-11-21 11:20:00', 'Quadra do CEJA'),
  (242, 'ALTERAR', 247, 243, 'Futsal', 'Sub 13', 'MASCULINO', 'SEMIFINAL', NULL, NULL, 1, '2026-11-21 12:00:00', 'Quadra do CEJA', '2026-11-21 12:00:00', 'Quadra do CEJA'),
  (243, 'ALTERAR', 248, 244, 'Futsal', 'Sub 13', 'MASCULINO', 'SEMIFINAL', NULL, NULL, 2, '2026-11-21 12:40:00', 'Quadra do CEJA', '2026-11-21 12:40:00', 'Quadra do CEJA'),
  (244, 'ALTERAR', 249, 245, 'Futsal', 'Sub 11', 'MASCULINO', 'SEMIFINAL', NULL, NULL, 1, '2026-11-21 13:20:00', 'Quadra do CEJA', '2026-11-21 13:20:00', 'Quadra do CEJA'),
  (245, 'ALTERAR', 250, 246, 'Futsal', 'Sub 11', 'MASCULINO', 'SEMIFINAL', NULL, NULL, 2, '2026-11-21 14:00:00', 'Quadra do CEJA', '2026-11-21 14:00:00', 'Quadra do CEJA'),
  (246, 'ALTERAR', 251, 247, 'Baleado', 'Sub 17', 'MASCULINO', 'FINAL', NULL, NULL, 1, '2026-11-21 14:40:00', 'Quadra do CEJA', '2026-11-21 14:40:00', 'Quadra do CEJA'),
  (247, 'ALTERAR', 252, 248, 'Baleado', 'Sub 15', 'MASCULINO', 'FINAL', NULL, NULL, 1, '2026-11-21 15:20:00', 'Quadra do CEJA', '2026-11-21 15:20:00', 'Quadra do CEJA'),
  (248, 'ALTERAR', 253, 249, 'Baleado', 'Sub 13', 'MASCULINO', 'FINAL', NULL, NULL, 1, '2026-11-21 16:00:00', 'Quadra do CEJA', '2026-11-21 16:00:00', 'Quadra do CEJA'),
  (249, 'ALTERAR', 254, 250, 'Baleado', 'Sub 17', 'FEMININO', 'FINAL', NULL, NULL, 1, '2026-11-21 16:40:00', 'Quadra do CEJA', '2026-11-21 16:40:00', 'Quadra do CEJA'),
  (250, 'ALTERAR', 255, 251, 'Baleado', 'Sub 13', 'FEMININO', 'SEMIFINAL', NULL, NULL, 1, '2026-11-21 08:00:00', 'Quadra do CEBC', '2026-11-21 08:00:00', 'Quadra do CEBC'),
  (251, 'ALTERAR', 256, 252, 'Baleado', 'Sub 13', 'FEMININO', 'SEMIFINAL', NULL, NULL, 2, '2026-11-21 08:40:00', 'Quadra do CEBC', '2026-11-21 08:40:00', 'Quadra do CEBC'),
  (252, 'ALTERAR', 257, 253, 'Baleado', 'Sub 11', 'FEMININO', 'SEMIFINAL', NULL, NULL, 1, '2026-11-21 09:20:00', 'Quadra do CEBC', '2026-11-21 09:20:00', 'Quadra do CEBC'),
  (253, 'ALTERAR', 258, 254, 'Basquete', 'Sub 15', 'FEMININO', 'FINAL', NULL, NULL, 1, '2026-11-21 10:00:00', 'Quadra do CEBC', '2026-11-21 10:00:00', 'Quadra do CEBC'),
  (254, 'ALTERAR', 259, 255, 'Futsal', 'Sub 15', 'MASCULINO', 'SEMIFINAL', NULL, NULL, 1, '2026-11-21 10:40:00', 'Quadra do CEBC', '2026-11-21 10:40:00', 'Quadra do CEBC'),
  (255, 'ALTERAR', 260, 256, 'Futsal', 'Sub 15', 'MASCULINO', 'SEMIFINAL', NULL, NULL, 2, '2026-11-21 11:00:00', 'Quadra do CEBC', '2026-11-21 11:00:00', 'Quadra do CEBC'),
  (256, 'ALTERAR', 261, 257, 'Futsal', 'Sub 15', 'FEMININO', 'SEMIFINAL', NULL, NULL, 1, '2026-11-21 11:40:00', 'Quadra do CEBC', '2026-11-21 11:40:00', 'Quadra do CEBC'),
  (257, 'ALTERAR', 262, 258, 'Futsal', 'Sub 15', 'FEMININO', 'SEMIFINAL', NULL, NULL, 2, '2026-11-21 12:20:00', 'Quadra do CEBC', '2026-11-21 12:20:00', 'Quadra do CEBC'),
  (258, 'ALTERAR', 263, 259, 'Handebol', 'Sub 15', 'FEMININO', 'FINAL', NULL, NULL, 1, '2026-11-21 13:00:00', 'Quadra do CEBC', '2026-11-21 13:00:00', 'Quadra do CEBC'),
  (259, 'ALTERAR', 264, 260, 'Futsal', 'Sub 13', 'FEMININO', 'FINAL', NULL, NULL, 1, '2026-11-21 13:40:00', 'Quadra do CEBC', '2026-11-21 13:40:00', 'Quadra do CEBC'),
  (260, 'ALTERAR', 265, 261, 'Futsal', 'Sub 9', 'MASCULINO', 'FINAL', NULL, NULL, 1, '2026-11-21 14:20:00', 'Quadra do CEBC', '2026-11-21 14:20:00', 'Quadra do CEBC'),
  (261, 'ALTERAR', 266, 262, 'Futsal', 'Sub 17', 'FEMININO', 'FINAL', NULL, NULL, 1, '2026-11-21 15:00:00', 'Quadra do CEBC', '2026-11-21 15:00:00', 'Quadra do CEBC'),
  (262, 'ALTERAR', 267, 263, 'Futsal', 'Sub 15', 'FEMININO', 'FINAL', NULL, NULL, 1, '2026-11-21 15:40:00', 'Quadra do CEBC', '2026-11-21 15:40:00', 'Quadra do CEBC'),
  (263, 'ALTERAR', 268, 264, 'Futsal', 'Sub 11', 'MASCULINO', 'FINAL', NULL, NULL, 1, '2026-11-21 16:20:00', 'Quadra do CEBC', '2026-11-21 16:20:00', 'Quadra do CEBC'),
  (264, 'ALTERAR', 269, 265, 'Handebol', 'Sub 9', 'FEMININO', 'GRUPOS', 'MARIA DA GLORIA', 'ADELIETA RAMALHO', 1, '2026-11-21 08:00:00', 'Quadra do CETI', '2026-11-21 08:00:00', 'Quadra do CETI'),
  (265, 'ALTERAR', 270, 266, 'Handebol', 'Sub 8', 'MASCULINO', 'GRUPOS', 'JOSE DIAS', 'ACM', 1, '2026-11-21 08:40:00', 'Quadra do CETI', '2026-11-21 08:40:00', 'Quadra do CETI'),
  (266, 'ALTERAR', 271, 267, 'Baleado', 'Sub 9', 'FEMININO', 'GRUPOS', 'PORTAL DO SABER', 'FRANCISCO AMORIM', 1, '2026-11-21 09:20:00', 'Quadra do CETI', '2026-11-21 09:20:00', 'Quadra do CETI'),
  (267, 'INCLUIR', NULL, 268, 'Baleado', 'Sub 9', 'FEMININO', 'GRUPOS', 'JOSE DIAS', 'ADELIETA RAMALHO', 2, NULL, NULL, '2026-11-21 10:00:00', 'Quadra do CETI'),
  (268, 'ALTERAR', 273, 269, 'Baleado', 'Sub 8', 'FEMININO', 'GRUPOS', 'JOSE DIAS', 'ACM', 2, '2026-11-21 10:40:00', 'Quadra do CETI', '2026-11-21 10:40:00', 'Quadra do CETI'),
  (269, 'ALTERAR', 274, 270, 'Futsal', 'Sub 8', 'FEMININO', 'GRUPOS', 'EMILIANO ZAPATA', 'JOSE DIAS', 2, '2026-11-21 11:20:00', 'Quadra do CETI', '2026-11-21 11:20:00', 'Quadra do CETI'),
  (270, 'ALTERAR', 275, 271, 'Futsal', 'Sub 11', 'FEMININO', 'GRUPOS', 'JOSE DIAS', 'MARLENE SANTANA', 2, '2026-11-21 12:00:00', 'Quadra do CETI', '2026-11-21 12:00:00', 'Quadra do CETI'),
  (271, 'ALTERAR', 276, 272, 'Futsal', 'Sub 9', 'FEMININO', 'GRUPOS', 'JOSE DIAS', 'MARLENE SANTANA', 2, '2026-11-21 12:40:00', 'Quadra do CETI', '2026-11-21 12:40:00', 'Quadra do CETI'),
  (272, 'ALTERAR', 277, 273, 'Futsal', 'Sub 8', 'MASCULINO', 'FINAL', NULL, NULL, 1, '2026-11-21 13:20:00', 'Quadra do CETI', '2026-11-21 13:20:00', 'Quadra do CETI'),
  (273, 'ALTERAR', 278, 274, 'Handebol', 'Sub 8', 'MASCULINO', 'FINAL', NULL, NULL, 1, '2026-11-21 14:00:00', 'Quadra do CETI', '2026-11-21 14:00:00', 'Quadra do CETI'),
  (274, 'ALTERAR', 280, 276, 'Handebol', 'Sub 9', 'FEMININO', 'FINAL', NULL, NULL, 1, '2026-11-21 15:20:00', 'Quadra do CETI', '2026-11-21 15:20:00', 'Quadra do CETI'),
  (275, 'ALTERAR', 281, 277, 'Baleado', 'Sub 9', 'MASCULINO', 'FINAL', NULL, NULL, 1, '2026-11-21 16:00:00', 'Quadra do CETI', '2026-11-21 16:00:00', 'Quadra do CETI'),
  (276, 'ALTERAR', 282, 278, 'Baleado', 'Sub 9', 'FEMININO', 'FINAL', NULL, NULL, 1, '2026-11-21 16:20:00', 'Quadra do CETI', '2026-11-21 16:20:00', 'Quadra do CETI'),
  (277, 'ALTERAR', 283, 279, 'Baleado', 'Sub 8', 'MASCULINO', 'GRUPOS', 'ACM', 'MARLENE SANTANA', 2, '2026-11-21 16:40:00', 'Quadra do CETI', '2026-11-21 16:40:00', 'Quadra do CETI'),
  (278, 'ALTERAR', 284, 280, 'Handebol', 'Sub 13', 'FEMININO', 'GRUPOS', 'CEJA', 'CEBC', 1, '2026-11-21 08:00:00', 'Ginásio de Esportes', '2026-11-21 08:00:00', 'Ginásio de Esportes'),
  (279, 'ALTERAR', 285, 281, 'Handebol', 'Sub 15', 'FEMININO', 'GRUPOS', 'Conveniada', 'CEJA', 1, '2026-11-21 08:40:00', 'Ginásio de Esportes', '2026-11-21 08:40:00', 'Ginásio de Esportes'),
  (280, 'ALTERAR', 286, 282, 'Handebol', 'Sub 15', 'FEMININO', 'GRUPOS', 'CEBC', 'CEBN', 1, '2026-11-21 09:20:00', 'Ginásio de Esportes', '2026-11-21 09:20:00', 'Ginásio de Esportes'),
  (281, 'ALTERAR', 287, 283, 'Baleado', 'Sub 11', 'FEMININO', 'SEMIFINAL', NULL, NULL, 2, '2026-11-21 10:00:00', 'Ginásio de Esportes', '2026-11-21 10:00:00', 'Ginásio de Esportes'),
  (282, 'ALTERAR', 288, 284, 'Futsal', 'Sub 7', 'MASCULINO', 'FINAL', NULL, NULL, 1, '2026-11-21 10:40:00', 'Ginásio de Esportes', '2026-11-21 10:40:00', 'Ginásio de Esportes'),
  (283, 'ALTERAR', 289, 285, 'Vôlei', 'Aberto', 'MISTO', 'FINAL', NULL, NULL, 1, '2026-11-21 11:20:00', 'Ginásio de Esportes', '2026-11-21 11:20:00', 'Ginásio de Esportes'),
  (284, 'ALTERAR', 290, 286, 'Vôlei', 'Sub 15', 'MISTO', 'FINAL', NULL, NULL, 1, '2026-11-21 12:00:00', 'Ginásio de Esportes', '2026-11-21 12:00:00', 'Ginásio de Esportes'),
  (285, 'ALTERAR', 291, 287, 'Vôlei', 'Sub 17', 'MISTO', 'FINAL', NULL, NULL, 1, '2026-11-21 12:40:00', 'Ginásio de Esportes', '2026-11-21 12:40:00', 'Ginásio de Esportes'),
  (286, 'ALTERAR', 292, 288, 'Basquete', 'Sub 17', 'FEMININO', 'FINAL', NULL, NULL, 1, '2026-11-21 13:20:00', 'Ginásio de Esportes', '2026-11-21 13:20:00', 'Ginásio de Esportes'),
  (287, 'ALTERAR', 293, 289, 'Basquete', 'Sub 15', 'MASCULINO', 'FINAL', NULL, NULL, 1, '2026-11-21 14:00:00', 'Ginásio de Esportes', '2026-11-21 14:00:00', 'Ginásio de Esportes'),
  (288, 'ALTERAR', 294, 290, 'Basquete', 'Sub 17', 'MASCULINO', 'FINAL', NULL, NULL, 1, '2026-11-21 14:40:00', 'Ginásio de Esportes', '2026-11-21 14:40:00', 'Ginásio de Esportes'),
  (289, 'ALTERAR', 295, 291, 'Baleado', 'Sub 11', 'FEMININO', 'FINAL', NULL, NULL, 1, '2026-11-21 15:20:00', 'Ginásio de Esportes', '2026-11-21 15:20:00', 'Ginásio de Esportes'),
  (290, 'ALTERAR', 296, 292, 'Handebol', 'Sub 17', 'FEMININO', 'FINAL', NULL, NULL, 1, '2026-11-21 16:00:00', 'Ginásio de Esportes', '2026-11-21 16:00:00', 'Ginásio de Esportes'),
  (291, 'ALTERAR', 297, 293, 'Handebol', 'Sub 17', 'MASCULINO', 'FINAL', NULL, NULL, 1, '2026-11-21 16:40:00', 'Ginásio de Esportes', '2026-11-21 16:40:00', 'Ginásio de Esportes'),
  (292, 'ALTERAR', 298, 294, 'Handebol', 'Aberto', 'MASCULINO', 'FINAL', NULL, NULL, 1, '2026-11-21 17:20:00', 'Ginásio de Esportes', '2026-11-21 17:20:00', 'Ginásio de Esportes'),
  (293, 'ALTERAR', 299, 295, 'Futsal', 'Sub 13', 'MASCULINO', 'FINAL', NULL, NULL, 1, '2026-11-21 18:00:00', 'Ginásio de Esportes', '2026-11-21 18:00:00', 'Ginásio de Esportes'),
  (294, 'ALTERAR', 300, 296, 'Futsal', 'Sub 15', 'MASCULINO', 'FINAL', NULL, NULL, 1, '2026-11-21 18:40:00', 'Ginásio de Esportes', '2026-11-21 18:40:00', 'Ginásio de Esportes'),
  (295, 'ALTERAR', 301, 297, 'Futsal', 'Aberto', 'FEMININO', 'FINAL', NULL, NULL, 1, '2026-11-21 19:20:00', 'Ginásio de Esportes', '2026-11-21 19:20:00', 'Ginásio de Esportes'),
  (296, 'ALTERAR', 302, 298, 'Futsal', 'Sub 17', 'MASCULINO', 'FINAL', NULL, NULL, 1, '2026-11-21 20:00:00', 'Ginásio de Esportes', '2026-11-21 20:00:00', 'Ginásio de Esportes'),
  (297, 'ALTERAR', 303, 299, 'Futsal', 'Aberto', 'MASCULINO', 'FINAL', NULL, NULL, 1, '2026-11-21 20:40:00', 'Ginásio de Esportes', '2026-11-21 20:40:00', 'Ginásio de Esportes'),
  (298, 'ALTERAR', 304, 300, 'Futebol Society', 'Sub 13', 'MASCULINO', 'FINAL', NULL, NULL, 1, '2026-11-21 08:40:00', 'Quadra do CETI', '2026-11-21 08:40:00', 'Campo Society do CETI'),
  (299, 'ALTERAR', 305, 301, 'Futebol Society', 'Sub 15', 'MASCULINO', 'FINAL', NULL, NULL, 1, '2026-11-21 09:20:00', 'Quadra do CETI', '2026-11-21 09:20:00', 'Campo Society do CETI'),
  (300, 'ALTERAR', 306, 302, 'Futebol Society', 'Sub 17', 'MASCULINO', 'FINAL', NULL, NULL, 1, '2026-11-21 10:00:00', 'Quadra do CETI', '2026-11-21 10:00:00', 'Campo Society do CETI'),
  (301, 'REMOVER', 114, NULL, 'Vôlei', 'Sub 17', 'MISTO', 'GRUPOS', 'CEBN', 'EMILIANO ZAPATA', 1, '2026-11-19 10:00:00', 'Quadra do CETI', NULL, NULL),
  (302, 'REMOVER', 122, NULL, 'Vôlei', 'Sub 17', 'MISTO', 'GRUPOS', 'EMILIANO ZAPATA', 'CETI', 1, '2026-11-19 15:20:00', 'Quadra do CETI', NULL, NULL),
  (303, 'REMOVER', 123, NULL, 'Vôlei', 'Sub 17', 'MISTO', 'GRUPOS', 'LUCIA ROCHA', 'CEBC', 1, '2026-11-19 16:00:00', 'Quadra do CETI', NULL, NULL),
  (304, 'REMOVER', 167, NULL, 'Baleado', 'Sub 9', 'FEMININO', 'GRUPOS', 'EMILIANO ZAPATA', 'ADELIETA RAMALHO', 1, '2026-11-20 11:20:00', 'Quadra do Maria da Glória', NULL, NULL),
  (305, 'REMOVER', 170, NULL, 'Vôlei', 'Sub 17', 'MISTO', 'GRUPOS', 'CETI', 'CEBN', 1, '2026-11-20 13:20:00', 'Quadra do Maria da Glória', NULL, NULL),
  (306, 'REMOVER', 193, NULL, 'Vôlei', 'Sub 17', 'MISTO', 'GRUPOS', 'LUCIA ROCHA', 'CEBC', 2, '2026-11-20 08:00:00', 'Quadra do CETI', NULL, NULL),
  (307, 'REMOVER', 218, NULL, 'Baleado', 'Sub 9', 'FEMININO', 'SEMIFINAL', NULL, NULL, 1, '2026-11-21 09:20:00', 'Quadra do Maria da Glória', NULL, NULL),
  (308, 'REMOVER', 233, NULL, 'Baleado', 'Sub 9', 'FEMININO', 'SEMIFINAL', NULL, NULL, 2, '2026-11-21 11:20:00', 'Quadra da Adelieta Ramalho', NULL, NULL),
  (309, 'REMOVER', 272, NULL, 'Baleado', 'Sub 9', 'FEMININO', 'GRUPOS', 'JOSE DIAS', 'EMILIANO ZAPATA', 1, '2026-11-21 10:00:00', 'Quadra do CETI', NULL, NULL);
-- A competição de cada linha (modalidade + categoria + gênero)
UPDATE alvo_db41 t
   SET t.comp_id = (SELECT MAX(c.id) FROM competicoes c
                      INNER JOIN modalidades m ON m.id = c.modalidade_id
                      INNER JOIN categorias cat ON cat.id = c.categoria_id
                     WHERE m.nome = t.modalidade AND cat.nome = t.categoria AND c.genero = t.genero),
       t.local_novo_id = (SELECT MAX(l.id) FROM locais_disputa l WHERE l.nome = t.local_novo);

-- ---------------------------------------------------------------------
-- Os jogos do banco: par de equipes, ocorrência do par na competição (ou ordem
-- no mata-mata) e se já foram mexidos
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS jogo_db41;
CREATE TEMPORARY TABLE jogo_db41 (
  id          INT          NOT NULL PRIMARY KEY,
  comp        INT          NOT NULL,
  fase        VARCHAR(10)  NOT NULL,
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
INSERT INTO jogo_db41 (id, comp, fase, e1n, e2n, occ, nt, dh, local_nome)
SELECT d.id, d.competicao_id, d.fase, d.e1n, d.e2n,
       ROW_NUMBER() OVER (PARTITION BY d.competicao_id, d.fase, d.chave ORDER BY d.data_hora, d.numero_tabela),
       d.numero_tabela, d.data_hora, d.local_nome
  FROM (SELECT j.id, j.competicao_id, j.fase, j.data_hora, j.numero_tabela, l.nome AS local_nome,
               s1.nome AS e1n, s2.nome AS e2n,
               CASE WHEN j.fase = 'GRUPOS' THEN CONCAT(LEAST(s1.nome, s2.nome), '|', GREATEST(s1.nome, s2.nome)) ELSE '' END AS chave
          FROM jogos j
          LEFT JOIN locais_disputa l ON l.id = j.local_id
          LEFT JOIN equipes q1 ON q1.id = j.equipe_1_id LEFT JOIN escolas s1 ON s1.id = q1.escola_id
          LEFT JOIN equipes q2 ON q2.id = j.equipe_2_id LEFT JOIN escolas s2 ON s2.id = q2.escola_id) d;

UPDATE jogo_db41 x
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

-- Cada linha do plano no banco (uma consulta por coluna: a tabela temporária
-- só pode ser lida uma vez em cada comando, erro 1137)
UPDATE alvo_db41 t
   SET t.achados = (SELECT COUNT(*) FROM jogo_db41 x
                     WHERE x.comp = t.comp_id AND x.fase = t.fase AND x.occ = t.occ
                       AND (t.fase <> 'GRUPOS' OR (x.e1n = t.e1 AND x.e2n = t.e2) OR (x.e1n = t.e2 AND x.e2n = t.e1)));
UPDATE alvo_db41 t
   SET t.jogo_id = (SELECT MAX(x.id) FROM jogo_db41 x
                     WHERE x.comp = t.comp_id AND x.fase = t.fase AND x.occ = t.occ
                       AND (t.fase <> 'GRUPOS' OR (x.e1n = t.e1 AND x.e2n = t.e2) OR (x.e1n = t.e2 AND x.e2n = t.e1)));

UPDATE alvo_db41 t
  LEFT JOIN jogo_db41 x ON x.id = t.jogo_id
   SET t.estado = CASE
         WHEN t.comp_id IS NULL THEN ''
         WHEN t.acao IN ('IGUAL', 'ALTERAR', 'INCLUIR') AND t.achados = 1
          AND x.nt = t.b AND x.dh <=> t.dh_novo AND x.local_nome <=> t.local_novo THEN 'FEITO'
         WHEN t.acao IN ('IGUAL', 'ALTERAR', 'REMOVER') AND t.achados = 1
          AND x.nt = t.a AND x.dh <=> t.dh_antes AND x.local_nome <=> t.local_antes THEN 'APLICAR'
         WHEN t.acao = 'INCLUIR' AND t.achados = 0 THEN 'APLICAR'
         WHEN t.acao = 'REMOVER' AND t.achados = 0 THEN 'FEITO'
         ELSE '' END;

-- Em quantas linhas cada jogo do banco caiu (tem de ser 1)
UPDATE jogo_db41 x SET x.plano = (SELECT COUNT(*) FROM alvo_db41 t WHERE t.jogo_id = x.id);

-- Os jogos que saem (para as vagas)
DROP TEMPORARY TABLE IF EXISTS sai_db41;
CREATE TEMPORARY TABLE sai_db41 (jogo_id INT NOT NULL PRIMARY KEY);
INSERT INTO sai_db41 (jogo_id)
SELECT jogo_id FROM alvo_db41 WHERE acao = 'REMOVER' AND estado = 'APLICAR' AND jogo_id IS NOT NULL;

SELECT acao, estado, COUNT(*) AS linhas FROM alvo_db41 GROUP BY acao, estado ORDER BY acao, estado;

-- O que muda (dia, hora ou local), entra ou sai
SELECT t.acao, t.a AS de, t.b AS para, CONCAT(t.modalidade, ' ', t.categoria, ' ', IF(t.genero = 'MISTO', 'Misto', LEFT(t.genero, 1))) AS competicao, t.fase,
       CONCAT(COALESCE(t.e1, '-'), ' x ', COALESCE(t.e2, '-')) AS jogo,
       CONCAT(COALESCE(DATE_FORMAT(t.dh_antes, '%d/%m %H:%i'), ''), ' ', COALESCE(t.local_antes, '')) AS antes,
       CONCAT(COALESCE(DATE_FORMAT(t.dh_novo, '%d/%m %H:%i'), ''), ' ', COALESCE(t.local_novo, '')) AS depois,
       t.achados, t.estado
  FROM alvo_db41 t
 WHERE t.acao IN ('INCLUIR', 'REMOVER') OR NOT (t.dh_antes <=> t.dh_novo AND t.local_antes <=> t.local_novo)
 ORDER BY t.acao, COALESCE(t.b, t.a);

-- ---------------------------------------------------------------------
-- As três competições que viram grupo único
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS comp_db41;
CREATE TEMPORARY TABLE comp_db41 (
  modalidade     VARCHAR(60) NOT NULL,
  categoria      VARCHAR(20) NOT NULL,
  genero         VARCHAR(10) NOT NULL,
  classif_antes  INT         NOT NULL,
  fase_antes     VARCHAR(10) NOT NULL,
  equipes_fim    INT         NOT NULL,
  grupo_fim      INT         NOT NULL,   -- jogos de grupo no fim
  achadas        INT         NOT NULL DEFAULT 0,
  comp_id        INT         NULL,
  grupo_a        INT         NULL,
  grupo_b        INT         NULL,
  grupos         INT         NOT NULL DEFAULT 0,
  qtd            INT         NULL,
  classif        INT         NULL,
  fase           VARCHAR(10) NULL,
  melhores       INT         NULL,
  turno          VARCHAR(12) NULL,
  finais         INT         NOT NULL DEFAULT 0,
  final_id       INT         NULL,
  vagas_final    INT         NOT NULL DEFAULT 0,
  vagas_outras   INT         NOT NULL DEFAULT 0,   -- vagas apontando para os grupos, fora da final e dos jogos que saem
  estado         VARCHAR(10) NOT NULL DEFAULT ''
);
INSERT INTO comp_db41 (modalidade, categoria, genero, classif_antes, fase_antes, equipes_fim, grupo_fim) VALUES
  ('Baleado', 'Sub 9',  'MASCULINO', 1, 'FINAL',     5, 5),
  ('Baleado', 'Sub 9',  'FEMININO',  2, 'SEMIFINAL', 5, 5),
  ('Vôlei',   'Sub 17', 'MISTO',     1, 'FINAL',     4, 4);

UPDATE comp_db41 x
   SET x.achadas = (SELECT COUNT(*) FROM competicoes c
                      INNER JOIN modalidades m ON m.id = c.modalidade_id
                      INNER JOIN categorias cat ON cat.id = c.categoria_id
                     WHERE m.nome = x.modalidade AND cat.nome = x.categoria AND c.genero = x.genero),
       x.comp_id = (SELECT MAX(c.id) FROM competicoes c
                      INNER JOIN modalidades m ON m.id = c.modalidade_id
                      INNER JOIN categorias cat ON cat.id = c.categoria_id
                     WHERE m.nome = x.modalidade AND cat.nome = x.categoria AND c.genero = x.genero);
UPDATE comp_db41 x
   SET x.grupo_a = (SELECT MAX(g.id) FROM grupos g WHERE g.competicao_id = x.comp_id AND g.nome = 'A'),
       x.grupo_b = (SELECT MAX(g.id) FROM grupos g WHERE g.competicao_id = x.comp_id AND g.nome = 'B'),
       x.grupos  = (SELECT COUNT(*) FROM grupos g WHERE g.competicao_id = x.comp_id),
       x.qtd     = (SELECT c.qtd_grupos FROM competicoes c WHERE c.id = x.comp_id),
       x.classif = (SELECT c.classificados_por_grupo FROM competicoes c WHERE c.id = x.comp_id),
       x.fase    = (SELECT c.proxima_fase FROM competicoes c WHERE c.id = x.comp_id),
       x.melhores = (SELECT c.melhores_segundos FROM competicoes c WHERE c.id = x.comp_id),
       x.turno   = (SELECT c.turno FROM competicoes c WHERE c.id = x.comp_id),
       x.finais  = (SELECT COUNT(*) FROM jogos j WHERE j.competicao_id = x.comp_id AND j.fase = 'FINAL'),
       x.final_id = (SELECT MAX(j.id) FROM jogos j WHERE j.competicao_id = x.comp_id AND j.fase = 'FINAL');
UPDATE comp_db41 x
   SET x.vagas_final = (SELECT COUNT(*) FROM jogo_vagas v WHERE v.jogo_id = x.final_id AND v.manual = 0),
       x.vagas_outras = (SELECT COUNT(*) FROM jogo_vagas v
                          WHERE v.grupo_id IN (x.grupo_a, x.grupo_b) AND v.jogo_id <> x.final_id
                            AND v.jogo_id NOT IN (SELECT s.jogo_id FROM sai_db41 s));
UPDATE comp_db41 x
   SET x.estado = CASE
         WHEN x.achadas <> 1 OR x.finais <> 1 OR x.melhores <> 0 OR x.turno <> 'UNICO' OR x.grupo_a IS NULL THEN ''
         WHEN x.grupos = 1 AND x.grupo_b IS NULL AND x.qtd = 1 AND x.classif = 2 AND x.fase = 'FINAL' THEN 'FEITO'
         WHEN x.grupos = 2 AND x.grupo_b IS NOT NULL AND x.qtd = 2 AND x.classif = x.classif_antes AND x.fase = x.fase_antes
          AND x.vagas_final = 2 AND x.vagas_outras = 0 THEN 'APLICAR'
         ELSE '' END;

SELECT CONCAT(modalidade, ' ', categoria, ' ', genero) AS competicao, achadas, grupos, qtd, classif, fase,
       melhores, turno, finais, vagas_final, vagas_outras, estado
  FROM comp_db41;

-- A equipe da Emiliano Zapata nas duas competições
DROP TEMPORARY TABLE IF EXISTS equipe_db41;
CREATE TEMPORARY TABLE equipe_db41 (
  competicao  VARCHAR(40) NOT NULL,
  comp_id     INT         NULL,
  achadas     INT         NOT NULL DEFAULT 0,
  equipe_id   INT         NULL,
  registros   INT         NOT NULL DEFAULT 0,   -- inscrição, súmula ou colocação
  estado      VARCHAR(10) NOT NULL DEFAULT ''
);
INSERT INTO equipe_db41 (competicao, comp_id)
SELECT CONCAT(modalidade, ' ', categoria, ' ', genero), comp_id FROM comp_db41 WHERE genero IN ('FEMININO', 'MISTO');
UPDATE equipe_db41 x
   SET x.achadas = (SELECT COUNT(*) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'EMILIANO ZAPATA'
                     WHERE e.competicao_id = x.comp_id),
       x.equipe_id = (SELECT MAX(e.id) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'EMILIANO ZAPATA'
                       WHERE e.competicao_id = x.comp_id);
UPDATE equipe_db41 x
   SET x.registros = (SELECT COUNT(*) FROM inscricoes_atletas i WHERE i.equipe_id = x.equipe_id)
                   + (SELECT COUNT(*) FROM sumula_atletas sa WHERE sa.equipe_id = x.equipe_id)
                   + (SELECT COUNT(*) FROM sumula_equipes se WHERE se.equipe_id = x.equipe_id)
                   + (SELECT COUNT(*) FROM colocacoes_finais cf WHERE cf.equipe_id = x.equipe_id);
UPDATE equipe_db41 x
   SET x.estado = CASE WHEN x.comp_id IS NULL THEN ''
                       WHEN x.achadas = 1 AND x.registros = 0 THEN 'APLICAR'
                       WHEN x.achadas = 0 THEN 'FEITO' ELSE '' END;
SELECT competicao, achadas, registros, estado FROM equipe_db41;

-- As equipes dos jogos novos (na competição do jogo)
UPDATE alvo_db41 t
   SET t.e1_id = (SELECT MAX(e.id) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id
                   WHERE e.competicao_id = t.comp_id AND s.nome = t.e1),
       t.e2_id = (SELECT MAX(e.id) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id
                   WHERE e.competicao_id = t.comp_id AND s.nome = t.e2)
 WHERE t.acao = 'INCLUIR';

SET @aplicar_db41 = (SELECT COUNT(*) FROM alvo_db41 WHERE acao <> 'IGUAL' AND estado = 'APLICAR')
                  + (SELECT COUNT(*) FROM comp_db41 WHERE estado = 'APLICAR')
                  + (SELECT COUNT(*) FROM equipe_db41 WHERE estado = 'APLICAR');
SET @feito_db41   = (SELECT COUNT(*) FROM alvo_db41 WHERE acao <> 'IGUAL' AND estado = 'FEITO')
                  + (SELECT COUNT(*) FROM comp_db41 WHERE estado = 'FEITO')
                  + (SELECT COUNT(*) FROM equipe_db41 WHERE estado = 'FEITO');
SET @jogos_db41 = (SELECT COUNT(*) FROM jogos);
SELECT @aplicar_db41 AS itens_a_aplicar, @feito_db41 AS itens_ja_feitos, @jogos_db41 AS jogos_no_banco;

-- ---------------------------------------------------------------------
-- Trava 1: o plano bate com o banco
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS trava_jogo_db41;
CREATE TEMPORARY TABLE trava_jogo_db41 (
  item VARCHAR(80) NOT NULL,
  ok   TINYINT     NOT NULL,
  CONSTRAINT db41_jogo_nao_bate CHECK (ok = 1)
);
INSERT INTO trava_jogo_db41 (item, ok)
SELECT CONCAT('linha ', ordem, ' (', acao, ' ', COALESCE(a, '-'), ' -> ', COALESCE(b, '-'), ')'),
       CASE WHEN estado <> '' AND (acao = 'REMOVER' OR local_novo_id IS NOT NULL)
             AND (acao <> 'INCLUIR' OR estado = 'FEITO' OR (e1_id IS NOT NULL AND e2_id IS NOT NULL)) THEN 1 ELSE 0 END
  FROM alvo_db41;
INSERT INTO trava_jogo_db41 (item, ok)
SELECT CONCAT('jogo do banco nº ', COALESCE(nt, '?'), ' em ', plano, ' linhas do plano'), 0
  FROM jogo_db41 WHERE plano <> 1;
DROP TEMPORARY TABLE trava_jogo_db41;

-- Trava 2: estado misto (parte como na 20267, parte como na 20268)
DROP TEMPORARY TABLE IF EXISTS trava_misto_db41;
CREATE TEMPORARY TABLE trava_misto_db41 (
  item VARCHAR(80) NOT NULL,
  ok   TINYINT     NOT NULL,
  CONSTRAINT db41_estado_misto CHECK (ok = 1)
);
INSERT INTO trava_misto_db41 (item, ok)
SELECT 'tudo APLICAR ou tudo FEITO', CASE WHEN @aplicar_db41 = 0 OR @feito_db41 = 0 THEN 1 ELSE 0 END;
DROP TEMPORARY TABLE trava_misto_db41;

-- Trava 3: nada que muda ou sai pode ter sido jogado (só quando há o que aplicar)
DROP TEMPORARY TABLE IF EXISTS trava_mexido_db41;
CREATE TEMPORARY TABLE trava_mexido_db41 (
  item VARCHAR(80) NOT NULL,
  ok   TINYINT     NOT NULL,
  CONSTRAINT db41_jogo_ja_mexido CHECK (ok = 1)
);
INSERT INTO trava_mexido_db41 (item, ok)
SELECT CONCAT('jogo nº ', x.nt), CASE WHEN x.sujo = 0 AND x.vaga_cheia = 0 THEN 1 ELSE 0 END
  FROM jogo_db41 x
  INNER JOIN alvo_db41 t ON t.jogo_id = x.id
 WHERE @aplicar_db41 > 0
   AND (t.acao IN ('ALTERAR', 'REMOVER')
        OR x.comp IN (SELECT c.comp_id FROM comp_db41 c));
INSERT INTO trava_mexido_db41 (item, ok)
SELECT 'vaga de outro jogo vinda de jogo que sai', CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END
  FROM jogo_vagas v
 WHERE v.jogo_origem_id IN (SELECT s.jogo_id FROM sai_db41 s)
   AND v.jogo_id NOT IN (SELECT c.final_id FROM comp_db41 c);
DROP TEMPORARY TABLE trava_mexido_db41;

-- Trava 4: as três competições e a equipe da Emiliano
DROP TEMPORARY TABLE IF EXISTS trava_comp_db41;
CREATE TEMPORARY TABLE trava_comp_db41 (
  item VARCHAR(80) NOT NULL,
  ok   TINYINT     NOT NULL,
  CONSTRAINT db41_competicao_nao_bate CHECK (ok = 1)
);
INSERT INTO trava_comp_db41 (item, ok)
SELECT CONCAT(modalidade, ' ', categoria, ' ', genero), CASE WHEN estado <> '' THEN 1 ELSE 0 END FROM comp_db41;
INSERT INTO trava_comp_db41 (item, ok)
SELECT CONCAT('Emiliano Zapata em ', competicao), CASE WHEN estado <> '' THEN 1 ELSE 0 END FROM equipe_db41;
INSERT INTO trava_comp_db41 (item, ok)
SELECT 'jogos novos só nas três competições', CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END
  FROM alvo_db41 t WHERE t.acao = 'INCLUIR' AND t.comp_id NOT IN (SELECT c.comp_id FROM comp_db41 c);
DROP TEMPORARY TABLE trava_comp_db41;

-- Contagens de antes
SET @vagas_antes_db41   = (SELECT COUNT(*) FROM jogo_vagas);
SET @equipes_antes_db41 = (SELECT COUNT(*) FROM equipes);
SET @grupos_antes_db41  = (SELECT COUNT(*) FROM grupos);

-- ---------------------------------------------------------------------
-- As escritas (só no que é APLICAR)
-- ---------------------------------------------------------------------
-- 1) As finais das três competições: 1º colocado x 2º colocado do grupo A
UPDATE jogo_vagas v
  INNER JOIN comp_db41 x ON x.final_id = v.jogo_id AND x.estado = 'APLICAR'
   SET v.tipo = 'GRUPO', v.grupo_id = x.grupo_a, v.posicao = v.lado, v.jogo_origem_id = NULL,
       v.rotulo = CONCAT(v.lado, 'º colocado'), v.manual = 0;
SET @vagas_finais_db41 = ROW_COUNT();

-- 2) Os jogos que saem (as vagas das semifinais vão junto: ON DELETE CASCADE)
DELETE j FROM jogos j INNER JOIN sai_db41 s ON s.jogo_id = j.id;
SET @jogos_removidos_db41 = ROW_COUNT();

-- 3) numero_tabela, fase 1: tira do caminho todos os que mudam de número
UPDATE jogos j
  INNER JOIN alvo_db41 t ON t.jogo_id = j.id AND t.acao = 'ALTERAR' AND t.estado = 'APLICAR'
   SET j.numero_tabela = 10000 + t.b
 WHERE NOT (t.a <=> t.b);

-- 4) numero_jogo das três competições, fase 1 (o índice único é por competição)
UPDATE jogos j
  INNER JOIN comp_db41 x ON x.comp_id = j.competicao_id AND x.estado = 'APLICAR'
   SET j.numero_jogo = 10000 + j.id;

-- 5) Grupo único: equipes e jogos do grupo B passam para o A
UPDATE equipes e
  INNER JOIN comp_db41 x ON x.comp_id = e.competicao_id AND x.estado = 'APLICAR'
   SET e.grupo_id = x.grupo_a
 WHERE e.grupo_id = x.grupo_b;
SET @equipes_movidas_db41 = ROW_COUNT();
UPDATE jogos j
  INNER JOIN comp_db41 x ON x.comp_id = j.competicao_id AND x.estado = 'APLICAR'
   SET j.grupo_id = x.grupo_a
 WHERE j.grupo_id = x.grupo_b;
SET @jogos_movidos_db41 = ROW_COUNT();

-- 6) A equipe da Emiliano Zapata sai das duas competições
DELETE e FROM equipes e INNER JOIN equipe_db41 x ON x.equipe_id = e.id AND x.estado = 'APLICAR';
SET @equipes_removidas_db41 = ROW_COUNT();

-- 7) O grupo B é apagado e a regra vira grupo único, 2 classificados, FINAL
DELETE g FROM grupos g INNER JOIN comp_db41 x ON x.grupo_b = g.id AND x.estado = 'APLICAR';
SET @grupos_removidos_db41 = ROW_COUNT();
UPDATE competicoes c
  INNER JOIN comp_db41 x ON x.comp_id = c.id AND x.estado = 'APLICAR'
   SET c.qtd_grupos = 1, c.classificados_por_grupo = 2, c.proxima_fase = 'FINAL';
SET @regras_mudadas_db41 = ROW_COUNT();

-- 8) Os jogos que ficam: número, dia, hora e local da 20268
UPDATE jogos j
  INNER JOIN alvo_db41 t ON t.jogo_id = j.id AND t.acao = 'ALTERAR' AND t.estado = 'APLICAR'
   SET j.numero_tabela = t.b, j.data_hora = t.dh_novo, j.local_id = t.local_novo_id;
SET @jogos_alterados_db41 = ROW_COUNT();

-- 9) Os jogos novos, no grupo A da competição
INSERT INTO jogos (competicao_id, numero_jogo, numero_tabela, fase, grupo_id, local_id, data_hora, equipe_1_id, equipe_2_id)
SELECT t.comp_id, 20000 + t.b, t.b, 'GRUPOS', x.grupo_a, t.local_novo_id, t.dh_novo, t.e1_id, t.e2_id
  FROM alvo_db41 t
  INNER JOIN comp_db41 x ON x.comp_id = t.comp_id
 WHERE t.acao = 'INCLUIR' AND t.estado = 'APLICAR';
SET @jogos_incluidos_db41 = ROW_COUNT();

-- 10) numero_jogo das três competições, fase 2: de 1 a N por data e hora
DROP TEMPORARY TABLE IF EXISTS ordem_db41;
CREATE TEMPORARY TABLE ordem_db41 (id INT NOT NULL PRIMARY KEY, nj INT NOT NULL);
INSERT INTO ordem_db41 (id, nj)
SELECT j.id, ROW_NUMBER() OVER (PARTITION BY j.competicao_id ORDER BY j.data_hora, j.numero_tabela)
  FROM jogos j
 WHERE j.competicao_id IN (SELECT x.comp_id FROM comp_db41 x WHERE x.estado = 'APLICAR');
UPDATE jogos j INNER JOIN ordem_db41 o ON o.id = j.id SET j.numero_jogo = o.nj;
SET @jogos_renumerados_db41 = ROW_COUNT();

-- 11) Rótulo "Vencedor do jogo N" com o número novo do jogo de origem
UPDATE jogo_vagas v
  INNER JOIN jogos jo ON jo.id = v.jogo_origem_id
   SET v.rotulo = CONCAT('Vencedor do jogo ', jo.numero_tabela)
 WHERE v.tipo = 'VENCEDOR' AND NOT (v.rotulo <=> CONCAT('Vencedor do jogo ', jo.numero_tabela));
SET @rotulos_db41 = ROW_COUNT();

-- ---------------------------------------------------------------------
-- Conferências
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS conferencia_db41;
CREATE TEMPORARY TABLE conferencia_db41 (
  item       VARCHAR(140) NOT NULL,
  esperado   INT          NOT NULL,
  encontrado INT          NOT NULL
);

INSERT INTO conferencia_db41 SELECT 'jogos de grupo (227)', 227, COUNT(*) FROM jogos WHERE fase = 'GRUPOS';
INSERT INTO conferencia_db41 SELECT 'jogos de mata-mata (73)', 73, COUNT(*) FROM jogos WHERE fase <> 'GRUPOS';
INSERT INTO conferencia_db41 SELECT '18/11: grupo (36)', 36, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-18';
INSERT INTO conferencia_db41 SELECT '18/11: mata-mata (0)', 0, COUNT(*) FROM jogos WHERE fase <> 'GRUPOS' AND DATE(data_hora) = '2026-11-18';
INSERT INTO conferencia_db41 SELECT '19/11: grupo (91)', 91, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-19';
INSERT INTO conferencia_db41 SELECT '19/11: mata-mata (0)', 0, COUNT(*) FROM jogos WHERE fase <> 'GRUPOS' AND DATE(data_hora) = '2026-11-19';
INSERT INTO conferencia_db41 SELECT '20/11: grupo (76)', 76, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-20';
INSERT INTO conferencia_db41 SELECT '20/11: mata-mata (9)', 9, COUNT(*) FROM jogos WHERE fase <> 'GRUPOS' AND DATE(data_hora) = '2026-11-20';
INSERT INTO conferencia_db41 SELECT '21/11: grupo (24)', 24, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-21';
INSERT INTO conferencia_db41 SELECT '21/11: mata-mata (64)', 64, COUNT(*) FROM jogos WHERE fase <> 'GRUPOS' AND DATE(data_hora) = '2026-11-21';
INSERT INTO conferencia_db41
SELECT 'jogo sem data ou fora de 18 a 21/11 (0)', 0, COUNT(*) FROM jogos
 WHERE data_hora IS NULL OR data_hora < '2026-11-18 00:00:00' OR data_hora >= '2026-11-22 00:00:00';
INSERT INTO conferencia_db41
SELECT 'numero_tabela repetido, vazio, fora de 1 a 302 ou 102/275 (0)', 0,
       (SELECT COUNT(*) FROM jogos WHERE numero_tabela IS NULL OR numero_tabela < 1 OR numero_tabela > 302 OR numero_tabela IN (102, 275))
     + (SELECT COUNT(*) FROM (SELECT numero_tabela FROM jogos GROUP BY numero_tabela HAVING COUNT(*) > 1) d);
INSERT INTO conferencia_db41
SELECT 'numero_jogo provisório que ficou (0)', 0, COUNT(*) FROM jogos WHERE numero_jogo >= 10000;
INSERT INTO conferencia_db41
SELECT 'equipe em dois jogos no mesmo dia e hora (0)', 0, COUNT(*)
  FROM (SELECT x.data_hora, x.equipe_id
          FROM (SELECT data_hora, equipe_1_id AS equipe_id FROM jogos
                UNION ALL SELECT data_hora, equipe_2_id FROM jogos) x
         WHERE x.equipe_id IS NOT NULL AND x.data_hora IS NOT NULL
         GROUP BY x.data_hora, x.equipe_id
        HAVING COUNT(*) > 1) d;
INSERT INTO conferencia_db41
SELECT 'jogos da 20268 no banco com número, dia, hora, local e equipes (300)', 300, COUNT(*)
  FROM alvo_db41 t
 WHERE t.acao <> 'REMOVER'
   AND (SELECT COUNT(*) FROM jogos j
          LEFT JOIN equipes q1 ON q1.id = j.equipe_1_id LEFT JOIN escolas s1 ON s1.id = q1.escola_id
          LEFT JOIN equipes q2 ON q2.id = j.equipe_2_id LEFT JOIN escolas s2 ON s2.id = q2.escola_id
         WHERE j.competicao_id = t.comp_id AND j.fase = t.fase AND j.numero_tabela = t.b
           AND j.data_hora = t.dh_novo AND j.local_id = t.local_novo_id
           AND (t.fase <> 'GRUPOS' OR (s1.nome = t.e1 AND s2.nome = t.e2) OR (s1.nome = t.e2 AND s2.nome = t.e1))) = 1;
INSERT INTO conferencia_db41
SELECT 'jogos no banco = jogos da 20268 (300)', 300, COUNT(*) FROM jogos;
INSERT INTO conferencia_db41
SELECT 'jogos que saem ainda no banco (0)', 0, COUNT(*) FROM jogos j INNER JOIN sai_db41 s ON s.jogo_id = j.id;
INSERT INTO conferencia_db41
SELECT 'vagas = antes - as 4 das semifinais que saem', @vagas_antes_db41 - 2 * (SELECT COUNT(*) FROM alvo_db41 WHERE acao = 'REMOVER' AND fase <> 'GRUPOS' AND estado = 'APLICAR'),
       COUNT(*) FROM jogo_vagas;
INSERT INTO conferencia_db41
SELECT 'equipes = antes - as da Emiliano', @equipes_antes_db41 - (SELECT COUNT(*) FROM equipe_db41 WHERE estado = 'APLICAR'), COUNT(*) FROM equipes;
INSERT INTO conferencia_db41
SELECT 'grupos = antes - os grupos B', @grupos_antes_db41 - (SELECT COUNT(*) FROM comp_db41 WHERE estado = 'APLICAR'), COUNT(*) FROM grupos;
INSERT INTO conferencia_db41
SELECT 'rótulo "Vencedor do jogo N" com número antigo (0)', 0, COUNT(*)
  FROM jogo_vagas v INNER JOIN jogos jo ON jo.id = v.jogo_origem_id
 WHERE v.tipo = 'VENCEDOR' AND NOT (v.rotulo <=> CONCAT('Vencedor do jogo ', jo.numero_tabela));
INSERT INTO conferencia_db41
SELECT 'vaga de grupo apontando para grupo de outra competição (0)', 0, COUNT(*)
  FROM jogo_vagas v INNER JOIN jogos j ON j.id = v.jogo_id INNER JOIN grupos g ON g.id = v.grupo_id
 WHERE v.tipo = 'GRUPO' AND g.competicao_id <> j.competicao_id;
-- As três competições
INSERT INTO conferencia_db41
SELECT CONCAT(x.modalidade, ' ', x.categoria, ' ', IF(x.genero = 'MISTO', 'Misto', LEFT(x.genero, 1)), ': grupo único, 2 classificados, FINAL (1)'), 1,
       (SELECT COUNT(*) FROM competicoes c WHERE c.id = x.comp_id AND c.qtd_grupos = 1 AND c.classificados_por_grupo = 2
           AND c.proxima_fase = 'FINAL' AND c.melhores_segundos = 0 AND c.turno = 'UNICO')
     * (SELECT CASE WHEN COUNT(*) = 1 AND MAX(g.nome) = 'A' THEN 1 ELSE 0 END FROM grupos g WHERE g.competicao_id = x.comp_id)
  FROM comp_db41 x;
INSERT INTO conferencia_db41
SELECT CONCAT(x.modalidade, ' ', x.categoria, ' ', IF(x.genero = 'MISTO', 'Misto', LEFT(x.genero, 1)), ': equipes no grupo A (', x.equipes_fim, ')'), x.equipes_fim,
       (SELECT COUNT(*) FROM equipes e WHERE e.competicao_id = x.comp_id AND e.grupo_id = x.grupo_a)
     + 100 * (SELECT COUNT(*) FROM equipes e WHERE e.competicao_id = x.comp_id AND NOT (e.grupo_id <=> x.grupo_a))
  FROM comp_db41 x;
INSERT INTO conferencia_db41
SELECT CONCAT(x.modalidade, ' ', x.categoria, ' ', IF(x.genero = 'MISTO', 'Misto', LEFT(x.genero, 1)), ': jogos de grupo no A (', x.grupo_fim, '), final (1), sem semifinal'),
       10 * x.grupo_fim + 1,
       10 * (SELECT COUNT(*) FROM jogos j WHERE j.competicao_id = x.comp_id AND j.fase = 'GRUPOS' AND j.grupo_id = x.grupo_a)
     + 100 * (SELECT COUNT(*) FROM jogos j WHERE j.competicao_id = x.comp_id AND j.fase = 'GRUPOS' AND NOT (j.grupo_id <=> x.grupo_a))
     + (SELECT COUNT(*) FROM jogos j WHERE j.competicao_id = x.comp_id AND j.fase = 'FINAL')
     + 1000 * (SELECT COUNT(*) FROM jogos j WHERE j.competicao_id = x.comp_id AND j.fase = 'SEMIFINAL')
  FROM comp_db41 x;
INSERT INTO conferencia_db41
SELECT CONCAT(x.modalidade, ' ', x.categoria, ' ', IF(x.genero = 'MISTO', 'Misto', LEFT(x.genero, 1)), ': final = 1º colocado x 2º colocado do A (2)'), 2,
       (SELECT COUNT(*) FROM jogos j INNER JOIN jogo_vagas v ON v.jogo_id = j.id
         WHERE j.competicao_id = x.comp_id AND j.fase = 'FINAL'
           AND v.tipo = 'GRUPO' AND v.grupo_id = x.grupo_a AND v.posicao = v.lado AND v.manual = 0
           AND v.rotulo = CONCAT(v.lado, 'º colocado') AND j.equipe_1_id IS NULL AND j.equipe_2_id IS NULL)
  FROM comp_db41 x;
INSERT INTO conferencia_db41
SELECT CONCAT(x.modalidade, ' ', x.categoria, ' ', IF(x.genero = 'MISTO', 'Misto', LEFT(x.genero, 1)), ': numero_jogo de 1 a N sem buraco (1)'), 1,
       (SELECT CASE WHEN MIN(j.numero_jogo) = 1 AND MAX(j.numero_jogo) = COUNT(*) THEN 1 ELSE 0 END
          FROM jogos j WHERE j.competicao_id = x.comp_id)
  FROM comp_db41 x;
INSERT INTO conferencia_db41
SELECT 'Emiliano Zapata no Baleado Sub 9 F e no Vôlei Sub 17 (0)', 0, COUNT(*)
  FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'EMILIANO ZAPATA'
 WHERE e.competicao_id IN (SELECT q.comp_id FROM equipe_db41 q);
INSERT INTO conferencia_db41
SELECT 'jogo de grupo com equipe de outro grupo, nas três (0)', 0, COUNT(*)
  FROM jogos j
  INNER JOIN equipes e1 ON e1.id = j.equipe_1_id
  INNER JOIN equipes e2 ON e2.id = j.equipe_2_id
 WHERE j.competicao_id IN (SELECT x.comp_id FROM comp_db41 x) AND j.fase = 'GRUPOS'
   AND NOT (e1.grupo_id <=> j.grupo_id AND e2.grupo_id <=> j.grupo_id);

SELECT item, esperado, encontrado, CASE WHEN esperado = encontrado THEN 'ok' ELSE 'DIVERGE' END AS situacao
  FROM conferencia_db41;

-- Trava 5: qualquer divergência para aqui, antes do COMMIT
DROP TEMPORARY TABLE IF EXISTS trava_conferencia_db41;
CREATE TEMPORARY TABLE trava_conferencia_db41 (
  item VARCHAR(140) NOT NULL,
  ok   TINYINT      NOT NULL,
  CONSTRAINT db41_conferencia_divergiu CHECK (ok = 1)
);
INSERT INTO trava_conferencia_db41 (item, ok)
SELECT item, CASE WHEN esperado = encontrado THEN 1 ELSE 0 END FROM conferencia_db41;
DROP TEMPORARY TABLE trava_conferencia_db41;
DROP TEMPORARY TABLE conferencia_db41;
DROP TEMPORARY TABLE ordem_db41;
DROP TEMPORARY TABLE equipe_db41;
DROP TEMPORARY TABLE sai_db41;
DROP TEMPORARY TABLE jogo_db41;

COMMIT;

-- ---------------------------------------------------------------------
-- Depois do COMMIT, só leitura
-- ---------------------------------------------------------------------
SELECT @vagas_finais_db41 AS vagas_das_finais, @jogos_removidos_db41 AS jogos_removidos,
       @jogos_alterados_db41 AS jogos_alterados, @jogos_incluidos_db41 AS jogos_incluidos,
       @equipes_movidas_db41 AS equipes_para_o_grupo_A, @jogos_movidos_db41 AS jogos_para_o_grupo_A,
       @equipes_removidas_db41 AS equipes_removidas, @grupos_removidos_db41 AS grupos_removidos,
       @regras_mudadas_db41 AS regras_mudadas, @jogos_renumerados_db41 AS numero_jogo_regravados,
       @rotulos_db41 AS rotulos_regravados;

-- As três competições: regra, equipes e jogos
SELECT CONCAT(m.nome, ' ', cat.nome, ' ', c.genero) AS competicao, c.qtd_grupos, c.classificados_por_grupo, c.proxima_fase
  FROM comp_db41 x
  INNER JOIN competicoes c ON c.id = x.comp_id
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id;
SELECT CONCAT(x.modalidade, ' ', x.categoria, ' ', x.genero) AS competicao, j.numero_jogo, j.numero_tabela, j.fase, g.nome AS grupo,
       DATE_FORMAT(j.data_hora, '%d/%m %H:%i') AS quando, l.nome AS local_,
       COALESCE(s1.nome, (SELECT v.rotulo FROM jogo_vagas v WHERE v.jogo_id = j.id AND v.lado = 1)) AS equipe_1,
       COALESCE(s2.nome, (SELECT v.rotulo FROM jogo_vagas v WHERE v.jogo_id = j.id AND v.lado = 2)) AS equipe_2
  FROM comp_db41 x
  INNER JOIN jogos j ON j.competicao_id = x.comp_id
  LEFT JOIN grupos g ON g.id = j.grupo_id
  LEFT JOIN locais_disputa l ON l.id = j.local_id
  LEFT JOIN equipes e1 ON e1.id = j.equipe_1_id LEFT JOIN escolas s1 ON s1.id = e1.escola_id
  LEFT JOIN equipes e2 ON e2.id = j.equipe_2_id LEFT JOIN escolas s2 ON s2.id = e2.escola_id
 ORDER BY x.modalidade, x.genero DESC, j.numero_jogo;

-- Aviso (não aborta): ESCOLA em dois jogos no mesmo dia e hora, envolvendo jogos que mudam ou entram
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
           FROM alvo_db41 t
           INNER JOIN jogos j2 ON j2.numero_tabela = t.b
           INNER JOIN equipes e2 ON e2.id IN (j2.equipe_1_id, j2.equipe_2_id)
          WHERE t.acao = 'INCLUIR' OR NOT (t.dh_antes <=> t.dh_novo))
 GROUP BY x.data_hora, s.id, s.nome
HAVING COUNT(*) > 1
 ORDER BY x.data_hora, s.nome;

-- Aviso (não aborta): ATLETA em dois jogos no mesmo dia e hora (inscrito nas
-- duas equipes), em toda a tabela. "mexido_pelo_db41" = um dos dois jogos entrou
-- ou mudou de dia/hora neste script. Só leitura: mostra nomes na tela, não grava.
DROP TEMPORARY TABLE IF EXISTS atleta_conflito_db41;
CREATE TEMPORARY TABLE atleta_conflito_db41 (
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
INSERT INTO atleta_conflito_db41 (atleta, escola, quando, nt_1, comp_1, local_1, nt_2, comp_2, local_2)
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
UPDATE atleta_conflito_db41 x SET x.mexido = 1
 WHERE x.nt_1 IN (SELECT t.b FROM alvo_db41 t WHERE t.acao = 'INCLUIR' OR NOT (t.dh_antes <=> t.dh_novo));
UPDATE atleta_conflito_db41 x SET x.mexido = 1
 WHERE x.nt_2 IN (SELECT t.b FROM alvo_db41 t WHERE t.acao = 'INCLUIR' OR NOT (t.dh_antes <=> t.dh_novo));

SELECT COUNT(*) AS atleta_em_dois_jogos_no_mesmo_horario, COALESCE(SUM(mexido), 0) AS mexido_pelo_db41
  FROM atleta_conflito_db41;
SELECT atleta, escola, DATE_FORMAT(quando, '%d/%m %H:%i') AS quando,
       CONCAT('nº ', nt_1, ' ', comp_1, ' (', COALESCE(local_1, 'sem local'), ')') AS jogo_1,
       CONCAT('nº ', nt_2, ' ', comp_2, ' (', COALESCE(local_2, 'sem local'), ')') AS jogo_2,
       IF(mexido = 1, 'sim', 'não') AS mexido_pelo_db41
  FROM atleta_conflito_db41
 ORDER BY quando, escola, atleta;
DROP TEMPORARY TABLE atleta_conflito_db41;

SELECT DATE_FORMAT(data_hora, '%d/%m') AS dia, SUM(fase = 'GRUPOS') AS grupo, SUM(fase <> 'GRUPOS') AS mata_mata, COUNT(*) AS total
  FROM jogos GROUP BY DATE_FORMAT(data_hora, '%d/%m') ORDER BY dia;

DROP TEMPORARY TABLE comp_db41;
DROP TEMPORARY TABLE alvo_db41;
