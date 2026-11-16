-- =====================================================================
-- MIGRAÇÃO 44 — Tabela de jogos 202610 do chefe (16/11/2026)
--
-- A tabela 202610 é IGUAL à 20269 (aplicada pelo db/43) com uma única
-- diferença: 3 jogos de 19/11, na Quadra da Adelieta Ramalho, trocam de
-- número e de horário (o dia e o local não mudam):
--
--   Futsal F Sub 15, CEBC x Conveniada ........ nº 64, 12:40 -> nº 62, 11:20
--   Futsal F Sub 13, CEJA x CEBN .............. nº 62, 11:20 -> nº 63, 12:00
--   Futsal F Sub 15, CEBN x Emiliano Zapata ... nº 63, 12:00 -> nº 64, 12:40
--
-- COMO O JOGO É ACHADO: competição (modalidade + categoria + gênero, nunca por
-- id) + fase de grupos + par de equipes (em qualquer ordem). Nunca pelo
-- numero_tabela nem pelo id. Cada jogo fica APLICAR (como na 20269), FEITO
-- (como na 202610) ou vazio (nenhum dos dois: para o script).
--
-- numero_jogo: nas duas competições ele já segue data e hora (e, no empate, o
-- numero_tabela); o script confere isso ANTES de escrever e recalcula, só no
-- Futsal F Sub 13 e no Futsal F Sub 15, de 1 a N nessa ordem. Na prática só o
-- Sub 15 muda (os jogos 1 e 2 se invertem); o Sub 13 fica igual.
--
-- Renumeração do numero_tabela em 2 FASES por causa do índice único (provisório
-- = 10000 + número novo).
--
-- IDEMPOTENTE: rodado de novo, cai tudo em FEITO e não grava nada.
--
-- SEGURANÇA: uma transação só. Quatro travas (CHECK em tabela temporária, erro
-- 3819 no MySQL e 4025 no MariaDB) param o script sem gravar nada:
--   db44_jogo_nao_bate        (antes de escrever: jogo não achado ou achado mais
--        de uma vez; jogo fora do estado da 20269 e da 202610; local diferente
--        da Quadra da Adelieta Ramalho; numero_jogo das duas competições fora de
--        data e hora)
--   db44_estado_misto         (antes de escrever: parte APLICAR e parte FEITO)
--   db44_jogo_ja_mexido       (antes de escrever: jogo com placar, vencedor,
--        cobranças, prorrogação, súmula, set, suspensão ou status diferente de
--        AGENDADO)
--   db44_conferencia_divergiu (antes do COMMIT: 299 jogos = 228 de grupo e 71 de
--        mata-mata, 36/92/75/25 e 0/0/9/62 por dia, numero_tabela de 1 a 299 sem
--        repetir, nenhuma equipe nem local com dois jogos no mesmo dia e hora,
--        os 3 jogos como na 202610, e NADA mais mudou: nenhum outro jogo mudou
--        de número, dia, hora, local, equipes ou competição, e o numero_jogo só
--        mudou nas duas competições)
-- No cliente mysql o erro encerra a sessão e a transação é desfeita. No
-- DBeaver, se um comando falhar, rode ROLLBACK antes de qualquer outra coisa.
--
-- Avisos que NÃO abortam (depois do COMMIT, só leitura): ESCOLA em dois jogos no
-- mesmo dia e hora envolvendo estes 3 jogos (o CEBN passa a jogar o nº 64 às
-- 19/11 12:40, o mesmo horário do nº 91, em quadras diferentes) e, na tabela
-- inteira, ATLETA inscrito em duas equipes que jogam no mesmo dia e hora
-- (marca se um dos jogos foi mexido por este script).
--
-- Só dados. Rode depois do 43. MySQL 8.0.16+ ou MariaDB 10.2+. Faça o dump
-- antes, na produção. Não entra no banco de fumaça. Sem dado de aluno.
-- NÃO repita o db/34, o db/39 nem o db/41 depois deste. Próximo script: o 45.
-- =====================================================================

