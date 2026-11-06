-- =====================================================================
-- MIGRAÇÃO 19 — equipes pela tabela NOVA de jogos do chefe (28/10/2026)
--
-- O chefe mandou a tabela renumerada (240 jogos de fase de grupos), que
-- substitui o lote 1 de 20/10. Vale a tabela (decisão de 20/10/2026). Ela
-- desfaz parte do db/14 e tira escolas que não jogam:
--
--   ENTRAM (se ainda não estiverem):
--     1. Baleado Feminino Sub 17: LUCIA ROCHA (grupo único, o A).
--     2. Handebol Feminino Sub 17: CETI (grupo único, o A).
--   SAEM (se existirem):
--     3. Baleado Feminino Sub 17: JOSENILDO LEITE.
--     4. Baleado Masculino Sub 11: JOSENILDO LEITE.
--     5. Futsal Feminino Sub 9: FRANCISCO AMORIM e PORTAL DO SABER.
--     6. Futsal Masculino Sub 9: CEBC.
--     7. Handebol Masculino Sub 8: FRANCISCO AMORIM.
--     8. Handebol Feminino Aberto: CETI e LUCIA ROCHA. A competição fica
--        sem equipes e sem jogos, mas continua cadastrada (51 competições):
--        a Tabela Geral a pula ("menos de duas equipes inscritas").
--     9. Futebol Society Masculino Sub 15: EMILIANO ZAPATA (só consta na
--        tabela de grupos; a tabela de jogos não tem jogo dela). Os grupos A
--        e B ficam com 3 equipes cada.
--
-- No jogos_estudantis_dev (28/10/2026) só existiam a 3, a 8 e a 9; a 4, a
-- 5, a 6 e a 7 ficam aqui para o caso de a produção divergir, e não fazem
-- nada quando a equipe não existe.
--
-- SEGURANÇA: antes de qualquer escrita, o script confere se as equipes que
-- vão sair têm jogos, súmulas, atletas inscritos ou colocação gravada. Se
-- tiverem, ele PARA COM ERRO (CHECK da tabela temporária abaixo, código
-- 3819 no MySQL e 4025 no MariaDB, com o nome
-- equipe_a_remover_tem_jogos_sumulas_ou_inscritos) e não escreve nada.
-- Os jogos do lote 1 ocupam as equipes da 3 e da 8: rode ANTES a parte 1
-- da limpeza (scripts/sql/limpar_dados_de_teste.sql), que apaga os jogos.
--
-- IDEMPOTENTE: rodar de novo não duplica nem remove nada a mais.
--
-- Rode depois do 17 (o 18 fica reservado para a trava de mesa por local).
-- Só dados: não mexe em estrutura, e o backend no ar lê o resultado sem
-- mudar. Precisa de MySQL 8.0.16+ ou MariaDB 10.2+ (CHECK de verdade).
-- =====================================================================

SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- As equipes que saem (modalidade, categoria, gênero, escola)
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS remover_db19;
CREATE TEMPORARY TABLE remover_db19 (
  slug      VARCHAR(30)  NOT NULL,
  categoria VARCHAR(20)  NOT NULL,
  genero    VARCHAR(10)  NOT NULL,
  escola    VARCHAR(100) NOT NULL
);
INSERT INTO remover_db19 (slug, categoria, genero, escola) VALUES
  ('baleado',  'Sub 17', 'FEMININO',  'JOSENILDO LEITE'),
  ('baleado',  'Sub 11', 'MASCULINO', 'JOSENILDO LEITE'),
  ('futsal',   'Sub 9',  'FEMININO',  'FRANCISCO AMORIM'),
  ('futsal',   'Sub 9',  'FEMININO',  'PORTAL DO SABER'),
  ('futsal',   'Sub 9',  'MASCULINO', 'CEBC'),
  ('handebol', 'Sub 8',  'MASCULINO', 'FRANCISCO AMORIM'),
  ('handebol', 'Aberto', 'FEMININO',  'CETI'),
  ('handebol', 'Aberto', 'FEMININO',  'LUCIA ROCHA'),
  ('futebol-society', 'Sub 15', 'MASCULINO', 'EMILIANO ZAPATA');

-- ---------------------------------------------------------------------
-- Trava: as equipes que vão sair precisam estar vazias
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS trava_db19;
CREATE TEMPORARY TABLE trava_db19 (
  equipe VARCHAR(160) NOT NULL,
  vazia  TINYINT      NOT NULL,
  CONSTRAINT equipe_a_remover_tem_jogos_sumulas_ou_inscritos CHECK (vazia = 1)
);

