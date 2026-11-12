-- =====================================================================
-- MIGRAÇÃO 39 — Baleado Sub 9: a José Dias passa do Masculino para o
-- Feminino, e os dois trocam de formato de mata-mata (tabela 20267 do chefe,
-- 12/11/2026; ver docs/importacao/contexto_tabela_20267.md, fora do git)
--
-- Estado final (dia, hora, local e numero_tabela NÃO mudam; nenhum jogo é
-- criado nem apagado):
--
--   BALEADO SUB 9 MASCULINO — 5 equipes, 2 grupos, 1 classificado por grupo,
--   FINAL direta:
--     Grupo A: Adelieta Ramalho e Marlene Santana (jogos 15 e 166, o mesmo
--              confronto duas vezes); o 166 passa a ser Marlene x Adelieta.
--     Grupo B: Teodulo Leite, Maria da Glória e Francisco Amorim (16, 76 e 210).
--     Final 281 (1º A x 1º B): passa do Feminino para o Masculino.
--     A equipe da José Dias sai (só se não tiver inscrição, súmula nem colocação).
--
--   BALEADO SUB 9 FEMININO — 6 equipes, 2 grupos, 2 classificados por grupo,
--   SEMIFINAL:
--     Grupo A: Maria da Glória, Portal do Saber e Francisco Amorim (165, 185 e 271).
--     Grupo B: José Dias (equipe criada), Adelieta Ramalho e Emiliano Zapata
--              (167, 211 e 272); o 211 passa do Masculino para o Feminino
--              (José Dias x Adelieta) e o 272 passa a ser José Dias x Emiliano.
--     Semifinais 218 (1º A x 2º B) e 233 (1º B x 2º A) e final 282 (vencedor
--     218 x vencedor 233): passam do Masculino para o Feminino.
--
-- Também: a regra de disputa das duas competições (classificados por grupo e
-- próxima fase), o grupo das vagas dos jogos que trocam de competição (tipo,
-- posição, jogo de origem e rótulo não mudam) e o numero_jogo das duas
-- competições, RENUMERADO por data e hora (em duas fases, por causa do
-- índice único por competição; o numero_tabela não muda).
--
-- Os jogos são achados pelo numero_tabela, conferindo que são do Baleado
-- Sub 9; as competições, por modalidade + categoria + gênero (nunca por id).
--
-- IDEMPOTENTE: cada item (jogo, equipe, regra) é APLICAR ou FEITO; rodado de
-- novo, cai tudo em FEITO e não grava nada.
--
-- SEGURANÇA: uma transação só. Três travas (CHECK em tabela temporária;
-- erro 3819 no MySQL e 4025 no MariaDB) param o script sem gravar nada:
--   db39_jogo_nao_bate        (antes de escrever: jogo não achado ou fora do
--        Baleado Sub 9; confronto, competição ou grupo diferente do de antes
--        e do de depois; jogo com placar, vencedor, cobranças, súmula, set ou
--        status diferente de AGENDADO; mata-mata com equipe já preenchida;
--        jogo a mais nas duas competições)
--   db39_equipe_ou_regra_nao_bate (antes de escrever: competição ou grupo não
--        achado; equipe da José Dias no Masculino com inscrição, súmula ou
--        colocação; regra de disputa diferente da de antes e da de depois)
--   db39_conferencia_divergiu (antes do COMMIT: 229 jogos de grupo e 75 de
--        mata-mata, 36/92/77/24 por dia, numero_tabela único, nenhuma equipe
--        em dois jogos no mesmo dia e hora, dia/hora/local/numero_tabela dos
--        15 jogos iguais aos de antes, as duas competições como acima,
--        numero_jogo de 1 a N sem buraco, vagas apontando para grupo da
--        própria competição)
-- No DBeaver, se um comando falhar, rode ROLLBACK antes de qualquer outra coisa.
--
-- Aviso que NÃO aborta: ESCOLA em dois jogos no mesmo dia e hora envolvendo
-- estes jogos (equipes e quadras diferentes; ex.: Adelieta às 20/11 10:40,
-- jogos 166 e 153).
--
-- Só dados. Rode depois do 38. MySQL 8.0.16+ ou MariaDB 10.2+. Faça o dump
-- antes. Não entra no banco de fumaça. NÃO repita o db/34 depois deste.
-- =====================================================================

SET NAMES utf8mb4;

START TRANSACTION;

-- Trava as competições do Baleado Sub 9 (e, com elas, a numeração dos jogos)
SELECT COUNT(*) AS competicoes_travadas
  FROM competicoes c
  INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.nome = 'Baleado'
  INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = 'Sub 9'
 FOR UPDATE;

