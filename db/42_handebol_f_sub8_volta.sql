-- =====================================================================
-- MIGRAÇÃO 42 — Handebol Sub 8 Feminino volta à tabela: ACM x José Dias,
-- jogos 102 e 275 (decisão de 14/11/2026: seguir a TABELA DE JOGOS 20268)
--
-- O db/35 (12/11/2026) tirou do sistema os dois jogos (então 102 e 279) e as
-- equipes do ACM e da José Dias nesta competição; a regra de disputa e o grupo A
-- ficaram. A tabela 20268 tem os jogos 102 e 275, e o usuário decidiu (14/11)
-- seguir a tabela. Este script:
--
--   1) recria as equipes do ACM e da JOSE DIAS no Handebol Sub 8 Feminino, no
--      grupo A (o único da competição), SEM atletas (as inscrições são feitas
--      depois pela página);
--   2) recria os dois jogos como jogos de GRUPO (o "FINAL" da tabela é só o 2º
--      jogo entre as mesmas duas equipes, como nas outras competições de 2
--      equipes com "melhor de dois jogos"), AGENDADOS:
--        nº 102: 19/11/2026 11:20, Quadra do CEBC, ACM x JOSE DIAS (numero_jogo 1)
--        nº 275: 21/11/2026 14:40, Quadra do CETI, ACM x JOSE DIAS (numero_jogo 2)
--   3) NÃO muda a regra de disputa: o db/35 não a alterou, e ela já é a das outras
--      competições de 2 equipes com ida e volta (1 grupo, 0 classificados, 0
--      melhores segundos, próxima fase NENHUMA, turno IDA_E_VOLTA). Se estiver
--      diferente disso, o script PARA (trava db42_competicao_nao_bate).
--
-- A competição é achada por modalidade + categoria + gênero (nunca por id).
--
-- IDEMPOTENTE: cada equipe e cada jogo é APLICAR (ainda não existe) ou FEITO (já
-- existe como descrito acima); rodado de novo, cai tudo em FEITO e não grava nada.
--
-- SEGURANÇA: uma transação só. Quatro travas (CHECK em tabela temporária, erro
-- 3819 no MySQL e 4025 no MariaDB) param o script sem gravar nada:
--   db42_competicao_nao_bate  (antes de escrever: competição ou grupo não achado;
--        regra diferente da descrita; equipe de outra escola na competição; jogo
--        da competição que não é um dos dois; equipe ou jogo diferente do descrito)
--   db42_numero_ou_horario_ocupado (antes de escrever: o numero_tabela 102 ou 275
--        usado por outro jogo; outro jogo no mesmo local a menos de 10 minutos —
--        a regra de conflito de local do sistema, regrasProvisorias.conflitoDeLocal;
--        local não cadastrado)
--   db42_estado_misto         (antes de escrever: parte APLICAR e parte FEITO)
--   db42_conferencia_divergiu (antes do COMMIT: 302 jogos, 229 de grupo e 73 de
--        mata-mata; por dia, grupo 36/92/76/25 e mata-mata 0/0/9/64; numero_tabela
--        de 1 a 302, todos únicos; nenhuma equipe em dois jogos no mesmo dia e hora;
--        nenhum local com dois jogos no mesmo dia e hora; a competição como acima)
-- No DBeaver, se um comando falhar, rode ROLLBACK antes de qualquer outra coisa.
--
-- Aviso que NÃO aborta (depois do COMMIT, só leitura): ESCOLA em outro jogo no
-- mesmo dia e hora do 102 ou do 275 (equipe e quadra diferentes; ex.: a José Dias
-- joga o nº 116, Futsal Sub 8 M, às 19/11 11:20 na Quadra do CETI).
--
-- Só dados. Rode depois do 41. MySQL 8.0.16+ ou MariaDB 10.2+. Faça o dump antes,
-- na produção. Não entra no banco de fumaça. Sem dado de aluno.
-- Próximo script: o 43.
-- =====================================================================

SET NAMES utf8mb4;

START TRANSACTION;

-- Trava os jogos: nada muda no meio do script (numero_tabela e horários)
SELECT COUNT(*) AS jogos_travados FROM jogos FOR UPDATE;

