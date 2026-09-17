-- =====================================================================
-- Correção do banco jogos_estudantis
-- Execute no DBeaver UM BLOCO POR VEZ, na ordem, conferindo os resultados.
-- =====================================================================

USE jogos_estudantis;

-- ---------------------------------------------------------------------
-- 0) DIAGNÓSTICO: confira as colunas reais da tabela atletas.
--    Esperado: id, escola_id, nome, data_nascimento, rg_ou_matricula
--    (o segundo "CREATE TABLE IF NOT EXISTS atletas" do seu script,
--     com equipe_id / rg_ra, foi ignorado porque a tabela já existia)
-- ---------------------------------------------------------------------
SHOW COLUMNS FROM atletas;

-- ---------------------------------------------------------------------
-- 1) SÚMULAS: hoje sumulas.aluno_id aponta para a tabela ALUNOS,
--    mas as telas enviam ids da tabela ATLETAS. Vamos trocar para atleta_id.
-- ---------------------------------------------------------------------

-- 1a) Veja se existem súmulas antigas com ids que não existem em atletas.
--     Se aparecer alguma linha, apague-a (são dados de teste) antes de seguir:
--     DELETE FROM sumulas WHERE aluno_id NOT IN (SELECT id FROM atletas);
SELECT * FROM sumulas WHERE aluno_id NOT IN (SELECT id FROM atletas);

-- 1b) Veja se há lançamentos repetidos do mesmo atleta no mesmo jogo.
--     Se aparecer algo, apague as duplicatas antes do passo 1e.
SELECT jogo_id, aluno_id, COUNT(*) AS qtd
FROM sumulas GROUP BY jogo_id, aluno_id HAVING COUNT(*) > 1;

-- 1c) Descubra o nome da chave estrangeira atual de aluno_id
SELECT CONSTRAINT_NAME
FROM information_schema.KEY_COLUMN_USAGE
WHERE TABLE_SCHEMA = 'jogos_estudantis'
  AND TABLE_NAME = 'sumulas'
  AND COLUMN_NAME = 'aluno_id'
  AND REFERENCED_TABLE_NAME IS NOT NULL;

-- 1d) Remova essa chave. Normalmente o nome é sumulas_ibfk_2;
--     se o passo 1c mostrou outro nome, troque abaixo.
ALTER TABLE sumulas DROP FOREIGN KEY sumulas_ibfk_2;

-- 1e) Renomeia a coluna, liga em atletas e impede lançamento duplicado
ALTER TABLE sumulas CHANGE aluno_id atleta_id INT NOT NULL;

ALTER TABLE sumulas
  ADD CONSTRAINT fk_sumulas_atleta
  FOREIGN KEY (atleta_id) REFERENCES atletas(id) ON DELETE CASCADE;

ALTER TABLE sumulas
  ADD UNIQUE KEY uq_sumulas_jogo_atleta (jogo_id, atleta_id);

-- ---------------------------------------------------------------------
-- 2) CLASSIFICAÇÃO: uma linha por escola (evita somar pontos em duplicado)
--    Se der erro de duplicidade, rode antes:
--    SELECT escola_id, COUNT(*) FROM classificacao GROUP BY escola_id HAVING COUNT(*) > 1;
-- ---------------------------------------------------------------------
ALTER TABLE classificacao
  ADD UNIQUE KEY uq_classificacao_escola (escola_id);

-- ---------------------------------------------------------------------
-- 2b) CLASSIFICAÇÃO: colunas de gols para o desempate da tabela
-- ---------------------------------------------------------------------
ALTER TABLE classificacao
  ADD COLUMN gols_pro    INT NOT NULL DEFAULT 0,
  ADD COLUMN gols_contra INT NOT NULL DEFAULT 0,
  ADD COLUMN saldo_gols  INT NOT NULL DEFAULT 0;

-- ---------------------------------------------------------------------
-- 3) LIMPEZA OPCIONAL (só rode se tiver certeza de que não usa):
--    a tabela "equipes" veio do segundo script e nenhum código usa.
-- ---------------------------------------------------------------------
-- DROP TABLE equipes;

-- Conferência final
SHOW CREATE TABLE sumulas;
