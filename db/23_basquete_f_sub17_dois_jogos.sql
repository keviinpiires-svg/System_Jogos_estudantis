-- =====================================================================
-- MIGRAÇÃO 23 — Basquete Feminino Sub 17 com 2 equipes e 2 jogos (04/11/2026)
--
-- Pedido do chefe: a competição passa a ter só CEJA e CEBC, com dois jogos,
-- um em cada mandante. A CETI sai. Só os jogos que já existem são mexidos;
-- hora, data, local e numero_jogo ficam como estão.
--
--   antes:  nº 102 (jogo 1)  19/11 10:00  CETI x CEJA
--           nº 209 (jogo 2)  20/11 08:00  CEBC x CETI
--           nº 217 (jogo 3)  20/11 13:20  CEJA x CEBC
--   depois: nº 102 (jogo 1)  19/11 10:00  CEJA x CEBC
--           nº 209 (jogo 2)  20/11 08:00  CEBC x CEJA
--           nº 217 sai (era o último, numero_jogo 3: não deixa buraco)
--           a equipe CETI sai da competição
--
-- NUMERAÇÃO: o numero_tabela é o número da tabela do chefe, único mas com
-- lacunas desde o db/20 (237 jogos, números de 1 a 295). Tirar o 217 deixa
-- mais uma lacuna e NÃO renumera nenhum outro jogo. O numero_jogo da
-- competição (1, 2, 3) fica 1 e 2, sem buraco, porque o 217 era o último.
--
-- Cada jogo é achado pelo número da tabela + a competição (Basquete
-- Feminino Sub 17) + a data, a hora, o local e as duas escolas, pelos nomes.
--
-- Esta migração NÃO muda a regra de disputa da competição (grupo único, 2
-- classificados, próxima fase FINAL, turno único). O resultado final mostra
-- o formato atual, para a decisão do chefe: as outras competições de 2
-- equipes e 2 jogos usam "melhor de dois jogos" (ida e volta, sem fase seguinte).
--
-- SEGURANÇA: uma transação só. Duas travas (CHECK em tabela temporária, erro
-- 3819 no MySQL e 4025 no MariaDB) param o script sem gravar nada:
--   basquete_f_sub17_nao_bate_com_a_descricao   (antes de qualquer escrita)
--   conferencia_do_db23_divergiu                 (antes do COMMIT)
-- A primeira só deixa passar dois estados: o ORIGINAL (os 3 jogos como no
-- "antes", todos AGENDADOS, sem placar, sem súmula, sem set; a CETI sem atleta
-- inscrito, sem súmula e sem colocação, e com jogo só nos nº 102 e 209) e o
-- JÁ FEITO (como no "depois": não muda nada). Qualquer outra coisa — jogo com
-- súmula ou placar, jogo a mais (por exemplo, uma final já gerada), equipe com
-- atleta, hora ou local diferentes — para o script.
-- No cliente mysql o erro encerra a sessão e a transação é desfeita. No
-- DBeaver, se um comando falhar, rode ROLLBACK antes de qualquer outra coisa.
--
-- IDEMPOTENTE: rodado de novo depois, cai no estado "já feito", não grava
-- nada e as conferências passam.
--
-- Só dados. Não depende dos outros scripts além do 20. MySQL 8.0.16+ ou
-- MariaDB 10.2+ (CHECK de verdade). Faça o dump do banco antes.
-- =====================================================================

SET NAMES utf8mb4;

START TRANSACTION;

-- ---------------------------------------------------------------------
-- Os ids que o script usa, achados pelos nomes (NULL se não existirem)
-- ---------------------------------------------------------------------
SET @comp := (SELECT c.id FROM competicoes c
                INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.slug = 'basquete'
                INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = 'Sub 17'
               WHERE c.genero = 'FEMININO');

SET @eq_ceja := (SELECT e.id FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'CEJA' WHERE e.competicao_id = @comp);
SET @eq_cebc := (SELECT e.id FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'CEBC' WHERE e.competicao_id = @comp);
SET @eq_ceti := (SELECT e.id FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'CETI' WHERE e.competicao_id = @comp);

SET @j102 := (SELECT id FROM jogos WHERE competicao_id = @comp AND numero_tabela = 102);
SET @j209 := (SELECT id FROM jogos WHERE competicao_id = @comp AND numero_tabela = 209);
SET @j217 := (SELECT id FROM jogos WHERE competicao_id = @comp AND numero_tabela = 217);

