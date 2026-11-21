-- =====================================================================
-- MIGRAÇÃO 34 — Tabela de jogos 20266 do chefe (10/11/2026)
--
-- Aplica a TABELA DE JOGOS 20266 (substitui a 20265, que nunca foi aplicada) sobre
-- o que o db/26 a db/29 deixaram: 234 jogos de grupo e 75 de mata-mata viram
-- 231 de grupo e 75 de mata-mata (306 no total, numerados de 1 a 306).
-- Mapa jogo a jogo: docs/importacao/mapa_tabela_20266.csv (fora do git); os
-- valores estão escritos aqui e o script não lê arquivo nenhum.
--
--   26 MANTER (jogo 6 só muda a hora, ver abaixo), 204 ALTERAR de grupo e 75
--   ALTERAR de mata-mata (número e/ou dia, hora, local), 4 REMOVER e 1 INCLUIR.
--
-- REMOVEM-SE os jogos de grupo 33 (Handebol M Sub 9: a competição fica SEM nenhum
-- jogo, a confirmar com o chefe), 101 e 204 (Basquete F Sub 17, CETI x CEJA e
-- CEBC x CETI) e 189 (Handebol F Sub 17, CEBN x CEBC), e as vagas que dependam deles.
-- ENTRA o nº 102: Handebol F Sub 8, ACM x JOSE DIAS, 19/11 11:20, Quadra do CEBC,
-- ligado ao grupo da competição (que passa a ter o 102 e o 279).
-- O nº 173 -> 185 (Baleado F Sub 9) muda para a Quadra do CEJA. Vale a tabela 20266
-- em tudo, inclusive o jogo 6 às 18:50 (no banco está às 17:50: decisão de 10/11/2026).
-- Lucia Rocha x CETI do Baleado F Sub 17 = nº 244. A final do Basquete F Sub 17
-- (nº 289 -> 292) tem as equipes fixas CEJA x CEBC, com as duas vagas manuais
-- (manual = 1: o preenchimento automático não as desfaz).
--
-- O rótulo "Vencedor do jogo N" das vagas é REGRAVADO com o número novo do jogo de
-- origem (o jogo_origem_id não muda). O nº 226 da tabela (final do Handebol M
-- Sub 11) diz "173 x 173": o certo, e o que o banco tem, é 172 x 173.
--
-- Vôlei, jogos 116 -> 121 e 117 -> 122: só mudam de número, dia e hora. A troca de
-- COMPETIÇÃO (Masculino -> Misto) NÃO é feita aqui: o script apenas MOSTRA onde cada
-- um está hoje (competição, grupo e equipes). MASCULINO e MISTO contam como o mesmo gênero
-- na busca do jogo (o db/32 troca um pelo outro).
-- Rode DEPOIS do db/32 (ele confere os jogos 119, 170, 203 e 292 do Vôlei Aberto
-- pelos números de ANTES desta tabela).
--
-- COMPARAÇÃO COM O BANCO: cada jogo é achado NO BANCO sem usar o id da competição (que muda de
-- um banco para outro): quem muda ou fica, pela modalidade, categoria e gênero + numero_jogo (que o
-- script não muda); quem SAI, pelo numero_tabela atual + a mesma competição. O script lista o que
-- difere da coluna "atual" do mapa (dia, hora e local), em vez de confiar nela. Um REMOVER que não
-- acha o jogo conta como FEITO e, com o resto por aplicar, PARA em db34_estado_misto (nunca em silêncio).
--
-- IDEMPOTENTE: cada jogo é APLICAR (ainda como antes), FEITO (já como a tabela 20266
-- manda) ou IGUAL (nada muda). Estado misto entre os jogos que mudam PARA o script.
-- Rodado de novo, cai em FEITO e não grava nada.
--
-- SEGURANÇA: uma transação só. Quatro travas (CHECK em tabela temporária, erro
-- 3819 no MySQL e 4025 no MariaDB) param o script sem gravar nada:
--   db34_jogo_nao_bate           (antes de qualquer escrita: jogo não achado; jogo
--        que muda ou sai com placar, vencedor, súmula, set ou status diferente de
--        AGENDADO; mata-mata com a vaga já preenchida; local fora do cadastro)
--   db34_estado_misto            (antes de qualquer escrita)
--   db34_inclusao_ou_final_nao_batem (antes de qualquer escrita: a competição do
--        nº 102 com as duas equipes no mesmo grupo; a final com CEJA e CEBC)
--   db34_conferencia_divergiu    (antes do COMMIT)
-- No cliente mysql o erro encerra a sessão e a transação é desfeita. No
-- DBeaver, se um comando falhar, rode ROLLBACK antes de qualquer outra coisa.
--
-- Renumeração em 2 FASES por causa do índice único de numero_tabela: primeiro
-- +10000 em todos os jogos que mudam (grupo e mata-mata), depois o número novo.
-- O numero_jogo de cada competição NÃO é renumerado (ficam buracos, como nos db/24
-- e db/26); o nº 102 recebe o próximo numero_jogo da competição.
--
-- Só dados. Rode depois do 33. MySQL 8.0.16+ ou MariaDB 10.2+. Faça o dump do
-- banco antes, na produção. Não entra no banco de fumaça.
-- =====================================================================

SET NAMES utf8mb4;

START TRANSACTION;

-- Trava os jogos: nada muda no meio do script
SELECT COUNT(*) AS jogos_travados FROM jogos FOR UPDATE;

-- ---------------------------------------------------------------------
-- O plano (310 linhas) e o que foi achado em cada uma
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS alvo_db34;
CREATE TEMPORARY TABLE alvo_db34 (
  ordem          INT          NOT NULL,
  tipo           VARCHAR(5)   NOT NULL,   -- GRUPO ou MATA
  acao           VARCHAR(10)  NOT NULL,   -- MANTER, ALTERAR, REMOVER ou INCLUIR
  a              INT          NULL,       -- nº atual (numero_tabela)
  b              INT          NULL,       -- nº novo
  modalidade     VARCHAR(60)  NOT NULL,
  categoria      VARCHAR(20)  NOT NULL,
  dh_mapa        DATETIME     NULL,       -- dia e hora ATUAIS segundo o mapa
  dh_novo        DATETIME     NULL,
  local_esperado VARCHAR(80)  NULL,       -- local que o banco devia ter hoje
  local_novo     VARCHAR(80)  NULL,
  genero         VARCHAR(10)  NOT NULL,   -- gênero da competição (MASCULINO e MISTO contam como o mesmo: o db/32 troca um pelo outro)
  njogo          INT          NULL,       -- numero_jogo na competição: a identidade do jogo, que este script não muda
  n_achado       INT          NOT NULL DEFAULT 0,
  jt_num         INT          NULL,       -- numero_tabela, dia/hora e local que o jogo achado tem HOJE
  jt_dh          DATETIME     NULL,
  jt_local       VARCHAR(80)  NULL,
  jogo_id        INT          NULL,
  local_ok       TINYINT      NOT NULL DEFAULT 1,
  sujo           INT          NOT NULL DEFAULT 0,   -- status, placar, súmula ou set
  vaga_cheia     INT          NOT NULL DEFAULT 0,   -- mata-mata com equipe já na vaga
  estado         VARCHAR(10)  NOT NULL DEFAULT ''   -- APLICAR, FEITO ou IGUAL
);

