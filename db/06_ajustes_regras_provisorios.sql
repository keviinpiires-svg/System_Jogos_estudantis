-- =====================================================================
-- MIGRAÇÃO 06 — ajustes de regra decididos em 30/09/2026
--
-- **PROVISÓRIO: o chefe vai revisar.** Se a decisão mudar, altere aqui e
-- rode de novo; o script é idempotente (grava valores fixos, não incrementa).
--
-- Handebol Masculino Aberto
--   A tabela de grupos dizia "melhor de dois jogos" com TRÊS equipes, o que
--   não fecha: melhor de dois é formato de dois times. A importação registrou
--   turno IDA_E_VOLTA e nenhum classificado, deixando a competição sem
--   desfecho.
--   Decisão: todos contra todos em TURNO ÚNICO; o 1º e o 2º vão à final.
--
-- As demais regras provisórias (melhor segundo, empate no mata-mata, placar
-- do W.O. e folha do baleado) são CÓDIGO, não dado, e moram num arquivo só:
-- src/config/regrasProvisorias.js
-- =====================================================================

SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- 1) Antes (para você conferir o que vai mudar)
-- ---------------------------------------------------------------------
SELECT c.id, m.nome AS modalidade, cat.nome AS categoria, c.genero,
       c.qtd_grupos, c.classificados_por_grupo, c.proxima_fase, c.turno,
       (SELECT COUNT(*) FROM equipes e WHERE e.competicao_id = c.id) AS equipes
  FROM competicoes c
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
 WHERE m.slug = 'handebol' AND cat.nome = 'Aberto' AND c.genero = 'MASCULINO';

-- ---------------------------------------------------------------------
-- 2) O ajuste
-- ---------------------------------------------------------------------
UPDATE competicoes c
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
   SET c.turno = 'UNICO',
       c.classificados_por_grupo = 2,
       c.melhores_segundos = 0,
       c.proxima_fase = 'FINAL'
 WHERE m.slug = 'handebol' AND cat.nome = 'Aberto' AND c.genero = 'MASCULINO';

-- ---------------------------------------------------------------------
-- 3) Depois (esperado: turno UNICO, 2 classificados, próxima fase FINAL)
-- ---------------------------------------------------------------------
SELECT c.id, m.nome AS modalidade, cat.nome AS categoria, c.genero,
       c.qtd_grupos, c.classificados_por_grupo, c.proxima_fase, c.turno
  FROM competicoes c
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
 WHERE m.slug = 'handebol' AND cat.nome = 'Aberto' AND c.genero = 'MASCULINO';


-- ---------------------------------------------------------------------
-- PARA VOLTAR AO QUE A IMPORTAÇÃO TINHA GRAVADO
-- ---------------------------------------------------------------------
-- UPDATE competicoes c
--   INNER JOIN modalidades m ON m.id = c.modalidade_id
--   INNER JOIN categorias cat ON cat.id = c.categoria_id
--    SET c.turno = 'IDA_E_VOLTA', c.classificados_por_grupo = 0,
--        c.melhores_segundos = 0, c.proxima_fase = 'NENHUMA'
--  WHERE m.slug = 'handebol' AND cat.nome = 'Aberto' AND c.genero = 'MASCULINO';