-- ---------------------------------------------------------------------
-- O que cada jogo é (1 = bate). "Limpo" = AGENDADO, sem placar, sem
-- pênaltis, sem vencedor, sem súmula, sem set.
-- ---------------------------------------------------------------------
SET @limpos := (
  SELECT COUNT(*) FROM jogos j
   WHERE j.id IN (COALESCE(@j102, 0), COALESCE(@j209, 0), COALESCE(@j217, 0))
     AND j.status = 'AGENDADO' AND j.placar_1 IS NULL AND j.placar_2 IS NULL
     AND j.penaltis_1 IS NULL AND j.penaltis_2 IS NULL AND j.vencedor_equipe_id IS NULL
     AND NOT EXISTS (SELECT 1 FROM sumula_equipes x WHERE x.jogo_id = j.id)
     AND NOT EXISTS (SELECT 1 FROM sumula_atletas x WHERE x.jogo_id = j.id)
     AND NOT EXISTS (SELECT 1 FROM jogo_sets x WHERE x.jogo_id = j.id));

-- Jogo achado com as equipes, o dia e a hora esperados, no CEBC
SET @orig_102 := (SELECT COUNT(*) FROM jogos j INNER JOIN locais_disputa l ON l.id = j.local_id AND l.nome = 'Quadra do CEBC'
                   WHERE j.id = @j102 AND j.equipe_1_id = @eq_ceti AND j.equipe_2_id = @eq_ceja AND j.data_hora = '2026-11-19 10:00:00');
SET @orig_209 := (SELECT COUNT(*) FROM jogos j INNER JOIN locais_disputa l ON l.id = j.local_id AND l.nome = 'Quadra do CEBC'
                   WHERE j.id = @j209 AND j.equipe_1_id = @eq_cebc AND j.equipe_2_id = @eq_ceti AND j.data_hora = '2026-11-20 08:00:00');
SET @orig_217 := (SELECT COUNT(*) FROM jogos j INNER JOIN locais_disputa l ON l.id = j.local_id AND l.nome = 'Quadra do CEBC'
                   WHERE j.id = @j217 AND j.equipe_1_id = @eq_ceja AND j.equipe_2_id = @eq_cebc AND j.data_hora = '2026-11-20 13:20:00');

SET @novo_102 := (SELECT COUNT(*) FROM jogos j INNER JOIN locais_disputa l ON l.id = j.local_id AND l.nome = 'Quadra do CEBC'
                   WHERE j.id = @j102 AND j.equipe_1_id = @eq_ceja AND j.equipe_2_id = @eq_cebc AND j.data_hora = '2026-11-19 10:00:00');
SET @novo_209 := (SELECT COUNT(*) FROM jogos j INNER JOIN locais_disputa l ON l.id = j.local_id AND l.nome = 'Quadra do CEBC'
                   WHERE j.id = @j209 AND j.equipe_1_id = @eq_cebc AND j.equipe_2_id = @eq_ceja AND j.data_hora = '2026-11-20 08:00:00');

-- A CETI: sem atleta, sem súmula, sem colocação, e com jogo só nos nº 102 e 209
SET @ceti_limpa := (SELECT COUNT(*) FROM equipes e
                     WHERE e.id = @eq_ceti
                       AND NOT EXISTS (SELECT 1 FROM inscricoes_atletas x WHERE x.equipe_id = e.id)
                       AND NOT EXISTS (SELECT 1 FROM sumula_equipes x WHERE x.equipe_id = e.id)
                       AND NOT EXISTS (SELECT 1 FROM sumula_atletas x WHERE x.equipe_id = e.id)
                       AND NOT EXISTS (SELECT 1 FROM colocacoes_finais x WHERE x.equipe_id = e.id)
                       AND (SELECT COUNT(*) FROM jogos g WHERE g.equipe_1_id = e.id OR g.equipe_2_id = e.id) = 2
                       AND (SELECT COUNT(*) FROM jogos g WHERE (g.equipe_1_id = e.id OR g.equipe_2_id = e.id)
                                AND g.id IN (COALESCE(@j102, 0), COALESCE(@j209, 0))) = 2);

SET @equipes_na_competicao := (SELECT COUNT(*) FROM equipes WHERE competicao_id = @comp);
SET @jogos_na_competicao   := (SELECT COUNT(*) FROM jogos WHERE competicao_id = @comp);
SET @jogos_de_grupo        := (SELECT COUNT(*) FROM jogos WHERE competicao_id = @comp AND fase = 'GRUPOS');