-- ---------------------------------------------------------------------
-- As duas competições e os seus grupos
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS comp_db39;
CREATE TEMPORARY TABLE comp_db39 (
  genero         VARCHAR(10) NOT NULL,
  achadas        INT         NOT NULL DEFAULT 0,
  comp_id        INT         NULL,
  grupo_a        INT         NULL,
  grupo_b        INT         NULL,
  grupos         INT         NOT NULL DEFAULT 0,
  -- regra de disputa: antes e depois
  classif_antes  INT         NOT NULL,
  fase_antes     VARCHAR(20) NOT NULL,
  classif_fim    INT         NOT NULL,
  fase_fim       VARCHAR(20) NOT NULL,
  classif_atual  INT         NULL,
  fase_atual     VARCHAR(20) NULL,
  qtd_grupos     INT         NULL,
  melhores       INT         NULL,
  turno          VARCHAR(20) NULL,
  estado_regra   VARCHAR(10) NOT NULL DEFAULT ''
);
INSERT INTO comp_db39 (genero, classif_antes, fase_antes, classif_fim, fase_fim) VALUES
  ('MASCULINO', 2, 'SEMIFINAL', 1, 'FINAL'),
  ('FEMININO',  1, 'FINAL',     2, 'SEMIFINAL');

UPDATE comp_db39 x
   SET x.achadas = (SELECT COUNT(*) FROM competicoes c
                      INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.nome = 'Baleado'
                      INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = 'Sub 9'
                     WHERE c.genero = x.genero),
       x.comp_id = (SELECT MAX(c.id) FROM competicoes c
                      INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.nome = 'Baleado'
                      INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = 'Sub 9'
                     WHERE c.genero = x.genero);
UPDATE comp_db39 x
   SET x.grupo_a = (SELECT MAX(g.id) FROM grupos g WHERE g.competicao_id = x.comp_id AND g.nome = 'A'),
       x.grupo_b = (SELECT MAX(g.id) FROM grupos g WHERE g.competicao_id = x.comp_id AND g.nome = 'B'),
       x.grupos  = (SELECT COUNT(*) FROM grupos g WHERE g.competicao_id = x.comp_id),
       x.classif_atual = (SELECT c.classificados_por_grupo FROM competicoes c WHERE c.id = x.comp_id),
       x.fase_atual    = (SELECT c.proxima_fase FROM competicoes c WHERE c.id = x.comp_id),
       x.qtd_grupos    = (SELECT c.qtd_grupos FROM competicoes c WHERE c.id = x.comp_id),
       x.melhores      = (SELECT c.melhores_segundos FROM competicoes c WHERE c.id = x.comp_id),
       x.turno         = (SELECT c.turno FROM competicoes c WHERE c.id = x.comp_id);
UPDATE comp_db39 x
   SET x.estado_regra = CASE
         WHEN x.classif_atual = x.classif_fim AND x.fase_atual = x.fase_fim THEN 'FEITO'
         WHEN x.classif_atual = x.classif_antes AND x.fase_atual = x.fase_antes THEN 'APLICAR'
         ELSE '' END;

SET @cm_db39  = (SELECT comp_id FROM comp_db39 WHERE genero = 'MASCULINO');
SET @cf_db39  = (SELECT comp_id FROM comp_db39 WHERE genero = 'FEMININO');
SET @gma_db39 = (SELECT grupo_a FROM comp_db39 WHERE genero = 'MASCULINO');
SET @gmb_db39 = (SELECT grupo_b FROM comp_db39 WHERE genero = 'MASCULINO');
SET @gfa_db39 = (SELECT grupo_a FROM comp_db39 WHERE genero = 'FEMININO');
SET @gfb_db39 = (SELECT grupo_b FROM comp_db39 WHERE genero = 'FEMININO');

SELECT genero, achadas, grupos, qtd_grupos, melhores, turno,
       CONCAT(classif_atual, ' / ', fase_atual) AS regra_atual,
       CONCAT(classif_fim, ' / ', fase_fim) AS regra_final, estado_regra
  FROM comp_db39 ORDER BY genero DESC;

-- ---------------------------------------------------------------------
-- As equipes: a José Dias sai do Masculino e entra no Feminino (grupo B)
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS equipe_db39;
CREATE TEMPORARY TABLE equipe_db39 (
  item        VARCHAR(40) NOT NULL,
  achadas     INT         NOT NULL DEFAULT 0,
  equipe_id   INT         NULL,
  registros   INT         NOT NULL DEFAULT 0,   -- inscrição, súmula ou colocação
  grupo_ok    TINYINT     NOT NULL DEFAULT 1,
  estado      VARCHAR(10) NOT NULL DEFAULT ''
);
INSERT INTO equipe_db39 (item) VALUES ('JOSE DIAS sai do Masculino'), ('JOSE DIAS entra no Feminino');

UPDATE equipe_db39 x
   SET x.achadas = (SELECT COUNT(*) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'JOSE DIAS'
                     WHERE e.competicao_id = CASE WHEN x.item LIKE '%Masculino' THEN @cm_db39 ELSE @cf_db39 END),
       x.equipe_id = (SELECT MAX(e.id) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'JOSE DIAS'
                       WHERE e.competicao_id = CASE WHEN x.item LIKE '%Masculino' THEN @cm_db39 ELSE @cf_db39 END);
UPDATE equipe_db39 x
   SET x.registros = (SELECT COUNT(*) FROM inscricoes_atletas i WHERE i.equipe_id = x.equipe_id)
                   + (SELECT COUNT(*) FROM sumula_atletas sa WHERE sa.equipe_id = x.equipe_id)
                   + (SELECT COUNT(*) FROM sumula_equipes se WHERE se.equipe_id = x.equipe_id)
                   + (SELECT COUNT(*) FROM colocacoes_finais cf WHERE cf.equipe_id = x.equipe_id),
       x.grupo_ok = CASE WHEN x.item LIKE '%Feminino' AND x.equipe_id IS NOT NULL
                          AND NOT ((SELECT grupo_id FROM equipes WHERE id = x.equipe_id) <=> @gfb_db39) THEN 0 ELSE 1 END;
