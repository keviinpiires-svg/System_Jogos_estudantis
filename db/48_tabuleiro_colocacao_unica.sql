-- =====================================================================
-- MIGRAÇÃO 48 — tabuleiro com uma colocação só por categoria (21/11/2026)
--
-- Pedido do usuário: a página do tabuleiro lança a colocação final de cada
-- escola nos jogos de tabuleiro, SEM dividir por jogo (xadrez, dama, dominó)
-- e sem nome de atleta. As colocações passam a ser gravadas na modalidade
-- "Tabuleiro" (slug tabuleiro), criada aqui. Ela não tem competição, então
-- não aparece no menu de modalidades. Não mexe em nenhum dado existente.
-- Rode depois do 47 e antes do deploy do backend. Sem dado de aluno.
-- =====================================================================

INSERT INTO modalidades (nome, slug, tipo, tipo_placar, ordem)
SELECT 'Tabuleiro', 'tabuleiro', 'INDIVIDUAL', 'PONTOS', 8
 WHERE NOT EXISTS (SELECT 1 FROM modalidades WHERE slug = 'tabuleiro');

SELECT id, nome, slug, tipo FROM modalidades WHERE slug = 'tabuleiro';
