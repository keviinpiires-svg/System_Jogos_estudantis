-- =====================================================================
-- MIGRAÇÃO 10 — locais "Quadra do CEBC" e "Quadra do CEJA" (chefe, 12/10/2026)
--
-- Motivo: o chefe definiu uma mesa por local de jogo e pediu esses dois
-- locais. Não há tela nem rota para cadastrar local (GET /api/locais é só
-- leitura), então o cadastro vem por script.
--
-- A "Quadra do CEJA" JÁ EXISTE em quem rodou o 04_locais.sql (a carga de
-- produção rodou). Por isso o script é IDEMPOTENTE: cada local só entra se
-- ainda não houver um com o mesmo nome. Rodar duas vezes não duplica nada,
-- e o banco onde a quadra já existe ganha só a do CEBC.
--
-- Sem INSERT IGNORE de propósito: ele engoliria qualquer outro erro.
-- A comparação de nome usa a collation do servidor: na produção
-- (utf8mb4_0900_ai_ci) ela ignora maiúsculas e acentos, como o índice
-- único uq_locais_nome.
--
-- Rode depois do 04_locais.sql. Só dados: não mexe em estrutura, e o
-- backend no ar não precisa mudar para ler os locais novos.
-- =====================================================================

SET NAMES utf8mb4;

INSERT INTO locais_disputa (nome)
SELECT 'Quadra do CEBC' FROM DUAL
 WHERE NOT EXISTS (SELECT 1 FROM locais_disputa WHERE nome = 'Quadra do CEBC');

INSERT INTO locais_disputa (nome)
SELECT 'Quadra do CEJA' FROM DUAL
 WHERE NOT EXISTS (SELECT 1 FROM locais_disputa WHERE nome = 'Quadra do CEJA');

-- ---------------------------------------------------------------------
-- Conferência: os dois aparecem uma vez cada, e o total de locais
-- (na produção, eram 4 antes deste script; o esperado depois é 5)
-- ---------------------------------------------------------------------
SELECT id, nome FROM locais_disputa ORDER BY id;
SELECT nome, COUNT(*) AS vezes
  FROM locais_disputa
 WHERE nome IN ('Quadra do CEBC', 'Quadra do CEJA')
 GROUP BY nome;