UPDATE equipe_db39 x
   SET x.estado = CASE
         WHEN x.item LIKE '%Masculino' AND x.achadas = 1 AND x.registros = 0 THEN 'APLICAR'
         WHEN x.item LIKE '%Masculino' AND x.achadas = 0 THEN 'FEITO'
         WHEN x.item LIKE '%Feminino'  AND x.achadas = 0 THEN 'APLICAR'
         WHEN x.item LIKE '%Feminino'  AND x.achadas = 1 AND x.grupo_ok = 1 THEN 'FEITO'
         ELSE '' END;

SELECT item, achadas, registros, grupo_ok, estado FROM equipe_db39;

-- ---------------------------------------------------------------------
-- Os 15 jogos do Baleado Sub 9 (11 de grupo e 4 de mata-mata): antes e depois
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS alvo_db39;
CREATE TEMPORARY TABLE alvo_db39 (
  numero_tabela INT          NOT NULL,
  fase          VARCHAR(20)  NOT NULL,
  genero_antes  VARCHAR(10)  NOT NULL,
  grupo_antes   VARCHAR(2)   NULL,
  e1_antes      VARCHAR(100) NULL,
  e2_antes      VARCHAR(100) NULL,
  genero_fim    VARCHAR(10)  NOT NULL,
  grupo_fim     VARCHAR(2)   NULL,
  e1_fim        VARCHAR(100) NULL,
  e2_fim        VARCHAR(100) NULL,
  -- o que está no banco
  achados       INT          NOT NULL DEFAULT 0,
  jogo_id       INT          NULL,
  genero_atual  VARCHAR(10)  NULL,
  fase_atual    VARCHAR(20)  NULL,
  grupo_atual   VARCHAR(10)  NULL,
  e1_atual      VARCHAR(100) NULL,
  e2_atual      VARCHAR(100) NULL,
  data_hora     DATETIME     NULL,
  local_id      INT          NULL,
  numero_jogo   INT          NULL,
  sujo          INT          NOT NULL DEFAULT 0,   -- placar, súmula, set, status, vaga preenchida
  estado        VARCHAR(10)  NOT NULL DEFAULT '',
  -- o que vai para o banco
  comp_fim      INT          NULL,
  grupo_fim_id  INT          NULL,
  e1_fim_id     INT          NULL,
  e2_fim_id     INT          NULL,
  nj_fim        INT          NULL
);

INSERT INTO alvo_db39 (numero_tabela, fase, genero_antes, grupo_antes, e1_antes, e2_antes, genero_fim, grupo_fim, e1_fim, e2_fim) VALUES
  ( 15, 'GRUPOS',    'MASCULINO', 'A', 'ADELIETA RAMALHO', 'MARLENE SANTANA',  'MASCULINO', 'A', 'ADELIETA RAMALHO', 'MARLENE SANTANA'),
  ( 16, 'GRUPOS',    'MASCULINO', 'B', 'TEODULO LEITE',    'MARIA DA GLORIA',  'MASCULINO', 'B', 'TEODULO LEITE',    'MARIA DA GLORIA'),
  ( 76, 'GRUPOS',    'MASCULINO', 'B', 'MARIA DA GLORIA',  'FRANCISCO AMORIM', 'MASCULINO', 'B', 'MARIA DA GLORIA',  'FRANCISCO AMORIM'),
  (166, 'GRUPOS',    'MASCULINO', 'A', 'MARLENE SANTANA',  'JOSE DIAS',        'MASCULINO', 'A', 'MARLENE SANTANA',  'ADELIETA RAMALHO'),
  (210, 'GRUPOS',    'MASCULINO', 'B', 'FRANCISCO AMORIM', 'TEODULO LEITE',    'MASCULINO', 'B', 'FRANCISCO AMORIM', 'TEODULO LEITE'),
  (211, 'GRUPOS',    'MASCULINO', 'A', 'JOSE DIAS',        'ADELIETA RAMALHO', 'FEMININO',  'B', 'JOSE DIAS',        'ADELIETA RAMALHO'),
  (281, 'FINAL',     'FEMININO',  NULL, NULL, NULL,                            'MASCULINO', NULL, NULL, NULL),
  (165, 'GRUPOS',    'FEMININO',  'A', 'MARIA DA GLORIA',  'PORTAL DO SABER',  'FEMININO',  'A', 'MARIA DA GLORIA',  'PORTAL DO SABER'),
  (167, 'GRUPOS',    'FEMININO',  'B', 'EMILIANO ZAPATA',  'ADELIETA RAMALHO', 'FEMININO',  'B', 'EMILIANO ZAPATA',  'ADELIETA RAMALHO'),
  (185, 'GRUPOS',    'FEMININO',  'A', 'FRANCISCO AMORIM', 'MARIA DA GLORIA',  'FEMININO',  'A', 'FRANCISCO AMORIM', 'MARIA DA GLORIA'),
  (271, 'GRUPOS',    'FEMININO',  'A', 'PORTAL DO SABER',  'FRANCISCO AMORIM', 'FEMININO',  'A', 'PORTAL DO SABER',  'FRANCISCO AMORIM'),
  (272, 'GRUPOS',    'FEMININO',  'B', 'ADELIETA RAMALHO', 'EMILIANO ZAPATA',  'FEMININO',  'B', 'JOSE DIAS',        'EMILIANO ZAPATA'),
  (218, 'SEMIFINAL', 'MASCULINO', NULL, NULL, NULL,                            'FEMININO',  NULL, NULL, NULL),
  (233, 'SEMIFINAL', 'MASCULINO', NULL, NULL, NULL,                            'FEMININO',  NULL, NULL, NULL),
  (282, 'FINAL',     'MASCULINO', NULL, NULL, NULL,                            'FEMININO',  NULL, NULL, NULL);