SET NAMES utf8mb4;

START TRANSACTION;

-- Trava os jogos: nada muda no meio do script
SELECT COUNT(*) AS jogos_travados FROM jogos FOR UPDATE;

-- ---------------------------------------------------------------------
-- O plano: os 3 jogos
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS alvo_db44;
CREATE TEMPORARY TABLE alvo_db44 (
  ordem        INT          NOT NULL PRIMARY KEY,
  modalidade   VARCHAR(60)  NOT NULL,
  categoria    VARCHAR(20)  NOT NULL,
  genero       VARCHAR(10)  NOT NULL,
  e1           VARCHAR(100) NOT NULL,
  e2           VARCHAR(100) NOT NULL,
  local_nome   VARCHAR(80)  NOT NULL,   -- não muda
  a            INT          NOT NULL,   -- numero_tabela na 20269
  b            INT          NOT NULL,   -- numero_tabela na 202610
  dh_antes     DATETIME     NOT NULL,
  dh_novo      DATETIME     NOT NULL,
  -- o que foi achado
  comp_id      INT          NULL,
  achados      INT          NOT NULL DEFAULT 0,
  jogo_id      INT          NULL,
  nt_atual     INT          NULL,
  dh_atual     DATETIME     NULL,
  local_atual  VARCHAR(80)  NULL,
  sujo         INT          NOT NULL DEFAULT 0,   -- status, placar, cobranças, súmula, set, suspensão
  estado       VARCHAR(10)  NOT NULL DEFAULT ''   -- APLICAR, FEITO ou vazio
);

INSERT INTO alvo_db44 (ordem, modalidade, categoria, genero, e1, e2, local_nome, a, b, dh_antes, dh_novo) VALUES
  (1, 'Futsal', 'Sub 15', 'FEMININO', 'CEBC', 'Conveniada',      'Quadra da Adelieta Ramalho', 64, 62, '2026-11-19 12:40:00', '2026-11-19 11:20:00'),
  (2, 'Futsal', 'Sub 13', 'FEMININO', 'CEJA', 'CEBN',            'Quadra da Adelieta Ramalho', 62, 63, '2026-11-19 11:20:00', '2026-11-19 12:00:00'),
  (3, 'Futsal', 'Sub 15', 'FEMININO', 'CEBN', 'EMILIANO ZAPATA', 'Quadra da Adelieta Ramalho', 63, 64, '2026-11-19 12:00:00', '2026-11-19 12:40:00');

-- A competição de cada jogo (modalidade + categoria + gênero) e o jogo (competição + fase + par de equipes)
UPDATE alvo_db44 t
   SET t.comp_id = (SELECT MAX(c.id) FROM competicoes c
                      INNER JOIN modalidades m ON m.id = c.modalidade_id
                      INNER JOIN categorias cat ON cat.id = c.categoria_id
                     WHERE m.nome = t.modalidade AND cat.nome = t.categoria AND c.genero = t.genero);
UPDATE alvo_db44 t
   SET t.achados = (SELECT COUNT(*) FROM jogos j
                      INNER JOIN equipes q1 ON q1.id = j.equipe_1_id INNER JOIN escolas s1 ON s1.id = q1.escola_id
                      INNER JOIN equipes q2 ON q2.id = j.equipe_2_id INNER JOIN escolas s2 ON s2.id = q2.escola_id
                     WHERE j.competicao_id = t.comp_id AND j.fase = 'GRUPOS'
                       AND ((s1.nome = t.e1 AND s2.nome = t.e2) OR (s1.nome = t.e2 AND s2.nome = t.e1))),
       t.jogo_id = (SELECT MAX(j.id) FROM jogos j
                      INNER JOIN equipes q1 ON q1.id = j.equipe_1_id INNER JOIN escolas s1 ON s1.id = q1.escola_id
                      INNER JOIN equipes q2 ON q2.id = j.equipe_2_id INNER JOIN escolas s2 ON s2.id = q2.escola_id
                     WHERE j.competicao_id = t.comp_id AND j.fase = 'GRUPOS'
                       AND ((s1.nome = t.e1 AND s2.nome = t.e2) OR (s1.nome = t.e2 AND s2.nome = t.e1)));

