-- =====================================================================
-- MIGRAÇÃO 27 — Futebol Society Sub 17 Masculino em grupo único (06/11/2026)
--
-- Roda logo DEPOIS do db/26. A tabela nova do chefe trouxe 4 jogos para essa
-- competição, todos entre uma equipe do grupo A (CEBC, CEJA) e uma do grupo B
-- (CETI, VITORIA LIMA). Com 2 grupos, nenhum jogo é "do grupo": a tabela de
-- cada grupo ficaria sem jogos e o "1 classificado por grupo" não teria critério.
-- O usuário aprovou (06/11/2026) juntar as 4 equipes num grupo só, no formato
-- das outras competições de 4 equipes e 4 jogos (cada equipe joga 2):
--
--   antes:  2 grupos (A: CEBC e CEJA; B: CETI e VITORIA LIMA), 1 classificado
--           por grupo, próxima fase FINAL; os 4 jogos sem grupo (db/26)
--   depois: grupo único A com as 4 equipes, 2 classificados, próxima fase
--           FINAL; o grupo B é apagado; os 4 jogos ficam no grupo A
--
-- É uma MUDANÇA DE REGRA DE DISPUTA desta competição (qtd_grupos 2 → 1 e
-- classificados_por_grupo 1 → 2), por decisão do usuário. Turno, melhores
-- segundos e pontos por vitória/empate/derrota não mudam.
--
-- SEGURANÇA: uma transação só. Duas travas (CHECK em tabela temporária, erro
-- 3819 no MySQL e 4025 no MariaDB) param o script sem gravar nada:
--   society17_nao_bate_com_a_descricao    (antes de qualquer escrita)
--   conferencia_do_db27_divergiu           (antes do COMMIT)
-- A primeira só deixa passar dois estados: o ORIGINAL (os 2 grupos com as
-- equipes acima, a competição com qtd_grupos 2 e 1 classificado por grupo, e
-- exatamente 4 jogos, todos AGENDADOS, sem placar, súmula nem set, sem grupo) e o
-- JÁ FEITO (grupo único A com as 4 equipes e os 4 jogos nele). Qualquer outra
-- coisa para o script.
-- No cliente mysql o erro encerra a sessão e a transação é desfeita. No
-- DBeaver, se um comando falhar, rode ROLLBACK antes de qualquer outra coisa.
--
-- IDEMPOTENTE: rodado de novo depois, cai em "já feito" e não grava nada.
--
-- Só dados. Rode depois do 26. MySQL 8.0.16+ ou MariaDB 10.2+ (CHECK de
-- verdade). Faça o dump do banco antes, na produção.
-- =====================================================================

SET NAMES utf8mb4;

START TRANSACTION;

-- ---------------------------------------------------------------------
-- O que há hoje na competição
-- ---------------------------------------------------------------------
SET @comp := (SELECT c.id FROM competicoes c
                INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.slug = 'futebol-society'
                INNER JOIN categorias k ON k.id = c.categoria_id AND k.nome = 'Sub 17'
               WHERE c.genero = 'MASCULINO');
SET @grupo_a := (SELECT id FROM grupos WHERE competicao_id = @comp AND nome = 'A');
SET @grupo_b := (SELECT id FROM grupos WHERE competicao_id = @comp AND nome = 'B');
SET @grupos  := (SELECT COUNT(*) FROM grupos WHERE competicao_id = @comp);
SET @equipes := (SELECT COUNT(*) FROM equipes WHERE competicao_id = @comp);
SET @jogos   := (SELECT COUNT(*) FROM jogos WHERE competicao_id = @comp);

-- Equipes de cada grupo (pelas escolas)
SET @a_ok := (SELECT COUNT(*) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id
               WHERE e.competicao_id = @comp AND e.grupo_id = @grupo_a AND s.nome IN ('CEBC', 'CEJA'));
SET @b_ok := (SELECT COUNT(*) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id
               WHERE e.competicao_id = @comp AND e.grupo_id = @grupo_b AND s.nome IN ('CETI', 'VITORIA LIMA'));
SET @todas_no_a := (SELECT COUNT(*) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id
                     WHERE e.competicao_id = @comp AND e.grupo_id = @grupo_a
                       AND s.nome IN ('CEBC', 'CEJA', 'CETI', 'VITORIA LIMA'));

