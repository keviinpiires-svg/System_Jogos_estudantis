-- =====================================================================
-- MIGRAÇÃO 21 — troca os números da tabela dos jogos 27 e 29 (04/11/2026)
--
-- Os dois são da Quadra do CETI em 18/11/2026. Só o numero_tabela muda;
-- hora, local, equipes e numero_jogo ficam como estão:
--
--   antes:  27 = Futsal M Sub 7, ADELIETA RAMALHO x TEODULO LEITE, 15:10
--           29 = Futsal M Sub 9, EMILIANO ZAPATA x JOSE DIAS,      16:30
--   depois: 27 = Futsal M Sub 9, EMILIANO ZAPATA x JOSE DIAS,      16:30
--           29 = Futsal M Sub 7, ADELIETA RAMALHO x TEODULO LEITE, 15:10
--
-- Cada jogo é achado pelo número + a data e a hora + o local + a competição
-- + as duas escolas, na ordem, pelos nomes.
--
-- SEGURANÇA: uma transação só. Duas travas (CHECK em tabela temporária, erro
-- 3819 no MySQL e 4025 no MariaDB) param o script sem gravar nada:
--   jogos_27_e_29_nao_batem_com_a_descricao   (antes de qualquer escrita)
--   conferencia_do_db21_divergiu               (antes do COMMIT)
-- A primeira só deixa passar dois estados: o ORIGINAL (os dois jogos como no
-- "antes", ambos AGENDADOS: aí troca) e o JÁ TROCADO (como no "depois": aí
-- não muda nada). Qualquer outra coisa — jogo diferente, outra hora, outro
-- local, ou jogo iniciado antes da troca — para o script.
-- No cliente mysql o erro encerra a sessão e a transação é desfeita. No
-- DBeaver, se um comando falhar, rode ROLLBACK antes de qualquer outra coisa.
--
-- IDEMPOTENTE: rodado de novo depois da troca, cai no estado "já trocado",
-- não grava nada e as conferências passam.
--
-- Só dados. Rode depois do 20. MySQL 8.0.16+ ou MariaDB 10.2+ (CHECK de verdade).
-- =====================================================================

SET NAMES utf8mb4;

START TRANSACTION;

-- ---------------------------------------------------------------------
-- Os jogos de número 27 e 29, com o que cada um é (1 = bate, 0 = não)
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS jogos_db21;
CREATE TEMPORARY TABLE jogos_db21 (
  jogo_id       INT               NOT NULL PRIMARY KEY,
  numero_tabela SMALLINT UNSIGNED NOT NULL,
  original_27   TINYINT           NOT NULL,   -- é o 27 de antes, AGENDADO
  original_29   TINYINT           NOT NULL,   -- é o 29 de antes, AGENDADO
  trocado_27    TINYINT           NOT NULL,   -- é o 27 de depois
  trocado_29    TINYINT           NOT NULL    -- é o 29 de depois
);

INSERT INTO jogos_db21 (jogo_id, numero_tabela, original_27, original_29, trocado_27, trocado_29)
SELECT j.id, j.numero_tabela,
       -- 27 de antes: Futsal M Sub 7, ADELIETA RAMALHO x TEODULO LEITE, 15:10, AGENDADO
       CASE WHEN j.numero_tabela = 27 AND j.data_hora = '2026-11-18 15:10:00'
                 AND cat.nome = 'Sub 7' AND s1.nome = 'ADELIETA RAMALHO' AND s2.nome = 'TEODULO LEITE'
                 AND j.status = 'AGENDADO' THEN 1 ELSE 0 END,
       -- 29 de antes: Futsal M Sub 9, EMILIANO ZAPATA x JOSE DIAS, 16:30, AGENDADO
       CASE WHEN j.numero_tabela = 29 AND j.data_hora = '2026-11-18 16:30:00'
                 AND cat.nome = 'Sub 9' AND s1.nome = 'EMILIANO ZAPATA' AND s2.nome = 'JOSE DIAS'
                 AND j.status = 'AGENDADO' THEN 1 ELSE 0 END,
       -- 27 de depois: EMILIANO ZAPATA x JOSE DIAS, 16:30
       CASE WHEN j.numero_tabela = 27 AND j.data_hora = '2026-11-18 16:30:00'
                 AND cat.nome = 'Sub 9' AND s1.nome = 'EMILIANO ZAPATA' AND s2.nome = 'JOSE DIAS'
            THEN 1 ELSE 0 END,
       -- 29 de depois: ADELIETA RAMALHO x TEODULO LEITE, 15:10
       CASE WHEN j.numero_tabela = 29 AND j.data_hora = '2026-11-18 15:10:00'
                 AND cat.nome = 'Sub 7' AND s1.nome = 'ADELIETA RAMALHO' AND s2.nome = 'TEODULO LEITE'
            THEN 1 ELSE 0 END
  FROM jogos j
  INNER JOIN competicoes c ON c.id = j.competicao_id
  INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.slug = 'futsal'
  INNER JOIN categorias cat ON cat.id = c.categoria_id
  INNER JOIN locais_disputa l ON l.id = j.local_id AND l.nome = 'Quadra do CETI'
  INNER JOIN equipes e1 ON e1.id = j.equipe_1_id INNER JOIN escolas s1 ON s1.id = e1.escola_id
  INNER JOIN equipes e2 ON e2.id = j.equipe_2_id INNER JOIN escolas s2 ON s2.id = e2.escola_id
 WHERE j.numero_tabela IN (27, 29) AND c.genero = 'MASCULINO';