UPDATE alvo_db44 t
  INNER JOIN jogos j ON j.id = t.jogo_id
  LEFT JOIN locais_disputa l ON l.id = j.local_id
   SET t.nt_atual = j.numero_tabela, t.dh_atual = j.data_hora, t.local_atual = l.nome,
       t.sujo = (j.status <> 'AGENDADO') + (j.placar_1 IS NOT NULL) + (j.placar_2 IS NOT NULL)
              + (j.vencedor_equipe_id IS NOT NULL) + (j.penaltis_1 IS NOT NULL) + (j.penaltis_2 IS NOT NULL)
              + (j.prorrogacao <> 0) + (j.baleou_primeiro_equipe_id IS NOT NULL)
              + (SELECT COUNT(*) FROM sumula_atletas sa WHERE sa.jogo_id = j.id)
              + (SELECT COUNT(*) FROM sumula_equipes se WHERE se.jogo_id = j.id)
              + (SELECT COUNT(*) FROM jogo_sets js WHERE js.jogo_id = j.id)
              + (SELECT COUNT(*) FROM suspensoes su WHERE su.jogo_origem_id = j.id);

UPDATE alvo_db44 t
   SET t.estado = CASE
         WHEN t.comp_id IS NULL OR t.achados <> 1 THEN ''
         WHEN t.nt_atual = t.b AND t.dh_atual = t.dh_novo AND t.local_atual = t.local_nome THEN 'FEITO'
         WHEN t.nt_atual = t.a AND t.dh_atual = t.dh_antes AND t.local_atual = t.local_nome THEN 'APLICAR'
         ELSE '' END;

SET @aplicar_db44 = (SELECT COUNT(*) FROM alvo_db44 WHERE estado = 'APLICAR');
SET @feito_db44   = (SELECT COUNT(*) FROM alvo_db44 WHERE estado = 'FEITO');
SET @cf13_db44    = (SELECT MAX(comp_id) FROM alvo_db44 WHERE categoria = 'Sub 13');
SET @cf15_db44    = (SELECT MAX(comp_id) FROM alvo_db44 WHERE categoria = 'Sub 15');
SET @faz_db44     = (@aplicar_db44 > 0);

SELECT ordem, CONCAT(modalidade, ' ', categoria, ' ', LEFT(genero, 1)) AS competicao, CONCAT(e1, ' x ', e2) AS jogo,
       a AS nt_antes, b AS nt_novo, DATE_FORMAT(dh_antes, '%d/%m %H:%i') AS hora_antes, DATE_FORMAT(dh_novo, '%H:%i') AS hora_nova,
       achados, nt_atual, DATE_FORMAT(dh_atual, '%d/%m %H:%i') AS hora_atual, local_atual, sujo, estado
  FROM alvo_db44 ORDER BY ordem;
SELECT @aplicar_db44 AS itens_a_aplicar, @feito_db44 AS itens_ja_feitos, (SELECT COUNT(*) FROM jogos) AS jogos_no_banco;

-- O numero_jogo das duas competições segue data e hora (e, no empate, o
-- numero_tabela)? Contado ANTES de escrever: se não seguir, o script para
DROP TEMPORARY TABLE IF EXISTS ordem_antes_db44;
CREATE TEMPORARY TABLE ordem_antes_db44 (id INT NOT NULL PRIMARY KEY, nj INT NOT NULL, esperado INT NOT NULL);
INSERT INTO ordem_antes_db44 (id, nj, esperado)
SELECT j.id, j.numero_jogo, ROW_NUMBER() OVER (PARTITION BY j.competicao_id ORDER BY j.data_hora, j.numero_tabela)
  FROM jogos j WHERE j.competicao_id IN (@cf13_db44, @cf15_db44);
