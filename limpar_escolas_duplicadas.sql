-- =====================================================================
-- LIMPEZA DE ESCOLAS DUPLICADAS
-- Une escolas com o mesmo nome (ignorando caixa e espaços), mantendo o
-- registro de MENOR id e repontando todas as tabelas dependentes.
--
-- ANTES DE RODAR: faça backup da base.
-- Execute bloco a bloco no DBeaver, conferindo o resultado de cada um.
-- =====================================================================


-- ---------------------------------------------------------------------
-- PASSO 1 — DIAGNÓSTICO (só leitura, rode e confira antes de seguir)
-- ---------------------------------------------------------------------
SELECT
  UPPER(TRIM(nome))            AS nome_normalizado,
  COUNT(*)                     AS quantidade,
  GROUP_CONCAT(id ORDER BY id) AS ids,
  MIN(id)                      AS id_que_sera_mantido
FROM escolas
GROUP BY UPPER(TRIM(nome))
HAVING COUNT(*) > 1;

-- Se a consulta acima não retornar nada, não há duplicatas:
-- pule direto para o PASSO 7.


-- ---------------------------------------------------------------------
-- PASSO 2 — MAPA duplicado -> correto
-- (CREATE TABLE faz commit implícito, por isso vem antes da transação)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS _merge_escolas;

CREATE TABLE _merge_escolas (
  id_duplicado INT PRIMARY KEY,
  id_correto   INT NOT NULL,
  nome         VARCHAR(150)
);

INSERT INTO _merge_escolas (id_duplicado, id_correto, nome)
SELECT e.id, c.id_correto, e.nome
FROM escolas e
JOIN (
  SELECT UPPER(TRIM(nome)) AS chave, MIN(id) AS id_correto
  FROM escolas
  GROUP BY UPPER(TRIM(nome))
  HAVING COUNT(*) > 1
) c ON UPPER(TRIM(e.nome)) = c.chave
WHERE e.id <> c.id_correto;

-- Confira o mapa: cada linha é uma escola que será absorvida por outra
SELECT m.id_duplicado, m.nome AS nome_duplicado,
       m.id_correto, e.nome AS nome_mantido
FROM _merge_escolas m
JOIN escolas e ON e.id = m.id_correto;


-- ---------------------------------------------------------------------
-- PASSO 3 — QUANTOS REGISTROS SERÃO MOVIDOS (só leitura)
-- ---------------------------------------------------------------------
SELECT 'atletas'           AS tabela, COUNT(*) AS registros FROM atletas           WHERE escola_id   IN (SELECT id_duplicado FROM _merge_escolas)
UNION ALL SELECT 'alunos',            COUNT(*) FROM alunos            WHERE escola_id   IN (SELECT id_duplicado FROM _merge_escolas)
UNION ALL SELECT 'diretores',         COUNT(*) FROM diretores         WHERE escola_id   IN (SELECT id_duplicado FROM _merge_escolas)
UNION ALL SELECT 'resultados_provas', COUNT(*) FROM resultados_provas WHERE escola_id   IN (SELECT id_duplicado FROM _merge_escolas)
UNION ALL SELECT 'jogos (mandante)',  COUNT(*) FROM jogos             WHERE escola_1_id IN (SELECT id_duplicado FROM _merge_escolas)
UNION ALL SELECT 'jogos (visitante)', COUNT(*) FROM jogos             WHERE escola_2_id IN (SELECT id_duplicado FROM _merge_escolas)
UNION ALL SELECT 'grupos_escolas',    COUNT(*) FROM grupos_escolas    WHERE escola_id   IN (SELECT id_duplicado FROM _merge_escolas)
UNION ALL SELECT 'classificacao',     COUNT(*) FROM classificacao     WHERE escola_id   IN (SELECT id_duplicado FROM _merge_escolas);


-- ---------------------------------------------------------------------
-- PASSO 4 — MIGRAÇÃO (transação: ou tudo, ou nada)
-- Rode do START TRANSACTION até o COMMIT.
-- Se algo der errado no meio, rode ROLLBACK; em vez de COMMIT;
-- ---------------------------------------------------------------------
START TRANSACTION;

