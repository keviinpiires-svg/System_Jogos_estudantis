-- =====================================================================
-- MIGRAÇÃO 16 — pontos lançados do atletismo por PROVA (21/10/2026)
--
-- Motivo: no atletismo cada prova tem a sua folha (regulamento: Sub 8 e
-- Sub 9 só correm 50 m; Sub 11 a Sub 17 fazem salto em distância e 100 m).
-- Com um campo só por escola, a mesa digitava a segunda folha por cima da
-- primeira e os pontos do salto sumiam. Agora cada prova é um lançamento
-- próprio, e a Tabela Geral soma as provas da escola sozinha (ela já soma
-- todas as linhas de pontos_lancados).
--
-- - prova_id (NULL no xadrez, na dama e no dominó) aponta para
--   provas_atletismo, que já existe desde o 02 (50 m, 100 m e salto).
-- - O índice único passa a incluir a prova. Como o MySQL não compara NULL
--   num índice único (o tabuleiro poderia repetir a escola), ele usa a
--   coluna calculada prova_chave = COALESCE(prova_id, 0).
--
-- Compatível com o que está gravado: as linhas existentes ficam com
-- prova_id NULL. Na produção não há nenhuma (a limpeza zerou a tabela); a
-- conferência abaixo conta linhas de atletismo sem prova, e o esperado é 0.
-- Compatível com o backend que está no ar (ele não lê a coluna; o índice
-- novo é mais permissivo só para o atletismo, que ele lança sem prova).
--
-- RODA UMA VEZ: de novo, falha sem mudar nada (coluna duplicada).
-- Rode depois do 15. A trava de mesa por local passa a ser o 18 (o 17 é o
-- histórico das correções dos pontos lançados).
-- =====================================================================

SET NAMES utf8mb4;

ALTER TABLE pontos_lancados
  ADD COLUMN prova_id INT NULL AFTER genero,
  ADD COLUMN prova_chave INT AS (COALESCE(prova_id, 0)) STORED AFTER prova_id,
  ADD CONSTRAINT fk_pontos_lancados_prova FOREIGN KEY (prova_id)
    REFERENCES provas_atletismo (id) ON DELETE RESTRICT,
  ADD UNIQUE KEY uq_pontos_lancados_prova (modalidade_id, categoria_id, genero, prova_chave, escola_id),
  DROP INDEX uq_pontos_lancados;

-- ---------------------------------------------------------------------
-- Conferência: as colunas, o índice novo e quantas linhas de atletismo
-- ficaram sem prova (o esperado é 0)
-- ---------------------------------------------------------------------
SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, EXTRA
  FROM information_schema.COLUMNS
 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pontos_lancados' AND COLUMN_NAME IN ('prova_id', 'prova_chave');
SELECT INDEX_NAME, GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS colunas
  FROM information_schema.STATISTICS
 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pontos_lancados' AND NON_UNIQUE = 0 AND INDEX_NAME <> 'PRIMARY'
 GROUP BY INDEX_NAME;
SELECT COUNT(*) AS atletismo_sem_prova
  FROM pontos_lancados p
  INNER JOIN modalidades m ON m.id = p.modalidade_id
 WHERE m.slug = 'atletismo' AND p.prova_id IS NULL;