SET @nj_fora_db44 = (SELECT COUNT(*) FROM ordem_antes_db44 WHERE nj <> esperado);
DROP TEMPORARY TABLE ordem_antes_db44;

-- Retrato dos jogos antes de escrever (para provar que nada mais mudou)
DROP TEMPORARY TABLE IF EXISTS retrato_db44;
CREATE TEMPORARY TABLE retrato_db44 (
  id INT NOT NULL PRIMARY KEY, comp INT NOT NULL, nt INT NULL, nj INT NOT NULL, dh DATETIME NULL,
  local_id INT NULL, e1 INT NULL, e2 INT NULL, grupo INT NULL, fase VARCHAR(10) NOT NULL
);
INSERT INTO retrato_db44 (id, comp, nt, nj, dh, local_id, e1, e2, grupo, fase)
SELECT id, competicao_id, numero_tabela, numero_jogo, data_hora, local_id, equipe_1_id, equipe_2_id, grupo_id, fase FROM jogos;
SET @jogos_antes_db44 = (SELECT COUNT(*) FROM retrato_db44);

-- ---------------------------------------------------------------------
-- Trava 1: o plano bate com o banco
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS trava_jogo_db44;
CREATE TEMPORARY TABLE trava_jogo_db44 (
  item VARCHAR(100) NOT NULL,
  ok   TINYINT      NOT NULL,
  CONSTRAINT db44_jogo_nao_bate CHECK (ok = 1)
);
INSERT INTO trava_jogo_db44 (item, ok)
SELECT CONCAT('jogo ', a, ' -> ', b, ' (', e1, ' x ', e2, ')'), CASE WHEN estado <> '' THEN 1 ELSE 0 END FROM alvo_db44;
INSERT INTO trava_jogo_db44 (item, ok)
SELECT 'os 3 jogos são jogos distintos', CASE WHEN COUNT(DISTINCT jogo_id) = 3 THEN 1 ELSE 0 END FROM alvo_db44;
INSERT INTO trava_jogo_db44 (item, ok)
SELECT 'numero_jogo das duas competições segue data e hora (jogos fora da ordem: 0)', CASE WHEN @nj_fora_db44 = 0 THEN 1 ELSE 0 END;
DROP TEMPORARY TABLE trava_jogo_db44;

-- Trava 2: estado misto (parte como na 20269, parte como na 202610)
DROP TEMPORARY TABLE IF EXISTS trava_misto_db44;
CREATE TEMPORARY TABLE trava_misto_db44 (
  item VARCHAR(80) NOT NULL,
  ok   TINYINT     NOT NULL,
  CONSTRAINT db44_estado_misto CHECK (ok = 1)
);
INSERT INTO trava_misto_db44 (item, ok)
SELECT 'os 3 APLICAR ou os 3 FEITO', CASE WHEN @aplicar_db44 = 0 OR @feito_db44 = 0 THEN 1 ELSE 0 END;
DROP TEMPORARY TABLE trava_misto_db44;

-- Trava 3: nada que muda pode ter sido jogado (só quando há o que aplicar)
DROP TEMPORARY TABLE IF EXISTS trava_mexido_db44;
CREATE TEMPORARY TABLE trava_mexido_db44 (
  item VARCHAR(80) NOT NULL,
  ok   TINYINT     NOT NULL,
  CONSTRAINT db44_jogo_ja_mexido CHECK (ok = 1)
);
INSERT INTO trava_mexido_db44 (item, ok)
SELECT CONCAT('jogo nº ', a), CASE WHEN sujo = 0 THEN 1 ELSE 0 END FROM alvo_db44 WHERE @faz_db44;
DROP TEMPORARY TABLE trava_mexido_db44;

