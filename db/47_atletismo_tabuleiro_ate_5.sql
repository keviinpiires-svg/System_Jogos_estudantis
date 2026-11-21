-- =====================================================================
-- MIGRAÇÃO 47 — atletismo e tabuleiro lançam do 1º ao 5º lugar (21/11/2026)
--
-- Pedido do usuário: a colocação final das escolas no atletismo e no
-- tabuleiro (xadrez, dama e dominó) vai até o 5º lugar, que também pontua
-- na Tabela Geral (pontuacao_geral: 10, 8, 6, 4 e 2). Só o limite da
-- colocação muda (era 1 a 3). Não mexe em nenhum dado. Sem dado de aluno.
-- Rode ANTES (ou junto) do deploy do backend que aceita 4º e 5º.
-- =====================================================================

ALTER TABLE atletismo_colocacoes
  DROP CHECK chk_atletismo_col_colocacao,
  ADD CONSTRAINT chk_atletismo_col_colocacao CHECK (colocacao BETWEEN 1 AND 5);

ALTER TABLE tabuleiro_colocacoes
  DROP CHECK chk_tabuleiro_col_colocacao,
  ADD CONSTRAINT chk_tabuleiro_col_colocacao CHECK (colocacao BETWEEN 1 AND 5);

-- Conferência: as duas regras têm de dizer "between 1 and 5"
SELECT TABLE_NAME, CONSTRAINT_NAME, CHECK_CLAUSE
  FROM information_schema.CHECK_CONSTRAINTS cc
  JOIN information_schema.TABLE_CONSTRAINTS tc USING (CONSTRAINT_SCHEMA, CONSTRAINT_NAME)
 WHERE CONSTRAINT_SCHEMA = DATABASE()
   AND CONSTRAINT_NAME IN ('chk_atletismo_col_colocacao', 'chk_tabuleiro_col_colocacao');