-- ---------------------------------------------------------------------
-- A competição, o grupo e a regra
-- ---------------------------------------------------------------------
SET @comps_db42 = (SELECT COUNT(*) FROM competicoes c
                     INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.nome = 'Handebol'
                     INNER JOIN categorias k ON k.id = c.categoria_id AND k.nome = 'Sub 8'
                    WHERE c.genero = 'FEMININO');
SET @comp_db42 = (SELECT MAX(c.id) FROM competicoes c
                    INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.nome = 'Handebol'
                    INNER JOIN categorias k ON k.id = c.categoria_id AND k.nome = 'Sub 8'
                   WHERE c.genero = 'FEMININO');
SET @grupos_db42 = (SELECT COUNT(*) FROM grupos WHERE competicao_id = @comp_db42);
SET @grupo_db42  = (SELECT MAX(id) FROM grupos WHERE competicao_id = @comp_db42 AND nome = 'A');
SET @regra_ok_db42 = (SELECT COUNT(*) FROM competicoes c
                       WHERE c.id = @comp_db42 AND c.qtd_grupos = 1 AND c.classificados_por_grupo = 0
                         AND c.melhores_segundos = 0 AND c.proxima_fase = 'NENHUMA' AND c.turno = 'IDA_E_VOLTA');
SET @outras_equipes_db42 = (SELECT COUNT(*) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id
                             WHERE e.competicao_id = @comp_db42 AND s.nome NOT IN ('ACM', 'JOSE DIAS'));

SELECT c.id IS NOT NULL AS achada, @comps_db42 AS competicoes, @grupos_db42 AS grupos,
       c.qtd_grupos, c.classificados_por_grupo, c.melhores_segundos, c.proxima_fase, c.turno,
       @regra_ok_db42 AS regra_ok, @outras_equipes_db42 AS equipes_de_outras_escolas
  FROM (SELECT 1) d LEFT JOIN competicoes c ON c.id = @comp_db42;

-- ---------------------------------------------------------------------
-- As duas equipes
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS equipe_db42;
CREATE TEMPORARY TABLE equipe_db42 (
  escola     VARCHAR(100) NOT NULL,
  escola_id  INT          NULL,
  achadas    INT          NOT NULL DEFAULT 0,
  equipe_id  INT          NULL,
  grupo_ok   TINYINT      NOT NULL DEFAULT 0,
  estado     VARCHAR(10)  NOT NULL DEFAULT ''
);
INSERT INTO equipe_db42 (escola) VALUES ('ACM'), ('JOSE DIAS');
UPDATE equipe_db42 x
   SET x.escola_id = (SELECT MAX(s.id) FROM escolas s WHERE s.nome = x.escola),
       x.achadas   = (SELECT COUNT(*) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id
                       WHERE e.competicao_id = @comp_db42 AND s.nome = x.escola),
       x.equipe_id = (SELECT MAX(e.id) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id
                       WHERE e.competicao_id = @comp_db42 AND s.nome = x.escola);
UPDATE equipe_db42 x
   SET x.grupo_ok = CASE WHEN (SELECT e.grupo_id FROM equipes e WHERE e.id = x.equipe_id) <=> @grupo_db42 THEN 1 ELSE 0 END;
UPDATE equipe_db42 x
   SET x.estado = CASE WHEN x.escola_id IS NULL OR @comp_db42 IS NULL THEN ''
                       WHEN x.achadas = 0 THEN 'APLICAR'
                       WHEN x.achadas = 1 AND x.grupo_ok = 1 THEN 'FEITO'
                       ELSE '' END;
SELECT escola, achadas, grupo_ok, estado FROM equipe_db42;

