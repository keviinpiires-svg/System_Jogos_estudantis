-- =====================================================================
-- MIGRAÇÃO 46 — faltas por atleta de 0 a 20 (futsal e society) (16/11/2026)
--
-- Na súmula de futsal e society a mesa passa a lançar a falta de cada atleta
-- (sumula_atletas.faltas) e o total da equipe por tempo é calculado a partir
-- do tempo selecionado. O regulamento não define limite individual de faltas
-- nessas modalidades, então o teto de 20 é só uma trava contra erro de
-- digitação (decisão do usuário, 16/11/2026).
--
-- O que muda no banco: só o CHECK da coluna, que desde o db/05 aceita de 0 a
-- 5 (o limite do basquete, em que a 5ª falta exclui o atleta). Passa a aceitar
-- de 0 a 20. O limite de cada modalidade continua no código
-- (src/config/folhasSumula.js): basquete 0 a 5, futsal e society 0 a 20, as
-- demais 0. Nenhuma coluna nova, nenhum dado mexido.
--
-- IDEMPOTENTE: só troca a trava se ela ainda não for a de 0 a 20 (consulta ao
-- information_schema + PREPARE). Rodado de novo, não muda nada. Sem dado de
-- aluno. MySQL 8.0.19+ (DROP CONSTRAINT em CHECK) ou MariaDB 10.2+.
--
-- Compatível com o backend que está no ar (ele só grava de 0 a 5). O backend
-- novo grava até 20 em futsal e society: rode este script ANTES do push dele,
-- com dump antes (na produção). Rode depois do 45.
-- =====================================================================

SET NAMES utf8mb4;

-- Já está na versão de 0 a 20? (o texto da trava traz o número do limite)
SET @tem := (SELECT COUNT(*) FROM information_schema.CHECK_CONSTRAINTS
              WHERE CONSTRAINT_SCHEMA = DATABASE() AND CONSTRAINT_NAME = 'chk_sumula_atletas_faltas');
SET @ja_20 := (SELECT COUNT(*) FROM information_schema.CHECK_CONSTRAINTS
                WHERE CONSTRAINT_SCHEMA = DATABASE() AND CONSTRAINT_NAME = 'chk_sumula_atletas_faltas'
                  AND CHECK_CLAUSE LIKE '%20%');
SET @precisa := (@ja_20 = 0);

-- 1) tira a trava antiga (0 a 5), se existir
SET @sql := IF(@precisa AND @tem > 0,
  'ALTER TABLE sumula_atletas DROP CONSTRAINT chk_sumula_atletas_faltas',
  'SELECT ''trava antiga não precisa sair'' AS db46');
PREPARE passo FROM @sql;
EXECUTE passo;
DEALLOCATE PREPARE passo;

-- 2) põe a nova (0 a 20)
SET @sql := IF(@precisa,
  'ALTER TABLE sumula_atletas ADD CONSTRAINT chk_sumula_atletas_faltas CHECK (faltas BETWEEN 0 AND 20)',
  'SELECT ''chk_sumula_atletas_faltas já é de 0 a 20'' AS db46');
PREPARE passo FROM @sql;
EXECUTE passo;
DEALLOCATE PREPARE passo;

-- 3) Conferência: a trava (esperado: 0 a 20) e quantas linhas já têm falta
SELECT CONSTRAINT_NAME AS trava, CHECK_CLAUSE AS regra
  FROM information_schema.CHECK_CONSTRAINTS
 WHERE CONSTRAINT_SCHEMA = DATABASE() AND CONSTRAINT_NAME = 'chk_sumula_atletas_faltas';

SELECT COUNT(*) AS linhas_com_falta, COALESCE(MAX(faltas), 0) AS maior_falta FROM sumula_atletas WHERE faltas > 0;

-- PARA DESFAZER (só se nenhum atleta tiver mais de 5 faltas gravadas):
-- ALTER TABLE sumula_atletas DROP CONSTRAINT chk_sumula_atletas_faltas;
-- ALTER TABLE sumula_atletas ADD CONSTRAINT chk_sumula_atletas_faltas CHECK (faltas BETWEEN 0 AND 5);
