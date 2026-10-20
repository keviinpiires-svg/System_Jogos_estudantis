-- =====================================================================
-- LIMPEZA DOS DADOS DE TESTE — fora da numeração do db/ de propósito:
-- não é migração, é uma faxina para rodar UMA VEZ antes do evento.
--
-- APAGA (dados que o evento produz):
--   jogos, sumula_equipes, sumula_atletas, jogo_sets, colocacoes_finais,
--   pontos_lancados, ajustes_pontos_geral, suspensoes e resultados_atletismo
--   (este último está sem uso desde 12/10/2026, mas aponta para atletas e
--   precisa sair antes deles na parte opcional).
-- MANTÉM (estrutura e cadastros):
--   escolas, escola_apelidos, modalidades, categorias, competições, grupos,
--   equipes, locais, usuários, configuração do evento, etapas de ensino,
--   pontuação da tabela geral e provas de atletismo.
-- ATLETAS E INSCRIÇÕES: na PARTE 2, comentada. Só rode se decidir apagá-los.
--
-- É o mesmo conjunto que o "Reiniciar Campeonato" (DELETE /api/campeonato/reset)
-- apaga, na mesma ordem, mas aqui você roda e confere passo a passo.
--
-- COMO RODAR (DBeaver, conexão `railway`):
--   * ANTES: dump do jogos_2026 conferido (tamanho, "-- Dump completed").
--   * Ative o banco jogos_2026 e rode o inventário (inventario_producao.sql).
--   * Rode ESTE arquivo inteiro como script (Alt+X) ou comando a comando
--     (Ctrl+Enter), na ordem. A trava do começo para tudo se o banco ativo
--     não for o jogos_2026 (ou um banco de teste com "dev" no nome).
--   * Se o DBeaver estiver em modo "manual commit", confirme no fim.
--
-- As tabelas não levam prefixo de banco: valem para o banco ATIVO, que a
-- trava confere. Validado em 20/10/2026 no MySQL 8.0.46 (e antes no MariaDB
-- 10.4 do desenvolvimento), em banco descartável com dados de teste em todas as
-- tabelas (01 a 11, como a produção hoje), partes 1 e 2: as tabelas zeram, os
-- contadores voltam a 1, as 39 chaves estrangeiras seguem de pé e recusando,
-- os cadastros não mudam, e o 12, o 13 e o 14 rodam limpos depois. Num banco
-- sem "dev" no nome, a trava parou com o erro 3819 antes de apagar.
-- =====================================================================

SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- Trava: só no jogos_2026 ou num banco de teste com "dev" no nome. Em
-- qualquer outro (o antigo `railway`, por exemplo), o CHECK recusa
-- (erro 3819, banco_ativo_nao_e_jogos_2026) e nada é apagado.
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS trava_limpeza;
CREATE TEMPORARY TABLE trava_limpeza (
  banco VARCHAR(64) NOT NULL,   -- sem banco ativo, DATABASE() é NULL e o INSERT já recusa
  CONSTRAINT banco_ativo_nao_e_jogos_2026 CHECK (banco = 'jogos_2026' OR banco LIKE '%dev%')
);
INSERT INTO trava_limpeza (banco) VALUES (DATABASE());
DROP TEMPORARY TABLE trava_limpeza;

-- Antes: quantas linhas cada tabela tem (anote para comparar)
SELECT 'antes' AS momento,
       (SELECT COUNT(*) FROM jogos) AS jogos,
       (SELECT COUNT(*) FROM sumula_equipes) AS sumula_equipes,
       (SELECT COUNT(*) FROM sumula_atletas) AS sumula_atletas,
       (SELECT COUNT(*) FROM jogo_sets) AS jogo_sets,
       (SELECT COUNT(*) FROM colocacoes_finais) AS colocacoes,
       (SELECT COUNT(*) FROM pontos_lancados) AS pontos_lancados,
       (SELECT COUNT(*) FROM ajustes_pontos_geral) AS ajustes,
       (SELECT COUNT(*) FROM suspensoes) AS suspensoes,
       (SELECT COUNT(*) FROM resultados_atletismo) AS resultados_atletismo,
       (SELECT COUNT(*) FROM atletas) AS atletas,
       (SELECT COUNT(*) FROM inscricoes_atletas) AS inscricoes;

