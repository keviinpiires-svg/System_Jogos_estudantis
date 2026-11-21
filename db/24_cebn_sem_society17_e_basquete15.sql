-- =====================================================================
-- MIGRAÇÃO 24 — CEBN sai do Futebol Society Sub 17 M e do Basquete Sub 15 M (05/11/2026)
--
-- Pedido do chefe: o CEBN não terá equipe nessas duas competições. Saem os
-- jogos do CEBN e a equipe do CEBN de cada uma. Nada mais é mexido: nenhum
-- outro jogo é renumerado (nem o numero_tabela nem o numero_jogo) e a regra de
-- disputa das competições não muda.
--
--   Futebol Society Sub 17 Masculino (grupos A e B, 1 classificado por grupo,
--   próxima fase FINAL):
--     sai o nº 127 (jogo 2)  19/11 08:40  CEBN x CEBC   Campo Society Arena Social
--     sai o nº 195 (jogo 5)  20/11 10:00  CEJA x CEBN   Campo Society do CETI
--   Basquete Sub 15 Masculino (grupo único A, 2 classificados, próxima fase FINAL):
--     sai o nº 103 (jogo 1)  19/11 10:40  CEBN x Conveniada  Quadra do CEBC
--     sai o nº 112 (jogo 2)  19/11 16:40  CEBN x CEBC        Quadra do CEBC
--
-- NUMERAÇÃO: o numero_tabela é o número da tabela do chefe, único e com
-- lacunas; os quatro jogos deixam mais lacunas e nenhum outro é renumerado. O
-- numero_jogo de cada competição fica com buraco (Society: 1, 3, 4; Basquete: 3
-- e 4) porque este script NÃO renumera. O excluirJogo do sistema compactaria;
-- se quiserem sem buraco, é um passo à parte, a aprovar.
--
-- Cada jogo é achado pelo número da tabela + a competição + a data, a hora, o
-- local, o status e as duas escolas, pelos nomes.
--
-- SEGURANÇA: uma transação só. Duas travas (CHECK em tabela temporária, erro
-- 3819 no MySQL e 4025 no MariaDB) param o script sem gravar nada:
--   cebn_nas_duas_competicoes_nao_bate_com_a_descricao   (antes de qualquer escrita)
--   conferencia_do_db24_divergiu                          (antes do COMMIT)
-- A primeira só deixa passar dois estados: o ORIGINAL (os 4 jogos como no
-- "antes", AGENDADOS, sem placar, sem súmula, sem set; as duas equipes do CEBN
-- sem atleta inscrito, sem súmula e sem colocação, com jogo só nesses 4) e o
-- JÁ FEITO (as duas equipes e os 4 jogos já não existem). Qualquer outra coisa
-- — placar, súmula, set, atleta ou colocação, jogo a mais, só uma das duas
-- competições já feita — para o script.
-- No cliente mysql o erro encerra a sessão e a transação é desfeita. No
-- DBeaver, se um comando falhar, rode ROLLBACK antes de qualquer outra coisa.
--
-- IDEMPOTENTE: rodado de novo depois, cai no estado "já feito", não grava
-- nada e as conferências passam.
--
-- Só dados. MySQL 8.0.16+ ou MariaDB 10.2+ (CHECK de verdade). Faça o dump
-- do banco antes.
-- =====================================================================

SET NAMES utf8mb4;

START TRANSACTION;

-- ---------------------------------------------------------------------
-- Os ids que o script usa, achados pelos nomes (NULL se não existirem)
-- ---------------------------------------------------------------------
SET @soc := (SELECT c.id FROM competicoes c
               INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.slug = 'futebol-society'
               INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = 'Sub 17'
              WHERE c.genero = 'MASCULINO');
SET @bas := (SELECT c.id FROM competicoes c
               INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.slug = 'basquete'
               INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = 'Sub 15'
              WHERE c.genero = 'MASCULINO');

SET @eq_soc := (SELECT e.id FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'CEBN' WHERE e.competicao_id = @soc);
SET @eq_bas := (SELECT e.id FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'CEBN' WHERE e.competicao_id = @bas);

SET @j127 := (SELECT id FROM jogos WHERE competicao_id = @soc AND numero_tabela = 127);
SET @j195 := (SELECT id FROM jogos WHERE competicao_id = @soc AND numero_tabela = 195);
SET @j103 := (SELECT id FROM jogos WHERE competicao_id = @bas AND numero_tabela = 103);
SET @j112 := (SELECT id FROM jogos WHERE competicao_id = @bas AND numero_tabela = 112);