-- O jogo pelo numero_tabela, só se for do Baleado Sub 9
UPDATE alvo_db39 t
   SET t.achados = (SELECT COUNT(*) FROM jogos j WHERE j.numero_tabela = t.numero_tabela AND j.competicao_id IN (@cm_db39, @cf_db39)),
       t.jogo_id = (SELECT MAX(j.id) FROM jogos j WHERE j.numero_tabela = t.numero_tabela AND j.competicao_id IN (@cm_db39, @cf_db39));

UPDATE alvo_db39 t
  INNER JOIN jogos j ON j.id = t.jogo_id
  INNER JOIN competicoes c ON c.id = j.competicao_id
  LEFT JOIN grupos g ON g.id = j.grupo_id
  LEFT JOIN equipes e1 ON e1.id = j.equipe_1_id
  LEFT JOIN escolas s1 ON s1.id = e1.escola_id
  LEFT JOIN equipes e2 ON e2.id = j.equipe_2_id
  LEFT JOIN escolas s2 ON s2.id = e2.escola_id
   SET t.genero_atual = c.genero, t.fase_atual = j.fase, t.grupo_atual = g.nome,
       t.e1_atual = s1.nome, t.e2_atual = s2.nome,
       t.data_hora = j.data_hora, t.local_id = j.local_id, t.numero_jogo = j.numero_jogo,
       t.sujo = (j.status <> 'AGENDADO') + (j.placar_1 IS NOT NULL) + (j.placar_2 IS NOT NULL)
              + (j.vencedor_equipe_id IS NOT NULL) + (j.penaltis_1 IS NOT NULL) + (j.penaltis_2 IS NOT NULL)
              + (j.baleou_primeiro_equipe_id IS NOT NULL)
              + (SELECT COUNT(*) FROM sumula_atletas sa WHERE sa.jogo_id = j.id)
              + (SELECT COUNT(*) FROM sumula_equipes se WHERE se.jogo_id = j.id)
              + (SELECT COUNT(*) FROM jogo_sets js WHERE js.jogo_id = j.id)
              -- mata-mata com a vaga já preenchida
              + CASE WHEN j.fase <> 'GRUPOS' AND (j.equipe_1_id IS NOT NULL OR j.equipe_2_id IS NOT NULL) THEN 1 ELSE 0 END;

UPDATE alvo_db39 t
   SET t.estado = CASE
         WHEN t.achados <> 1 OR t.fase_atual <> t.fase THEN ''
         WHEN t.genero_atual = t.genero_fim AND t.grupo_atual <=> t.grupo_fim
          AND t.e1_atual <=> t.e1_fim AND t.e2_atual <=> t.e2_fim THEN 'FEITO'
         WHEN t.genero_atual = t.genero_antes AND t.grupo_atual <=> t.grupo_antes
          AND t.e1_atual <=> t.e1_antes AND t.e2_atual <=> t.e2_antes THEN 'APLICAR'
         ELSE '' END;

-- Para onde vai cada jogo
UPDATE alvo_db39 t
   SET t.comp_fim = CASE t.genero_fim WHEN 'MASCULINO' THEN @cm_db39 ELSE @cf_db39 END,
       t.grupo_fim_id = CASE
         WHEN t.grupo_fim IS NULL THEN NULL
         WHEN t.genero_fim = 'MASCULINO' THEN CASE t.grupo_fim WHEN 'A' THEN @gma_db39 ELSE @gmb_db39 END
         ELSE CASE t.grupo_fim WHEN 'A' THEN @gfa_db39 ELSE @gfb_db39 END END;

-- numero_jogo final: por data e hora (e numero_tabela), dentro de cada competição
-- (a tabela temporária é lida uma vez por consulta: erro 1137 — por isso a cópia)
DROP TEMPORARY TABLE IF EXISTS ordem_db39;
CREATE TEMPORARY TABLE ordem_db39 (numero_tabela INT NOT NULL PRIMARY KEY, nj INT NOT NULL);
INSERT INTO ordem_db39 (numero_tabela, nj)
SELECT numero_tabela, ROW_NUMBER() OVER (PARTITION BY genero_fim ORDER BY data_hora, numero_tabela)
  FROM alvo_db39;
