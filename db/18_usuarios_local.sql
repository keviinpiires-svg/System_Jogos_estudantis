-- =====================================================================
-- MIGRAÇÃO 18 — trava de mesa por local (28/10/2026)
--
-- Decisão do chefe (12/10/2026): uma conta de mesa (PLACAR) por local de
-- jogo. A coluna usuarios.local_id prende a conta ao local:
--   * PLACAR com local: só inicia jogo e lança súmula de jogo DAQUELE local
--     (403 nos outros, com o nome dos dois locais);
--   * PLACAR sem local (NULL): sem trava, para ninguém ficar bloqueado por
--     esquecimento — a tela /usuarios mostra "sem local definido";
--   * ADMIN: nunca travado (o backend grava NULL para ele).
-- Tabuleiro e Atletismo (pontos lançados) não têm local: seguem abertos a
-- toda conta PLACAR.
--
-- A trava lê o local do BANCO a cada escrita (não do token): mudar o local
-- da conta vale na hora, sem novo login.
--
-- IDEMPOTENTE: coluna, índice e chave estrangeira só entram se faltarem
-- (consulta ao information_schema + PREPARE), igual no MySQL 8 e no
-- MariaDB. Rodado de novo, não muda nada. Compatível com o backend que está
-- no ar (ele não lê a coluna). O backend novo lê: rode ANTES do push dele.
-- Rode depois do 17 (o 19 já existe e independe deste).
-- =====================================================================

SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- 1) A coluna, logo depois do perfil
-- ---------------------------------------------------------------------
SET @falta := (SELECT COUNT(*) = 0 FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'usuarios' AND COLUMN_NAME = 'local_id');
SET @sql := IF(@falta,
  'ALTER TABLE usuarios ADD COLUMN local_id INT NULL AFTER perfil',
  'SELECT ''usuarios.local_id já existe'' AS db18');
PREPARE passo FROM @sql;
EXECUTE passo;
DEALLOCATE PREPARE passo;

-- ---------------------------------------------------------------------
-- 2) O índice da chave estrangeira (nome fixo, para a conferência achar)
-- ---------------------------------------------------------------------
SET @falta := (SELECT COUNT(*) = 0 FROM information_schema.STATISTICS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'usuarios' AND INDEX_NAME = 'ix_usuarios_local');
SET @sql := IF(@falta,
  'ALTER TABLE usuarios ADD KEY ix_usuarios_local (local_id)',
  'SELECT ''ix_usuarios_local já existe'' AS db18');
PREPARE passo FROM @sql;
EXECUTE passo;
DEALLOCATE PREPARE passo;

-- ---------------------------------------------------------------------
-- 3) O local precisa existir. RESTRICT: apagar um local que tem mesa
--    é recusado (troque a mesa de local antes).
-- ---------------------------------------------------------------------
SET @falta := (SELECT COUNT(*) = 0 FROM information_schema.TABLE_CONSTRAINTS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'usuarios'
                  AND CONSTRAINT_NAME = 'fk_usuarios_local' AND CONSTRAINT_TYPE = 'FOREIGN KEY');
SET @sql := IF(@falta,
  'ALTER TABLE usuarios ADD CONSTRAINT fk_usuarios_local FOREIGN KEY (local_id) REFERENCES locais_disputa (id) ON DELETE RESTRICT',
  'SELECT ''fk_usuarios_local já existe'' AS db18');
PREPARE passo FROM @sql;
EXECUTE passo;
DEALLOCATE PREPARE passo;

-- ---------------------------------------------------------------------
-- 4) Conferência: a coluna (int, aceita nulo), a chave estrangeira, e as
--    contas de mesa com e sem local (logo depois do script, todas sem)
-- ---------------------------------------------------------------------
SELECT COLUMN_NAME AS coluna, COLUMN_TYPE AS tipo, IS_NULLABLE AS aceita_nulo
  FROM information_schema.COLUMNS
 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'usuarios' AND COLUMN_NAME = 'local_id';

SELECT CONSTRAINT_NAME AS chave, REFERENCED_TABLE_NAME AS aponta_para
  FROM information_schema.REFERENTIAL_CONSTRAINTS
 WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'usuarios' AND CONSTRAINT_NAME = 'fk_usuarios_local';

SELECT perfil, SUM(local_id IS NOT NULL) AS com_local, SUM(local_id IS NULL) AS sem_local
  FROM usuarios GROUP BY perfil;
