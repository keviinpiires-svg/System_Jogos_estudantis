-- =====================================================================
-- MIGRAÇÃO 14 — equipes e competição pela tabela oficial de jogos do chefe
-- (20/10/2026)
--
-- Decisão do usuário: onde o cadastro e a tabela do chefe divergem, vale a
-- tabela do chefe. Três ajustes:
--
--   1. Baleado Feminino Sub 17: sai LUCIA ROCHA, entra JOSENILDO LEITE, no
--      mesmo grupo das outras (CEBC, CEJA, CETI).
--   2. Handebol Feminino Sub 17: sai CETI, entra CEBC, no mesmo grupo das
--      outras (CEBN, CEJA).
--   3. Handebol Masculino Sub 9: competição nova, com ADELIETA RAMALHO e
--      FRANCISCO AMORIM, no formato das outras competições de 2 escolas
--      ("melhor de dois jogos": 1 grupo, sem mata-mata, IDA_E_VOLTA). A
--      tabela do chefe dá um jogo só a ela (o 33).
--
-- SEGURANÇA: antes de qualquer escrita, o script confere se as equipes que
-- vão sair têm jogos, súmulas, atletas inscritos ou colocação gravada. Se
-- tiverem, ele PARA COM ERRO (CHECK da tabela temporária abaixo, código
-- 3819 no MySQL e 4025 no MariaDB, com o nome
-- equipe_a_remover_tem_jogos_sumulas_ou_inscritos) e não escreve nada.
-- Nesse caso, confira os dados antes de decidir. As chaves estrangeiras
-- (todas RESTRICT) também recusariam o DELETE, mas a trava vem antes, para
-- o script não parar no meio com parte já gravada.
--
-- IDEMPOTENTE: rodar de novo não duplica nem remove nada a mais (a equipe
-- que já saiu não existe mais para conferir, e a que entra só entra se
-- ainda não estiver lá).
--
-- Rode depois do 12 (o 13 é o da escola Conveniada). Só dados: não mexe em
-- estrutura, e o backend no ar não precisa mudar para ler o resultado.
-- Precisa de MySQL 8.0.16+ ou MariaDB 10.2+ (CHECK de verdade).
-- =====================================================================

SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- Trava: as equipes que vão sair precisam estar vazias
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS trava_db14;
CREATE TEMPORARY TABLE trava_db14 (
  equipe VARCHAR(100) NOT NULL,
  vazia  TINYINT      NOT NULL,
  CONSTRAINT equipe_a_remover_tem_jogos_sumulas_ou_inscritos CHECK (vazia = 1)
);

-- Uma linha por equipe a remover que ainda existe; vazia = 0 faz o CHECK
-- recusar e o script parar aqui
INSERT INTO trava_db14 (equipe, vazia)
SELECT CONCAT(es.nome, ' em ', m.nome, ' ', cat.nome, ' ', c.genero),
       CASE WHEN EXISTS (SELECT 1 FROM jogos j
                          WHERE e.id IN (j.equipe_1_id, j.equipe_2_id)
                             OR j.vencedor_equipe_id = e.id
                             OR j.baleou_primeiro_equipe_id = e.id)
              OR EXISTS (SELECT 1 FROM sumula_equipes s WHERE s.equipe_id = e.id)
              OR EXISTS (SELECT 1 FROM inscricoes_atletas i WHERE i.equipe_id = e.id)
              OR EXISTS (SELECT 1 FROM colocacoes_finais cf WHERE cf.equipe_id = e.id)
            THEN 0 ELSE 1 END
  FROM equipes e
  INNER JOIN competicoes c ON c.id = e.competicao_id
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
  INNER JOIN escolas es ON es.id = e.escola_id
 WHERE (m.slug = 'baleado' AND cat.nome = 'Sub 17' AND c.genero = 'FEMININO' AND es.nome = 'LUCIA ROCHA')
    OR (m.slug = 'handebol' AND cat.nome = 'Sub 17' AND c.genero = 'FEMININO' AND es.nome = 'CETI');

DROP TEMPORARY TABLE trava_db14;

-- ---------------------------------------------------------------------
-- 1. Baleado Feminino Sub 17: sai LUCIA ROCHA, entra JOSENILDO LEITE
-- ---------------------------------------------------------------------
-- A nova entra no grupo das que ficam (CEBC, CEJA, CETI)
INSERT INTO equipes (competicao_id, escola_id, grupo_id)
SELECT c.id, nova.id,
       (SELECT e.grupo_id FROM equipes e INNER JOIN escolas es ON es.id = e.escola_id
         WHERE e.competicao_id = c.id AND es.nome = 'CEBC')
  FROM competicoes c
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
  INNER JOIN escolas nova ON nova.nome = 'JOSENILDO LEITE'
 WHERE m.slug = 'baleado' AND cat.nome = 'Sub 17' AND c.genero = 'FEMININO'
   AND NOT EXISTS (SELECT 1 FROM equipes e WHERE e.competicao_id = c.id AND e.escola_id = nova.id);