-- ---------------------------------------------------------------------
-- As escritas (só no que é APLICAR)
-- ---------------------------------------------------------------------
-- 1) numero_tabela, fase 1: tira os 3 do caminho (índice único)
UPDATE jogos j
  INNER JOIN alvo_db44 t ON t.jogo_id = j.id AND t.estado = 'APLICAR'
   SET j.numero_tabela = 10000 + t.b;

-- 2) numero_tabela e horário da 202610 (dia e local não mudam)
UPDATE jogos j
  INNER JOIN alvo_db44 t ON t.jogo_id = j.id AND t.estado = 'APLICAR'
   SET j.numero_tabela = t.b, j.data_hora = t.dh_novo;
SET @jogos_alterados_db44 = ROW_COUNT();

-- 3) numero_jogo do Futsal F Sub 13 e do Futsal F Sub 15: de 1 a N por data e
--    hora (e, no empate, numero_tabela), em 2 fases (o índice único é por competição)
UPDATE jogos j SET j.numero_jogo = 10000 + j.numero_tabela
 WHERE j.competicao_id IN (@cf13_db44, @cf15_db44) AND @faz_db44;
DROP TEMPORARY TABLE IF EXISTS ordem_db44;
CREATE TEMPORARY TABLE ordem_db44 (id INT NOT NULL PRIMARY KEY, nj INT NOT NULL);
INSERT INTO ordem_db44 (id, nj)
SELECT j.id, ROW_NUMBER() OVER (PARTITION BY j.competicao_id ORDER BY j.data_hora, j.numero_tabela)
  FROM jogos j WHERE j.competicao_id IN (@cf13_db44, @cf15_db44) AND @faz_db44;
UPDATE jogos j INNER JOIN ordem_db44 o ON o.id = j.id SET j.numero_jogo = o.nj;
SET @jogos_renumerados_db44 = ROW_COUNT();

-- 4) Rótulo "Vencedor do jogo N": só de jogos que não mudaram de número entre estes
--    (nenhum dos 3 é origem de vaga; conferido abaixo), então nada a regravar

-- ---------------------------------------------------------------------
-- Conferências
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS conferencia_db44;
CREATE TEMPORARY TABLE conferencia_db44 (
  item       VARCHAR(140) NOT NULL,
  esperado   INT          NOT NULL,
  encontrado INT          NOT NULL
);

INSERT INTO conferencia_db44 SELECT 'jogos no banco (299)', 299, COUNT(*) FROM jogos;
INSERT INTO conferencia_db44 SELECT 'jogos de grupo (228)', 228, COUNT(*) FROM jogos WHERE fase = 'GRUPOS';
INSERT INTO conferencia_db44 SELECT 'jogos de mata-mata (71)', 71, COUNT(*) FROM jogos WHERE fase <> 'GRUPOS';
INSERT INTO conferencia_db44 SELECT '18/11: grupo (36)', 36, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-18';
INSERT INTO conferencia_db44 SELECT '18/11: mata-mata (0)', 0, COUNT(*) FROM jogos WHERE fase <> 'GRUPOS' AND DATE(data_hora) = '2026-11-18';
INSERT INTO conferencia_db44 SELECT '19/11: grupo (92)', 92, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-19';
INSERT INTO conferencia_db44 SELECT '19/11: mata-mata (0)', 0, COUNT(*) FROM jogos WHERE fase <> 'GRUPOS' AND DATE(data_hora) = '2026-11-19';
INSERT INTO conferencia_db44 SELECT '20/11: grupo (75)', 75, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-20';
INSERT INTO conferencia_db44 SELECT '20/11: mata-mata (9)', 9, COUNT(*) FROM jogos WHERE fase <> 'GRUPOS' AND DATE(data_hora) = '2026-11-20';
INSERT INTO conferencia_db44 SELECT '21/11: grupo (25)', 25, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-21';
INSERT INTO conferencia_db44 SELECT '21/11: mata-mata (62)', 62, COUNT(*) FROM jogos WHERE fase <> 'GRUPOS' AND DATE(data_hora) = '2026-11-21';
INSERT INTO conferencia_db44
SELECT 'numero_tabela de 1 a 299, sem repetir nem faltar (299)', 299, COUNT(DISTINCT numero_tabela) FROM jogos
 WHERE numero_tabela BETWEEN 1 AND 299;