-- ---------------------------------------------------------------------
-- Os dois jogos
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS jogo_db42;
CREATE TEMPORARY TABLE jogo_db42 (
  numero_tabela INT          NOT NULL PRIMARY KEY,
  numero_jogo   INT          NOT NULL,
  data_hora     DATETIME     NOT NULL,
  local_nome    VARCHAR(80)  NOT NULL,
  local_id      INT          NULL,
  com_numero    INT          NOT NULL DEFAULT 0,   -- jogos com este numero_tabela (qualquer competição)
  como_descrito INT          NOT NULL DEFAULT 0,   -- jogos com este numero_tabela exatamente como descrito
  local_ocupado INT          NOT NULL DEFAULT 0,   -- OUTRO jogo no mesmo local a menos de 10 minutos
  estado        VARCHAR(10)  NOT NULL DEFAULT ''
);
INSERT INTO jogo_db42 (numero_tabela, numero_jogo, data_hora, local_nome) VALUES
  (102, 1, '2026-11-19 11:20:00', 'Quadra do CEBC'),
  (275, 2, '2026-11-21 14:40:00', 'Quadra do CETI');

UPDATE jogo_db42 t
   SET t.local_id = (SELECT MAX(l.id) FROM locais_disputa l WHERE l.nome = t.local_nome),
       t.com_numero = (SELECT COUNT(*) FROM jogos j WHERE j.numero_tabela = t.numero_tabela);
UPDATE jogo_db42 t
   SET t.como_descrito = (SELECT COUNT(*) FROM jogos j
                            INNER JOIN equipes e1 ON e1.id = j.equipe_1_id INNER JOIN escolas s1 ON s1.id = e1.escola_id
                            INNER JOIN equipes e2 ON e2.id = j.equipe_2_id INNER JOIN escolas s2 ON s2.id = e2.escola_id
                           WHERE j.numero_tabela = t.numero_tabela AND j.competicao_id = @comp_db42
                             AND j.fase = 'GRUPOS' AND j.grupo_id <=> @grupo_db42 AND j.numero_jogo = t.numero_jogo
                             AND j.data_hora = t.data_hora AND j.local_id = t.local_id
                             AND s1.nome = 'ACM' AND s2.nome = 'JOSE DIAS'),
       t.local_ocupado = (SELECT COUNT(*) FROM jogos j
                           WHERE j.local_id = t.local_id AND j.data_hora IS NOT NULL
                             AND ABS(TIMESTAMPDIFF(MINUTE, j.data_hora, t.data_hora)) < 10
                             AND NOT (j.numero_tabela <=> t.numero_tabela));
UPDATE jogo_db42 t
   SET t.estado = CASE WHEN t.local_id IS NULL THEN ''
                       WHEN t.com_numero = 0 THEN 'APLICAR'
                       WHEN t.com_numero = 1 AND t.como_descrito = 1 THEN 'FEITO'
                       ELSE '' END;

SET @jogos_na_comp_db42 = (SELECT COUNT(*) FROM jogos WHERE competicao_id = @comp_db42);
SET @jogos_feitos_db42  = (SELECT COUNT(*) FROM jogo_db42 WHERE estado = 'FEITO');

SELECT numero_tabela, numero_jogo, DATE_FORMAT(data_hora, '%d/%m %H:%i') AS quando, local_nome,
       com_numero, como_descrito, local_ocupado, estado
  FROM jogo_db42 ORDER BY numero_tabela;

SET @aplicar_db42 = (SELECT COUNT(*) FROM equipe_db42 WHERE estado = 'APLICAR')
                  + (SELECT COUNT(*) FROM jogo_db42 WHERE estado = 'APLICAR');
SET @feito_db42   = (SELECT COUNT(*) FROM equipe_db42 WHERE estado = 'FEITO')
                  + (SELECT COUNT(*) FROM jogo_db42 WHERE estado = 'FEITO');
SELECT @aplicar_db42 AS itens_a_aplicar, @feito_db42 AS itens_ja_feitos, @jogos_na_comp_db42 AS jogos_na_competicao;