-- 4.1 Tabelas com vínculo simples
UPDATE atletas           a JOIN _merge_escolas m ON a.escola_id = m.id_duplicado SET a.escola_id = m.id_correto;
UPDATE alunos            a JOIN _merge_escolas m ON a.escola_id = m.id_duplicado SET a.escola_id = m.id_correto;
UPDATE diretores         d JOIN _merge_escolas m ON d.escola_id = m.id_duplicado SET d.escola_id = m.id_correto;
UPDATE resultados_provas r JOIN _merge_escolas m ON r.escola_id = m.id_duplicado SET r.escola_id = m.id_correto;

-- 4.2 Jogos: a escola aparece em duas colunas
UPDATE jogos j JOIN _merge_escolas m ON j.escola_1_id = m.id_duplicado SET j.escola_1_id = m.id_correto;
UPDATE jogos j JOIN _merge_escolas m ON j.escola_2_id = m.id_duplicado SET j.escola_2_id = m.id_correto;

-- 4.3 grupos_escolas tem chave primária (grupo_id, escola_id): se as duas
--     escolas estiverem no mesmo grupo, o UPDATE colidiria. O IGNORE move o
--     que dá, e o DELETE seguinte remove os vínculos que sobraram repetidos.
UPDATE IGNORE grupos_escolas g JOIN _merge_escolas m ON g.escola_id = m.id_duplicado SET g.escola_id = m.id_correto;
DELETE g FROM grupos_escolas g JOIN _merge_escolas m ON g.escola_id = m.id_duplicado;

-- 4.4 classificacao tem UNIQUE em escola_id e não é mais lida pelo sistema
--     (a classificação é calculada a partir de jogos). As linhas órfãs são
--     apagadas em vez de migradas, para não violar a restrição.
DELETE c FROM classificacao c JOIN _merge_escolas m ON c.escola_id = m.id_duplicado;

-- 4.5 Agora nenhuma tabela aponta para as duplicadas: pode remover
DELETE e FROM escolas e JOIN _merge_escolas m ON e.id = m.id_duplicado;

COMMIT;


-- ---------------------------------------------------------------------
-- PASSO 5 — CONFERÊNCIA (só leitura). O esperado é ZERO em tudo.
-- ---------------------------------------------------------------------
SELECT 'escolas duplicadas restantes' AS verificacao, COUNT(*) AS total FROM (
  SELECT 1 FROM escolas GROUP BY UPPER(TRIM(nome)) HAVING COUNT(*) > 1
) x
UNION ALL SELECT 'atletas orfaos',        COUNT(*) FROM atletas a LEFT JOIN escolas e ON e.id = a.escola_id   WHERE e.id IS NULL
UNION ALL SELECT 'jogos orfaos (mand.)',  COUNT(*) FROM jogos   j LEFT JOIN escolas e ON e.id = j.escola_1_id WHERE e.id IS NULL
UNION ALL SELECT 'jogos orfaos (visit.)', COUNT(*) FROM jogos   j LEFT JOIN escolas e ON e.id = j.escola_2_id WHERE e.id IS NULL;


-- ---------------------------------------------------------------------
-- PASSO 6 — LIMPEZA DO MAPA
-- ---------------------------------------------------------------------
DROP TABLE _merge_escolas;


-- ---------------------------------------------------------------------
-- PASSO 7 — PADRONIZAR OS NOMES QUE JÁ EXISTEM
-- Deixa a base no mesmo formato que o backend passou a gravar.
-- ---------------------------------------------------------------------
UPDATE escolas
SET nome = UPPER(TRIM(REPLACE(REPLACE(nome, '  ', ' '), '  ', ' ')));

SELECT id, nome FROM escolas ORDER BY nome;


-- ---------------------------------------------------------------------
-- PASSO 8 — TRAVA DEFINITIVA
-- Impede duplicatas mesmo em cadastros simultâneos, que a verificação do
-- backend sozinha não pega. A colação da coluna é case-insensitive, então
-- este índice também barra 'cebn' quando 'CEBN' já existe.
-- Só funciona se o PASSO 5 não acusou duplicatas.
-- ---------------------------------------------------------------------
ALTER TABLE escolas ADD UNIQUE KEY uq_escolas_nome (nome);

SHOW INDEX FROM escolas;
