-- =====================================================================
-- MIGRAÇÃO 50 — atletismo sem prova e sem gênero (21/11/2026)
--
-- Pedido do usuário: o atletismo lança só a colocação final de cada escola
-- por categoria (Anos Iniciais, Anos Finais, Ensino Médio), sem prova, sem
-- gênero e sem nome de atleta. O gênero passa a aceitar MISTO (o backend
-- grava MISTO e a prova "Atletismo"). Não altera nenhum dado existente.
-- Rode depois do 49. Sem dado de aluno.
-- =====================================================================

ALTER TABLE atletismo_colocacoes
  MODIFY genero ENUM('MASCULINO', 'FEMININO', 'MISTO') NOT NULL;

SELECT COLUMN_TYPE FROM information_schema.COLUMNS
 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'atletismo_colocacoes' AND COLUMN_NAME = 'genero';