SET @regra_antes  := (SELECT COUNT(*) FROM competicoes WHERE id = @comp AND qtd_grupos = 2
                       AND classificados_por_grupo = 1 AND melhores_segundos = 0 AND proxima_fase = 'FINAL');
SET @regra_depois := (SELECT COUNT(*) FROM competicoes WHERE id = @comp AND qtd_grupos = 1
                       AND classificados_por_grupo = 2 AND melhores_segundos = 0 AND proxima_fase = 'FINAL');

-- Jogos: AGENDADO, sem placar, pênaltis nem vencedor, sem súmula, sem set
SET @limpos := (
  SELECT COUNT(*) FROM jogos j
   WHERE j.competicao_id = @comp AND j.fase = 'GRUPOS'
     AND j.status = 'AGENDADO' AND j.placar_1 IS NULL AND j.placar_2 IS NULL
     AND j.penaltis_1 IS NULL AND j.penaltis_2 IS NULL AND j.vencedor_equipe_id IS NULL
     AND NOT EXISTS (SELECT 1 FROM sumula_equipes x WHERE x.jogo_id = j.id)
     AND NOT EXISTS (SELECT 1 FROM sumula_atletas x WHERE x.jogo_id = j.id)
     AND NOT EXISTS (SELECT 1 FROM jogo_sets x WHERE x.jogo_id = j.id));
SET @sem_grupo    := (SELECT COUNT(*) FROM jogos WHERE competicao_id = @comp AND fase = 'GRUPOS' AND grupo_id IS NULL);
SET @jogos_no_a   := (SELECT COUNT(*) FROM jogos WHERE competicao_id = @comp AND fase = 'GRUPOS' AND grupo_id = @grupo_a);
SET @jogos_grupos := (SELECT COUNT(*) FROM jogos WHERE competicao_id = @comp AND fase = 'GRUPOS');

SET @estado := CASE
  WHEN @comp IS NOT NULL AND @grupo_a IS NOT NULL AND @grupo_b IS NOT NULL AND @grupos = 2
       AND @equipes = 4 AND @a_ok = 2 AND @b_ok = 2 AND @regra_antes = 1
       AND @jogos = 4 AND @jogos_grupos = 4 AND @limpos = 4 AND @sem_grupo = 4 THEN 'original: aplica'
  WHEN @comp IS NOT NULL AND @grupo_a IS NOT NULL AND @grupo_b IS NULL AND @grupos = 1
       AND @equipes = 4 AND @todas_no_a = 4 AND @regra_depois = 1
       AND @jogos_grupos = 4 AND @jogos_no_a = 4 THEN 'já feito: nada a fazer'
  ELSE 'não bate' END;

-- O que foi achado (antes da trava, para ver o motivo se ela parar)
SELECT @grupos AS grupos, @equipes AS equipes, @a_ok AS no_a, @b_ok AS no_b, @regra_antes AS regra_antes,
       @jogos AS jogos, @limpos AS jogos_limpos, @sem_grupo AS jogos_sem_grupo, @estado AS estado;

-- ---------------------------------------------------------------------
-- Trava 1: só o estado original ou o já feito. Qualquer outra coisa para aqui.
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS trava_society17_db27;
CREATE TEMPORARY TABLE trava_society17_db27 (
  estado VARCHAR(40) NOT NULL,
  ok     TINYINT     NOT NULL,
  CONSTRAINT society17_nao_bate_com_a_descricao CHECK (ok = 1)
);
INSERT INTO trava_society17_db27 (estado, ok)
VALUES (@estado, CASE WHEN @estado = 'não bate' THEN 0 ELSE 1 END);

SELECT @estado AS db27;
DROP TEMPORARY TABLE trava_society17_db27;

-- ---------------------------------------------------------------------
-- A mudança, só no estado original (no "já feito" nenhuma linha casa).
-- Ordem: equipes e jogos para o grupo A, depois some o B, depois a regra.
-- ---------------------------------------------------------------------
UPDATE equipes SET grupo_id = @grupo_a
 WHERE competicao_id = @comp AND grupo_id = @grupo_b AND @estado = 'original: aplica';

UPDATE jogos SET grupo_id = @grupo_a
 WHERE competicao_id = @comp AND fase = 'GRUPOS' AND @estado = 'original: aplica';