UPDATE alvo_db39 t INNER JOIN ordem_db39 o ON o.numero_tabela = t.numero_tabela SET t.nj_fim = o.nj;

SELECT numero_tabela AS tab, fase, achados, DATE_FORMAT(data_hora, '%d/%m %H:%i') AS quando,
       CONCAT(genero_atual, ' ', COALESCE(grupo_atual, '-'), ': ', COALESCE(e1_atual, '?'), ' x ', COALESCE(e2_atual, '?')) AS hoje,
       CONCAT(genero_fim, ' ', COALESCE(grupo_fim, '-'), ': ', COALESCE(e1_fim, '?'), ' x ', COALESCE(e2_fim, '?')) AS depois,
       numero_jogo, nj_fim, sujo, estado
  FROM alvo_db39 ORDER BY genero_fim DESC, nj_fim;

SET @jogos_nas_comps_db39 = (SELECT COUNT(*) FROM jogos WHERE competicao_id IN (@cm_db39, @cf_db39));

-- ---------------------------------------------------------------------
-- Trava 1: os jogos
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS trava_jogo_db39;
CREATE TEMPORARY TABLE trava_jogo_db39 (
  item VARCHAR(60) NOT NULL,
  ok   TINYINT     NOT NULL,
  CONSTRAINT db39_jogo_nao_bate CHECK (ok = 1)
);
INSERT INTO trava_jogo_db39 (item, ok)
SELECT CONCAT('jogo ', numero_tabela), CASE WHEN estado <> '' AND sujo = 0 THEN 1 ELSE 0 END FROM alvo_db39;
INSERT INTO trava_jogo_db39 (item, ok)
SELECT 'as duas competições têm só estes 15 jogos', CASE WHEN @jogos_nas_comps_db39 = 15 THEN 1 ELSE 0 END;
DROP TEMPORARY TABLE trava_jogo_db39;

-- Trava 2: competições, grupos, equipes e regra
DROP TEMPORARY TABLE IF EXISTS trava_equipe_db39;
CREATE TEMPORARY TABLE trava_equipe_db39 (
  item VARCHAR(60) NOT NULL,
  ok   TINYINT     NOT NULL,
  CONSTRAINT db39_equipe_ou_regra_nao_bate CHECK (ok = 1)
);
INSERT INTO trava_equipe_db39 (item, ok)
SELECT CONCAT('competição ', genero),
       CASE WHEN achadas = 1 AND grupos = 2 AND grupo_a IS NOT NULL AND grupo_b IS NOT NULL
             AND qtd_grupos = 2 AND melhores = 0 AND estado_regra <> '' THEN 1 ELSE 0 END
  FROM comp_db39;
INSERT INTO trava_equipe_db39 (item, ok)
SELECT item, CASE WHEN estado <> '' THEN 1 ELSE 0 END FROM equipe_db39;
DROP TEMPORARY TABLE trava_equipe_db39;

-- Contagens de antes (para as conferências)
SET @grupo_antes_db39 = (SELECT COUNT(*) FROM jogos WHERE fase = 'GRUPOS');
SET @mata_antes_db39  = (SELECT COUNT(*) FROM jogos WHERE fase <> 'GRUPOS');
SET @jogos_aplicar_db39 = (SELECT COALESCE(SUM(estado = 'APLICAR'), 0) FROM alvo_db39);
SET @renumerar_db39 = (SELECT COUNT(*) FROM alvo_db39 WHERE numero_jogo <> nj_fim);

-- ---------------------------------------------------------------------
-- As escritas (só no que é APLICAR)
-- ---------------------------------------------------------------------
-- 1) A equipe da José Dias no Feminino, no grupo B
INSERT INTO equipes (competicao_id, escola_id, grupo_id)
SELECT @cf_db39, s.id, @gfb_db39
  FROM escolas s
 WHERE s.nome = 'JOSE DIAS'
   AND (SELECT estado FROM equipe_db39 WHERE item LIKE '%Feminino') = 'APLICAR';
SET @equipe_criada_db39 = ROW_COUNT();

-- As equipes de destino de cada jogo (com a José Dias do Feminino já criada)
UPDATE alvo_db39 t
   SET t.e1_fim_id = (SELECT MAX(e.id) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id
                       WHERE e.competicao_id = t.comp_fim AND s.nome = t.e1_fim),
       t.e2_fim_id = (SELECT MAX(e.id) FROM equipes e INNER JOIN escolas s ON s.id = e.escola_id
                       WHERE e.competicao_id = t.comp_fim AND s.nome = t.e2_fim);

-- 2) numero_jogo, fase 1: tira os 15 do caminho (o índice único é por
--    competição). O número provisório é 10000 + numero_tabela, único no banco
--    inteiro: um jogo que troca de competição não esbarra no número de outro.
UPDATE jogos j
  INNER JOIN alvo_db39 t ON t.jogo_id = j.id
   SET j.numero_jogo = 10000 + j.numero_tabela
 WHERE @jogos_aplicar_db39 + @renumerar_db39 > 0;

-- 3) Os jogos que trocam de competição, de grupo ou de equipe
UPDATE jogos j
  INNER JOIN alvo_db39 t ON t.jogo_id = j.id AND t.estado = 'APLICAR'
   SET j.competicao_id = t.comp_fim, j.grupo_id = t.grupo_fim_id,
       j.equipe_1_id = t.e1_fim_id, j.equipe_2_id = t.e2_fim_id;