-- ---------------------------------------------------------------------
-- Cada jogo é o esperado? (data, hora, local, as duas escolas, na ordem)
-- ---------------------------------------------------------------------
SET @ok_127 := (SELECT COUNT(*) FROM jogos j
                  INNER JOIN locais_disputa l ON l.id = j.local_id AND l.nome = 'Campo Society Arena Social'
                  INNER JOIN equipes e1 ON e1.id = j.equipe_1_id INNER JOIN escolas s1 ON s1.id = e1.escola_id AND s1.nome = 'CEBN'
                  INNER JOIN equipes e2 ON e2.id = j.equipe_2_id INNER JOIN escolas s2 ON s2.id = e2.escola_id AND s2.nome = 'CEBC'
                 WHERE j.id = @j127 AND j.data_hora = '2026-11-19 08:40:00');
SET @ok_195 := (SELECT COUNT(*) FROM jogos j
                  INNER JOIN locais_disputa l ON l.id = j.local_id AND l.nome = 'Campo Society do CETI'
                  INNER JOIN equipes e1 ON e1.id = j.equipe_1_id INNER JOIN escolas s1 ON s1.id = e1.escola_id AND s1.nome = 'CEJA'
                  INNER JOIN equipes e2 ON e2.id = j.equipe_2_id INNER JOIN escolas s2 ON s2.id = e2.escola_id AND s2.nome = 'CEBN'
                 WHERE j.id = @j195 AND j.data_hora = '2026-11-20 10:00:00');
SET @ok_103 := (SELECT COUNT(*) FROM jogos j
                  INNER JOIN locais_disputa l ON l.id = j.local_id AND l.nome = 'Quadra do CEBC'
                  INNER JOIN equipes e1 ON e1.id = j.equipe_1_id INNER JOIN escolas s1 ON s1.id = e1.escola_id AND s1.nome = 'CEBN'
                  INNER JOIN equipes e2 ON e2.id = j.equipe_2_id INNER JOIN escolas s2 ON s2.id = e2.escola_id AND s2.nome = 'Conveniada'
                 WHERE j.id = @j103 AND j.data_hora = '2026-11-19 10:40:00');
SET @ok_112 := (SELECT COUNT(*) FROM jogos j
                  INNER JOIN locais_disputa l ON l.id = j.local_id AND l.nome = 'Quadra do CEBC'
                  INNER JOIN equipes e1 ON e1.id = j.equipe_1_id INNER JOIN escolas s1 ON s1.id = e1.escola_id AND s1.nome = 'CEBN'
                  INNER JOIN equipes e2 ON e2.id = j.equipe_2_id INNER JOIN escolas s2 ON s2.id = e2.escola_id AND s2.nome = 'CEBC'
                 WHERE j.id = @j112 AND j.data_hora = '2026-11-19 16:40:00');

-- "Limpo" = AGENDADO, sem placar, sem pênaltis, sem vencedor, sem súmula, sem set
SET @limpos := (
  SELECT COUNT(*) FROM jogos j
   WHERE j.id IN (COALESCE(@j127, 0), COALESCE(@j195, 0), COALESCE(@j103, 0), COALESCE(@j112, 0))
     AND j.status = 'AGENDADO' AND j.placar_1 IS NULL AND j.placar_2 IS NULL
     AND j.penaltis_1 IS NULL AND j.penaltis_2 IS NULL AND j.vencedor_equipe_id IS NULL
     AND NOT EXISTS (SELECT 1 FROM sumula_equipes x WHERE x.jogo_id = j.id)
     AND NOT EXISTS (SELECT 1 FROM sumula_atletas x WHERE x.jogo_id = j.id)
     AND NOT EXISTS (SELECT 1 FROM jogo_sets x WHERE x.jogo_id = j.id));

-- As equipes do CEBN: sem atleta, sem súmula, sem colocação, e com jogo só nos
-- 2 jogos esperados de cada competição
SET @cebn_limpo := (
  SELECT COUNT(*) FROM equipes e
   WHERE e.id IN (COALESCE(@eq_soc, 0), COALESCE(@eq_bas, 0))
     AND NOT EXISTS (SELECT 1 FROM inscricoes_atletas x WHERE x.equipe_id = e.id)
     AND NOT EXISTS (SELECT 1 FROM sumula_equipes x WHERE x.equipe_id = e.id)
     AND NOT EXISTS (SELECT 1 FROM sumula_atletas x WHERE x.equipe_id = e.id)
     AND NOT EXISTS (SELECT 1 FROM colocacoes_finais x WHERE x.equipe_id = e.id)
     AND (SELECT COUNT(*) FROM jogos g WHERE g.equipe_1_id = e.id OR g.equipe_2_id = e.id) = 2
     AND (SELECT COUNT(*) FROM jogos g WHERE (g.equipe_1_id = e.id OR g.equipe_2_id = e.id)
              AND g.id IN (COALESCE(@j127, 0), COALESCE(@j195, 0), COALESCE(@j103, 0), COALESCE(@j112, 0))) = 2);

