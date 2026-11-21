-- =====================================================================
-- MIGRAÇÃO 25 — elenco de 14 no handebol e no baleado (06/11/2026)
--
-- Decisão do usuário (06/11/2026): o teto de atletas por equipe em Handebol e
-- Baleado volta a 14, igual ao regulamento escrito (docs/referencias/
-- regulamento_2026.md). Isso desfaz o db/09, que baixou o teto para 12 pela
-- resposta do chefe de 07/10/2026. O mínimo continua 10, só como aviso.
--
-- O limite é DADO: mora em modalidades.max_atletas, que o código só lê
-- (inscrição e importação de atletas recusam a inscrição quando a equipe chega
-- ao teto). Esta migração só troca esse número; não apaga nem mexe em nenhuma
-- inscrição. As folhas de súmula de handebol e baleado passam a ter 14 linhas
-- no código (src/config/folhasSumula.js), no mesmo deploy.
--
-- SEGURANÇA: uma transação só. Duas travas (CHECK em tabela temporária, erro
-- 3819 no MySQL e 4025 no MariaDB) param o script sem gravar nada:
--   elenco_handebol_baleado_nao_bate_com_a_descricao   (antes de qualquer escrita)
--   conferencia_do_db25_divergiu                        (antes do COMMIT)
-- A primeira só deixa passar dois estados: o ORIGINAL (handebol e baleado,
-- os dois, com max_atletas = 12: aí atualiza) e o JÁ FEITO (os dois com 14: aí
-- não grava nada). Qualquer outra coisa — uma modalidade só, valores
-- diferentes, uma das duas sem existir — para o script.
-- No cliente mysql o erro encerra a sessão e a transação é desfeita. No
-- DBeaver, se um comando falhar, rode ROLLBACK antes de qualquer outra coisa.
--
-- IDEMPOTENTE: rodado de novo, cai em "já feito" e não grava nada.
--
-- Só dados, compatível com o backend no ar (que lê o número). Depende do 02
-- e do 09. MySQL 8.0.16+ ou MariaDB 10.2+ (CHECK de verdade). Faça o dump do
-- banco antes, na produção.
-- =====================================================================

SET NAMES utf8mb4;

START TRANSACTION;

-- ---------------------------------------------------------------------
-- O que há hoje nas duas modalidades
-- ---------------------------------------------------------------------
SET @achadas := (SELECT COUNT(*) FROM modalidades WHERE slug IN ('handebol', 'baleado'));
SET @com_12   := (SELECT COUNT(*) FROM modalidades WHERE slug IN ('handebol', 'baleado') AND max_atletas = 12);
SET @com_14   := (SELECT COUNT(*) FROM modalidades WHERE slug IN ('handebol', 'baleado') AND max_atletas = 14);

SET @estado := CASE
  WHEN @achadas = 2 AND @com_12 = 2 THEN 'original: aplica'
  WHEN @achadas = 2 AND @com_14 = 2 THEN 'já feito: nada a fazer'
  ELSE 'não bate' END;

-- O que foi achado (antes da trava, para ver o motivo se ela parar)
SELECT slug, min_atletas, max_atletas FROM modalidades WHERE slug IN ('handebol', 'baleado') ORDER BY slug;

-- ---------------------------------------------------------------------
-- Trava 1: só o estado original ou o já feito. Qualquer outra coisa para aqui.
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS trava_elenco_db25;
CREATE TEMPORARY TABLE trava_elenco_db25 (
  estado VARCHAR(40) NOT NULL,
  ok     TINYINT     NOT NULL,
  CONSTRAINT elenco_handebol_baleado_nao_bate_com_a_descricao CHECK (ok = 1)
);
INSERT INTO trava_elenco_db25 (estado, ok)
VALUES (@estado, CASE WHEN @estado = 'não bate' THEN 0 ELSE 1 END);

SELECT @estado AS db25;
DROP TEMPORARY TABLE trava_elenco_db25;

-- ---------------------------------------------------------------------
-- A mudança, só no estado original (no "já feito" nenhuma linha casa)
-- ---------------------------------------------------------------------
UPDATE modalidades SET max_atletas = 14
 WHERE slug IN ('handebol', 'baleado') AND @estado = 'original: aplica';

-- ---------------------------------------------------------------------
-- Conferências. A tabela mostra o esperado e o encontrado; a trava logo
-- depois desfaz tudo se alguma divergir.
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS conferencia_db25;
CREATE TEMPORARY TABLE conferencia_db25 (
  item       VARCHAR(90) NOT NULL,
  esperado   INT         NOT NULL,
  encontrado INT         NOT NULL
);

INSERT INTO conferencia_db25 (item, esperado, encontrado)
SELECT 'handebol e baleado com max_atletas = 14', 2, COUNT(*) FROM modalidades
           WHERE slug IN ('handebol', 'baleado') AND max_atletas = 14
UNION ALL SELECT 'handebol e baleado com min_atletas = 10 (só aviso)', 2, COUNT(*) FROM modalidades
           WHERE slug IN ('handebol', 'baleado') AND min_atletas = 10
UNION ALL SELECT 'futsal, society, vôlei e basquete continuam com max_atletas = 14', 4, COUNT(*) FROM modalidades
           WHERE slug IN ('futsal', 'futebol-society', 'volei', 'basquete') AND max_atletas = 14
UNION ALL SELECT 'equipes de handebol ou baleado com mais de 14 inscritos', 0, COUNT(*) FROM (
             SELECT i.equipe_id FROM inscricoes_atletas i
               INNER JOIN equipes e ON e.id = i.equipe_id
               INNER JOIN competicoes c ON c.id = e.competicao_id
               INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.slug IN ('handebol', 'baleado')
              GROUP BY i.equipe_id HAVING COUNT(*) > 14) acima;

SELECT item, esperado, encontrado,
       CASE WHEN esperado = encontrado THEN 'ok' ELSE 'DIVERGE' END AS situacao
  FROM conferencia_db25;

-- Trava 2: qualquer divergência para aqui, antes do COMMIT
DROP TEMPORARY TABLE IF EXISTS trava_conferencia_db25;
CREATE TEMPORARY TABLE trava_conferencia_db25 (
  item VARCHAR(90) NOT NULL,
  ok   TINYINT     NOT NULL,
  CONSTRAINT conferencia_do_db25_divergiu CHECK (ok = 1)
);
INSERT INTO trava_conferencia_db25 (item, ok)
SELECT item, CASE WHEN esperado = encontrado THEN 1 ELSE 0 END FROM conferencia_db25;

DROP TEMPORARY TABLE trava_conferencia_db25;
DROP TEMPORARY TABLE conferencia_db25;

COMMIT;

-- ---------------------------------------------------------------------
-- Depois do COMMIT, só leitura: o teto por modalidade
-- ---------------------------------------------------------------------
SELECT slug, min_atletas, max_atletas FROM modalidades ORDER BY ordem;