-- O que foi achado (antes da trava, para ver o motivo se ela parar)
SELECT numero_tabela, jogo_id, original_27, original_29, trocado_27, trocado_29
  FROM jogos_db21 ORDER BY numero_tabela;

-- ---------------------------------------------------------------------
-- Trava 1: estado ORIGINAL (os dois de antes) ou JÁ TROCADO (os dois de
-- depois). Nada encontrado, ou só um, ou qualquer mistura: para aqui.
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS trava_jogos_db21;
CREATE TEMPORARY TABLE trava_jogos_db21 (
  estado VARCHAR(40) NOT NULL,
  ok     TINYINT     NOT NULL,
  CONSTRAINT jogos_27_e_29_nao_batem_com_a_descricao CHECK (ok = 1)
);
INSERT INTO trava_jogos_db21 (estado, ok)
SELECT CASE WHEN SUM(original_27) = 1 AND SUM(original_29) = 1 THEN 'original: troca'
            WHEN SUM(trocado_27) = 1 AND SUM(trocado_29) = 1 THEN 'já trocado: nada a fazer'
            ELSE 'não bate' END,
       CASE WHEN (SUM(original_27) = 1 AND SUM(original_29) = 1)
              OR (SUM(trocado_27) = 1 AND SUM(trocado_29) = 1) THEN 1 ELSE 0 END
  FROM jogos_db21;

SELECT estado AS db21 FROM trava_jogos_db21;
DROP TEMPORARY TABLE trava_jogos_db21;

-- ---------------------------------------------------------------------
-- A troca, só no estado original (no "já trocado", a lista sai vazia).
-- Duas fases por causa do índice único de numero_tabela: primeiro o número
-- novo + 10000, depois o número novo.
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS troca_db21;
CREATE TEMPORARY TABLE troca_db21 (
  jogo_id     INT               NOT NULL PRIMARY KEY,
  numero_novo SMALLINT UNSIGNED NOT NULL
);
INSERT INTO troca_db21 (jogo_id, numero_novo)
SELECT jogo_id, CASE WHEN original_27 = 1 THEN 29 ELSE 27 END
  FROM jogos_db21
 WHERE original_27 = 1 OR original_29 = 1;

UPDATE jogos j INNER JOIN troca_db21 t ON t.jogo_id = j.id
   SET j.numero_tabela = t.numero_novo + 10000;
UPDATE jogos j INNER JOIN troca_db21 t ON t.jogo_id = j.id
   SET j.numero_tabela = t.numero_novo;

DROP TEMPORARY TABLE troca_db21;
DROP TEMPORARY TABLE jogos_db21;

-- ---------------------------------------------------------------------
-- Conferências. A tabela mostra o esperado e o encontrado; a trava logo
-- depois desfaz tudo se alguma divergir.
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS conferencia_db21;
CREATE TEMPORARY TABLE conferencia_db21 (
  item       VARCHAR(90) NOT NULL,
  esperado   INT         NOT NULL,
  encontrado INT         NOT NULL
);