SET @eq_na_soc := (SELECT COUNT(*) FROM equipes WHERE competicao_id = @soc);
SET @eq_na_bas := (SELECT COUNT(*) FROM equipes WHERE competicao_id = @bas);
SET @jg_na_soc := (SELECT COUNT(*) FROM jogos WHERE competicao_id = @soc);
SET @jg_na_bas := (SELECT COUNT(*) FROM jogos WHERE competicao_id = @bas);
SET @grupo_soc := (SELECT COUNT(*) FROM jogos WHERE competicao_id = @soc AND fase = 'GRUPOS');
SET @grupo_bas := (SELECT COUNT(*) FROM jogos WHERE competicao_id = @bas AND fase = 'GRUPOS');

-- Os dois estados aceitos
SET @estado := CASE
  WHEN @soc IS NOT NULL AND @bas IS NOT NULL AND @eq_soc IS NOT NULL AND @eq_bas IS NOT NULL
       AND @ok_127 = 1 AND @ok_195 = 1 AND @ok_103 = 1 AND @ok_112 = 1 AND @limpos = 4 AND @cebn_limpo = 2
       AND @eq_na_soc = 5 AND @eq_na_bas = 4 AND @jg_na_soc = 5 AND @jg_na_bas = 4 THEN 'original: aplica'
  WHEN @soc IS NOT NULL AND @bas IS NOT NULL AND @eq_soc IS NULL AND @eq_bas IS NULL
       AND @j127 IS NULL AND @j195 IS NULL AND @j103 IS NULL AND @j112 IS NULL
       AND @eq_na_soc = 4 AND @eq_na_bas = 3 AND @grupo_soc = 3 AND @grupo_bas = 2 THEN 'já feito: nada a fazer'
  ELSE 'não bate' END;

-- O que foi achado (antes da trava, para ver o motivo se ela parar)
SELECT @soc AS society17, @bas AS basquete15, @eq_na_soc AS equipes_soc, @eq_na_bas AS equipes_bas,
       @jg_na_soc AS jogos_soc, @jg_na_bas AS jogos_bas, @ok_127 AS ok_127, @ok_195 AS ok_195,
       @ok_103 AS ok_103, @ok_112 AS ok_112, @limpos AS jogos_limpos, @cebn_limpo AS cebn_limpo, @estado AS estado;

-- ---------------------------------------------------------------------
-- Trava 1: só o estado original ou o já feito. Qualquer outra coisa para aqui.
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS trava_cebn_db24;
CREATE TEMPORARY TABLE trava_cebn_db24 (
  estado VARCHAR(40) NOT NULL,
  ok     TINYINT     NOT NULL,
  CONSTRAINT cebn_nas_duas_competicoes_nao_bate_com_a_descricao CHECK (ok = 1)
);
INSERT INTO trava_cebn_db24 (estado, ok)
VALUES (@estado, CASE WHEN @estado = 'não bate' THEN 0 ELSE 1 END);

SELECT @estado AS db24;
DROP TEMPORARY TABLE trava_cebn_db24;

-- ---------------------------------------------------------------------
-- As remoções, só no estado original (no "já feito" nenhuma linha casa).
-- Primeiro os jogos, depois as equipes que ficaram sem jogo.
-- ---------------------------------------------------------------------
DELETE FROM jogos
 WHERE id IN (COALESCE(@j127, 0), COALESCE(@j195, 0), COALESCE(@j103, 0), COALESCE(@j112, 0))
   AND @estado = 'original: aplica';

DELETE FROM equipes
 WHERE id IN (COALESCE(@eq_soc, 0), COALESCE(@eq_bas, 0))
   AND @estado = 'original: aplica';

-- ---------------------------------------------------------------------
-- Conferências. A tabela mostra o esperado e o encontrado; a trava logo
-- depois desfaz tudo se alguma divergir.
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS conferencia_db24;
CREATE TEMPORARY TABLE conferencia_db24 (
  item       VARCHAR(90) NOT NULL,
  esperado   INT         NOT NULL,
  encontrado INT         NOT NULL
);

