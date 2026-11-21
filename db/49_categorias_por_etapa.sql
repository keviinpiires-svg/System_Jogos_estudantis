-- =====================================================================
-- MIGRAÇÃO 49 — categorias por etapa de ensino no atletismo e no tabuleiro
-- (21/11/2026, pedido do usuário)
--
-- O atletismo e o tabuleiro passam a lançar a colocação por ETAPA:
-- Anos Iniciais, Anos Finais e Ensino Médio (tabela etapas_ensino).
-- Cria as três categorias, ligadas à etapa, sem idade máxima. Elas não têm
-- competição, então não mexem nas coletivas, na importação nem no menu.
-- Não altera nenhum dado existente. Rode depois do 48. Sem dado de aluno.
-- =====================================================================

INSERT INTO categorias (nome, idade_maxima, ordem, etapa_ensino_id)
SELECT e.nome, NULL, 8 + e.ordem, e.id
  FROM etapas_ensino e
 WHERE e.nome IN ('Anos Iniciais', 'Anos Finais', 'Ensino Médio')
   AND NOT EXISTS (SELECT 1 FROM categorias c WHERE c.nome = e.nome);

SELECT id, nome, ordem, etapa_ensino_id FROM categorias WHERE etapa_ensino_id IS NOT NULL ORDER BY ordem;