INSERT INTO conferencia_db44
SELECT 'numero_tabela vazio, fora de 1 a 299 ou provisório (0)', 0, COUNT(*) FROM jogos
 WHERE numero_tabela IS NULL OR numero_tabela < 1 OR numero_tabela > 299;
INSERT INTO conferencia_db44
SELECT 'numero_jogo provisório que ficou (0)', 0, COUNT(*) FROM jogos WHERE numero_jogo >= 10000;
INSERT INTO conferencia_db44
SELECT 'equipe em dois jogos no mesmo dia e hora (0)', 0, COUNT(*)
  FROM (SELECT x.data_hora, x.equipe_id
          FROM (SELECT data_hora, equipe_1_id AS equipe_id FROM jogos
                UNION ALL SELECT data_hora, equipe_2_id FROM jogos) x
         WHERE x.equipe_id IS NOT NULL AND x.data_hora IS NOT NULL
         GROUP BY x.data_hora, x.equipe_id
        HAVING COUNT(*) > 1) d;
INSERT INTO conferencia_db44
SELECT 'local com dois jogos no mesmo dia e hora (0)', 0, COUNT(*)
  FROM (SELECT local_id, data_hora FROM jogos
         WHERE local_id IS NOT NULL AND data_hora IS NOT NULL
         GROUP BY local_id, data_hora HAVING COUNT(*) > 1) d;
-- Os 3 jogos como na 202610
INSERT INTO conferencia_db44
SELECT 'os 3 jogos com número, dia, hora e local da 202610 (3)', 3, COUNT(*)
  FROM alvo_db44 t
 WHERE (SELECT COUNT(*) FROM jogos j INNER JOIN locais_disputa l ON l.id = j.local_id
         WHERE j.id = t.jogo_id AND j.numero_tabela = t.b AND j.data_hora = t.dh_novo AND l.nome = t.local_nome) = 1;
-- E nada mais mudou
INSERT INTO conferencia_db44
SELECT 'jogos que mudaram de número ou hora fora dos 3 (0)', 0, COUNT(*)
  FROM retrato_db44 r INNER JOIN jogos j ON j.id = r.id
 WHERE (NOT (j.numero_tabela <=> r.nt) OR NOT (j.data_hora <=> r.dh))
   AND j.id NOT IN (SELECT jogo_id FROM alvo_db44 WHERE estado = 'APLICAR');
INSERT INTO conferencia_db44
SELECT 'jogos com competição, fase, grupo, local ou equipes diferentes de antes (0)', 0, COUNT(*)
  FROM retrato_db44 r INNER JOIN jogos j ON j.id = r.id
 WHERE j.competicao_id <> r.comp OR j.fase <> r.fase OR NOT (j.grupo_id <=> r.grupo)
    OR NOT (j.local_id <=> r.local_id) OR NOT (j.equipe_1_id <=> r.e1) OR NOT (j.equipe_2_id <=> r.e2);
INSERT INTO conferencia_db44
SELECT 'jogos que mudaram de numero_jogo fora do Futsal F Sub 13 e Sub 15 (0)', 0, COUNT(*)
  FROM retrato_db44 r INNER JOIN jogos j ON j.id = r.id
 WHERE j.numero_jogo <> r.nj AND j.competicao_id NOT IN (@cf13_db44, @cf15_db44);
INSERT INTO conferencia_db44
SELECT 'jogos no banco = jogos de antes', @jogos_antes_db44, COUNT(*) FROM jogos;
-- numero_jogo das duas competições: de 1 a N, sem buraco, por data e hora
INSERT INTO conferencia_db44
SELECT 'Futsal F Sub 13 e Sub 15: numero_jogo de 1 a N por data e hora (jogos fora da ordem: 0)', 0, COUNT(*)
  FROM (SELECT j.numero_jogo, ROW_NUMBER() OVER (PARTITION BY j.competicao_id ORDER BY j.data_hora, j.numero_tabela) AS ordem
          FROM jogos j WHERE j.competicao_id IN (@cf13_db44, @cf15_db44)) d
 WHERE d.numero_jogo <> d.ordem;