INSERT INTO alvo_db34 (ordem, tipo, acao, a, b, modalidade, categoria, genero, dh_mapa, dh_novo, local_esperado, local_novo, njogo) VALUES
  (  1, 'GRUPO', 'MANTER', 1, 1, 'Baleado', 'Sub 11', 'MASCULINO', '2026-11-18 14:30:00', '2026-11-18 14:30:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 1),
  (  2, 'GRUPO', 'MANTER', 2, 2, 'Baleado', 'Sub 13', 'MASCULINO', '2026-11-18 15:10:00', '2026-11-18 15:10:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 1),
  (  3, 'GRUPO', 'MANTER', 3, 3, 'Baleado', 'Sub 13', 'FEMININO', '2026-11-18 15:50:00', '2026-11-18 15:50:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 3),
  (  4, 'GRUPO', 'MANTER', 4, 4, 'Handebol', 'Sub 17', 'FEMININO', '2026-11-18 16:30:00', '2026-11-18 16:30:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 1),
  (  5, 'GRUPO', 'MANTER', 5, 5, 'Baleado', 'Sub 17', 'MASCULINO', '2026-11-18 17:10:00', '2026-11-18 17:10:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 1),
  (  6, 'GRUPO', 'MANTER', 6, 6, 'Futsal', 'Aberto', 'MASCULINO', '2026-11-18 18:50:00', '2026-11-18 18:50:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 1),
  (  7, 'GRUPO', 'MANTER', 7, 7, 'Futsal', 'Sub 17', 'MASCULINO', '2026-11-18 18:30:00', '2026-11-18 18:30:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 3),
  (  8, 'GRUPO', 'MANTER', 8, 8, 'Futsal', 'Sub 17', 'MASCULINO', '2026-11-18 19:20:00', '2026-11-18 19:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 4),
  (  9, 'GRUPO', 'MANTER', 9, 9, 'Futsal', 'Aberto', 'MASCULINO', '2026-11-18 20:00:00', '2026-11-18 20:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 2),
  ( 10, 'GRUPO', 'MANTER', 10, 10, 'Futsal', 'Aberto', 'MASCULINO', '2026-11-18 20:40:00', '2026-11-18 20:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 3),
  ( 11, 'GRUPO', 'MANTER', 11, 11, 'Baleado', 'Sub 11', 'MASCULINO', '2026-11-18 14:30:00', '2026-11-18 14:30:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 2),
  ( 12, 'GRUPO', 'MANTER', 12, 12, 'Baleado', 'Sub 13', 'MASCULINO', '2026-11-18 15:10:00', '2026-11-18 15:10:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 2),
  ( 13, 'GRUPO', 'ALTERAR', 14, 13, 'Handebol', 'Sub 11', 'MASCULINO', '2026-11-18 16:30:00', '2026-11-18 15:50:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 2),
  ( 14, 'GRUPO', 'ALTERAR', 13, 14, 'Handebol', 'Sub 11', 'MASCULINO', '2026-11-18 15:50:00', '2026-11-18 16:30:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 1),
  ( 15, 'GRUPO', 'MANTER', 15, 15, 'Baleado', 'Sub 9', 'MASCULINO', '2026-11-18 14:20:00', '2026-11-18 14:20:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 1),
  ( 16, 'GRUPO', 'MANTER', 16, 16, 'Baleado', 'Sub 9', 'MASCULINO', '2026-11-18 14:40:00', '2026-11-18 14:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 2),
  ( 17, 'GRUPO', 'MANTER', 17, 17, 'Baleado', 'Sub 13', 'FEMININO', '2026-11-18 15:20:00', '2026-11-18 15:20:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 1),
  ( 18, 'GRUPO', 'MANTER', 18, 18, 'Baleado', 'Sub 13', 'FEMININO', '2026-11-18 15:40:00', '2026-11-18 15:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 2),
  ( 19, 'GRUPO', 'MANTER', 19, 19, 'Baleado', 'Sub 13', 'FEMININO', '2026-11-18 16:00:00', '2026-11-18 16:00:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 4),
  ( 20, 'GRUPO', 'MANTER', 20, 20, 'Baleado', 'Sub 13', 'MASCULINO', '2026-11-18 16:20:00', '2026-11-18 16:20:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 3),
  ( 21, 'GRUPO', 'MANTER', 21, 21, 'Handebol', 'Sub 13', 'MASCULINO', '2026-11-18 16:40:00', '2026-11-18 16:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 1),
  ( 22, 'GRUPO', 'ALTERAR', 22, 22, 'Futsal', 'Sub 15', 'MASCULINO', '2026-11-18 14:30:00', '2026-11-18 14:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 1),
  ( 23, 'GRUPO', 'ALTERAR', 23, 23, 'Futsal', 'Sub 15', 'MASCULINO', '2026-11-18 15:10:00', '2026-11-18 14:40:00', 'Quadra do CEJA', 'Quadra do CEJA', 2),
  ( 24, 'GRUPO', 'ALTERAR', 24, 24, 'Futsal', 'Sub 17', 'MASCULINO', '2026-11-18 15:50:00', '2026-11-18 15:30:00', 'Quadra do CEJA', 'Quadra do CEJA', 1),
  ( 25, 'GRUPO', 'ALTERAR', 25, 25, 'Futsal', 'Sub 17', 'MASCULINO', '2026-11-18 16:30:00', '2026-11-18 16:10:00', 'Quadra do CEJA', 'Quadra do CEJA', 2),
  ( 26, 'GRUPO', 'MANTER', 26, 26, 'Futsal', 'Sub 7', 'MASCULINO', '2026-11-18 14:30:00', '2026-11-18 14:30:00', 'Quadra do CETI', 'Quadra do CETI', 1),
  ( 27, 'GRUPO', 'MANTER', 27, 27, 'Futsal', 'Sub 9', 'MASCULINO', '2026-11-18 15:10:00', '2026-11-18 15:10:00', 'Quadra do CETI', 'Quadra do CETI', 2),
  ( 28, 'GRUPO', 'MANTER', 28, 28, 'Futsal', 'Sub 9', 'MASCULINO', '2026-11-18 15:50:00', '2026-11-18 15:50:00', 'Quadra do CETI', 'Quadra do CETI', 1),
  ( 29, 'GRUPO', 'MANTER', 29, 29, 'Futsal', 'Sub 7', 'MASCULINO', '2026-11-18 16:30:00', '2026-11-18 16:30:00', 'Quadra do CETI', 'Quadra do CETI', 2),
  ( 30, 'GRUPO', 'MANTER', 30, 30, 'Futsal', 'Sub 11', 'MASCULINO', '2026-11-18 14:30:00', '2026-11-18 14:30:00', 'Quadra do CEBC', 'Quadra do CEBC', 1),
  ( 31, 'GRUPO', 'MANTER', 31, 31, 'Futsal', 'Sub 11', 'MASCULINO', '2026-11-18 15:10:00', '2026-11-18 15:10:00', 'Quadra do CEBC', 'Quadra do CEBC', 2),
  ( 32, 'GRUPO', 'MANTER', 32, 32, 'Futsal', 'Sub 11', 'MASCULINO', '2026-11-18 15:50:00', '2026-11-18 15:50:00', 'Quadra do CEBC', 'Quadra do CEBC', 3),
  ( 33, 'GRUPO', 'ALTERAR', 34, 33, 'Basquete', 'Sub 15', 'FEMININO', '2026-11-18 17:10:00', '2026-11-18 16:30:00', 'Quadra do CEBC', 'Quadra do CEBC', 1),
  ( 34, 'GRUPO', 'ALTERAR', 35, 34, 'Futebol Society', 'Sub 15', 'MASCULINO', '2026-11-18 15:00:00', '2026-11-18 15:00:00', 'Campo Society Arena Social', 'Campo Society Arena Social', 1),
  ( 35, 'GRUPO', 'ALTERAR', 36, 35, 'Futebol Society', 'Sub 15', 'MASCULINO', '2026-11-18 15:40:00', '2026-11-18 15:40:00', 'Campo Society Arena Social', 'Campo Society Arena Social', 6),
  ( 36, 'GRUPO', 'ALTERAR', 37, 36, 'Futebol Society', 'Sub 17', 'MASCULINO', '2026-11-18 16:20:00', '2026-11-18 16:20:00', 'Campo Society Arena Social', 'Campo Society Arena Social', 1),
  ( 37, 'GRUPO', 'ALTERAR', 38, 37, 'Baleado', 'Sub 11', 'MASCULINO', '2026-11-19 08:00:00', '2026-11-19 08:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 3),
  ( 38, 'GRUPO', 'ALTERAR', 39, 38, 'Baleado', 'Sub 11', 'MASCULINO', '2026-11-19 08:40:00', '2026-11-19 08:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 4),
  ( 39, 'GRUPO', 'ALTERAR', 40, 39, 'Baleado', 'Sub 13', 'MASCULINO', '2026-11-19 09:20:00', '2026-11-19 09:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 4),
  ( 40, 'GRUPO', 'ALTERAR', 41, 40, 'Baleado', 'Sub 13', 'MASCULINO', '2026-11-19 10:00:00', '2026-11-19 10:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 5),
  ( 41, 'GRUPO', 'ALTERAR', 42, 41, 'Futsal', 'Sub 17', 'FEMININO', '2026-11-19 10:40:00', '2026-11-19 10:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 1),
  ( 42, 'GRUPO', 'ALTERAR', 43, 42, 'Futsal', 'Sub 15', 'MASCULINO', '2026-11-19 11:20:00', '2026-11-19 11:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 8),
  ( 43, 'GRUPO', 'ALTERAR', 44, 43, 'Futsal', 'Sub 15', 'MASCULINO', '2026-11-19 12:00:00', '2026-11-19 12:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 5),
  ( 44, 'GRUPO', 'ALTERAR', 45, 44, 'Futsal', 'Sub 13', 'MASCULINO', '2026-11-19 12:40:00', '2026-11-19 12:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 1),
  ( 45, 'GRUPO', 'ALTERAR', 46, 45, 'Futsal', 'Sub 13', 'MASCULINO', '2026-11-19 13:20:00', '2026-11-19 13:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 2),
  ( 46, 'GRUPO', 'ALTERAR', 47, 46, 'Futsal', 'Sub 13', 'MASCULINO', '2026-11-19 14:00:00', '2026-11-19 14:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 3),
  ( 47, 'GRUPO', 'ALTERAR', 48, 47, 'Baleado', 'Sub 11', 'MASCULINO', '2026-11-19 14:40:00', '2026-11-19 14:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 5),
  ( 48, 'GRUPO', 'ALTERAR', 49, 48, 'Baleado', 'Sub 13', 'MASCULINO', '2026-11-19 15:20:00', '2026-11-19 15:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 7),
  ( 49, 'GRUPO', 'ALTERAR', 51, 49, 'Baleado', 'Sub 17', 'FEMININO', '2026-11-19 16:40:00', '2026-11-19 16:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 1),
  ( 50, 'GRUPO', 'ALTERAR', 52, 50, 'Handebol', 'Aberto', 'MASCULINO', '2026-11-19 17:20:00', '2026-11-19 16:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 1),
  ( 51, 'GRUPO', 'ALTERAR', 50, 51, 'Baleado', 'Sub 13', 'MASCULINO', '2026-11-19 16:00:00', '2026-11-19 17:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 8),
  ( 52, 'GRUPO', 'ALTERAR', 53, 52, 'Futsal', 'Aberto', 'MASCULINO', '2026-11-19 18:00:00', '2026-11-19 18:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 4),
  ( 53, 'GRUPO', 'ALTERAR', 54, 53, 'Futsal', 'Aberto', 'FEMININO', '2026-11-19 18:40:00', '2026-11-19 18:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 1),
  ( 54, 'GRUPO', 'ALTERAR', 55, 54, 'Futsal', 'Sub 17', 'MASCULINO', '2026-11-19 19:20:00', '2026-11-19 19:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 8),
  ( 55, 'GRUPO', 'ALTERAR', 56, 55, 'Futsal', 'Aberto', 'MASCULINO', '2026-11-19 20:00:00', '2026-11-19 20:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 5),
  ( 56, 'GRUPO', 'ALTERAR', 57, 56, 'Futsal', 'Aberto', 'MASCULINO', '2026-11-19 20:40:00', '2026-11-19 20:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 6),
  ( 57, 'GRUPO', 'ALTERAR', 58, 57, 'Baleado', 'Sub 13', 'FEMININO', '2026-11-19 08:00:00', '2026-11-19 08:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 5),
  ( 58, 'GRUPO', 'ALTERAR', 59, 58, 'Baleado', 'Sub 13', 'FEMININO', '2026-11-19 08:40:00', '2026-11-19 08:40:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 6),
  ( 59, 'GRUPO', 'ALTERAR', 60, 59, 'Baleado', 'Sub 13', 'FEMININO', '2026-11-19 09:20:00', '2026-11-19 09:20:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 7),
  ( 60, 'GRUPO', 'ALTERAR', 61, 60, 'Handebol', 'Sub 11', 'MASCULINO', '2026-11-19 10:00:00', '2026-11-19 10:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 3),
  ( 61, 'GRUPO', 'ALTERAR', 62, 61, 'Handebol', 'Sub 11', 'MASCULINO', '2026-11-19 10:40:00', '2026-11-19 10:40:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 4),
  ( 62, 'GRUPO', 'ALTERAR', 63, 62, 'Futsal', 'Sub 13', 'FEMININO', '2026-11-19 11:20:00', '2026-11-19 11:20:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 1),
  ( 63, 'GRUPO', 'ALTERAR', 64, 63, 'Futsal', 'Sub 15', 'FEMININO', '2026-11-19 12:00:00', '2026-11-19 12:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 1),
  ( 64, 'GRUPO', 'ALTERAR', 65, 64, 'Futsal', 'Sub 15', 'FEMININO', '2026-11-19 12:40:00', '2026-11-19 12:40:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 2),
  ( 65, 'GRUPO', 'ALTERAR', 66, 65, 'Futsal', 'Sub 11', 'MASCULINO', '2026-11-19 13:20:00', '2026-11-19 13:20:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 8),
  ( 66, 'GRUPO', 'ALTERAR', 67, 66, 'Handebol', 'Sub 13', 'MASCULINO', '2026-11-19 14:00:00', '2026-11-19 14:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 3),
  ( 67, 'GRUPO', 'ALTERAR', 69, 67, 'Handebol', 'Sub 11', 'FEMININO', '2026-11-19 15:20:00', '2026-11-19 14:40:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 1),
  ( 68, 'GRUPO', 'ALTERAR', 70, 68, 'Handebol', 'Sub 11', 'FEMININO', '2026-11-19 16:00:00', '2026-11-19 15:20:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 2),
  ( 69, 'GRUPO', 'ALTERAR', 68, 69, 'Handebol', 'Sub 8', 'MASCULINO', '2026-11-19 14:40:00', '2026-11-19 16:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 1),
  ( 70, 'GRUPO', 'ALTERAR', 71, 70, 'Futsal', 'Sub 9', 'MASCULINO', '2026-11-19 08:00:00', '2026-11-19 08:00:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 3),
  ( 71, 'GRUPO', 'ALTERAR', 72, 71, 'Futsal', 'Sub 9', 'MASCULINO', '2026-11-19 08:40:00', '2026-11-19 08:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 4),
  ( 72, 'GRUPO', 'ALTERAR', 73, 72, 'Baleado', 'Sub 17', 'MASCULINO', '2026-11-19 09:20:00', '2026-11-19 09:20:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 2),
  ( 73, 'GRUPO', 'ALTERAR', 74, 73, 'Baleado', 'Sub 13', 'MASCULINO', '2026-11-19 10:00:00', '2026-11-19 10:00:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 6),
  ( 74, 'GRUPO', 'ALTERAR', 75, 74, 'Baleado', 'Sub 15', 'MASCULINO', '2026-11-19 10:40:00', '2026-11-19 10:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 1),
  ( 75, 'GRUPO', 'ALTERAR', 76, 75, 'Baleado', 'Sub 15', 'MASCULINO', '2026-11-19 11:20:00', '2026-11-19 11:20:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 2),
  ( 76, 'GRUPO', 'ALTERAR', 77, 76, 'Baleado', 'Sub 9', 'MASCULINO', '2026-11-19 12:00:00', '2026-11-19 12:00:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 3),
  ( 77, 'GRUPO', 'ALTERAR', 78, 77, 'Futsal', 'Sub 17', 'FEMININO', '2026-11-19 12:40:00', '2026-11-19 12:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 2),
  ( 78, 'GRUPO', 'ALTERAR', 79, 78, 'Futsal', 'Sub 13', 'FEMININO', '2026-11-19 13:20:00', '2026-11-19 13:20:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 2),
  ( 79, 'GRUPO', 'ALTERAR', 80, 79, 'Futsal', 'Sub 9', 'MASCULINO', '2026-11-19 14:00:00', '2026-11-19 14:00:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 5),
  ( 80, 'GRUPO', 'ALTERAR', 81, 80, 'Futsal', 'Sub 9', 'MASCULINO', '2026-11-19 14:40:00', '2026-11-19 14:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 6),
  ( 81, 'GRUPO', 'ALTERAR', 82, 81, 'Baleado', 'Sub 13', 'FEMININO', '2026-11-19 15:20:00', '2026-11-19 15:20:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 8),
  ( 82, 'GRUPO', 'ALTERAR', 83, 82, 'Baleado', 'Sub 13', 'FEMININO', '2026-11-19 16:00:00', '2026-11-19 16:00:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 9),
  ( 83, 'GRUPO', 'ALTERAR', 84, 83, 'Baleado', 'Sub 13', 'FEMININO', '2026-11-19 16:40:00', '2026-11-19 16:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 10),
  ( 84, 'GRUPO', 'ALTERAR', 85, 84, 'Futsal', 'Sub 11', 'MASCULINO', '2026-11-19 08:00:00', '2026-11-19 08:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 4),
  ( 85, 'GRUPO', 'ALTERAR', 86, 85, 'Futsal', 'Sub 11', 'MASCULINO', '2026-11-19 08:40:00', '2026-11-19 08:40:00', 'Quadra do CEJA', 'Quadra do CEJA', 5),
  ( 86, 'GRUPO', 'ALTERAR', 87, 86, 'Futsal', 'Sub 17', 'MASCULINO', '2026-11-19 09:20:00', '2026-11-19 09:20:00', 'Quadra do CEJA', 'Quadra do CEJA', 5),
  ( 87, 'GRUPO', 'ALTERAR', 94, 87, 'Baleado', 'Sub 11', 'FEMININO', '2026-11-19 14:00:00', '2026-11-19 10:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 3),
  ( 88, 'GRUPO', 'ALTERAR', 88, 88, 'Futsal', 'Sub 17', 'MASCULINO', '2026-11-19 10:00:00', '2026-11-19 10:40:00', 'Quadra do CEJA', 'Quadra do CEJA', 6),
  ( 89, 'GRUPO', 'ALTERAR', 89, 89, 'Futsal', 'Sub 17', 'MASCULINO', '2026-11-19 10:40:00', '2026-11-19 11:20:00', 'Quadra do CEJA', 'Quadra do CEJA', 7),
  ( 90, 'GRUPO', 'ALTERAR', 90, 90, 'Baleado', 'Sub 15', 'FEMININO', '2026-11-19 11:20:00', '2026-11-19 12:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 1),
  ( 91, 'GRUPO', 'ALTERAR', 91, 91, 'Baleado', 'Sub 15', 'FEMININO', '2026-11-19 12:00:00', '2026-11-19 12:40:00', 'Quadra do CEJA', 'Quadra do CEJA', 2),
  ( 92, 'GRUPO', 'ALTERAR', 92, 92, 'Baleado', 'Sub 11', 'FEMININO', '2026-11-19 12:40:00', '2026-11-19 13:20:00', 'Quadra do CEJA', 'Quadra do CEJA', 1),
  ( 93, 'GRUPO', 'ALTERAR', 93, 93, 'Baleado', 'Sub 11', 'FEMININO', '2026-11-19 13:20:00', '2026-11-19 14:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 2),
  ( 94, 'GRUPO', 'ALTERAR', 95, 94, 'Baleado', 'Sub 11', 'FEMININO', '2026-11-19 14:40:00', '2026-11-19 14:40:00', 'Quadra do CEJA', 'Quadra do CEJA', 4),
  ( 95, 'GRUPO', 'ALTERAR', 96, 95, 'Handebol', 'Sub 13', 'MASCULINO', '2026-11-19 15:20:00', '2026-11-19 15:20:00', 'Quadra do CEJA', 'Quadra do CEJA', 4),
  ( 96, 'GRUPO', 'ALTERAR', 97, 96, 'Handebol', 'Sub 15', 'MASCULINO', '2026-11-19 16:00:00', '2026-11-19 16:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 1),
  ( 97, 'GRUPO', 'ALTERAR', 109, 97, 'Handebol', 'Sub 17', 'FEMININO', '2026-11-19 15:20:00', '2026-11-19 08:00:00', 'Quadra do CEBC', 'Quadra do CEBC', 2),
  ( 98, 'GRUPO', 'ALTERAR', 106, 98, 'Handebol', 'Sub 13', 'MASCULINO', '2026-11-19 13:20:00', '2026-11-19 08:40:00', 'Quadra do CEBC', 'Quadra do CEBC', 2),
  ( 99, 'GRUPO', 'ALTERAR', 98, 99, 'Handebol', 'Sub 9', 'FEMININO', '2026-11-19 08:00:00', '2026-11-19 09:20:00', 'Quadra do CEBC', 'Quadra do CEBC', 1),
  (100, 'GRUPO', 'ALTERAR', 99, 100, 'Futsal', 'Sub 15', 'MASCULINO', '2026-11-19 08:40:00', '2026-11-19 10:00:00', 'Quadra do CEBC', 'Quadra do CEBC', 3),
  (101, 'GRUPO', 'ALTERAR', 100, 101, 'Basquete', 'Sub 15', 'FEMININO', '2026-11-19 09:20:00', '2026-11-19 10:40:00', 'Quadra do CEBC', 'Quadra do CEBC', 2),
  (102, 'GRUPO', 'ALTERAR', 102, 103, 'Basquete', 'Sub 15', 'MASCULINO', '2026-11-19 10:40:00', '2026-11-19 12:00:00', 'Quadra do CEBC', 'Quadra do CEBC', 3),
  (103, 'GRUPO', 'ALTERAR', 103, 104, 'Basquete', 'Sub 17', 'MASCULINO', '2026-11-19 11:20:00', '2026-11-19 12:40:00', 'Quadra do CEBC', 'Quadra do CEBC', 1),
  (104, 'GRUPO', 'ALTERAR', 104, 105, 'Futsal', 'Sub 11', 'MASCULINO', '2026-11-19 12:00:00', '2026-11-19 13:20:00', 'Quadra do CEBC', 'Quadra do CEBC', 6),
  (105, 'GRUPO', 'ALTERAR', 105, 106, 'Futsal', 'Sub 11', 'MASCULINO', '2026-11-19 12:40:00', '2026-11-19 14:00:00', 'Quadra do CEBC', 'Quadra do CEBC', 7),
  (106, 'GRUPO', 'ALTERAR', 107, 107, 'Handebol', 'Sub 17', 'MASCULINO', '2026-11-19 14:00:00', '2026-11-19 14:40:00', 'Quadra do CEBC', 'Quadra do CEBC', 1),
  (107, 'GRUPO', 'ALTERAR', 108, 108, 'Handebol', 'Sub 17', 'MASCULINO', '2026-11-19 14:40:00', '2026-11-19 15:20:00', 'Quadra do CEBC', 'Quadra do CEBC', 2),
  (108, 'GRUPO', 'ALTERAR', 110, 109, 'Handebol', 'Sub 13', 'FEMININO', '2026-11-19 16:00:00', '2026-11-19 16:00:00', 'Quadra do CEBC', 'Quadra do CEBC', 1),
  (109, 'GRUPO', 'ALTERAR', 111, 110, 'Basquete', 'Sub 17', 'MASCULINO', '2026-11-19 16:40:00', '2026-11-19 16:40:00', 'Quadra do CEBC', 'Quadra do CEBC', 2),
  (110, 'GRUPO', 'ALTERAR', 112, 111, 'Futsal', 'Sub 9', 'FEMININO', '2026-11-19 08:00:00', '2026-11-19 08:00:00', 'Quadra do CETI', 'Quadra do CETI', 1),
  (111, 'GRUPO', 'ALTERAR', 113, 112, 'Futsal', 'Sub 7', 'MASCULINO', '2026-11-19 08:40:00', '2026-11-19 08:40:00', 'Quadra do CETI', 'Quadra do CETI', 3),
  (112, 'GRUPO', 'ALTERAR', 114, 113, 'Futsal', 'Sub 7', 'MASCULINO', '2026-11-19 09:20:00', '2026-11-19 09:20:00', 'Quadra do CETI', 'Quadra do CETI', 4),
  (113, 'GRUPO', 'ALTERAR', 115, 114, 'Vôlei', 'Sub 17', 'MISTO', '2026-11-19 10:00:00', '2026-11-19 10:00:00', 'Quadra do CETI', 'Quadra do CETI', 1),
  (114, 'GRUPO', 'ALTERAR', 119, 115, 'Vôlei', 'Aberto', 'MASCULINO', '2026-11-19 12:40:00', '2026-11-19 10:40:00', 'Quadra do CETI', 'Quadra do CETI', 1),
  (115, 'GRUPO', 'ALTERAR', 120, 116, 'Vôlei', 'Sub 15', 'MISTO', '2026-11-19 13:20:00', '2026-11-19 11:20:00', 'Quadra do CETI', 'Quadra do CETI', 2),
  (116, 'GRUPO', 'ALTERAR', 121, 117, 'Futsal', 'Sub 8', 'MASCULINO', '2026-11-19 14:00:00', '2026-11-19 12:00:00', 'Quadra do CETI', 'Quadra do CETI', 1),
  (117, 'GRUPO', 'ALTERAR', 122, 118, 'Futsal', 'Sub 8', 'MASCULINO', '2026-11-19 14:40:00', '2026-11-19 12:40:00', 'Quadra do CETI', 'Quadra do CETI', 2),
  (118, 'GRUPO', 'ALTERAR', 123, 119, 'Futsal', 'Sub 8', 'FEMININO', '2026-11-19 15:20:00', '2026-11-19 13:20:00', 'Quadra do CETI', 'Quadra do CETI', 1),
  (119, 'GRUPO', 'ALTERAR', 124, 120, 'Futsal', 'Sub 11', 'FEMININO', '2026-11-19 16:00:00', '2026-11-19 14:00:00', 'Quadra do CETI', 'Quadra do CETI', 1),
  (120, 'GRUPO', 'ALTERAR', 116, 121, 'Vôlei', 'Sub 15', 'MISTO', '2026-11-19 10:40:00', '2026-11-19 14:40:00', 'Quadra do CETI', 'Quadra do CETI', 1),
  (121, 'GRUPO', 'ALTERAR', 117, 122, 'Vôlei', 'Sub 17', 'MISTO', '2026-11-19 11:20:00', '2026-11-19 15:20:00', 'Quadra do CETI', 'Quadra do CETI', 2),
  (122, 'GRUPO', 'ALTERAR', 118, 123, 'Vôlei', 'Sub 17', 'MISTO', '2026-11-19 12:00:00', '2026-11-19 16:00:00', 'Quadra do CETI', 'Quadra do CETI', 3),
  (123, 'GRUPO', 'ALTERAR', 125, 124, 'Futebol Society', 'Sub 13', 'MASCULINO', '2026-11-19 08:30:00', '2026-11-19 08:30:00', 'Campo Society Arena Social', 'Campo Society Arena Social', 1),
  (124, 'GRUPO', 'ALTERAR', 126, 125, 'Futebol Society', 'Sub 17', 'MASCULINO', '2026-11-19 09:10:00', '2026-11-19 09:10:00', 'Campo Society Arena Social', 'Campo Society Arena Social', 2),
  (125, 'GRUPO', 'ALTERAR', 127, 126, 'Futebol Society', 'Sub 15', 'MASCULINO', '2026-11-19 09:50:00', '2026-11-19 09:50:00', 'Campo Society Arena Social', 'Campo Society Arena Social', 3),
  (126, 'GRUPO', 'ALTERAR', 128, 127, 'Futebol Society', 'Sub 15', 'MASCULINO', '2026-11-19 14:00:00', '2026-11-19 14:00:00', 'Campo Society Arena Social', 'Campo Society Arena Social', 4),
  (127, 'GRUPO', 'ALTERAR', 129, 128, 'Futebol Society', 'Sub 13', 'MASCULINO', '2026-11-19 14:40:00', '2026-11-19 14:40:00', 'Campo Society Arena Social', 'Campo Society Arena Social', 2),
  (128, 'GRUPO', 'ALTERAR', 130, 129, 'Futebol Society', 'Sub 17', 'MASCULINO', '2026-11-19 15:20:00', '2026-11-19 15:20:00', 'Campo Society Arena Social', 'Campo Society Arena Social', 3),
  (129, 'GRUPO', 'ALTERAR', 131, 130, 'Baleado', 'Sub 11', 'MASCULINO', '2026-11-20 08:00:00', '2026-11-20 08:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 6),
  (130, 'GRUPO', 'ALTERAR', 132, 131, 'Baleado', 'Sub 11', 'MASCULINO', '2026-11-20 08:40:00', '2026-11-20 08:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 7),
  (131, 'GRUPO', 'ALTERAR', 133, 132, 'Handebol', 'Sub 11', 'MASCULINO', '2026-11-20 09:20:00', '2026-11-20 09:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 5),
  (132, 'GRUPO', 'ALTERAR', 134, 133, 'Handebol', 'Sub 11', 'MASCULINO', '2026-11-20 10:00:00', '2026-11-20 10:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 6),
  (133, 'GRUPO', 'ALTERAR', 135, 134, 'Futsal', 'Sub 13', 'MASCULINO', '2026-11-20 10:40:00', '2026-11-20 10:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 4),
  (134, 'GRUPO', 'ALTERAR', 136, 135, 'Futsal', 'Sub 13', 'MASCULINO', '2026-11-20 11:20:00', '2026-11-20 11:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 5),
  (135, 'GRUPO', 'ALTERAR', 137, 136, 'Futsal', 'Sub 17', 'FEMININO', '2026-11-20 12:00:00', '2026-11-20 12:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 3),
  (136, 'GRUPO', 'ALTERAR', 138, 137, 'Futsal', 'Sub 17', 'FEMININO', '2026-11-20 12:40:00', '2026-11-20 12:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 4),
  (137, 'GRUPO', 'ALTERAR', 139, 138, 'Baleado', 'Sub 13', 'MASCULINO', '2026-11-20 13:20:00', '2026-11-20 13:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 9),
  (138, 'GRUPO', 'ALTERAR', 140, 139, 'Handebol', 'Aberto', 'MASCULINO', '2026-11-20 14:40:00', '2026-11-20 14:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 2),
  (139, 'GRUPO', 'ALTERAR', 141, 140, 'Baleado', 'Sub 15', 'FEMININO', '2026-11-20 15:20:00', '2026-11-20 15:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 3),
  (140, 'GRUPO', 'ALTERAR', 142, 141, 'Baleado', 'Sub 15', 'FEMININO', '2026-11-20 16:00:00', '2026-11-20 16:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 4),
  (141, 'GRUPO', 'ALTERAR', 143, 142, 'Handebol', 'Sub 17', 'MASCULINO', '2026-11-20 16:40:00', '2026-11-20 16:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 3),
  (142, 'GRUPO', 'ALTERAR', 144, 143, 'Handebol', 'Sub 17', 'MASCULINO', '2026-11-20 17:20:00', '2026-11-20 17:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 4),
  (143, 'GRUPO', 'ALTERAR', 145, 144, 'Futsal', 'Aberto', 'FEMININO', '2026-11-20 18:00:00', '2026-11-20 18:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 2),
  (144, 'GRUPO', 'ALTERAR', 150, 149, 'Handebol', 'Sub 11', 'FEMININO', '2026-11-20 08:00:00', '2026-11-20 08:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 3),
  (145, 'GRUPO', 'ALTERAR', 151, 150, 'Futsal', 'Sub 11', 'MASCULINO', '2026-11-20 08:40:00', '2026-11-20 08:40:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 9),
  (146, 'GRUPO', 'ALTERAR', 152, 151, 'Futsal', 'Sub 9', 'MASCULINO', '2026-11-20 09:20:00', '2026-11-20 09:20:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 7),
  (147, 'GRUPO', 'ALTERAR', 153, 152, 'Futsal', 'Sub 9', 'MASCULINO', '2026-11-20 10:00:00', '2026-11-20 10:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 8),
  (148, 'GRUPO', 'ALTERAR', 154, 153, 'Futsal', 'Sub 11', 'MASCULINO', '2026-11-20 10:40:00', '2026-11-20 10:40:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 10),
  (149, 'GRUPO', 'ALTERAR', 155, 154, 'Futsal', 'Sub 13', 'FEMININO', '2026-11-20 11:20:00', '2026-11-20 11:20:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 3),
  (150, 'GRUPO', 'ALTERAR', 156, 155, 'Handebol', 'Sub 8', 'MASCULINO', '2026-11-20 12:00:00', '2026-11-20 12:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 2),
  (151, 'GRUPO', 'ALTERAR', 157, 156, 'Handebol', 'Sub 13', 'MASCULINO', '2026-11-20 12:40:00', '2026-11-20 12:40:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 6),
  (152, 'GRUPO', 'ALTERAR', 158, 157, 'Baleado', 'Sub 13', 'MASCULINO', '2026-11-20 13:20:00', '2026-11-20 13:20:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 10),
  (153, 'GRUPO', 'ALTERAR', 159, 158, 'Handebol', 'Sub 11', 'MASCULINO', '2026-11-20 14:00:00', '2026-11-20 14:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 7),
  (154, 'GRUPO', 'ALTERAR', 160, 159, 'Handebol', 'Sub 11', 'FEMININO', '2026-11-20 14:40:00', '2026-11-20 14:40:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 5),
  (155, 'GRUPO', 'ALTERAR', 161, 160, 'Handebol', 'Sub 15', 'FEMININO', '2026-11-20 15:20:00', '2026-11-20 15:20:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 1),
  (156, 'GRUPO', 'ALTERAR', 162, 161, 'Handebol', 'Sub 15', 'FEMININO', '2026-11-20 16:00:00', '2026-11-20 16:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 2),
  (157, 'GRUPO', 'ALTERAR', 163, 162, 'Baleado', 'Sub 11', 'FEMININO', '2026-11-20 08:00:00', '2026-11-20 08:00:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 5),
  (158, 'GRUPO', 'ALTERAR', 164, 163, 'Baleado', 'Sub 8', 'MASCULINO', '2026-11-20 08:40:00', '2026-11-20 08:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 1),
  (159, 'GRUPO', 'ALTERAR', 165, 164, 'Baleado', 'Sub 8', 'FEMININO', '2026-11-20 09:20:00', '2026-11-20 09:20:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 1),
  (160, 'GRUPO', 'ALTERAR', 166, 165, 'Baleado', 'Sub 9', 'FEMININO', '2026-11-20 10:00:00', '2026-11-20 10:00:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 1),
  (161, 'GRUPO', 'ALTERAR', 167, 166, 'Baleado', 'Sub 9', 'MASCULINO', '2026-11-20 10:40:00', '2026-11-20 10:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 4),
  (162, 'GRUPO', 'ALTERAR', 168, 167, 'Baleado', 'Sub 9', 'FEMININO', '2026-11-20 11:20:00', '2026-11-20 11:20:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 2),
  (163, 'GRUPO', 'ALTERAR', 169, 168, 'Vôlei', 'Sub 15', 'MISTO', '2026-11-20 12:00:00', '2026-11-20 12:00:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 3),
  (164, 'GRUPO', 'ALTERAR', 170, 169, 'Vôlei', 'Aberto', 'MASCULINO', '2026-11-20 12:40:00', '2026-11-20 12:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 2),
  (165, 'GRUPO', 'ALTERAR', 171, 170, 'Vôlei', 'Sub 17', 'MISTO', '2026-11-20 13:20:00', '2026-11-20 13:20:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 4),
  (166, 'GRUPO', 'ALTERAR', 172, 171, 'Vôlei', 'Sub 15', 'MISTO', '2026-11-20 14:00:00', '2026-11-20 14:00:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 4),
  (167, 'GRUPO', 'ALTERAR', 177, 175, 'Futsal', 'Sub 15', 'FEMININO', '2026-11-20 08:00:00', '2026-11-20 08:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 3),
  (168, 'GRUPO', 'ALTERAR', 178, 176, 'Futsal', 'Sub 15', 'FEMININO', '2026-11-20 08:40:00', '2026-11-20 08:40:00', 'Quadra do CEJA', 'Quadra do CEJA', 4),
  (169, 'GRUPO', 'ALTERAR', 179, 177, 'Futsal', 'Sub 15', 'MASCULINO', '2026-11-20 09:20:00', '2026-11-20 09:20:00', 'Quadra do CEJA', 'Quadra do CEJA', 6),
  (170, 'GRUPO', 'ALTERAR', 180, 178, 'Futsal', 'Sub 15', 'MASCULINO', '2026-11-20 10:00:00', '2026-11-20 10:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 7),
  (171, 'GRUPO', 'ALTERAR', 181, 179, 'Baleado', 'Sub 11', 'FEMININO', '2026-11-20 10:40:00', '2026-11-20 10:40:00', 'Quadra do CEJA', 'Quadra do CEJA', 6),
  (172, 'GRUPO', 'ALTERAR', 182, 180, 'Baleado', 'Sub 15', 'MASCULINO', '2026-11-20 11:20:00', '2026-11-20 11:20:00', 'Quadra do CEJA', 'Quadra do CEJA', 3),
  (173, 'GRUPO', 'ALTERAR', 183, 181, 'Handebol', 'Sub 13', 'FEMININO', '2026-11-20 12:00:00', '2026-11-20 12:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 2),
  (174, 'GRUPO', 'ALTERAR', 184, 182, 'Handebol', 'Sub 13', 'MASCULINO', '2026-11-20 12:40:00', '2026-11-20 12:40:00', 'Quadra do CEJA', 'Quadra do CEJA', 5),
  (175, 'GRUPO', 'ALTERAR', 185, 183, 'Handebol', 'Sub 17', 'FEMININO', '2026-11-20 13:20:00', '2026-11-20 13:20:00', 'Quadra do CEJA', 'Quadra do CEJA', 3),
  (176, 'GRUPO', 'ALTERAR', 186, 184, 'Baleado', 'Sub 17', 'FEMININO', '2026-11-20 14:00:00', '2026-11-20 14:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 2),
  (177, 'GRUPO', 'ALTERAR', 173, 185, 'Baleado', 'Sub 9', 'FEMININO', '2026-11-20 14:40:00', '2026-11-20 14:40:00', 'Quadra do Maria da Glória', 'Quadra do CEJA', 3),
  (178, 'GRUPO', 'ALTERAR', 187, 186, 'Futsal', 'Sub 13', 'MASCULINO', '2026-11-20 14:40:00', '2026-11-20 15:20:00', 'Quadra do CEJA', 'Quadra do CEJA', 6),
  (179, 'GRUPO', 'ALTERAR', 188, 187, 'Futsal', 'Sub 13', 'MASCULINO', '2026-11-20 15:20:00', '2026-11-20 16:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 7),
  (180, 'GRUPO', 'ALTERAR', 190, 188, 'Futebol Society', 'Sub 13', 'MASCULINO', '2026-11-20 08:40:00', '2026-11-20 08:40:00', 'Campo Society do CETI', 'Campo Society do CETI', 3),
  (181, 'GRUPO', 'ALTERAR', 191, 189, 'Futebol Society', 'Sub 15', 'MASCULINO', '2026-11-20 09:20:00', '2026-11-20 09:20:00', 'Campo Society do CETI', 'Campo Society do CETI', 5),
  (182, 'GRUPO', 'ALTERAR', 192, 190, 'Futebol Society', 'Sub 17', 'MASCULINO', '2026-11-20 10:00:00', '2026-11-20 10:00:00', 'Campo Society do CETI', 'Campo Society do CETI', 4),
  (183, 'GRUPO', 'ALTERAR', 193, 191, 'Futebol Society', 'Sub 13', 'MASCULINO', '2026-11-20 15:00:00', '2026-11-20 15:00:00', 'Campo Society do CETI', 'Campo Society do CETI', 4),
  (184, 'GRUPO', 'ALTERAR', 194, 192, 'Futebol Society', 'Sub 13', 'MASCULINO', '2026-11-20 15:40:00', '2026-11-20 15:40:00', 'Campo Society do CETI', 'Campo Society do CETI', 5),
  (185, 'GRUPO', 'ALTERAR', 202, 193, 'Vôlei', 'Sub 17', 'MISTO', '2026-11-20 12:40:00', '2026-11-20 08:00:00', 'Quadra do CETI', 'Quadra do CETI', 5),
  (186, 'GRUPO', 'ALTERAR', 203, 194, 'Vôlei', 'Aberto', 'MASCULINO', '2026-11-20 13:20:00', '2026-11-20 08:40:00', 'Quadra do CETI', 'Quadra do CETI', 3),
  (187, 'GRUPO', 'ALTERAR', 195, 195, 'Futsal', 'Sub 8', 'MASCULINO', '2026-11-20 08:00:00', '2026-11-20 09:20:00', 'Quadra do CETI', 'Quadra do CETI', 3),
  (188, 'GRUPO', 'ALTERAR', 196, 196, 'Futsal', 'Sub 8', 'MASCULINO', '2026-11-20 08:40:00', '2026-11-20 10:00:00', 'Quadra do CETI', 'Quadra do CETI', 4),
  (189, 'GRUPO', 'ALTERAR', 197, 197, 'Baleado', 'Sub 11', 'FEMININO', '2026-11-20 09:20:00', '2026-11-20 10:40:00', 'Quadra do CETI', 'Quadra do CETI', 7),
  (190, 'GRUPO', 'ALTERAR', 199, 199, 'Baleado', 'Sub 11', 'FEMININO', '2026-11-20 10:40:00', '2026-11-20 12:00:00', 'Quadra do CETI', 'Quadra do CETI', 8),
  (191, 'GRUPO', 'ALTERAR', 200, 200, 'Handebol', 'Sub 9', 'FEMININO', '2026-11-20 11:20:00', '2026-11-20 12:40:00', 'Quadra do CETI', 'Quadra do CETI', 2),
  (192, 'GRUPO', 'ALTERAR', 201, 201, 'Futsal', 'Sub 8', 'MASCULINO', '2026-11-20 12:00:00', '2026-11-20 13:20:00', 'Quadra do CETI', 'Quadra do CETI', 5),
  (193, 'GRUPO', 'ALTERAR', 205, 202, 'Basquete', 'Sub 15', 'FEMININO', '2026-11-20 08:40:00', '2026-11-20 08:00:00', 'Quadra do CEBC', 'Quadra do CEBC', 3),
  (194, 'GRUPO', 'ALTERAR', 206, 203, 'Basquete', 'Sub 15', 'MASCULINO', '2026-11-20 09:20:00', '2026-11-20 08:40:00', 'Quadra do CEBC', 'Quadra do CEBC', 5),
  (195, 'GRUPO', 'ALTERAR', 207, 204, 'Futsal', 'Sub 15', 'FEMININO', '2026-11-20 10:00:00', '2026-11-20 09:20:00', 'Quadra do CEBC', 'Quadra do CEBC', 5),
  (196, 'GRUPO', 'ALTERAR', 208, 205, 'Futsal', 'Sub 15', 'FEMININO', '2026-11-20 10:40:00', '2026-11-20 10:00:00', 'Quadra do CEBC', 'Quadra do CEBC', 6),
  (197, 'GRUPO', 'ALTERAR', 209, 206, 'Handebol', 'Sub 11', 'FEMININO', '2026-11-20 11:20:00', '2026-11-20 10:40:00', 'Quadra do CEBC', 'Quadra do CEBC', 4),
  (198, 'GRUPO', 'ALTERAR', 210, 207, 'Basquete', 'Sub 17', 'MASCULINO', '2026-11-20 12:00:00', '2026-11-20 11:20:00', 'Quadra do CEBC', 'Quadra do CEBC', 3),
  (199, 'GRUPO', 'ALTERAR', 211, 208, 'Basquete', 'Sub 15', 'MASCULINO', '2026-11-20 12:40:00', '2026-11-20 12:00:00', 'Quadra do CEBC', 'Quadra do CEBC', 4),
  (200, 'GRUPO', 'ALTERAR', 212, 209, 'Basquete', 'Sub 17', 'FEMININO', '2026-11-20 13:20:00', '2026-11-20 12:40:00', 'Quadra do CEBC', 'Quadra do CEBC', 1),
  (201, 'GRUPO', 'ALTERAR', 213, 210, 'Baleado', 'Sub 9', 'MASCULINO', '2026-11-20 14:00:00', '2026-11-20 13:20:00', 'Quadra do CEBC', 'Quadra do CEBC', 5),
  (202, 'GRUPO', 'ALTERAR', 214, 211, 'Baleado', 'Sub 9', 'MASCULINO', '2026-11-20 14:40:00', '2026-11-20 14:00:00', 'Quadra do CEBC', 'Quadra do CEBC', 6),
  (203, 'GRUPO', 'ALTERAR', 216, 213, 'Handebol', 'Sub 15', 'MASCULINO', '2026-11-20 16:00:00', '2026-11-20 15:20:00', 'Quadra do CEBC', 'Quadra do CEBC', 2),
  (204, 'GRUPO', 'ALTERAR', 217, 214, 'Handebol', 'Sub 15', 'MASCULINO', '2026-11-20 16:40:00', '2026-11-20 16:00:00', 'Quadra do CEBC', 'Quadra do CEBC', 3),
  (205, 'GRUPO', 'ALTERAR', 218, 215, 'Handebol', 'Aberto', 'MASCULINO', '2026-11-20 17:20:00', '2026-11-20 16:40:00', 'Quadra do CEBC', 'Quadra do CEBC', 3),
  (206, 'GRUPO', 'ALTERAR', 219, 216, 'Handebol', 'Sub 15', 'MASCULINO', '2026-11-21 08:00:00', '2026-11-21 08:00:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 4),
  (207, 'GRUPO', 'ALTERAR', 220, 217, 'Handebol', 'Sub 17', 'MASCULINO', '2026-11-21 08:40:00', '2026-11-21 08:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 5),
  (208, 'GRUPO', 'ALTERAR', 231, 228, 'Handebol', 'Sub 11', 'FEMININO', '2026-11-21 08:00:00', '2026-11-21 08:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 6),
  (209, 'GRUPO', 'ALTERAR', 232, 229, 'Baleado', 'Sub 15', 'MASCULINO', '2026-11-21 08:40:00', '2026-11-21 08:40:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 4),
  (210, 'GRUPO', 'ALTERAR', 233, 230, 'Baleado', 'Sub 15', 'MASCULINO', '2026-11-21 09:20:00', '2026-11-21 09:20:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 5),
  (211, 'GRUPO', 'ALTERAR', 234, 231, 'Baleado', 'Sub 17', 'MASCULINO', '2026-11-21 10:00:00', '2026-11-21 10:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 3),
  (212, 'GRUPO', 'ALTERAR', 235, 232, 'Baleado', 'Sub 17', 'MASCULINO', '2026-11-21 10:40:00', '2026-11-21 10:40:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 4),
  (213, 'GRUPO', 'ALTERAR', 244, 241, 'Baleado', 'Sub 15', 'FEMININO', '2026-11-21 08:00:00', '2026-11-21 08:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 5),
  (214, 'GRUPO', 'ALTERAR', 245, 242, 'Baleado', 'Sub 15', 'FEMININO', '2026-11-21 08:40:00', '2026-11-21 08:40:00', 'Quadra do CEJA', 'Quadra do CEJA', 6),
  (215, 'GRUPO', 'ALTERAR', 246, 243, 'Baleado', 'Sub 17', 'FEMININO', '2026-11-21 09:20:00', '2026-11-21 09:20:00', 'Quadra do CEJA', 'Quadra do CEJA', 3),
  (216, 'GRUPO', 'ALTERAR', 247, 244, 'Baleado', 'Sub 17', 'FEMININO', '2026-11-21 10:00:00', '2026-11-21 10:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 4),
  (217, 'GRUPO', 'ALTERAR', 249, 246, 'Futsal', 'Aberto', 'FEMININO', '2026-11-21 11:20:00', '2026-11-21 11:20:00', 'Quadra do CEJA', 'Quadra do CEJA', 3),
  (218, 'GRUPO', 'ALTERAR', 272, 269, 'Handebol', 'Sub 9', 'FEMININO', '2026-11-21 08:00:00', '2026-11-21 08:00:00', 'Quadra do CETI', 'Quadra do CETI', 3),
  (219, 'GRUPO', 'ALTERAR', 273, 270, 'Handebol', 'Sub 8', 'MASCULINO', '2026-11-21 08:40:00', '2026-11-21 08:40:00', 'Quadra do CETI', 'Quadra do CETI', 3),
  (220, 'GRUPO', 'ALTERAR', 274, 271, 'Baleado', 'Sub 9', 'FEMININO', '2026-11-21 09:20:00', '2026-11-21 09:20:00', 'Quadra do CETI', 'Quadra do CETI', 4),
  (221, 'GRUPO', 'ALTERAR', 275, 272, 'Baleado', 'Sub 9', 'FEMININO', '2026-11-21 10:00:00', '2026-11-21 10:00:00', 'Quadra do CETI', 'Quadra do CETI', 5),
  (222, 'GRUPO', 'ALTERAR', 276, 273, 'Baleado', 'Sub 8', 'FEMININO', '2026-11-21 10:40:00', '2026-11-21 10:40:00', 'Quadra do CETI', 'Quadra do CETI', 2),
  (223, 'GRUPO', 'ALTERAR', 277, 274, 'Futsal', 'Sub 8', 'FEMININO', '2026-11-21 11:20:00', '2026-11-21 11:20:00', 'Quadra do CETI', 'Quadra do CETI', 2),
  (224, 'GRUPO', 'ALTERAR', 278, 275, 'Futsal', 'Sub 11', 'FEMININO', '2026-11-21 12:00:00', '2026-11-21 12:00:00', 'Quadra do CETI', 'Quadra do CETI', 2),
  (225, 'GRUPO', 'ALTERAR', 279, 276, 'Futsal', 'Sub 9', 'FEMININO', '2026-11-21 12:40:00', '2026-11-21 12:40:00', 'Quadra do CETI', 'Quadra do CETI', 2),
  (226, 'GRUPO', 'ALTERAR', 282, 279, 'Handebol', 'Sub 8', 'FEMININO', '2026-11-21 14:40:00', '2026-11-21 14:40:00', 'Quadra do CETI', 'Quadra do CETI', 1),
  (227, 'GRUPO', 'ALTERAR', 286, 283, 'Baleado', 'Sub 8', 'MASCULINO', '2026-11-21 16:40:00', '2026-11-21 16:40:00', 'Quadra do CETI', 'Quadra do CETI', 2),
  (228, 'GRUPO', 'ALTERAR', 287, 284, 'Handebol', 'Sub 13', 'FEMININO', '2026-11-21 08:00:00', '2026-11-21 08:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 3),
  (229, 'GRUPO', 'ALTERAR', 288, 285, 'Handebol', 'Sub 15', 'FEMININO', '2026-11-21 08:40:00', '2026-11-21 08:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 3),
  (230, 'GRUPO', 'ALTERAR', 289, 286, 'Handebol', 'Sub 15', 'FEMININO', '2026-11-21 09:20:00', '2026-11-21 09:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 4),
  (231, 'GRUPO', 'REMOVER', 33, NULL, 'Handebol', 'Sub 9', 'MASCULINO', '2026-11-18 16:30:00', NULL, 'Quadra do CEBC', NULL, 1),
  (232, 'GRUPO', 'REMOVER', 101, NULL, 'Basquete', 'Sub 17', 'FEMININO', '2026-11-19 10:00:00', NULL, 'Quadra do CEBC', NULL, 2),
  (233, 'GRUPO', 'REMOVER', 189, NULL, 'Handebol', 'Sub 17', 'FEMININO', '2026-11-20 16:00:00', NULL, 'Quadra do CEJA', NULL, 4),
  (234, 'GRUPO', 'REMOVER', 204, NULL, 'Basquete', 'Sub 17', 'FEMININO', '2026-11-20 08:00:00', NULL, 'Quadra do CEBC', NULL, 3),
  (235, 'GRUPO', 'INCLUIR', NULL, 102, 'Handebol', 'Sub 8', 'FEMININO', NULL, '2026-11-19 11:20:00', NULL, 'Quadra do CEBC', NULL),
  (236, 'MATA', 'ALTERAR', 146, 145, 'Futsal', 'Sub 17', 'MASCULINO', '2026-11-20 18:40:00', '2026-11-20 18:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 9),
  (237, 'MATA', 'ALTERAR', 147, 146, 'Futsal', 'Sub 17', 'MASCULINO', '2026-11-20 19:20:00', '2026-11-20 19:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 10),
  (238, 'MATA', 'ALTERAR', 148, 147, 'Futsal', 'Aberto', 'MASCULINO', '2026-11-20 20:00:00', '2026-11-20 20:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 7),
  (239, 'MATA', 'ALTERAR', 149, 148, 'Futsal', 'Aberto', 'MASCULINO', '2026-11-20 20:40:00', '2026-11-20 20:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 8),
  (240, 'MATA', 'ALTERAR', 174, 172, 'Handebol', 'Sub 11', 'MASCULINO', '2026-11-20 15:20:00', '2026-11-20 14:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 8),
  (241, 'MATA', 'ALTERAR', 175, 173, 'Handebol', 'Sub 11', 'MASCULINO', '2026-11-20 16:00:00', '2026-11-20 15:20:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 9),
  (242, 'MATA', 'ALTERAR', 176, 174, 'Handebol', 'Sub 13', 'MASCULINO', '2026-11-20 16:40:00', '2026-11-20 16:00:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 7),
  (243, 'MATA', 'ALTERAR', 198, 198, 'Baleado', 'Sub 13', 'MASCULINO', '2026-11-20 10:00:00', '2026-11-20 11:20:00', 'Quadra do CETI', 'Quadra do CETI', 11),
  (244, 'MATA', 'ALTERAR', 215, 212, 'Baleado', 'Sub 11', 'MASCULINO', '2026-11-20 15:20:00', '2026-11-20 14:40:00', 'Quadra do CEBC', 'Quadra do CEBC', 8),
  (245, 'MATA', 'ALTERAR', 221, 218, 'Baleado', 'Sub 9', 'MASCULINO', '2026-11-21 09:20:00', '2026-11-21 09:20:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 7),
  (246, 'MATA', 'ALTERAR', 222, 219, 'Baleado', 'Sub 15', 'FEMININO', '2026-11-21 10:00:00', '2026-11-21 10:00:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 7),
  (247, 'MATA', 'ALTERAR', 223, 220, 'Baleado', 'Sub 15', 'FEMININO', '2026-11-21 10:40:00', '2026-11-21 10:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 8),
  (248, 'MATA', 'ALTERAR', 224, 221, 'Futsal', 'Sub 9', 'MASCULINO', '2026-11-21 11:20:00', '2026-11-21 11:20:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 9),
  (249, 'MATA', 'ALTERAR', 225, 222, 'Futsal', 'Sub 9', 'MASCULINO', '2026-11-21 12:00:00', '2026-11-21 12:00:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 10),
  (250, 'MATA', 'ALTERAR', 226, 223, 'Baleado', 'Sub 11', 'MASCULINO', '2026-11-21 12:40:00', '2026-11-21 12:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 9),
  (251, 'MATA', 'ALTERAR', 227, 224, 'Handebol', 'Sub 13', 'MASCULINO', '2026-11-21 13:20:00', '2026-11-21 13:20:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 9),
  (252, 'MATA', 'ALTERAR', 228, 225, 'Handebol', 'Sub 13', 'FEMININO', '2026-11-21 14:00:00', '2026-11-21 14:00:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 4),
  (253, 'MATA', 'ALTERAR', 229, 226, 'Handebol', 'Sub 11', 'MASCULINO', '2026-11-21 14:40:00', '2026-11-21 14:40:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 10),
  (254, 'MATA', 'ALTERAR', 230, 227, 'Handebol', 'Sub 15', 'MASCULINO', '2026-11-21 15:20:00', '2026-11-21 15:20:00', 'Quadra do Maria da Glória', 'Quadra do Maria da Glória', 5),
  (255, 'MATA', 'ALTERAR', 236, 233, 'Baleado', 'Sub 9', 'MASCULINO', '2026-11-21 11:20:00', '2026-11-21 11:20:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 8),
  (256, 'MATA', 'ALTERAR', 237, 234, 'Handebol', 'Sub 11', 'FEMININO', '2026-11-21 12:00:00', '2026-11-21 12:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 7),
  (257, 'MATA', 'ALTERAR', 238, 235, 'Handebol', 'Sub 11', 'FEMININO', '2026-11-21 12:40:00', '2026-11-21 12:40:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 8),
  (258, 'MATA', 'ALTERAR', 239, 236, 'Baleado', 'Sub 13', 'MASCULINO', '2026-11-21 13:20:00', '2026-11-21 13:20:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 12),
  (259, 'MATA', 'ALTERAR', 240, 237, 'Baleado', 'Sub 15', 'FEMININO', '2026-11-21 14:00:00', '2026-11-21 14:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 9),
  (260, 'MATA', 'ALTERAR', 241, 238, 'Baleado', 'Sub 13', 'FEMININO', '2026-11-21 14:40:00', '2026-11-21 14:40:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 13),
  (261, 'MATA', 'ALTERAR', 242, 239, 'Handebol', 'Sub 11', 'FEMININO', '2026-11-21 15:20:00', '2026-11-21 15:20:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 9),
  (262, 'MATA', 'ALTERAR', 243, 240, 'Baleado', 'Sub 11', 'MASCULINO', '2026-11-21 16:00:00', '2026-11-21 16:00:00', 'Quadra da Adelieta Ramalho', 'Quadra da Adelieta Ramalho', 10),
  (263, 'MATA', 'ALTERAR', 248, 245, 'Handebol', 'Sub 13', 'MASCULINO', '2026-11-21 10:40:00', '2026-11-21 10:40:00', 'Quadra do CEJA', 'Quadra do CEJA', 8),
  (264, 'MATA', 'ALTERAR', 250, 247, 'Futsal', 'Sub 13', 'MASCULINO', '2026-11-21 12:00:00', '2026-11-21 12:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 8),
  (265, 'MATA', 'ALTERAR', 251, 248, 'Futsal', 'Sub 13', 'MASCULINO', '2026-11-21 12:40:00', '2026-11-21 12:40:00', 'Quadra do CEJA', 'Quadra do CEJA', 9),
  (266, 'MATA', 'ALTERAR', 252, 249, 'Futsal', 'Sub 11', 'MASCULINO', '2026-11-21 13:20:00', '2026-11-21 13:20:00', 'Quadra do CEJA', 'Quadra do CEJA', 11),
  (267, 'MATA', 'ALTERAR', 253, 250, 'Futsal', 'Sub 11', 'MASCULINO', '2026-11-21 14:00:00', '2026-11-21 14:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 12),
  (268, 'MATA', 'ALTERAR', 254, 251, 'Baleado', 'Sub 17', 'MASCULINO', '2026-11-21 14:40:00', '2026-11-21 14:40:00', 'Quadra do CEJA', 'Quadra do CEJA', 5),
  (269, 'MATA', 'ALTERAR', 255, 252, 'Baleado', 'Sub 15', 'MASCULINO', '2026-11-21 15:20:00', '2026-11-21 15:20:00', 'Quadra do CEJA', 'Quadra do CEJA', 6),
  (270, 'MATA', 'ALTERAR', 256, 253, 'Baleado', 'Sub 13', 'MASCULINO', '2026-11-21 16:00:00', '2026-11-21 16:00:00', 'Quadra do CEJA', 'Quadra do CEJA', 13),
  (271, 'MATA', 'ALTERAR', 257, 254, 'Baleado', 'Sub 17', 'FEMININO', '2026-11-21 16:40:00', '2026-11-21 16:40:00', 'Quadra do CEJA', 'Quadra do CEJA', 5),
  (272, 'MATA', 'ALTERAR', 258, 255, 'Baleado', 'Sub 13', 'FEMININO', '2026-11-21 08:00:00', '2026-11-21 08:00:00', 'Quadra do CEBC', 'Quadra do CEBC', 11),
  (273, 'MATA', 'ALTERAR', 259, 256, 'Baleado', 'Sub 13', 'FEMININO', '2026-11-21 08:40:00', '2026-11-21 08:40:00', 'Quadra do CEBC', 'Quadra do CEBC', 12),
  (274, 'MATA', 'ALTERAR', 260, 257, 'Baleado', 'Sub 11', 'FEMININO', '2026-11-21 09:20:00', '2026-11-21 09:20:00', 'Quadra do CEBC', 'Quadra do CEBC', 9),
  (275, 'MATA', 'ALTERAR', 262, 258, 'Basquete', 'Sub 15', 'FEMININO', '2026-11-21 10:40:00', '2026-11-21 10:00:00', 'Quadra do CEBC', 'Quadra do CEBC', 4),
  (276, 'MATA', 'ALTERAR', 263, 259, 'Futsal', 'Sub 15', 'MASCULINO', '2026-11-21 11:00:00', '2026-11-21 10:40:00', 'Quadra do CEBC', 'Quadra do CEBC', 9),
  (277, 'MATA', 'ALTERAR', 264, 260, 'Futsal', 'Sub 15', 'MASCULINO', '2026-11-21 11:40:00', '2026-11-21 11:00:00', 'Quadra do CEBC', 'Quadra do CEBC', 10),
  (278, 'MATA', 'ALTERAR', 265, 261, 'Futsal', 'Sub 15', 'FEMININO', '2026-11-21 12:20:00', '2026-11-21 11:40:00', 'Quadra do CEBC', 'Quadra do CEBC', 7),
  (279, 'MATA', 'ALTERAR', 266, 262, 'Futsal', 'Sub 15', 'FEMININO', '2026-11-21 13:00:00', '2026-11-21 12:20:00', 'Quadra do CEBC', 'Quadra do CEBC', 8),
  (280, 'MATA', 'ALTERAR', 261, 263, 'Handebol', 'Sub 15', 'FEMININO', '2026-11-21 10:00:00', '2026-11-21 13:00:00', 'Quadra do CEBC', 'Quadra do CEBC', 5),
  (281, 'MATA', 'ALTERAR', 267, 264, 'Futsal', 'Sub 13', 'FEMININO', '2026-11-21 13:40:00', '2026-11-21 13:40:00', 'Quadra do CEBC', 'Quadra do CEBC', 4),
  (282, 'MATA', 'ALTERAR', 268, 265, 'Futsal', 'Sub 9', 'MASCULINO', '2026-11-21 14:20:00', '2026-11-21 14:20:00', 'Quadra do CEBC', 'Quadra do CEBC', 11),
  (283, 'MATA', 'ALTERAR', 269, 266, 'Futsal', 'Sub 17', 'FEMININO', '2026-11-21 15:00:00', '2026-11-21 15:00:00', 'Quadra do CEBC', 'Quadra do CEBC', 5),
  (284, 'MATA', 'ALTERAR', 270, 267, 'Futsal', 'Sub 15', 'FEMININO', '2026-11-21 15:40:00', '2026-11-21 15:40:00', 'Quadra do CEBC', 'Quadra do CEBC', 9),
  (285, 'MATA', 'ALTERAR', 271, 268, 'Futsal', 'Sub 11', 'MASCULINO', '2026-11-21 16:20:00', '2026-11-21 16:20:00', 'Quadra do CEBC', 'Quadra do CEBC', 13),
  (286, 'MATA', 'ALTERAR', 280, 277, 'Futsal', 'Sub 8', 'MASCULINO', '2026-11-21 13:20:00', '2026-11-21 13:20:00', 'Quadra do CETI', 'Quadra do CETI', 6),
  (287, 'MATA', 'ALTERAR', 281, 278, 'Handebol', 'Sub 8', 'MASCULINO', '2026-11-21 14:00:00', '2026-11-21 14:00:00', 'Quadra do CETI', 'Quadra do CETI', 4),
  (288, 'MATA', 'ALTERAR', 283, 280, 'Handebol', 'Sub 9', 'FEMININO', '2026-11-21 15:20:00', '2026-11-21 15:20:00', 'Quadra do CETI', 'Quadra do CETI', 4),
  (289, 'MATA', 'ALTERAR', 284, 281, 'Baleado', 'Sub 9', 'FEMININO', '2026-11-21 16:00:00', '2026-11-21 16:00:00', 'Quadra do CETI', 'Quadra do CETI', 6),
  (290, 'MATA', 'ALTERAR', 285, 282, 'Baleado', 'Sub 9', 'MASCULINO', '2026-11-21 16:20:00', '2026-11-21 16:20:00', 'Quadra do CETI', 'Quadra do CETI', 9),
  (291, 'MATA', 'ALTERAR', 290, 287, 'Baleado', 'Sub 11', 'FEMININO', '2026-11-21 10:00:00', '2026-11-21 10:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 10),
  (292, 'MATA', 'ALTERAR', 291, 288, 'Futsal', 'Sub 7', 'MASCULINO', '2026-11-21 10:40:00', '2026-11-21 10:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 5),
  (293, 'MATA', 'ALTERAR', 292, 289, 'Vôlei', 'Aberto', 'MASCULINO', '2026-11-21 11:20:00', '2026-11-21 11:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 4),
  (294, 'MATA', 'ALTERAR', 293, 290, 'Vôlei', 'Sub 15', 'MISTO', '2026-11-21 12:00:00', '2026-11-21 12:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 5),
  (295, 'MATA', 'ALTERAR', 294, 291, 'Vôlei', 'Sub 17', 'MISTO', '2026-11-21 12:40:00', '2026-11-21 12:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 6),
  (296, 'MATA', 'ALTERAR', 295, 292, 'Basquete', 'Sub 17', 'FEMININO', '2026-11-21 13:20:00', '2026-11-21 13:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 4),
  (297, 'MATA', 'ALTERAR', 296, 293, 'Basquete', 'Sub 15', 'MASCULINO', '2026-11-21 14:00:00', '2026-11-21 14:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 6),
  (298, 'MATA', 'ALTERAR', 297, 294, 'Basquete', 'Sub 17', 'MASCULINO', '2026-11-21 14:40:00', '2026-11-21 14:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 4),
  (299, 'MATA', 'ALTERAR', 298, 295, 'Baleado', 'Sub 11', 'FEMININO', '2026-11-21 15:20:00', '2026-11-21 15:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 11),
  (300, 'MATA', 'ALTERAR', 299, 296, 'Handebol', 'Sub 17', 'FEMININO', '2026-11-21 16:00:00', '2026-11-21 16:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 5),
  (301, 'MATA', 'ALTERAR', 300, 297, 'Handebol', 'Sub 17', 'MASCULINO', '2026-11-21 16:40:00', '2026-11-21 16:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 6),
  (302, 'MATA', 'ALTERAR', 301, 298, 'Handebol', 'Aberto', 'MASCULINO', '2026-11-21 17:20:00', '2026-11-21 17:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 4),
  (303, 'MATA', 'ALTERAR', 302, 299, 'Futsal', 'Sub 13', 'MASCULINO', '2026-11-21 18:00:00', '2026-11-21 18:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 10),
  (304, 'MATA', 'ALTERAR', 303, 300, 'Futsal', 'Sub 15', 'MASCULINO', '2026-11-21 18:40:00', '2026-11-21 18:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 11),
  (305, 'MATA', 'ALTERAR', 304, 301, 'Futsal', 'Aberto', 'FEMININO', '2026-11-21 19:20:00', '2026-11-21 19:20:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 4),
  (306, 'MATA', 'ALTERAR', 305, 302, 'Futsal', 'Sub 17', 'MASCULINO', '2026-11-21 20:00:00', '2026-11-21 20:00:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 11),
  (307, 'MATA', 'ALTERAR', 306, 303, 'Futsal', 'Aberto', 'MASCULINO', '2026-11-21 20:40:00', '2026-11-21 20:40:00', 'Ginásio de Esportes', 'Ginásio de Esportes', 9),
  (308, 'MATA', 'ALTERAR', 307, 304, 'Futebol Society', 'Sub 13', 'MASCULINO', '2026-11-21 08:40:00', '2026-11-21 08:40:00', 'Quadra do CETI', 'Quadra do CETI', 6),
  (309, 'MATA', 'ALTERAR', 308, 305, 'Futebol Society', 'Sub 15', 'MASCULINO', '2026-11-21 09:20:00', '2026-11-21 09:20:00', 'Quadra do CETI', 'Quadra do CETI', 7),
  (310, 'MATA', 'ALTERAR', 309, 306, 'Futebol Society', 'Sub 17', 'MASCULINO', '2026-11-21 10:00:00', '2026-11-21 10:00:00', 'Quadra do CETI', 'Quadra do CETI', 5);

-- Acha o jogo SEM usar o id da competição (o id muda de um banco para outro: o Handebol M Sub 9, criado
-- pelo db/14, é o 51 na produção). Quem muda ou fica (MANTER e ALTERAR) é achado pela modalidade, categoria
-- e gênero da competição + numero_jogo (que o script não muda); quem SAI (REMOVER), pelo numero_tabela
-- atual + a mesma competição. MASCULINO e MISTO contam como o mesmo gênero (o db/32 troca um pelo outro).
-- Dois jogos nunca se confundem, mesmo que dois números se troquem entre jogos do mesmo horário e local.
UPDATE alvo_db34 t
   SET t.n_achado = (SELECT COUNT(*) FROM jogos j
                       INNER JOIN competicoes c ON c.id = j.competicao_id
                       INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.nome = t.modalidade
                       INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = t.categoria
                      WHERE (c.genero = t.genero OR (c.genero IN ('MASCULINO', 'MISTO') AND t.genero IN ('MASCULINO', 'MISTO')))
                        AND (j.fase = 'GRUPOS') = (t.tipo = 'GRUPO')
                        AND ((t.acao = 'REMOVER' AND j.numero_tabela = t.a) OR (t.acao <> 'REMOVER' AND j.numero_jogo = t.njogo))),
       t.jogo_id = (SELECT MAX(j.id) FROM jogos j
                       INNER JOIN competicoes c ON c.id = j.competicao_id
                       INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.nome = t.modalidade
                       INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = t.categoria
                      WHERE (c.genero = t.genero OR (c.genero IN ('MASCULINO', 'MISTO') AND t.genero IN ('MASCULINO', 'MISTO')))
                        AND (j.fase = 'GRUPOS') = (t.tipo = 'GRUPO')
                        AND ((t.acao = 'REMOVER' AND j.numero_tabela = t.a) OR (t.acao <> 'REMOVER' AND j.numero_jogo = t.njogo)));

-- O nº 102 não tem identidade ainda: se já existir (nº 102 na competição, no dia e hora), é FEITO
UPDATE alvo_db34 t
   SET t.jogo_id = (SELECT MAX(j.id) FROM jogos j
                      INNER JOIN competicoes c ON c.id = j.competicao_id AND c.genero = t.genero
                      INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.nome = t.modalidade
                      INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = t.categoria
                     WHERE j.numero_tabela = t.b AND j.data_hora = t.dh_novo),
       t.n_achado = (SELECT COUNT(*) FROM jogos j
                       INNER JOIN competicoes c ON c.id = j.competicao_id AND c.genero = t.genero
                       INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.nome = t.modalidade
                       INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = t.categoria
                      WHERE j.numero_tabela = t.b AND j.data_hora = t.dh_novo)
 WHERE t.acao = 'INCLUIR';

UPDATE alvo_db34 t
  INNER JOIN jogos j ON j.id = t.jogo_id
   SET t.jt_num = j.numero_tabela, t.jt_dh = j.data_hora,
       t.jt_local = (SELECT l.nome FROM locais_disputa l WHERE l.id = j.local_id);

UPDATE alvo_db34 t
   SET t.estado = CASE
         WHEN t.acao = 'REMOVER' THEN CASE WHEN t.n_achado = 1 THEN 'APLICAR' WHEN t.n_achado = 0 THEN 'FEITO' ELSE '' END
         WHEN t.acao = 'INCLUIR' THEN CASE WHEN t.n_achado = 1 THEN 'FEITO' WHEN t.n_achado = 0 THEN 'APLICAR' ELSE '' END
         WHEN t.n_achado <> 1 THEN ''
         WHEN t.jt_num = t.b AND t.jt_dh = t.dh_novo AND t.jt_local = t.local_novo THEN
              CASE WHEN t.a = t.b AND t.dh_novo = t.dh_mapa AND t.local_novo = t.local_esperado THEN 'IGUAL' ELSE 'FEITO' END
         WHEN t.jt_num = t.a THEN 'APLICAR'
         ELSE '' END,
       t.local_ok = CASE WHEN t.acao = 'REMOVER' THEN 1
         WHEN (SELECT COUNT(*) FROM locais_disputa l WHERE l.nome = t.local_novo) = 1 THEN 1 ELSE 0 END;

UPDATE alvo_db34 t
   SET t.sujo = (SELECT COUNT(*) FROM jogos j
                  WHERE j.id = t.jogo_id
                    AND (j.status <> 'AGENDADO' OR j.placar_1 IS NOT NULL OR j.placar_2 IS NOT NULL
                         OR j.vencedor_equipe_id IS NOT NULL OR j.penaltis_1 IS NOT NULL OR j.penaltis_2 IS NOT NULL
                         OR EXISTS (SELECT 1 FROM sumula_atletas sa WHERE sa.jogo_id = j.id)
                         OR EXISTS (SELECT 1 FROM sumula_equipes se WHERE se.jogo_id = j.id)
                         OR EXISTS (SELECT 1 FROM jogo_sets js WHERE js.jogo_id = j.id))),
       t.vaga_cheia = (SELECT COUNT(*) FROM jogos j
                        WHERE j.id = t.jogo_id AND t.tipo = 'MATA'
                          AND (j.equipe_1_id IS NOT NULL OR j.equipe_2_id IS NOT NULL));

-- O que foi achado (resumo; antes das travas, para ver o motivo se elas pararem)
SELECT tipo, acao, estado, COUNT(*) AS linhas, SUM(jogo_id IS NULL) AS sem_jogo,
       SUM(sujo) AS com_placar_sumula_ou_status, SUM(vaga_cheia) AS com_vaga_preenchida
  FROM alvo_db34
 GROUP BY tipo, acao, estado
 ORDER BY tipo, acao, estado;

-- ---------------------------------------------------------------------
-- COMPARAÇÃO COM O BANCO (não aborta): o que o banco TEM hoje e difere da coluna
-- "atual" do mapa. Exemplo: o jogo 6 está às 17:50 no banco e o mapa diz 18:50.
-- ---------------------------------------------------------------------
SELECT t.ordem, t.a AS nº_atual, t.b AS nº_novo, t.tipo, t.acao,
       DATE_FORMAT(j.data_hora, '%d/%m %H:%i') AS hora_no_banco, DATE_FORMAT(t.dh_mapa, '%d/%m %H:%i') AS hora_no_mapa_atual,
       DATE_FORMAT(t.dh_novo, '%d/%m %H:%i') AS hora_nova,
       l.nome AS local_no_banco, t.local_esperado, t.local_novo
  FROM alvo_db34 t
  INNER JOIN jogos j ON j.id = t.jogo_id
  LEFT JOIN locais_disputa l ON l.id = j.local_id
 WHERE t.estado = 'APLICAR' AND t.acao <> 'REMOVER'
   AND (j.data_hora <> t.dh_mapa OR COALESCE(l.nome, '') <> COALESCE(t.local_esperado, ''))
 ORDER BY t.ordem;

-- ---------------------------------------------------------------------
-- O que de fato muda de dia, hora ou local (só os jogos por aplicar)
-- ---------------------------------------------------------------------
SELECT t.a AS nº_atual, t.b AS nº_novo, t.tipo,
       DATE_FORMAT(j.data_hora, '%d/%m %H:%i') AS de, DATE_FORMAT(t.dh_novo, '%d/%m %H:%i') AS para,
       l.nome AS local_de, t.local_novo AS local_para
  FROM alvo_db34 t
  INNER JOIN jogos j ON j.id = t.jogo_id
  LEFT JOIN locais_disputa l ON l.id = j.local_id
 WHERE t.estado = 'APLICAR' AND t.acao IN ('MANTER', 'ALTERAR')
   AND (j.data_hora <> t.dh_novo OR COALESCE(l.nome, '') <> t.local_novo)
 ORDER BY t.ordem;

-- ---------------------------------------------------------------------
-- VÔLEI, nº 116 -> 121 e 117 -> 122: onde os jogos estão HOJE (a troca de
-- competição NÃO é feita por este script: depende de aprovação)
-- ---------------------------------------------------------------------
SELECT t.a AS nº_atual, t.b AS nº_novo, m.nome AS modalidade, cat.nome AS categoria, c.genero AS competicao_hoje,
       g.nome AS grupo, s1.nome AS equipe_1, s2.nome AS equipe_2, j.status
  FROM alvo_db34 t
  INNER JOIN jogos j ON j.id = t.jogo_id
  INNER JOIN competicoes c ON c.id = j.competicao_id
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
  LEFT JOIN grupos g ON g.id = j.grupo_id
  LEFT JOIN equipes e1 ON e1.id = j.equipe_1_id LEFT JOIN escolas s1 ON s1.id = e1.escola_id
  LEFT JOIN equipes e2 ON e2.id = j.equipe_2_id LEFT JOIN escolas s2 ON s2.id = e2.escola_id
 WHERE t.a IN (116, 117) AND t.modalidade = 'Vôlei' AND t.tipo = 'GRUPO';

-- ---------------------------------------------------------------------
-- Trava 1: cada linha achou o jogo; o que muda ou sai está AGENDADO, sem placar,
-- súmula nem set, e sem vaga de mata-mata preenchida; o local novo existe.
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS trava_alvo_db34;
CREATE TEMPORARY TABLE trava_alvo_db34 (
  linha INT     NOT NULL,
  ok    TINYINT NOT NULL,
  CONSTRAINT db34_jogo_nao_bate CHECK (ok = 1)
);
INSERT INTO trava_alvo_db34 (linha, ok)
SELECT ordem,
       CASE WHEN estado = '' THEN 0
            WHEN local_ok = 0 THEN 0
            WHEN acao <> 'INCLUIR' AND NOT (acao = 'REMOVER' AND estado = 'FEITO') AND jogo_id IS NULL THEN 0
            WHEN estado = 'APLICAR' AND acao <> 'INCLUIR' AND (sujo > 0 OR vaga_cheia > 0) THEN 0
            ELSE 1 END
  FROM alvo_db34;
DROP TEMPORARY TABLE trava_alvo_db34;

-- Trava 2: ou tudo por aplicar, ou tudo já feito (IGUAL vale para os dois). Um REMOVER que não acha
-- o jogo conta como FEITO e, com o resto por aplicar, dá estado misto: o script PARA, não segue em silêncio.
SET @aplicar_db34 = (SELECT COALESCE(SUM(estado = 'APLICAR'), 0) FROM alvo_db34);
SET @feito_db34   = (SELECT COALESCE(SUM(estado = 'FEITO'), 0) FROM alvo_db34);

DROP TEMPORARY TABLE IF EXISTS trava_estado_db34;
CREATE TEMPORARY TABLE trava_estado_db34 (
  situacao VARCHAR(40) NOT NULL,
  ok       TINYINT     NOT NULL,
  CONSTRAINT db34_estado_misto CHECK (ok = 1)
);
INSERT INTO trava_estado_db34 (situacao, ok)
SELECT CASE WHEN @aplicar_db34 > 0 AND @feito_db34 = 0 THEN 'aplicar'
            WHEN @feito_db34 > 0 AND @aplicar_db34 = 0 THEN 'já feito: nada a fazer'
            ELSE 'estado misto' END,
       CASE WHEN @aplicar_db34 > 0 AND @feito_db34 = 0 THEN 1
            WHEN @feito_db34 > 0 AND @aplicar_db34 = 0 THEN 1 ELSE 0 END;

SELECT situacao AS db34 FROM trava_estado_db34;
DROP TEMPORARY TABLE trava_estado_db34;

-- ---------------------------------------------------------------------
-- O nº 102 (Handebol F Sub 8, ACM x JOSE DIAS) e a final do Basquete F Sub 17
-- (nº 292 depois; 295 antes, 289 no 20265): equipes e grupo achados antes de gravar.
-- ---------------------------------------------------------------------
SET @estado102_db34 = (SELECT estado FROM alvo_db34 WHERE acao = 'INCLUIR');
SET @estado292_db34 = (SELECT estado FROM alvo_db34 WHERE b = 292 AND tipo = 'MATA');
SET @jogo292_db34   = (SELECT jogo_id FROM alvo_db34 WHERE b = 292 AND tipo = 'MATA');

DROP TEMPORARY TABLE IF EXISTS especiais_db34;
CREATE TEMPORARY TABLE especiais_db34 (
  comp102   INT NULL, comps102 INT NOT NULL, acm INT NULL, acms INT NOT NULL, jd INT NULL, jds INT NOT NULL,
  grupo102  INT NULL, grupos_iguais102 TINYINT NOT NULL, local102 INT NULL, locais102 INT NOT NULL, numero_jogo102 INT NULL,
  comp292   INT NULL, comps292 INT NOT NULL, ceja INT NULL, cejas INT NOT NULL, cebc INT NULL, cebcs INT NOT NULL
);
INSERT INTO especiais_db34 (comp102, comps102, acm, acms, jd, jds, grupo102, grupos_iguais102, local102, locais102, numero_jogo102,
                            comp292, comps292, ceja, cejas, cebc, cebcs)
SELECT
  (SELECT MAX(c.id) FROM competicoes c INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.nome = 'Handebol'
     INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = 'Sub 8' WHERE c.genero = 'FEMININO'),
  (SELECT COUNT(*) FROM competicoes c INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.nome = 'Handebol'
     INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = 'Sub 8' WHERE c.genero = 'FEMININO'),
  (SELECT MAX(e.id) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'ACM'
     INNER JOIN competicoes c ON c.id = e.competicao_id AND c.genero = 'FEMININO'
     INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.nome = 'Handebol'
     INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = 'Sub 8'),
  (SELECT COUNT(*) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'ACM'
     INNER JOIN competicoes c ON c.id = e.competicao_id AND c.genero = 'FEMININO'
     INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.nome = 'Handebol'
     INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = 'Sub 8'),
  (SELECT MAX(e.id) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'JOSE DIAS'
     INNER JOIN competicoes c ON c.id = e.competicao_id AND c.genero = 'FEMININO'
     INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.nome = 'Handebol'
     INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = 'Sub 8'),
  (SELECT COUNT(*) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'JOSE DIAS'
     INNER JOIN competicoes c ON c.id = e.competicao_id AND c.genero = 'FEMININO'
     INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.nome = 'Handebol'
     INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = 'Sub 8'),
  0, 0,
  (SELECT MAX(l.id) FROM locais_disputa l WHERE l.nome = 'Quadra do CEBC'),
  (SELECT COUNT(*) FROM locais_disputa l WHERE l.nome = 'Quadra do CEBC'),
  NULL,
  (SELECT MAX(c.id) FROM competicoes c INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.nome = 'Basquete'
     INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = 'Sub 17' WHERE c.genero = 'FEMININO'),
  (SELECT COUNT(*) FROM competicoes c INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.nome = 'Basquete'
     INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = 'Sub 17' WHERE c.genero = 'FEMININO'),
  (SELECT MAX(e.id) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'CEJA'
     INNER JOIN competicoes c ON c.id = e.competicao_id AND c.genero = 'FEMININO'
     INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.nome = 'Basquete'
     INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = 'Sub 17'),
  (SELECT COUNT(*) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'CEJA'
     INNER JOIN competicoes c ON c.id = e.competicao_id AND c.genero = 'FEMININO'
     INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.nome = 'Basquete'
     INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = 'Sub 17'),
  (SELECT MAX(e.id) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'CEBC'
     INNER JOIN competicoes c ON c.id = e.competicao_id AND c.genero = 'FEMININO'
     INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.nome = 'Basquete'
     INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = 'Sub 17'),
  (SELECT COUNT(*) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'CEBC'
     INNER JOIN competicoes c ON c.id = e.competicao_id AND c.genero = 'FEMININO'
     INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.nome = 'Basquete'
     INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = 'Sub 17');

-- O grupo do nº 102: as duas equipes têm de estar no MESMO grupo (e ele existe)
UPDATE especiais_db34 x
   SET x.grupo102 = (SELECT e.grupo_id FROM equipes e WHERE e.id = x.acm),
       x.grupos_iguais102 = CASE WHEN (SELECT e.grupo_id FROM equipes e WHERE e.id = x.acm) IS NOT NULL
                                  AND (SELECT e.grupo_id FROM equipes e WHERE e.id = x.acm)
                                    = (SELECT e.grupo_id FROM equipes e WHERE e.id = x.jd) THEN 1 ELSE 0 END,
       x.numero_jogo102 = (SELECT COALESCE(MAX(j.numero_jogo), 0) + 1 FROM jogos j WHERE j.competicao_id = x.comp102);

DROP TEMPORARY TABLE IF EXISTS trava_especiais_db34;
CREATE TEMPORARY TABLE trava_especiais_db34 (
  item VARCHAR(80) NOT NULL,
  ok   TINYINT     NOT NULL,
  CONSTRAINT db34_inclusao_ou_final_nao_batem CHECK (ok = 1)
);
INSERT INTO trava_especiais_db34 (item, ok)
SELECT 'nº 102: competição, equipes, grupo e local',
       CASE WHEN comps102 = 1 AND acms = 1 AND jds = 1 AND grupos_iguais102 = 1 AND locais102 = 1 THEN 1 ELSE 0 END
  FROM especiais_db34;
-- A final só precisa de CEJA e CEBC (cada uma uma vez) quando ainda vai ser gravada
INSERT INTO trava_especiais_db34 (item, ok)
SELECT 'final 292: competição e equipes',
       CASE WHEN @estado292_db34 <> 'APLICAR' THEN 1
            WHEN comps292 = 1 AND cejas = 1 AND cebcs = 1 THEN 1 ELSE 0 END
  FROM especiais_db34;
DROP TEMPORARY TABLE trava_especiais_db34;

SET @comp102_db34 = (SELECT comp102 FROM especiais_db34);
SET @acm_db34     = (SELECT acm FROM especiais_db34);
SET @jd_db34      = (SELECT jd FROM especiais_db34);
SET @grupo102_db34 = (SELECT grupo102 FROM especiais_db34);
SET @local102_db34 = (SELECT local102 FROM especiais_db34);
SET @njogo102_db34 = (SELECT numero_jogo102 FROM especiais_db34);
SET @comp292_db34 = (SELECT comp292 FROM especiais_db34);
SET @ceja_db34    = (SELECT ceja FROM especiais_db34);
SET @cebc_db34    = (SELECT cebc FROM especiais_db34);
DROP TEMPORARY TABLE especiais_db34;

-- Antes de gravar: contagens que não podem mudar sem querer
SET @jogos_antes_db34 = (SELECT COUNT(*) FROM jogos);
SET @vagas_antes_db34 = (SELECT COUNT(*) FROM jogo_vagas);
SET @mudam_db34 = (SELECT COUNT(*) FROM alvo_db34 WHERE acao IN ('MANTER', 'ALTERAR'));

-- ---------------------------------------------------------------------
-- As escritas (só no estado APLICAR)
-- ---------------------------------------------------------------------
-- 1) Saem os 4 jogos de grupo (e as vagas que dependem deles, se houver; as vagas do próprio
--    jogo saem junto, pela chave estrangeira em cascata)
DELETE v FROM jogo_vagas v
  INNER JOIN alvo_db34 t ON t.jogo_id = v.jogo_origem_id AND t.acao = 'REMOVER' AND t.estado = 'APLICAR';
SET @vagas_dependentes_db34 = ROW_COUNT();

DELETE j FROM jogos j
  INNER JOIN alvo_db34 t ON t.jogo_id = j.id AND t.acao = 'REMOVER' AND t.estado = 'APLICAR';
SET @removidos_db34 = ROW_COUNT();

-- 2) Renumeração em 2 fases (+10000 e depois o número novo), grupo e mata-mata
UPDATE jogos j
  INNER JOIN alvo_db34 t ON t.jogo_id = j.id AND t.estado = 'APLICAR' AND t.acao IN ('MANTER', 'ALTERAR')
   SET j.numero_tabela = j.numero_tabela + 10000;
SET @fase1_db34 = ROW_COUNT();

UPDATE jogos j
  INNER JOIN alvo_db34 t ON t.jogo_id = j.id AND t.estado = 'APLICAR' AND t.acao IN ('MANTER', 'ALTERAR')
   SET j.numero_tabela = t.b,
       j.data_hora = t.dh_novo,
       j.local_id = (SELECT l.id FROM locais_disputa l WHERE l.nome = t.local_novo);
SET @fase2_db34 = ROW_COUNT();

-- 3) O nº 102 (Handebol F Sub 8, ACM x JOSE DIAS), no grupo da competição
INSERT INTO jogos (competicao_id, numero_jogo, numero_tabela, fase, grupo_id, local_id, data_hora, equipe_1_id, equipe_2_id, status)
SELECT @comp102_db34, @njogo102_db34, 102, 'GRUPOS', @grupo102_db34, @local102_db34, '2026-11-19 11:20:00', @acm_db34, @jd_db34, 'AGENDADO'
 WHERE @estado102_db34 = 'APLICAR';
SET @inseridos_db34 = ROW_COUNT();

-- 4) Final do Basquete F Sub 17: CEJA x CEBC, as duas vagas manuais
UPDATE jogos j
   SET j.equipe_1_id = @ceja_db34, j.equipe_2_id = @cebc_db34
 WHERE j.id = @jogo292_db34 AND @estado292_db34 = 'APLICAR';
UPDATE jogo_vagas v
   SET v.manual = 1
 WHERE v.jogo_id = @jogo292_db34 AND @estado292_db34 = 'APLICAR';

-- 5) Rótulo "Vencedor do jogo N" com o número novo do jogo de origem (o id não muda)
UPDATE jogo_vagas v
  INNER JOIN jogos o ON o.id = v.jogo_origem_id
   SET v.rotulo = CONCAT('Vencedor do jogo ', o.numero_tabela)
 WHERE v.tipo = 'VENCEDOR';

-- ---------------------------------------------------------------------
-- Conferências. A tabela mostra o esperado e o encontrado; a trava logo
-- depois desfaz tudo se alguma divergir.
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS conferencia_db34;
CREATE TEMPORARY TABLE conferencia_db34 (
  item       VARCHAR(120) NOT NULL,
  esperado   INT          NOT NULL,
  encontrado INT          NOT NULL
);

INSERT INTO conferencia_db34 (item, esperado, encontrado)
SELECT 'jogos de grupo', 231, COUNT(*) FROM jogos WHERE fase = 'GRUPOS';
INSERT INTO conferencia_db34 (item, esperado, encontrado)
SELECT 'jogos de mata-mata', 75, COUNT(*) FROM jogos WHERE fase <> 'GRUPOS';
INSERT INTO conferencia_db34 (item, esperado, encontrado)
SELECT 'jogos de grupo em 18/11', 36, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-18';
INSERT INTO conferencia_db34 (item, esperado, encontrado)
SELECT 'jogos de grupo em 19/11', 93, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-19';
INSERT INTO conferencia_db34 (item, esperado, encontrado)
SELECT 'jogos de grupo em 20/11', 77, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-20';
INSERT INTO conferencia_db34 (item, esperado, encontrado)
SELECT 'jogos de grupo em 21/11', 25, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-21';
INSERT INTO conferencia_db34 (item, esperado, encontrado)
SELECT 'numero_tabela distintos (1 a 306, sem buraco nem repetição)', 306, COUNT(DISTINCT numero_tabela) FROM jogos WHERE numero_tabela BETWEEN 1 AND 306;
INSERT INTO conferencia_db34 (item, esperado, encontrado)
SELECT 'jogos sem numero_tabela ou fora de 1 a 306 (0)', 0, COUNT(*) FROM jogos WHERE numero_tabela IS NULL OR numero_tabela NOT BETWEEN 1 AND 306;
INSERT INTO conferencia_db34 (item, esperado, encontrado)
SELECT 'datas fora de 18 a 21/11 ou sem data (0)', 0, COUNT(*) FROM jogos
 WHERE data_hora IS NULL OR DATE(data_hora) NOT BETWEEN '2026-11-18' AND '2026-11-21';
INSERT INTO conferencia_db34 (item, esperado, encontrado)
SELECT 'equipes em dois jogos no mesmo dia e hora (0)', 0, COUNT(*)
  FROM (SELECT x.e FROM (SELECT equipe_1_id AS e, data_hora AS dh FROM jogos
                          UNION ALL SELECT equipe_2_id, data_hora FROM jogos) x
         WHERE x.e IS NOT NULL AND x.dh IS NOT NULL
         GROUP BY x.e, x.dh HAVING COUNT(*) > 1) y;
INSERT INTO conferencia_db34 (item, esperado, encontrado)
SELECT 'jogos que mudam: nº, dia, hora e local como a tabela manda', @mudam_db34, COUNT(*)
  FROM jogos j
  INNER JOIN alvo_db34 t ON t.jogo_id = j.id AND t.acao IN ('MANTER', 'ALTERAR')
  INNER JOIN locais_disputa l ON l.id = j.local_id AND l.nome = t.local_novo
 WHERE j.numero_tabela = t.b AND j.data_hora = t.dh_novo;
INSERT INTO conferencia_db34 (item, esperado, encontrado)
SELECT 'jogos removidos que ainda existem (0)', 0, COUNT(*)
  FROM jogos j INNER JOIN alvo_db34 t ON t.jogo_id = j.id AND t.acao = 'REMOVER';
INSERT INTO conferencia_db34 (item, esperado, encontrado)
SELECT 'jogos que saíram (4 ao aplicar, 0 se já feito)', CASE WHEN @aplicar_db34 > 0 THEN 4 ELSE 0 END, @removidos_db34;
INSERT INTO conferencia_db34 (item, esperado, encontrado)
SELECT 'nº 102: Handebol F Sub 8, ACM x JOSE DIAS, 19/11 11:20, Quadra do CEBC, no grupo (1)', 1, COUNT(*)
  FROM jogos j INNER JOIN locais_disputa l ON l.id = j.local_id AND l.nome = 'Quadra do CEBC'
 WHERE j.numero_tabela = 102 AND j.competicao_id = @comp102_db34 AND j.grupo_id = @grupo102_db34
   AND j.data_hora = '2026-11-19 11:20:00' AND j.equipe_1_id = @acm_db34 AND j.equipe_2_id = @jd_db34 AND j.status = 'AGENDADO';
INSERT INTO conferencia_db34 (item, esperado, encontrado)
SELECT 'Handebol F Sub 8 com 2 jogos (102 e 279)', 2, COUNT(*) FROM jogos WHERE competicao_id = @comp102_db34;
INSERT INTO conferencia_db34 (item, esperado, encontrado)
SELECT 'final 292 do Basquete F Sub 17 com CEJA x CEBC (1)', 1, COUNT(*)
  FROM jogos j WHERE j.id = @jogo292_db34 AND j.numero_tabela = 292 AND j.competicao_id = @comp292_db34
   AND j.equipe_1_id = @ceja_db34 AND j.equipe_2_id = @cebc_db34;
INSERT INTO conferencia_db34 (item, esperado, encontrado)
SELECT 'vagas da final 292 manuais (2)', 2, COUNT(*) FROM jogo_vagas WHERE jogo_id = @jogo292_db34 AND manual = 1;
INSERT INTO conferencia_db34 (item, esperado, encontrado)
SELECT 'jogos de mata-mata com equipe na vaga (só a final 292)', 1, COUNT(*)
  FROM jogos WHERE fase <> 'GRUPOS' AND (equipe_1_id IS NOT NULL OR equipe_2_id IS NOT NULL);
INSERT INTO conferencia_db34 (item, esperado, encontrado)
SELECT 'rótulos "Vencedor do jogo N" que não apontam para o número novo (0)', 0, COUNT(*)
  FROM jogo_vagas v INNER JOIN jogos o ON o.id = v.jogo_origem_id
 WHERE v.tipo = 'VENCEDOR' AND v.rotulo <> CONCAT('Vencedor do jogo ', o.numero_tabela);
INSERT INTO conferencia_db34 (item, esperado, encontrado)
SELECT 'vagas depois = vagas de antes - as que dependiam dos removidos',
       @vagas_antes_db34 - @vagas_dependentes_db34, COUNT(*)
  FROM jogo_vagas;
INSERT INTO conferencia_db34 (item, esperado, encontrado)
SELECT 'Lucia Rocha x CETI do Baleado F Sub 17 é o nº 244 (1)', 1, COUNT(*)
  FROM jogos j INNER JOIN competicoes c ON c.id = j.competicao_id AND c.genero = 'FEMININO'
  INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.nome = 'Baleado'
  INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = 'Sub 17'
  INNER JOIN equipes e1 ON e1.id = j.equipe_1_id INNER JOIN escolas s1 ON s1.id = e1.escola_id
  INNER JOIN equipes e2 ON e2.id = j.equipe_2_id INNER JOIN escolas s2 ON s2.id = e2.escola_id
 WHERE j.numero_tabela = 244 AND ((s1.nome = 'LUCIA ROCHA' AND s2.nome = 'CETI') OR (s1.nome = 'CETI' AND s2.nome = 'LUCIA ROCHA'));

SELECT item, esperado, encontrado,
       CASE WHEN esperado = encontrado THEN 'ok' ELSE 'DIVERGE' END AS situacao
  FROM conferencia_db34;

-- Trava 4: qualquer divergência para aqui, antes do COMMIT
DROP TEMPORARY TABLE IF EXISTS trava_conferencia_db34;
CREATE TEMPORARY TABLE trava_conferencia_db34 (
  item VARCHAR(120) NOT NULL,
  ok   TINYINT      NOT NULL,
  CONSTRAINT db34_conferencia_divergiu CHECK (ok = 1)
);
INSERT INTO trava_conferencia_db34 (item, ok)
SELECT item, CASE WHEN esperado = encontrado THEN 1 ELSE 0 END FROM conferencia_db34;

DROP TEMPORARY TABLE trava_conferencia_db34;
DROP TEMPORARY TABLE conferencia_db34;
DROP TEMPORARY TABLE alvo_db34;

COMMIT;

-- ---------------------------------------------------------------------
-- Depois do COMMIT, só leitura
-- ---------------------------------------------------------------------
-- Avisos (não travam): jogos no mesmo local com menos de 10 minutos entre os inícios
SELECT a.numero_tabela AS jogo_a, b.numero_tabela AS jogo_b, l.nome AS local,
       DATE_FORMAT(a.data_hora, '%d/%m %H:%i') AS hora_a, DATE_FORMAT(b.data_hora, '%d/%m %H:%i') AS hora_b
  FROM jogos a
  INNER JOIN jogos b ON b.local_id = a.local_id AND b.id > a.id
                    AND ABS(TIMESTAMPDIFF(MINUTE, a.data_hora, b.data_hora)) < 10
  INNER JOIN locais_disputa l ON l.id = a.local_id
 ORDER BY a.data_hora;

-- Competições que ficaram sem nenhum jogo de grupo (a confirmar com o chefe)
SELECT m.nome AS modalidade, cat.nome AS categoria, c.genero
  FROM competicoes c
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
 WHERE EXISTS (SELECT 1 FROM equipes e WHERE e.competicao_id = c.id)
   AND NOT EXISTS (SELECT 1 FROM jogos j WHERE j.competicao_id = c.id);

-- Os jogos citados no pedido
SELECT j.numero_tabela, m.nome AS modalidade, cat.nome AS categoria, c.genero, j.fase,
       DATE_FORMAT(j.data_hora, '%d/%m %H:%i') AS dia_hora, l.nome AS local
  FROM jogos j
  INNER JOIN competicoes c ON c.id = j.competicao_id
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
  LEFT JOIN locais_disputa l ON l.id = j.local_id
 WHERE j.numero_tabela IN (6, 102, 121, 122, 185, 244, 289, 292)
 ORDER BY j.numero_tabela;