DELETE FROM grupos WHERE id = @grupo_b AND @estado = 'original: aplica';

UPDATE competicoes SET qtd_grupos = 1, classificados_por_grupo = 2, proxima_fase = 'FINAL'
 WHERE id = @comp AND @estado = 'original: aplica';

-- ---------------------------------------------------------------------
-- Conferências. A tabela mostra o esperado e o encontrado; a trava logo
-- depois desfaz tudo se alguma divergir.
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS conferencia_db27;
CREATE TEMPORARY TABLE conferencia_db27 (
  item       VARCHAR(90) NOT NULL,
  esperado   INT         NOT NULL,
  encontrado INT         NOT NULL
);

INSERT INTO conferencia_db27 (item, esperado, encontrado)
SELECT 'grupos da competição (só o A)', 1, COUNT(*) FROM grupos WHERE competicao_id = @comp
UNION ALL SELECT 'grupo B depois de apagado', 0, COUNT(*) FROM grupos WHERE competicao_id = @comp AND nome = 'B'
UNION ALL SELECT 'equipes no grupo A (CEBC, CEJA, CETI e VITORIA LIMA)', 4, COUNT(*) FROM equipes e
           INNER JOIN escolas s ON s.id = e.escola_id
           WHERE e.competicao_id = @comp AND e.grupo_id = @grupo_a AND s.nome IN ('CEBC', 'CEJA', 'CETI', 'VITORIA LIMA')
UNION ALL SELECT 'equipes da competição sem grupo ou fora do A', 0, COUNT(*) FROM equipes
           WHERE competicao_id = @comp AND (grupo_id IS NULL OR grupo_id <> @grupo_a)
UNION ALL SELECT 'jogos de grupo da competição', 4, COUNT(*) FROM jogos WHERE competicao_id = @comp AND fase = 'GRUPOS'
UNION ALL SELECT 'jogos de grupo no grupo A', 4, COUNT(*) FROM jogos WHERE competicao_id = @comp AND fase = 'GRUPOS' AND grupo_id = @grupo_a
UNION ALL SELECT 'competição com 1 grupo, 2 classificados, 0 melhores segundos e próxima fase FINAL', 1, COUNT(*) FROM competicoes
           WHERE id = @comp AND qtd_grupos = 1 AND classificados_por_grupo = 2 AND melhores_segundos = 0 AND proxima_fase = 'FINAL';

SELECT item, esperado, encontrado,
       CASE WHEN esperado = encontrado THEN 'ok' ELSE 'DIVERGE' END AS situacao
  FROM conferencia_db27;

-- Trava 2: qualquer divergência para aqui, antes do COMMIT
DROP TEMPORARY TABLE IF EXISTS trava_conferencia_db27;
CREATE TEMPORARY TABLE trava_conferencia_db27 (
  item VARCHAR(90) NOT NULL,
  ok   TINYINT     NOT NULL,
  CONSTRAINT conferencia_do_db27_divergiu CHECK (ok = 1)
);
INSERT INTO trava_conferencia_db27 (item, ok)
SELECT item, CASE WHEN esperado = encontrado THEN 1 ELSE 0 END FROM conferencia_db27;

DROP TEMPORARY TABLE trava_conferencia_db27;
DROP TEMPORARY TABLE conferencia_db27;

COMMIT;

-- ---------------------------------------------------------------------
-- Depois do COMMIT, só leitura: a competição como ficou
-- ---------------------------------------------------------------------
SELECT c.id AS competicao_id, c.qtd_grupos, c.classificados_por_grupo, c.melhores_segundos, c.proxima_fase, c.turno
  FROM competicoes c WHERE c.id = @comp;

SELECT j.numero_tabela, j.numero_jogo, g.nome AS grupo, j.data_hora, s1.nome AS equipe_1, s2.nome AS equipe_2
  FROM jogos j
  LEFT JOIN grupos g ON g.id = j.grupo_id
  INNER JOIN equipes e1 ON e1.id = j.equipe_1_id INNER JOIN escolas s1 ON s1.id = e1.escola_id
  INNER JOIN equipes e2 ON e2.id = j.equipe_2_id INNER JOIN escolas s2 ON s2.id = e2.escola_id
 WHERE j.competicao_id = @comp
 ORDER BY j.numero_jogo;