-- Nenhum dos 3 é origem de vaga (o rótulo "Vencedor do jogo N" não depende deles)
INSERT INTO conferencia_db44
SELECT 'vaga que tem um dos 3 jogos como origem (0)', 0, COUNT(*)
  FROM jogo_vagas v INNER JOIN alvo_db44 t ON t.jogo_id = v.jogo_origem_id;
INSERT INTO conferencia_db44
SELECT 'rótulo "Vencedor do jogo N" com número errado (0)', 0, COUNT(*)
  FROM jogo_vagas v INNER JOIN jogos jo ON jo.id = v.jogo_origem_id
 WHERE v.tipo = 'VENCEDOR' AND NOT (v.rotulo <=> CONCAT('Vencedor do jogo ', jo.numero_tabela));

SELECT item, esperado, encontrado, CASE WHEN esperado = encontrado THEN 'ok' ELSE 'DIVERGE' END AS situacao
  FROM conferencia_db44;

-- Trava 4: qualquer divergência para aqui, antes do COMMIT
DROP TEMPORARY TABLE IF EXISTS trava_conferencia_db44;
CREATE TEMPORARY TABLE trava_conferencia_db44 (
  item VARCHAR(140) NOT NULL,
  ok   TINYINT      NOT NULL,
  CONSTRAINT db44_conferencia_divergiu CHECK (ok = 1)
);
INSERT INTO trava_conferencia_db44 (item, ok)
SELECT item, CASE WHEN esperado = encontrado THEN 1 ELSE 0 END FROM conferencia_db44;
DROP TEMPORARY TABLE trava_conferencia_db44;
DROP TEMPORARY TABLE conferencia_db44;
DROP TEMPORARY TABLE ordem_db44;
DROP TEMPORARY TABLE retrato_db44;

COMMIT;

-- ---------------------------------------------------------------------
-- Depois do COMMIT, só leitura
-- ---------------------------------------------------------------------
SELECT @jogos_alterados_db44 AS jogos_alterados, @jogos_renumerados_db44 AS numero_jogo_regravados;

-- Os 3 jogos e o numero_jogo das duas competições, como ficaram
SELECT CONCAT(m.nome, ' ', cat.nome, ' ', LEFT(c.genero, 1)) AS competicao, j.numero_jogo, j.numero_tabela, j.fase,
       DATE_FORMAT(j.data_hora, '%d/%m %H:%i') AS quando, l.nome AS local_,
       COALESCE(s1.nome, (SELECT v.rotulo FROM jogo_vagas v WHERE v.jogo_id = j.id AND v.lado = 1)) AS equipe_1,
       COALESCE(s2.nome, (SELECT v.rotulo FROM jogo_vagas v WHERE v.jogo_id = j.id AND v.lado = 2)) AS equipe_2
  FROM jogos j
  INNER JOIN competicoes c ON c.id = j.competicao_id
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
  LEFT JOIN locais_disputa l ON l.id = j.local_id
  LEFT JOIN equipes e1 ON e1.id = j.equipe_1_id LEFT JOIN escolas s1 ON s1.id = e1.escola_id
  LEFT JOIN equipes e2 ON e2.id = j.equipe_2_id LEFT JOIN escolas s2 ON s2.id = e2.escola_id
 WHERE j.competicao_id IN (@cf13_db44, @cf15_db44)
 ORDER BY cat.ordem, j.numero_jogo;