-- Os dois estados aceitos
SET @estado := CASE
  WHEN @comp IS NOT NULL AND @eq_ceja IS NOT NULL AND @eq_cebc IS NOT NULL AND @eq_ceti IS NOT NULL
       AND @orig_102 = 1 AND @orig_209 = 1 AND @orig_217 = 1 AND @limpos = 3
       AND @ceti_limpa = 1 AND @equipes_na_competicao = 3 AND @jogos_na_competicao = 3 THEN 'original: aplica'
  WHEN @comp IS NOT NULL AND @eq_ceja IS NOT NULL AND @eq_cebc IS NOT NULL AND @eq_ceti IS NULL
       AND @novo_102 = 1 AND @novo_209 = 1 AND @j217 IS NULL
       AND @equipes_na_competicao = 2 AND @jogos_de_grupo = 2 THEN 'já feito: nada a fazer'
  ELSE 'não bate' END;

-- O que foi achado (antes da trava, para ver o motivo se ela parar)
SELECT @comp AS competicao_id, @equipes_na_competicao AS equipes, @jogos_na_competicao AS jogos,
       @orig_102 AS orig_102, @orig_209 AS orig_209, @orig_217 AS orig_217, @limpos AS jogos_limpos,
       @ceti_limpa AS ceti_limpa, @novo_102 AS novo_102, @novo_209 AS novo_209, @estado AS estado;

-- ---------------------------------------------------------------------
-- Trava 1: só o estado original ou o já feito. Qualquer outra coisa para aqui.
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS trava_basquete_db23;
CREATE TEMPORARY TABLE trava_basquete_db23 (
  estado VARCHAR(40) NOT NULL,
  ok     TINYINT     NOT NULL,
  CONSTRAINT basquete_f_sub17_nao_bate_com_a_descricao CHECK (ok = 1)
);
INSERT INTO trava_basquete_db23 (estado, ok)
VALUES (@estado, CASE WHEN @estado = 'não bate' THEN 0 ELSE 1 END);

SELECT @estado AS db23;
DROP TEMPORARY TABLE trava_basquete_db23;

-- ---------------------------------------------------------------------
-- As mudanças, só no estado original (no "já feito" nenhuma linha casa).
-- Primeiro os jogos, depois a equipe que ficou sem jogo.
-- ---------------------------------------------------------------------
UPDATE jogos SET equipe_1_id = @eq_ceja, equipe_2_id = @eq_cebc
 WHERE id = @j102 AND @estado = 'original: aplica';

UPDATE jogos SET equipe_2_id = @eq_ceja
 WHERE id = @j209 AND @estado = 'original: aplica';

DELETE FROM jogos WHERE id = @j217 AND @estado = 'original: aplica';

DELETE FROM equipes WHERE id = @eq_ceti AND @estado = 'original: aplica';

-- ---------------------------------------------------------------------
-- Conferências. A tabela mostra o esperado e o encontrado; a trava logo
-- depois desfaz tudo se alguma divergir.
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS conferencia_db23;
CREATE TEMPORARY TABLE conferencia_db23 (
  item       VARCHAR(90) NOT NULL,
  esperado   INT         NOT NULL,
  encontrado INT         NOT NULL
);

INSERT INTO conferencia_db23 (item, esperado, encontrado)
SELECT 'equipes da competição', 2, COUNT(*) FROM equipes WHERE competicao_id = @comp
UNION ALL SELECT 'equipes da competição que são CEJA ou CEBC', 2, COUNT(*) FROM equipes e
           INNER JOIN escolas s ON s.id = e.escola_id AND s.nome IN ('CEJA', 'CEBC') WHERE e.competicao_id = @comp
UNION ALL SELECT 'jogos de grupo da competição (a final, se existir, fica de fora)', 2, COUNT(*) FROM jogos
           WHERE competicao_id = @comp AND fase = 'GRUPOS'
UNION ALL SELECT 'jogos da competição que não são de grupo nem a final', 0, COUNT(*) FROM jogos
           WHERE competicao_id = @comp AND fase NOT IN ('GRUPOS', 'FINAL')