-- ---------------------------------------------------------------------
-- Trava 1: a competição
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS trava_comp_db42;
CREATE TEMPORARY TABLE trava_comp_db42 (
  item VARCHAR(80) NOT NULL,
  ok   TINYINT     NOT NULL,
  CONSTRAINT db42_competicao_nao_bate CHECK (ok = 1)
);
INSERT INTO trava_comp_db42 (item, ok) VALUES
  ('uma competição Handebol Sub 8 Feminino', CASE WHEN @comps_db42 = 1 THEN 1 ELSE 0 END),
  ('só o grupo A', CASE WHEN @grupos_db42 = 1 AND @grupo_db42 IS NOT NULL THEN 1 ELSE 0 END),
  ('regra: 1 grupo, 0 classificados, NENHUMA, IDA_E_VOLTA', CASE WHEN @regra_ok_db42 = 1 THEN 1 ELSE 0 END),
  ('nenhuma equipe de outra escola', CASE WHEN @outras_equipes_db42 = 0 THEN 1 ELSE 0 END),
  -- jogos da competição: nenhum (antes) ou só os dois (depois)
  ('jogos da competição: só o 102 e o 275', CASE WHEN @jogos_na_comp_db42 = @jogos_feitos_db42 THEN 1 ELSE 0 END);
INSERT INTO trava_comp_db42 (item, ok)
SELECT CONCAT('equipe ', escola), CASE WHEN estado <> '' THEN 1 ELSE 0 END FROM equipe_db42;
DROP TEMPORARY TABLE trava_comp_db42;

-- Trava 2: número e horário livres
DROP TEMPORARY TABLE IF EXISTS trava_ocupado_db42;
CREATE TEMPORARY TABLE trava_ocupado_db42 (
  item VARCHAR(80) NOT NULL,
  ok   TINYINT     NOT NULL,
  CONSTRAINT db42_numero_ou_horario_ocupado CHECK (ok = 1)
);
INSERT INTO trava_ocupado_db42 (item, ok)
SELECT CONCAT('jogo ', numero_tabela), CASE WHEN estado <> '' AND local_ocupado = 0 THEN 1 ELSE 0 END FROM jogo_db42;
DROP TEMPORARY TABLE trava_ocupado_db42;

-- Trava 3: estado misto
DROP TEMPORARY TABLE IF EXISTS trava_misto_db42;
CREATE TEMPORARY TABLE trava_misto_db42 (
  item VARCHAR(80) NOT NULL,
  ok   TINYINT     NOT NULL,
  CONSTRAINT db42_estado_misto CHECK (ok = 1)
);
INSERT INTO trava_misto_db42 (item, ok)
SELECT 'tudo APLICAR ou tudo FEITO', CASE WHEN @aplicar_db42 = 0 OR @feito_db42 = 0 THEN 1 ELSE 0 END;
DROP TEMPORARY TABLE trava_misto_db42;

-- ---------------------------------------------------------------------
-- As escritas (só no que é APLICAR)
-- ---------------------------------------------------------------------
-- 1) As duas equipes, no grupo A, sem atletas
INSERT INTO equipes (competicao_id, escola_id, grupo_id)
SELECT @comp_db42, x.escola_id, @grupo_db42 FROM equipe_db42 x WHERE x.estado = 'APLICAR';
SET @equipes_criadas_db42 = ROW_COUNT();

SET @acm_db42 = (SELECT MAX(e.id) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id
                  WHERE e.competicao_id = @comp_db42 AND s.nome = 'ACM');
SET @jd_db42  = (SELECT MAX(e.id) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id
                  WHERE e.competicao_id = @comp_db42 AND s.nome = 'JOSE DIAS');

-- 2) Os dois jogos de grupo, ACM x JOSE DIAS
INSERT INTO jogos (competicao_id, numero_jogo, numero_tabela, fase, grupo_id, local_id, data_hora, equipe_1_id, equipe_2_id, status)
SELECT @comp_db42, t.numero_jogo, t.numero_tabela, 'GRUPOS', @grupo_db42, t.local_id, t.data_hora, @acm_db42, @jd_db42, 'AGENDADO'
  FROM jogo_db42 t WHERE t.estado = 'APLICAR'
 ORDER BY t.numero_jogo;
SET @jogos_criados_db42 = ROW_COUNT();