-- Uma linha por equipe a remover que existe; vazia = 0 faz o CHECK recusar
INSERT INTO trava_db19 (equipe, vazia)
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
  INNER JOIN remover_db19 r ON r.slug = m.slug AND r.categoria = cat.nome
                           AND r.genero = c.genero AND r.escola = es.nome;

DROP TEMPORARY TABLE trava_db19;

-- Antes: o que existe das equipes a remover (anote para o relatório)
SELECT CONCAT(r.escola, ' em ', r.slug, ' ', r.categoria, ' ', r.genero) AS equipe_a_remover,
       CASE WHEN e.id IS NULL THEN 'não existe' ELSE CONCAT('existe (equipe ', e.id, ')') END AS antes
  FROM remover_db19 r
  LEFT JOIN modalidades m ON m.slug = r.slug
  LEFT JOIN categorias cat ON cat.nome = r.categoria
  LEFT JOIN competicoes c ON c.modalidade_id = m.id AND c.categoria_id = cat.id AND c.genero = r.genero
  LEFT JOIN escolas es ON es.nome = r.escola
  LEFT JOIN equipes e ON e.competicao_id = c.id AND e.escola_id = es.id;

-- ---------------------------------------------------------------------
-- 1 e 2. Entram LUCIA ROCHA (Baleado F Sub 17) e CETI (Handebol F Sub 17),
-- no grupo A, o único das duas competições
-- ---------------------------------------------------------------------
INSERT INTO equipes (competicao_id, escola_id, grupo_id)
SELECT c.id, nova.id, g.id
  FROM competicoes c
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
  INNER JOIN grupos g ON g.competicao_id = c.id AND g.nome = 'A'
  INNER JOIN escolas nova
          ON (m.slug = 'baleado'  AND nova.nome = 'LUCIA ROCHA')
          OR (m.slug = 'handebol' AND nova.nome = 'CETI')
 WHERE cat.nome = 'Sub 17' AND c.genero = 'FEMININO' AND m.slug IN ('baleado', 'handebol')
   AND NOT EXISTS (SELECT 1 FROM equipes e WHERE e.competicao_id = c.id AND e.escola_id = nova.id);

-- ---------------------------------------------------------------------
-- 3 a 9. Saem as equipes da lista
-- ---------------------------------------------------------------------
DELETE e FROM equipes e
  INNER JOIN competicoes c ON c.id = e.competicao_id
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
  INNER JOIN escolas es ON es.id = e.escola_id
  INNER JOIN remover_db19 r ON r.slug = m.slug AND r.categoria = cat.nome
                           AND r.genero = c.genero AND r.escola = es.nome;

DROP TEMPORARY TABLE remover_db19;

-- ---------------------------------------------------------------------
-- Conferência: as competições mexidas, com as escolas e os grupos
--   Baleado F Sub 17:   CEBC, CEJA, CETI, LUCIA ROCHA (A)
--   Handebol F Sub 17:  CEBC, CEBN, CEJA, CETI (A)
--   Handebol F Aberto:  nenhuma equipe
--   Society M Sub 15:   CEJA, Conveniada, JOSE DIAS (A); CEBC, CEBN, CETI (B)
--   Baleado M Sub 11, Futsal Sub 9 F e M, Handebol M Sub 8: sem as que saíram
-- e o total de competições (51, como antes)
-- ---------------------------------------------------------------------
SELECT m.nome AS modalidade, cat.nome AS categoria, c.genero,
       COALESCE(GROUP_CONCAT(CONCAT(es.nome, ' (', g.nome, ')') ORDER BY es.nome SEPARATOR ', '),
                '(nenhuma equipe)') AS equipes
  FROM competicoes c
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
  LEFT JOIN equipes e ON e.competicao_id = c.id
  LEFT JOIN escolas es ON es.id = e.escola_id
  LEFT JOIN grupos g ON g.id = e.grupo_id
 WHERE (m.slug IN ('baleado', 'handebol') AND cat.nome = 'Sub 17' AND c.genero = 'FEMININO')
    OR (m.slug = 'handebol' AND cat.nome = 'Aberto' AND c.genero = 'FEMININO')
    OR (m.slug = 'baleado'  AND cat.nome = 'Sub 11' AND c.genero = 'MASCULINO')
    OR (m.slug = 'futsal'   AND cat.nome = 'Sub 9')
    OR (m.slug = 'handebol' AND cat.nome = 'Sub 8'  AND c.genero = 'MASCULINO')
    OR (m.slug = 'futebol-society' AND cat.nome = 'Sub 15' AND c.genero = 'MASCULINO')
 GROUP BY c.id, m.nome, cat.nome, c.genero
 ORDER BY c.id;
SELECT COUNT(*) AS competicoes, (SELECT COUNT(*) FROM equipes) AS equipes FROM competicoes;