SET @jogos_mudados_db39 = ROW_COUNT();

-- 4) numero_jogo, fase 2: de 1 a N por data e hora em cada competição
UPDATE jogos j
  INNER JOIN alvo_db39 t ON t.jogo_id = j.id
   SET j.numero_jogo = t.nj_fim
 WHERE @jogos_aplicar_db39 + @renumerar_db39 > 0;
SET @jogos_renumerados_db39 = ROW_COUNT();

-- 5) Vagas: o grupo da vaga passa a ser o grupo de mesmo nome na competição do jogo
UPDATE jogo_vagas v
  INNER JOIN alvo_db39 t ON t.jogo_id = v.jogo_id
  INNER JOIN jogos j ON j.id = v.jogo_id
  INNER JOIN grupos gv ON gv.id = v.grupo_id
  INNER JOIN grupos gn ON gn.competicao_id = j.competicao_id AND gn.nome = gv.nome
   SET v.grupo_id = gn.id
 WHERE v.tipo = 'GRUPO' AND gv.competicao_id <> j.competicao_id;
SET @vagas_mudadas_db39 = ROW_COUNT();

-- 6) Regra de disputa
UPDATE competicoes c
  INNER JOIN comp_db39 x ON x.comp_id = c.id AND x.estado_regra = 'APLICAR'
   SET c.classificados_por_grupo = x.classif_fim, c.proxima_fase = x.fase_fim;
SET @regras_mudadas_db39 = ROW_COUNT();

-- 7) A equipe da José Dias sai do Masculino
DELETE e FROM equipes e
  INNER JOIN equipe_db39 x ON x.equipe_id = e.id AND x.item LIKE '%Masculino' AND x.estado = 'APLICAR';
SET @equipe_removida_db39 = ROW_COUNT();

-- ---------------------------------------------------------------------
-- Conferências
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS conferencia_db39;
CREATE TEMPORARY TABLE conferencia_db39 (
  item       VARCHAR(120) NOT NULL,
  esperado   INT          NOT NULL,
  encontrado INT          NOT NULL
);

INSERT INTO conferencia_db39 SELECT 'jogos de grupo (229)', 229, COUNT(*) FROM jogos WHERE fase = 'GRUPOS';
INSERT INTO conferencia_db39 SELECT 'jogos de mata-mata (75)', 75, COUNT(*) FROM jogos WHERE fase <> 'GRUPOS';
INSERT INTO conferencia_db39 SELECT 'jogos de grupo = antes', @grupo_antes_db39, COUNT(*) FROM jogos WHERE fase = 'GRUPOS';
INSERT INTO conferencia_db39 SELECT 'jogos de mata-mata = antes', @mata_antes_db39, COUNT(*) FROM jogos WHERE fase <> 'GRUPOS';
INSERT INTO conferencia_db39 SELECT 'jogos de grupo em 18/11 (36)', 36, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-18';
INSERT INTO conferencia_db39 SELECT 'jogos de grupo em 19/11 (92)', 92, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-19';
INSERT INTO conferencia_db39 SELECT 'jogos de grupo em 20/11 (77)', 77, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-20';
INSERT INTO conferencia_db39 SELECT 'jogos de grupo em 21/11 (24)', 24, COUNT(*) FROM jogos WHERE fase = 'GRUPOS' AND DATE(data_hora) = '2026-11-21';
INSERT INTO conferencia_db39
SELECT 'numero_tabela repetido ou vazio (0)', 0,
       (SELECT COUNT(*) FROM jogos WHERE numero_tabela IS NULL)
     + (SELECT COUNT(*) FROM (SELECT numero_tabela FROM jogos GROUP BY numero_tabela HAVING COUNT(*) > 1) d);
INSERT INTO conferencia_db39
SELECT 'equipe em dois jogos no mesmo dia e hora (0)', 0, COUNT(*)
  FROM (SELECT x.data_hora, x.equipe_id
          FROM (SELECT data_hora, equipe_1_id AS equipe_id FROM jogos
                UNION ALL SELECT data_hora, equipe_2_id FROM jogos) x
         WHERE x.equipe_id IS NOT NULL AND x.data_hora IS NOT NULL
         GROUP BY x.data_hora, x.equipe_id
        HAVING COUNT(*) > 1) d;
INSERT INTO conferencia_db39
SELECT 'dos 15 jogos, dia/hora/local/numero_tabela iguais aos de antes (15)', 15, COUNT(*)
  FROM alvo_db39 t INNER JOIN jogos j ON j.id = t.jogo_id
 WHERE j.numero_tabela = t.numero_tabela AND j.data_hora <=> t.data_hora AND j.local_id <=> t.local_id;