UNION ALL SELECT 'jogo nº 102 é CEJA x CEBC, 19/11 10:00, Quadra do CEBC', 1, COUNT(*) FROM jogos j
           INNER JOIN locais_disputa l ON l.id = j.local_id
           INNER JOIN equipes e1 ON e1.id = j.equipe_1_id INNER JOIN escolas s1 ON s1.id = e1.escola_id
           INNER JOIN equipes e2 ON e2.id = j.equipe_2_id INNER JOIN escolas s2 ON s2.id = e2.escola_id
           WHERE j.competicao_id = @comp AND j.numero_tabela = 102 AND j.data_hora = '2026-11-19 10:00:00'
             AND l.nome = 'Quadra do CEBC' AND s1.nome = 'CEJA' AND s2.nome = 'CEBC'
UNION ALL SELECT 'jogo nº 209 é CEBC x CEJA, 20/11 08:00, Quadra do CEBC', 1, COUNT(*) FROM jogos j
           INNER JOIN locais_disputa l ON l.id = j.local_id
           INNER JOIN equipes e1 ON e1.id = j.equipe_1_id INNER JOIN escolas s1 ON s1.id = e1.escola_id
           INNER JOIN equipes e2 ON e2.id = j.equipe_2_id INNER JOIN escolas s2 ON s2.id = e2.escola_id
           WHERE j.competicao_id = @comp AND j.numero_tabela = 209 AND j.data_hora = '2026-11-20 08:00:00'
             AND l.nome = 'Quadra do CEBC' AND s1.nome = 'CEBC' AND s2.nome = 'CEJA'
UNION ALL SELECT 'jogo nº 217 na competição (removido)', 0, COUNT(*) FROM jogos
           WHERE competicao_id = @comp AND numero_tabela = 217
UNION ALL SELECT 'jogos de grupo com a mesma equipe dos dois lados ou com a CETI', 0, COUNT(*) FROM jogos j
           WHERE j.competicao_id = @comp AND j.fase = 'GRUPOS'
             AND (j.equipe_1_id = j.equipe_2_id OR @eq_ceti IN (j.equipe_1_id, j.equipe_2_id))
UNION ALL SELECT 'numero_jogo dos jogos de grupo diferentes de 1 e 2 (sem buraco)', 0, COUNT(*) FROM jogos
           WHERE competicao_id = @comp AND fase = 'GRUPOS' AND numero_jogo NOT IN (1, 2)
UNION ALL SELECT 'números da tabela repetidos no banco', 0, COUNT(*) - COUNT(DISTINCT numero_tabela) FROM jogos
           WHERE numero_tabela IS NOT NULL
UNION ALL SELECT 'equipe CETI nesta competição', 0, COUNT(*) FROM equipes e
           INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'CETI' WHERE e.competicao_id = @comp;

SELECT item, esperado, encontrado,
       CASE WHEN esperado = encontrado THEN 'ok' ELSE 'DIVERGE' END AS situacao
  FROM conferencia_db23;

-- Trava 2: qualquer divergência para aqui, antes do COMMIT
DROP TEMPORARY TABLE IF EXISTS trava_conferencia_db23;
CREATE TEMPORARY TABLE trava_conferencia_db23 (
  item VARCHAR(90) NOT NULL,
  ok   TINYINT     NOT NULL,
  CONSTRAINT conferencia_do_db23_divergiu CHECK (ok = 1)
);
INSERT INTO trava_conferencia_db23 (item, ok)
SELECT item, CASE WHEN esperado = encontrado THEN 1 ELSE 0 END FROM conferencia_db23;

DROP TEMPORARY TABLE trava_conferencia_db23;
DROP TEMPORARY TABLE conferencia_db23;

COMMIT;

-- ---------------------------------------------------------------------
-- Depois do COMMIT, só leitura: a competição como ficou (inclui o formato
-- de disputa atual, para a decisão do chefe sobre "melhor de dois jogos")
-- ---------------------------------------------------------------------
SELECT c.id AS competicao_id, c.qtd_grupos, c.classificados_por_grupo, c.proxima_fase, c.turno
  FROM competicoes c WHERE c.id = @comp;

SELECT j.numero_tabela, j.numero_jogo, j.data_hora, l.nome AS local, s1.nome AS equipe_1, s2.nome AS equipe_2, j.status
  FROM jogos j
  INNER JOIN locais_disputa l ON l.id = j.local_id
  INNER JOIN equipes e1 ON e1.id = j.equipe_1_id INNER JOIN escolas s1 ON s1.id = e1.escola_id
  INNER JOIN equipes e2 ON e2.id = j.equipe_2_id INNER JOIN escolas s2 ON s2.id = e2.escola_id
 WHERE j.competicao_id = @comp
 ORDER BY j.numero_jogo;