INSERT INTO conferencia_db21 (item, esperado, encontrado)
SELECT 'jogos no total', 237, COUNT(*) FROM jogos
UNION ALL SELECT 'números da tabela repetidos', 0, COUNT(*) - COUNT(DISTINCT numero_tabela) FROM jogos
           WHERE numero_tabela IS NOT NULL
UNION ALL SELECT 'números da tabela distintos', 237, COUNT(DISTINCT numero_tabela) FROM jogos
UNION ALL SELECT 'jogo 27 é EMILIANO ZAPATA x JOSE DIAS às 16:30 de 18/11 (Quadra do CETI)', 1, COUNT(*) FROM jogos j
           INNER JOIN locais_disputa l ON l.id = j.local_id
           INNER JOIN equipes e1 ON e1.id = j.equipe_1_id INNER JOIN escolas s1 ON s1.id = e1.escola_id
           INNER JOIN equipes e2 ON e2.id = j.equipe_2_id INNER JOIN escolas s2 ON s2.id = e2.escola_id
           WHERE j.numero_tabela = 27 AND j.data_hora = '2026-11-18 16:30:00' AND l.nome = 'Quadra do CETI'
             AND s1.nome = 'EMILIANO ZAPATA' AND s2.nome = 'JOSE DIAS'
UNION ALL SELECT 'jogo 29 é ADELIETA RAMALHO x TEODULO LEITE às 15:10 de 18/11 (Quadra do CETI)', 1, COUNT(*) FROM jogos j
           INNER JOIN locais_disputa l ON l.id = j.local_id
           INNER JOIN equipes e1 ON e1.id = j.equipe_1_id INNER JOIN escolas s1 ON s1.id = e1.escola_id
           INNER JOIN equipes e2 ON e2.id = j.equipe_2_id INNER JOIN escolas s2 ON s2.id = e2.escola_id
           WHERE j.numero_tabela = 29 AND j.data_hora = '2026-11-18 15:10:00' AND l.nome = 'Quadra do CETI'
             AND s1.nome = 'ADELIETA RAMALHO' AND s2.nome = 'TEODULO LEITE'
UNION ALL SELECT 'números da tabela acima de 10000 (troca pela metade)', 0, COUNT(*) FROM jogos
           WHERE numero_tabela >= 10000;

SELECT item, esperado, encontrado,
       CASE WHEN esperado = encontrado THEN 'ok' ELSE 'DIVERGE' END AS situacao
  FROM conferencia_db21;

-- Trava 2: qualquer divergência para aqui, antes do COMMIT
DROP TEMPORARY TABLE IF EXISTS trava_conferencia_db21;
CREATE TEMPORARY TABLE trava_conferencia_db21 (
  item VARCHAR(90) NOT NULL,
  ok   TINYINT     NOT NULL,
  CONSTRAINT conferencia_do_db21_divergiu CHECK (ok = 1)
);
INSERT INTO trava_conferencia_db21 (item, ok)
SELECT item, CASE WHEN esperado = encontrado THEN 1 ELSE 0 END FROM conferencia_db21;

DROP TEMPORARY TABLE trava_conferencia_db21;
DROP TEMPORARY TABLE conferencia_db21;

COMMIT;

-- ---------------------------------------------------------------------
-- Depois do COMMIT, só leitura: a Quadra do CETI em 18/11, em ordem de hora
-- (o numero_jogo de cada competição não muda)
-- ---------------------------------------------------------------------
SELECT j.numero_tabela, j.numero_jogo, TIME(j.data_hora) AS hora, m.nome AS modalidade,
       cat.nome AS categoria, s1.nome AS equipe_1, s2.nome AS equipe_2, j.status
  FROM jogos j
  INNER JOIN competicoes c ON c.id = j.competicao_id
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
  INNER JOIN locais_disputa l ON l.id = j.local_id
  INNER JOIN equipes e1 ON e1.id = j.equipe_1_id INNER JOIN escolas s1 ON s1.id = e1.escola_id
  INNER JOIN equipes e2 ON e2.id = j.equipe_2_id INNER JOIN escolas s2 ON s2.id = e2.escola_id
 WHERE l.nome = 'Quadra do CETI' AND DATE(j.data_hora) = '2026-11-18'
 ORDER BY j.data_hora;
