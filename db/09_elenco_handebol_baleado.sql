-- =====================================================================
-- MIGRAÇÃO 09 — elenco de 12 atletas no handebol e no baleado
--
-- Motivo: resposta do chefe de 07/10/2026. Handebol e baleado passam a ter no
-- máximo 12 atletas por equipe (era 14); as demais modalidades seguem com 14.
-- O limite é DADO: mora em modalidades.max_atletas, que o código só lê
-- (inscricaoController recusa a inscrição quando a equipe chega ao teto).
--
-- Só dados, nenhuma coluna nova: compatível com o backend que está no ar.
-- Não apaga inscrição nenhuma. Uma equipe que já tenha mais de 12 inscritos
-- continua com eles, mas não aceita inscrição nova (a conferência no fim
-- lista essas equipes, para a organização decidir).
--
-- Rode depois do 02 (que carrega as modalidades com 14). Sintaxe para MySQL
-- 8.0.16+ e MariaDB 10.4+.
-- =====================================================================

SET NAMES utf8mb4;

UPDATE modalidades SET max_atletas = 12 WHERE slug IN ('handebol', 'baleado');

-- ---------------------------------------------------------------------
-- Conferência: o teto por modalidade, e as equipes que já passam de 12
-- ---------------------------------------------------------------------
SELECT slug, min_atletas, max_atletas FROM modalidades ORDER BY ordem;

SELECT m.slug, e.id AS equipe_id, COUNT(i.id) AS inscritos
  FROM equipes e
  INNER JOIN competicoes c ON c.id = e.competicao_id
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN inscricoes_atletas i ON i.equipe_id = e.id
 WHERE m.slug IN ('handebol', 'baleado')
 GROUP BY m.slug, e.id
HAVING COUNT(i.id) > 12;
