-- =====================================================================
-- MIGRAÇÃO 12 — locais "Quadra da Adelieta Ramalho", "Quadra do CETI" e
-- "Campo Society do CETI" (tabela oficial de jogos do chefe, 20/10/2026)
--
-- Motivo: a tabela de jogos do chefe usa esses três locais, que não estão
-- cadastrados. Não há tela nem rota para cadastrar local (GET /api/locais é
-- só leitura), então o cadastro vem por script, como no 10.
--
-- IDEMPOTENTE: cada local só entra se ainda não houver um com o mesmo nome.
-- Rodar duas vezes não duplica nada.
--
-- Sem INSERT IGNORE de propósito: ele engoliria qualquer outro erro.
-- A comparação de nome usa a collation do servidor: na produção
-- (utf8mb4_0900_ai_ci) ela ignora maiúsculas e acentos, como o índice
-- único uq_locais_nome.
--
-- Rode depois do 10_locais_cebc_ceja.sql. Só dados: não mexe em estrutura,
-- e o backend no ar não precisa mudar para ler os locais novos.
--
-- A trava de mesa por local (cada conta PLACAR presa ao seu local), que
-- estava planejada para este número, passa a ser o 15 (o 13 é o da escola
-- Conveniada e o 14, o das equipes pela tabela do chefe).
-- =====================================================================

SET NAMES utf8mb4;

INSERT INTO locais_disputa (nome)
SELECT 'Quadra da Adelieta Ramalho' FROM DUAL
 WHERE NOT EXISTS (SELECT 1 FROM locais_disputa WHERE nome = 'Quadra da Adelieta Ramalho');

INSERT INTO locais_disputa (nome)
SELECT 'Quadra do CETI' FROM DUAL
 WHERE NOT EXISTS (SELECT 1 FROM locais_disputa WHERE nome = 'Quadra do CETI');

INSERT INTO locais_disputa (nome)
SELECT 'Campo Society do CETI' FROM DUAL
 WHERE NOT EXISTS (SELECT 1 FROM locais_disputa WHERE nome = 'Campo Society do CETI');

-- ---------------------------------------------------------------------
-- Conferência: os três aparecem uma vez cada, e o total de locais
-- (5 depois do 10; o esperado depois deste script é 8)
-- ---------------------------------------------------------------------
SELECT id, nome FROM locais_disputa ORDER BY id;
SELECT nome, COUNT(*) AS vezes
  FROM locais_disputa
 WHERE nome IN ('Quadra da Adelieta Ramalho', 'Quadra do CETI', 'Campo Society do CETI')
 GROUP BY nome;