-- ---------------------------------------------------------------------
-- PARTE 1 — dados de jogo. Filhos antes dos pais: as chaves estrangeiras
-- continuam ligadas e conferem cada passo. Tudo numa transação: se um
-- comando falhar, nada do que veio antes fica gravado.
-- ---------------------------------------------------------------------
START TRANSACTION;

DELETE FROM sumula_atletas;
DELETE FROM sumula_equipes;
DELETE FROM jogo_sets;
DELETE FROM suspensoes;
DELETE FROM colocacoes_finais;
DELETE FROM ajustes_pontos_geral;
DELETE FROM pontos_lancados;
DELETE FROM resultados_atletismo;
DELETE FROM jogos;

COMMIT;

-- Contadores de volta para 1 (fora da transação: ALTER TABLE confirma
-- sozinho). Com a tabela vazia, o próximo id é 1.
ALTER TABLE sumula_atletas       AUTO_INCREMENT = 1;
ALTER TABLE sumula_equipes       AUTO_INCREMENT = 1;
ALTER TABLE jogo_sets            AUTO_INCREMENT = 1;
ALTER TABLE suspensoes           AUTO_INCREMENT = 1;
ALTER TABLE colocacoes_finais    AUTO_INCREMENT = 1;
ALTER TABLE ajustes_pontos_geral AUTO_INCREMENT = 1;
ALTER TABLE pontos_lancados      AUTO_INCREMENT = 1;
ALTER TABLE resultados_atletismo AUTO_INCREMENT = 1;
ALTER TABLE jogos                AUTO_INCREMENT = 1;

-- Depois: as tabelas de jogo em 0; atletas e inscrições como estavam
SELECT 'depois' AS momento,
       (SELECT COUNT(*) FROM jogos) AS jogos,
       (SELECT COUNT(*) FROM sumula_equipes) AS sumula_equipes,
       (SELECT COUNT(*) FROM sumula_atletas) AS sumula_atletas,
       (SELECT COUNT(*) FROM jogo_sets) AS jogo_sets,
       (SELECT COUNT(*) FROM colocacoes_finais) AS colocacoes,
       (SELECT COUNT(*) FROM pontos_lancados) AS pontos_lancados,
       (SELECT COUNT(*) FROM ajustes_pontos_geral) AS ajustes,
       (SELECT COUNT(*) FROM suspensoes) AS suspensoes,
       (SELECT COUNT(*) FROM resultados_atletismo) AS resultados_atletismo,
       (SELECT COUNT(*) FROM atletas) AS atletas,
       (SELECT COUNT(*) FROM inscricoes_atletas) AS inscricoes;

-- ---------------------------------------------------------------------
-- PARTE 2 — ATLETAS E INSCRIÇÕES (OPCIONAL, COMENTADA)
--
-- Só rode se decidir que os atletas cadastrados também são de teste. Ela
-- precisa da PARTE 1 antes (súmulas, suspensões e resultados de atletismo
-- apontam para eles). Escolas, equipes e o resto continuam.
--
-- Para rodar: tire o "-- " do começo de cada linha abaixo e execute.
-- ---------------------------------------------------------------------
-- START TRANSACTION;
-- DELETE FROM inscricoes_atletas;
-- DELETE FROM atletas;
-- COMMIT;
-- ALTER TABLE inscricoes_atletas AUTO_INCREMENT = 1;
-- ALTER TABLE atletas            AUTO_INCREMENT = 1;
-- SELECT (SELECT COUNT(*) FROM atletas) AS atletas, (SELECT COUNT(*) FROM inscricoes_atletas) AS inscricoes;