-- Aviso (não aborta): ESCOLA em dois jogos no mesmo dia e hora, envolvendo os 3 jogos
SELECT DATE_FORMAT(x.data_hora, '%d/%m %H:%i') AS quando, s.nome AS escola,
       GROUP_CONCAT(CONCAT('nº ', j.numero_tabela, ' ', m.nome, ' ', cat.nome, ' ', IF(c.genero = 'MISTO', 'Misto', LEFT(c.genero, 1)),
                           ' (', COALESCE(l.nome, 'sem local'), ')')
                    ORDER BY j.numero_tabela SEPARATOR ' | ') AS jogos
  FROM (SELECT id, data_hora, equipe_1_id AS equipe_id FROM jogos UNION ALL SELECT id, data_hora, equipe_2_id FROM jogos) x
  INNER JOIN jogos j ON j.id = x.id
  INNER JOIN equipes e ON e.id = x.equipe_id
  INNER JOIN escolas s ON s.id = e.escola_id
  INNER JOIN competicoes c ON c.id = j.competicao_id
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
  LEFT JOIN locais_disputa l ON l.id = j.local_id
 WHERE (x.data_hora, s.id) IN (
         SELECT j2.data_hora, e2.escola_id
           FROM alvo_db44 t
           INNER JOIN jogos j2 ON j2.id = t.jogo_id
           INNER JOIN equipes e2 ON e2.id IN (j2.equipe_1_id, j2.equipe_2_id))
 GROUP BY x.data_hora, s.id, s.nome
HAVING COUNT(*) > 1
 ORDER BY x.data_hora, s.nome;

-- Aviso (não aborta): ATLETA em dois jogos no mesmo dia e hora (inscrito nas
-- duas equipes), em toda a tabela. "mexido_pelo_db44" = um dos dois jogos é um
-- dos 3 que este script moveu. Só leitura: mostra nomes na tela, não grava.
DROP TEMPORARY TABLE IF EXISTS atleta_conflito_db44;
CREATE TEMPORARY TABLE atleta_conflito_db44 (
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
INSERT INTO atleta_conflito_db44 (atleta, escola, quando, nt_1, comp_1, local_1, nt_2, comp_2, local_2)
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
UPDATE atleta_conflito_db44 x SET x.mexido = 1 WHERE x.nt_1 IN (SELECT t.b FROM alvo_db44 t);
UPDATE atleta_conflito_db44 x SET x.mexido = 1 WHERE x.nt_2 IN (SELECT t.b FROM alvo_db44 t);

SELECT COUNT(*) AS atleta_em_dois_jogos_no_mesmo_horario, COALESCE(SUM(mexido), 0) AS mexido_pelo_db44
  FROM atleta_conflito_db44;
-- O caso que o chefe pediu atenção: 19/11 às 12:40, CEBN nos jogos 64 e 91 (quantos atletas)
SELECT COUNT(*) AS atletas_do_cebn_nos_jogos_64_e_91_as_12h40
  FROM atleta_conflito_db44
 WHERE quando = '2026-11-19 12:40:00' AND escola = 'CEBN' AND nt_1 = 64 AND nt_2 = 91;
SELECT atleta, escola, DATE_FORMAT(quando, '%d/%m %H:%i') AS quando,
       CONCAT('nº ', nt_1, ' ', comp_1, ' (', COALESCE(local_1, 'sem local'), ')') AS jogo_1,
       CONCAT('nº ', nt_2, ' ', comp_2, ' (', COALESCE(local_2, 'sem local'), ')') AS jogo_2,
       IF(mexido = 1, 'sim', 'não') AS mexido_pelo_db44
  FROM atleta_conflito_db44
 ORDER BY mexido DESC, quando, escola, atleta;
DROP TEMPORARY TABLE atleta_conflito_db44;

SELECT DATE_FORMAT(data_hora, '%d/%m') AS dia, SUM(fase = 'GRUPOS') AS grupo, SUM(fase <> 'GRUPOS') AS mata_mata, COUNT(*) AS total
  FROM jogos GROUP BY DATE_FORMAT(data_hora, '%d/%m') ORDER BY dia;

DROP TEMPORARY TABLE alvo_db44;