INSERT INTO conferencia_db24 (item, esperado, encontrado)
SELECT 'Society Sub 17 M: equipes', 4, COUNT(*) FROM equipes WHERE competicao_id = @soc
UNION ALL SELECT 'Basquete Sub 15 M: equipes', 3, COUNT(*) FROM equipes WHERE competicao_id = @bas
UNION ALL SELECT 'Society Sub 17 M: jogos de grupo (a final, se existir, fica de fora)', 3, COUNT(*) FROM jogos
           WHERE competicao_id = @soc AND fase = 'GRUPOS'
UNION ALL SELECT 'Basquete Sub 15 M: jogos de grupo (a final, se existir, fica de fora)', 2, COUNT(*) FROM jogos
           WHERE competicao_id = @bas AND fase = 'GRUPOS'
UNION ALL SELECT 'equipes do CEBN nas duas competições', 0, COUNT(*) FROM equipes e
           INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'CEBN'
           WHERE e.competicao_id IN (COALESCE(@soc, 0), COALESCE(@bas, 0))
UNION ALL SELECT 'jogos do CEBN nas duas competições', 0, COUNT(*) FROM jogos j
           INNER JOIN equipes e ON e.id IN (j.equipe_1_id, j.equipe_2_id)
           INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'CEBN'
           WHERE j.competicao_id IN (COALESCE(@soc, 0), COALESCE(@bas, 0))
UNION ALL SELECT 'jogos nº 127, 195, 103 e 112 nessas competições', 0, COUNT(*) FROM jogos
           WHERE (competicao_id = @soc AND numero_tabela IN (127, 195))
              OR (competicao_id = @bas AND numero_tabela IN (103, 112))
UNION ALL SELECT 'os 5 jogos que ficam (nº 37, 129, 132, 211, 216) continuam lá', 5, COUNT(*) FROM jogos
           WHERE (competicao_id = @soc AND numero_tabela IN (37, 129, 132))
              OR (competicao_id = @bas AND numero_tabela IN (211, 216))
UNION ALL SELECT 'números da tabela repetidos no banco', 0, COUNT(*) - COUNT(DISTINCT numero_tabela) FROM jogos
           WHERE numero_tabela IS NOT NULL;

SELECT item, esperado, encontrado,
       CASE WHEN esperado = encontrado THEN 'ok' ELSE 'DIVERGE' END AS situacao
  FROM conferencia_db24;

-- Trava 2: qualquer divergência para aqui, antes do COMMIT
DROP TEMPORARY TABLE IF EXISTS trava_conferencia_db24;
CREATE TEMPORARY TABLE trava_conferencia_db24 (
  item VARCHAR(90) NOT NULL,
  ok   TINYINT     NOT NULL,
  CONSTRAINT conferencia_do_db24_divergiu CHECK (ok = 1)
);
INSERT INTO trava_conferencia_db24 (item, ok)
SELECT item, CASE WHEN esperado = encontrado THEN 1 ELSE 0 END FROM conferencia_db24;

DROP TEMPORARY TABLE trava_conferencia_db24;
DROP TEMPORARY TABLE conferencia_db24;

COMMIT;

-- ---------------------------------------------------------------------
-- Depois do COMMIT, só leitura: as duas competições como ficaram (o formato
-- de disputa NÃO foi mexido)
-- ---------------------------------------------------------------------
SELECT c.id AS competicao_id, m.nome AS modalidade, cat.nome AS categoria, c.qtd_grupos,
       c.classificados_por_grupo, c.proxima_fase, c.turno
  FROM competicoes c
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
 WHERE c.id IN (COALESCE(@soc, 0), COALESCE(@bas, 0));

SELECT j.competicao_id, j.numero_tabela, j.numero_jogo, g.nome AS grupo, j.data_hora,
       s1.nome AS equipe_1, s2.nome AS equipe_2, j.status
  FROM jogos j
  INNER JOIN equipes e1 ON e1.id = j.equipe_1_id INNER JOIN escolas s1 ON s1.id = e1.escola_id
  INNER JOIN equipes e2 ON e2.id = j.equipe_2_id INNER JOIN escolas s2 ON s2.id = e2.escola_id
  LEFT JOIN grupos g ON g.id = j.grupo_id
 WHERE j.competicao_id IN (COALESCE(@soc, 0), COALESCE(@bas, 0))
 ORDER BY j.competicao_id, j.numero_jogo;