-- ---------------------------------------------------------------------
-- Conferências
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS conferencia_db42;
CREATE TEMPORARY TABLE conferencia_db42 (
  item       VARCHAR(120) NOT NULL,
  esperado   INT          NOT NULL,
  encontrado INT          NOT NULL
);
INSERT INTO conferencia_db42 SELECT 'jogos (302)', 302, COUNT(*) FROM jogos;
INSERT INTO conferencia_db42 SELECT 'jogos de grupo (229)', 229, COUNT(*) FROM jogos WHERE fase = 'GRUPOS';
INSERT INTO conferencia_db42 SELECT 'jogos de mata-mata (73)', 73, COUNT(*) FROM jogos WHERE fase <> 'GRUPOS';
INSERT INTO conferencia_db42 SELECT '18/11: grupo (36)', 36, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-18';
INSERT INTO conferencia_db42 SELECT '19/11: grupo (92)', 92, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-19';
INSERT INTO conferencia_db42 SELECT '20/11: grupo (76)', 76, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-20';
INSERT INTO conferencia_db42 SELECT '21/11: grupo (25)', 25, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-21';
INSERT INTO conferencia_db42 SELECT '18/11: mata-mata (0)', 0, COUNT(*) FROM jogos WHERE fase <> 'GRUPOS' AND DATE(data_hora) = '2026-11-18';
INSERT INTO conferencia_db42 SELECT '19/11: mata-mata (0)', 0, COUNT(*) FROM jogos WHERE fase <> 'GRUPOS' AND DATE(data_hora) = '2026-11-19';
INSERT INTO conferencia_db42 SELECT '20/11: mata-mata (9)', 9, COUNT(*) FROM jogos WHERE fase <> 'GRUPOS' AND DATE(data_hora) = '2026-11-20';
INSERT INTO conferencia_db42 SELECT '21/11: mata-mata (64)', 64, COUNT(*) FROM jogos WHERE fase <> 'GRUPOS' AND DATE(data_hora) = '2026-11-21';
INSERT INTO conferencia_db42
SELECT 'numero_tabela de 1 a 302, todos únicos (302)', 302,
       CASE WHEN MIN(numero_tabela) = 1 AND MAX(numero_tabela) = 302 AND SUM(numero_tabela IS NULL) = 0
            THEN COUNT(DISTINCT numero_tabela) ELSE -1 END
  FROM jogos;
INSERT INTO conferencia_db42
SELECT 'equipe em dois jogos no mesmo dia e hora (0)', 0, COUNT(*)
  FROM (SELECT x.data_hora, x.equipe_id
          FROM (SELECT data_hora, equipe_1_id AS equipe_id FROM jogos
                UNION ALL SELECT data_hora, equipe_2_id FROM jogos) x
         WHERE x.equipe_id IS NOT NULL AND x.data_hora IS NOT NULL
         GROUP BY x.data_hora, x.equipe_id
        HAVING COUNT(*) > 1) d;
INSERT INTO conferencia_db42
SELECT 'local com dois jogos no mesmo dia e hora (0)', 0, COUNT(*)
  FROM (SELECT local_id, data_hora FROM jogos
         WHERE local_id IS NOT NULL AND data_hora IS NOT NULL
         GROUP BY local_id, data_hora HAVING COUNT(*) > 1) d;
INSERT INTO conferencia_db42
SELECT 'Handebol Sub 8 F: equipes ACM e JOSE DIAS no grupo A (2)', 2, COUNT(*)
  FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id
 WHERE e.competicao_id = @comp_db42 AND e.grupo_id = @grupo_db42 AND s.nome IN ('ACM', 'JOSE DIAS');
INSERT INTO conferencia_db42
SELECT 'Handebol Sub 8 F: equipes no total (2)', 2, COUNT(*) FROM equipes WHERE competicao_id = @comp_db42;
INSERT INTO conferencia_db42
SELECT 'Handebol Sub 8 F: os jogos 102 e 275 como descritos (2)', 2, COUNT(*)
  FROM jogos j
  INNER JOIN jogo_db42 t ON t.numero_tabela = j.numero_tabela
 WHERE j.competicao_id = @comp_db42 AND j.fase = 'GRUPOS' AND j.grupo_id = @grupo_db42
   AND j.numero_jogo = t.numero_jogo AND j.data_hora = t.data_hora AND j.local_id = t.local_id
   AND j.equipe_1_id = @acm_db42 AND j.equipe_2_id = @jd_db42 AND j.status = 'AGENDADO';