INSERT INTO conferencia_db39
SELECT 'dos 15 jogos, no estado final (competição, grupo, equipes, numero_jogo) (15)', 15, COUNT(*)
  FROM alvo_db39 t
  INNER JOIN jogos j ON j.id = t.jogo_id
  LEFT JOIN equipes e1 ON e1.id = j.equipe_1_id LEFT JOIN escolas s1 ON s1.id = e1.escola_id
  LEFT JOIN equipes e2 ON e2.id = j.equipe_2_id LEFT JOIN escolas s2 ON s2.id = e2.escola_id
 WHERE j.competicao_id = t.comp_fim AND j.grupo_id <=> t.grupo_fim_id
   AND s1.nome <=> t.e1_fim AND s2.nome <=> t.e2_fim AND j.numero_jogo = t.nj_fim;
INSERT INTO conferencia_db39
SELECT 'Masculino: equipes (5)', 5, COUNT(*) FROM equipes WHERE competicao_id = @cm_db39;
INSERT INTO conferencia_db39
SELECT 'Masculino: jogos de grupo (5) e finais (1), sem semifinal', 51,
       10 * (SELECT COUNT(*) FROM jogos WHERE competicao_id = @cm_db39 AND fase = 'GRUPOS')
     + (SELECT COUNT(*) FROM jogos WHERE competicao_id = @cm_db39 AND fase = 'FINAL')
     + 100 * (SELECT COUNT(*) FROM jogos WHERE competicao_id = @cm_db39 AND fase = 'SEMIFINAL');
INSERT INTO conferencia_db39
SELECT 'Feminino: equipes (6)', 6, COUNT(*) FROM equipes WHERE competicao_id = @cf_db39;
INSERT INTO conferencia_db39
SELECT 'Feminino: jogos de grupo (6), semifinais (2) e final (1)', 621,
       100 * (SELECT COUNT(*) FROM jogos WHERE competicao_id = @cf_db39 AND fase = 'GRUPOS')
     + 10 * (SELECT COUNT(*) FROM jogos WHERE competicao_id = @cf_db39 AND fase = 'SEMIFINAL')
     + (SELECT COUNT(*) FROM jogos WHERE competicao_id = @cf_db39 AND fase = 'FINAL');
INSERT INTO conferencia_db39
SELECT 'grupos das equipes: M A=2, M B=3, F A=3, F B=3 (2333)', 2333,
       1000 * (SELECT COUNT(*) FROM equipes WHERE grupo_id = @gma_db39)
     + 100 * (SELECT COUNT(*) FROM equipes WHERE grupo_id = @gmb_db39)
     + 10 * (SELECT COUNT(*) FROM equipes WHERE grupo_id = @gfa_db39)
     + (SELECT COUNT(*) FROM equipes WHERE grupo_id = @gfb_db39);
INSERT INTO conferencia_db39
SELECT 'jogo de grupo com equipe de outro grupo (0)', 0, COUNT(*)
  FROM jogos j
  INNER JOIN equipes e1 ON e1.id = j.equipe_1_id
  INNER JOIN equipes e2 ON e2.id = j.equipe_2_id
 WHERE j.competicao_id IN (@cm_db39, @cf_db39) AND j.fase = 'GRUPOS'
   AND NOT (e1.grupo_id <=> j.grupo_id AND e2.grupo_id <=> j.grupo_id);
INSERT INTO conferencia_db39
SELECT 'numero_jogo de 1 a N sem buraco nas duas competições (2)', 2, COUNT(*)
  FROM (SELECT competicao_id FROM jogos WHERE competicao_id IN (@cm_db39, @cf_db39)
         GROUP BY competicao_id HAVING MIN(numero_jogo) = 1 AND MAX(numero_jogo) = COUNT(*)) d;
INSERT INTO conferencia_db39
SELECT 'regra: M 1/FINAL e F 2/SEMIFINAL (2)', 2, COUNT(*)
  FROM competicoes c
 WHERE (c.id = @cm_db39 AND c.classificados_por_grupo = 1 AND c.proxima_fase = 'FINAL')
    OR (c.id = @cf_db39 AND c.classificados_por_grupo = 2 AND c.proxima_fase = 'SEMIFINAL');
INSERT INTO conferencia_db39
SELECT 'vaga de grupo apontando para grupo de outra competição, em todo o banco (0)', 0, COUNT(*)
  FROM jogo_vagas v INNER JOIN jogos j ON j.id = v.jogo_id INNER JOIN grupos g ON g.id = v.grupo_id
 WHERE v.tipo = 'GRUPO' AND g.competicao_id <> j.competicao_id;
INSERT INTO conferencia_db39
SELECT 'vagas dos 4 mata-matas como na tabela (8)', 8, COUNT(*)
  FROM jogo_vagas v
  INNER JOIN jogos j ON j.id = v.jogo_id
  LEFT JOIN grupos g ON g.id = v.grupo_id
  LEFT JOIN jogos jo ON jo.id = v.jogo_origem_id
 WHERE (j.numero_tabela = 218 AND j.competicao_id = @cf_db39 AND v.tipo = 'GRUPO' AND v.manual = 0
         AND ((v.lado = 1 AND g.nome = 'A' AND v.posicao = 1) OR (v.lado = 2 AND g.nome = 'B' AND v.posicao = 2)))
    OR (j.numero_tabela = 233 AND j.competicao_id = @cf_db39 AND v.tipo = 'GRUPO' AND v.manual = 0
         AND ((v.lado = 1 AND g.nome = 'B' AND v.posicao = 1) OR (v.lado = 2 AND g.nome = 'A' AND v.posicao = 2)))
    OR (j.numero_tabela = 282 AND j.competicao_id = @cf_db39 AND v.tipo = 'VENCEDOR' AND v.manual = 0
         AND ((v.lado = 1 AND jo.numero_tabela = 218) OR (v.lado = 2 AND jo.numero_tabela = 233)))
    OR (j.numero_tabela = 281 AND j.competicao_id = @cm_db39 AND v.tipo = 'GRUPO' AND v.manual = 0
         AND ((v.lado = 1 AND g.nome = 'A' AND v.posicao = 1) OR (v.lado = 2 AND g.nome = 'B' AND v.posicao = 1)));