DELETE e FROM equipes e
  INNER JOIN competicoes c ON c.id = e.competicao_id
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
  INNER JOIN escolas es ON es.id = e.escola_id
 WHERE m.slug = 'baleado' AND cat.nome = 'Sub 17' AND c.genero = 'FEMININO' AND es.nome = 'LUCIA ROCHA';

-- ---------------------------------------------------------------------
-- 2. Handebol Feminino Sub 17: sai CETI, entra CEBC
-- ---------------------------------------------------------------------
INSERT INTO equipes (competicao_id, escola_id, grupo_id)
SELECT c.id, nova.id,
       (SELECT e.grupo_id FROM equipes e INNER JOIN escolas es ON es.id = e.escola_id
         WHERE e.competicao_id = c.id AND es.nome = 'CEBN')
  FROM competicoes c
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
  INNER JOIN escolas nova ON nova.nome = 'CEBC'
 WHERE m.slug = 'handebol' AND cat.nome = 'Sub 17' AND c.genero = 'FEMININO'
   AND NOT EXISTS (SELECT 1 FROM equipes e WHERE e.competicao_id = c.id AND e.escola_id = nova.id);

DELETE e FROM equipes e
  INNER JOIN competicoes c ON c.id = e.competicao_id
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
  INNER JOIN escolas es ON es.id = e.escola_id
 WHERE m.slug = 'handebol' AND cat.nome = 'Sub 17' AND c.genero = 'FEMININO' AND es.nome = 'CETI';

-- ---------------------------------------------------------------------
-- 3. Handebol Masculino Sub 9: competição de 2 escolas, como as outras
--    (handebol Sub 8 F: 1 grupo, 0 classificados, sem mata-mata,
--    IDA_E_VOLTA, 2 x 12 minutos)
-- ---------------------------------------------------------------------
INSERT INTO competicoes
  (modalidade_id, categoria_id, genero, qtd_grupos, classificados_por_grupo,
   melhores_segundos, proxima_fase, turno, minutos_por_tempo, minutos_por_tempo_final)
SELECT m.id, cat.id, 'MASCULINO', 1, 0, 0, 'NENHUMA', 'IDA_E_VOLTA', 12, NULL
  FROM modalidades m
  INNER JOIN categorias cat ON cat.nome = 'Sub 9'
 WHERE m.slug = 'handebol'
   AND NOT EXISTS (SELECT 1 FROM competicoes c WHERE c.modalidade_id = m.id
                     AND c.categoria_id = cat.id AND c.genero = 'MASCULINO');

INSERT INTO grupos (competicao_id, nome)
SELECT c.id, 'A'
  FROM competicoes c
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
 WHERE m.slug = 'handebol' AND cat.nome = 'Sub 9' AND c.genero = 'MASCULINO'
   AND NOT EXISTS (SELECT 1 FROM grupos g WHERE g.competicao_id = c.id AND g.nome = 'A');

INSERT INTO equipes (competicao_id, escola_id, grupo_id)
SELECT c.id, es.id, g.id
  FROM competicoes c
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
  INNER JOIN grupos g ON g.competicao_id = c.id AND g.nome = 'A'
  INNER JOIN escolas es ON es.nome IN ('ADELIETA RAMALHO', 'FRANCISCO AMORIM')
 WHERE m.slug = 'handebol' AND cat.nome = 'Sub 9' AND c.genero = 'MASCULINO'
   AND NOT EXISTS (SELECT 1 FROM equipes e WHERE e.competicao_id = c.id AND e.escola_id = es.id);

-- ---------------------------------------------------------------------
-- Conferência: as três competições com as escolas e os grupos esperados
--   Baleado F Sub 17:  CEBC, CEJA, CETI, JOSENILDO LEITE (grupo A)
--   Handebol F Sub 17: CEBC, CEBN, CEJA (grupo A)
--   Handebol M Sub 9:  ADELIETA RAMALHO, FRANCISCO AMORIM (grupo A,
--                      IDA_E_VOLTA, sem mata-mata)
-- e o total de competições (50 antes; 51 depois)
-- ---------------------------------------------------------------------
SELECT m.nome AS modalidade, cat.nome AS categoria, c.genero, c.turno, c.proxima_fase,
       GROUP_CONCAT(CONCAT(es.nome, ' (', g.nome, ')') ORDER BY es.nome SEPARATOR ', ') AS equipes
  FROM competicoes c
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
  INNER JOIN equipes e ON e.competicao_id = c.id
  INNER JOIN escolas es ON es.id = e.escola_id
  LEFT JOIN grupos g ON g.id = e.grupo_id
 WHERE (m.slug = 'baleado' AND cat.nome = 'Sub 17' AND c.genero = 'FEMININO')
    OR (m.slug = 'handebol' AND cat.nome = 'Sub 17' AND c.genero = 'FEMININO')
    OR (m.slug = 'handebol' AND cat.nome = 'Sub 9' AND c.genero = 'MASCULINO')
 GROUP BY c.id, m.nome, cat.nome, c.genero, c.turno, c.proxima_fase
 ORDER BY c.id;
SELECT COUNT(*) AS competicoes FROM competicoes;