INSERT INTO conferencia_db42
SELECT 'Handebol Sub 8 F: jogos no total (2)', 2, COUNT(*) FROM jogos WHERE competicao_id = @comp_db42;
INSERT INTO conferencia_db42
SELECT 'Handebol Sub 8 F: regra de ida e volta igual (1)', 1, COUNT(*) FROM competicoes c
 WHERE c.id = @comp_db42 AND c.qtd_grupos = 1 AND c.classificados_por_grupo = 0
   AND c.melhores_segundos = 0 AND c.proxima_fase = 'NENHUMA' AND c.turno = 'IDA_E_VOLTA';

SELECT item, esperado, encontrado, CASE WHEN esperado = encontrado THEN 'ok' ELSE 'DIVERGE' END AS situacao
  FROM conferencia_db42;

-- Trava 4: qualquer divergência para aqui, antes do COMMIT
DROP TEMPORARY TABLE IF EXISTS trava_conferencia_db42;
CREATE TEMPORARY TABLE trava_conferencia_db42 (
  item VARCHAR(120) NOT NULL,
  ok   TINYINT      NOT NULL,
  CONSTRAINT db42_conferencia_divergiu CHECK (ok = 1)
);
INSERT INTO trava_conferencia_db42 (item, ok)
SELECT item, CASE WHEN esperado = encontrado THEN 1 ELSE 0 END FROM conferencia_db42;
DROP TEMPORARY TABLE trava_conferencia_db42;
DROP TEMPORARY TABLE conferencia_db42;
DROP TEMPORARY TABLE equipe_db42;

COMMIT;

-- ---------------------------------------------------------------------
-- Depois do COMMIT, só leitura
-- ---------------------------------------------------------------------
SELECT @equipes_criadas_db42 AS equipes_criadas, @jogos_criados_db42 AS jogos_criados;

SELECT j.numero_jogo, j.numero_tabela, j.fase, g.nome AS grupo, DATE_FORMAT(j.data_hora, '%d/%m %H:%i') AS quando,
       l.nome AS local_, s1.nome AS equipe_1, s2.nome AS equipe_2, j.status
  FROM jogos j
  LEFT JOIN grupos g ON g.id = j.grupo_id
  LEFT JOIN locais_disputa l ON l.id = j.local_id
  LEFT JOIN equipes e1 ON e1.id = j.equipe_1_id LEFT JOIN escolas s1 ON s1.id = e1.escola_id
  LEFT JOIN equipes e2 ON e2.id = j.equipe_2_id LEFT JOIN escolas s2 ON s2.id = e2.escola_id
 WHERE j.competicao_id = @comp_db42
 ORDER BY j.numero_jogo;

-- Aviso (não aborta): a escola em OUTRO jogo no mesmo dia e hora do 102 ou do 275
SELECT DATE_FORMAT(j.data_hora, '%d/%m %H:%i') AS quando, s.nome AS escola,
       CONCAT('nº ', j.numero_tabela, ' ', m.nome, ' ', k.nome, ' ',
              CASE c.genero WHEN 'MISTO' THEN 'Misto' WHEN 'FEMININO' THEN 'F' ELSE 'M' END,
              ' (', COALESCE(l.nome, 'sem local'), ')') AS outro_jogo
  FROM jogo_db42 t
  INNER JOIN jogos j ON j.data_hora = t.data_hora AND j.numero_tabela <> t.numero_tabela
  INNER JOIN equipes e ON e.id IN (j.equipe_1_id, j.equipe_2_id)
  INNER JOIN escolas s ON s.id = e.escola_id AND s.nome IN ('ACM', 'JOSE DIAS')
  INNER JOIN competicoes c ON c.id = j.competicao_id
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias k ON k.id = c.categoria_id
  LEFT JOIN locais_disputa l ON l.id = j.local_id
 ORDER BY j.data_hora, s.nome;

SELECT DATE_FORMAT(data_hora, '%d/%m') AS dia, SUM(fase = 'GRUPOS') AS grupo, SUM(fase <> 'GRUPOS') AS mata_mata, COUNT(*) AS total
  FROM jogos GROUP BY DATE_FORMAT(data_hora, '%d/%m') ORDER BY dia;

DROP TEMPORARY TABLE jogo_db42;