SELECT item, esperado, encontrado, CASE WHEN esperado = encontrado THEN 'ok' ELSE 'DIVERGE' END AS situacao
  FROM conferencia_db39;

-- Trava 3: qualquer divergência para aqui, antes do COMMIT
DROP TEMPORARY TABLE IF EXISTS trava_conferencia_db39;
CREATE TEMPORARY TABLE trava_conferencia_db39 (
  item VARCHAR(120) NOT NULL,
  ok   TINYINT      NOT NULL,
  CONSTRAINT db39_conferencia_divergiu CHECK (ok = 1)
);
INSERT INTO trava_conferencia_db39 (item, ok)
SELECT item, CASE WHEN esperado = encontrado THEN 1 ELSE 0 END FROM conferencia_db39;
DROP TEMPORARY TABLE trava_conferencia_db39;
DROP TEMPORARY TABLE conferencia_db39;
DROP TEMPORARY TABLE ordem_db39;
DROP TEMPORARY TABLE equipe_db39;
DROP TEMPORARY TABLE comp_db39;

COMMIT;

-- ---------------------------------------------------------------------
-- Depois do COMMIT, só leitura
-- ---------------------------------------------------------------------
SELECT @equipe_criada_db39 AS equipe_criada, @jogos_mudados_db39 AS jogos_mudados,
       @jogos_renumerados_db39 AS jogos_renumerados, @vagas_mudadas_db39 AS vagas_mudadas,
       @regras_mudadas_db39 AS regras_mudadas, @equipe_removida_db39 AS equipe_removida;

-- As duas competições: regra, equipes e jogos
SELECT c.genero, c.qtd_grupos, c.classificados_por_grupo, c.melhores_segundos, c.proxima_fase, c.turno
  FROM competicoes c WHERE c.id IN (@cm_db39, @cf_db39) ORDER BY c.genero DESC;
SELECT c.genero, g.nome AS grupo, s.nome AS escola
  FROM equipes e
  INNER JOIN competicoes c ON c.id = e.competicao_id
  INNER JOIN escolas s ON s.id = e.escola_id
  LEFT JOIN grupos g ON g.id = e.grupo_id
 WHERE e.competicao_id IN (@cm_db39, @cf_db39)
 ORDER BY c.genero DESC, g.nome, s.nome;
SELECT c.genero, j.numero_jogo, j.numero_tabela, j.fase, g.nome AS grupo,
       DATE_FORMAT(j.data_hora, '%d/%m %H:%i') AS quando, l.nome AS local_,
       COALESCE(s1.nome, (SELECT rotulo FROM jogo_vagas v WHERE v.jogo_id = j.id AND v.lado = 1)) AS equipe_1,
       COALESCE(s2.nome, (SELECT rotulo FROM jogo_vagas v WHERE v.jogo_id = j.id AND v.lado = 2)) AS equipe_2
  FROM jogos j
  INNER JOIN competicoes c ON c.id = j.competicao_id
  LEFT JOIN grupos g ON g.id = j.grupo_id
  LEFT JOIN locais_disputa l ON l.id = j.local_id
  LEFT JOIN equipes e1 ON e1.id = j.equipe_1_id LEFT JOIN escolas s1 ON s1.id = e1.escola_id
  LEFT JOIN equipes e2 ON e2.id = j.equipe_2_id LEFT JOIN escolas s2 ON s2.id = e2.escola_id
 WHERE j.competicao_id IN (@cm_db39, @cf_db39)
 ORDER BY c.genero DESC, j.numero_jogo;

-- Aviso (não aborta): ESCOLA em dois jogos no mesmo dia e hora, envolvendo os 15 jogos
SELECT DATE_FORMAT(x.data_hora, '%d/%m %H:%i') AS quando, s.nome AS escola,
       GROUP_CONCAT(CONCAT('nº ', j.numero_tabela, ' ', m.nome, ' ', cat.nome, ' ', LEFT(c.genero, 1))
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
           FROM alvo_db39 t
           INNER JOIN jogos j2 ON j2.id = t.jogo_id
           INNER JOIN equipes e2 ON e2.id IN (j2.equipe_1_id, j2.equipe_2_id))
 GROUP BY x.data_hora, s.id, s.nome
HAVING COUNT(*) > 1
 ORDER BY x.data_hora, s.nome;

SELECT SUM(fase = 'GRUPOS') AS jogos_de_grupo, SUM(fase <> 'GRUPOS') AS jogos_de_mata_mata, COUNT(*) AS total FROM jogos;

DROP TEMPORARY TABLE alvo_db39;
