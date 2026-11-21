-- =====================================================================
-- MIGRAÇÃO 45 — a mesa (PLACAR) adiciona atleta na hora do jogo (16/11/2026)
--
-- Na hora do jogo a mesa pode inscrever, na equipe que vai jogar, um atleta
-- que faltou na ficha ou que entrou de última hora (e, se o atleta ainda não
-- existe, cadastrá-lo), e só pode tirar o que ela mesma colocou. Quem colocou
-- e quando fica gravado:
--
--   inscricoes_atletas.criado_por   usuário (mesa) que fez a inscrição
--   atletas.criado_por              usuário (mesa) que cadastrou o atleta
--   (criado_em já existe nas duas tabelas desde o db/01: não é recriado)
--
-- NULL = administrador ou importação (tudo o que já existe fica NULL). Quem
-- se identifica como mesa é só quem tem criado_por preenchido.
--
-- escolas.sigla: a sigla usada no código provisório de quem não tem
-- documento (<SIGLA>SRG<NNN>, guardado normalizado, ex.: ACMSRG028). Já
-- existiam códigos desse tipo no banco, com estas siglas; entram também as
-- das cinco escolas que ainda não tinham (FA, LR, MS, PS e TL). A escola é
-- achada pelo NOME, nunca por id.
--
-- Contas não são apagadas (a tela /usuarios desativa), por isso as chaves
-- estrangeiras são RESTRICT.
--
-- IDEMPOTENTE: coluna, índice, chave estrangeira e sigla só entram se
-- faltarem (information_schema + PREPARE), igual no MySQL 8 e no MariaDB.
-- Só dados de estrutura e as siglas, sem dado de aluno. Compatível com o
-- backend que está no ar (ele não lê nada disto). O backend novo lê: rode
-- ANTES do push dele. Rode depois do 44. Faça o dump antes, na produção.
-- =====================================================================

SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- 1) inscricoes_atletas.criado_por
-- ---------------------------------------------------------------------
SET @falta := (SELECT COUNT(*) = 0 FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'inscricoes_atletas' AND COLUMN_NAME = 'criado_por');
SET @sql := IF(@falta,
  'ALTER TABLE inscricoes_atletas ADD COLUMN criado_por INT NULL',
  'SELECT ''inscricoes_atletas.criado_por já existe'' AS db45');
PREPARE passo FROM @sql;
EXECUTE passo;
DEALLOCATE PREPARE passo;

SET @falta := (SELECT COUNT(*) = 0 FROM information_schema.STATISTICS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'inscricoes_atletas' AND INDEX_NAME = 'ix_inscricoes_criado_por');
SET @sql := IF(@falta,
  'ALTER TABLE inscricoes_atletas ADD KEY ix_inscricoes_criado_por (criado_por)',
  'SELECT ''ix_inscricoes_criado_por já existe'' AS db45');
PREPARE passo FROM @sql;
EXECUTE passo;
DEALLOCATE PREPARE passo;

SET @falta := (SELECT COUNT(*) = 0 FROM information_schema.TABLE_CONSTRAINTS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'inscricoes_atletas'
                  AND CONSTRAINT_NAME = 'fk_inscricoes_criado_por' AND CONSTRAINT_TYPE = 'FOREIGN KEY');
SET @sql := IF(@falta,
  'ALTER TABLE inscricoes_atletas ADD CONSTRAINT fk_inscricoes_criado_por FOREIGN KEY (criado_por) REFERENCES usuarios (id) ON DELETE RESTRICT',
  'SELECT ''fk_inscricoes_criado_por já existe'' AS db45');
PREPARE passo FROM @sql;
EXECUTE passo;
DEALLOCATE PREPARE passo;

-- ---------------------------------------------------------------------
-- 2) atletas.criado_por
-- ---------------------------------------------------------------------
SET @falta := (SELECT COUNT(*) = 0 FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'atletas' AND COLUMN_NAME = 'criado_por');
SET @sql := IF(@falta,
  'ALTER TABLE atletas ADD COLUMN criado_por INT NULL',
  'SELECT ''atletas.criado_por já existe'' AS db45');
PREPARE passo FROM @sql;
EXECUTE passo;
DEALLOCATE PREPARE passo;

SET @falta := (SELECT COUNT(*) = 0 FROM information_schema.STATISTICS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'atletas' AND INDEX_NAME = 'ix_atletas_criado_por');
SET @sql := IF(@falta,
  'ALTER TABLE atletas ADD KEY ix_atletas_criado_por (criado_por)',
  'SELECT ''ix_atletas_criado_por já existe'' AS db45');
PREPARE passo FROM @sql;
EXECUTE passo;
DEALLOCATE PREPARE passo;

SET @falta := (SELECT COUNT(*) = 0 FROM information_schema.TABLE_CONSTRAINTS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'atletas'
                  AND CONSTRAINT_NAME = 'fk_atletas_criado_por' AND CONSTRAINT_TYPE = 'FOREIGN KEY');
SET @sql := IF(@falta,
  'ALTER TABLE atletas ADD CONSTRAINT fk_atletas_criado_por FOREIGN KEY (criado_por) REFERENCES usuarios (id) ON DELETE RESTRICT',
  'SELECT ''fk_atletas_criado_por já existe'' AS db45');
PREPARE passo FROM @sql;
EXECUTE passo;
DEALLOCATE PREPARE passo;

-- ---------------------------------------------------------------------
-- 3) escolas.sigla (e as siglas, pelo nome da escola)
-- ---------------------------------------------------------------------
SET @falta := (SELECT COUNT(*) = 0 FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'escolas' AND COLUMN_NAME = 'sigla');
SET @sql := IF(@falta,
  'ALTER TABLE escolas ADD COLUMN sigla VARCHAR(10) NULL',
  'SELECT ''escolas.sigla já existe'' AS db45');
PREPARE passo FROM @sql;
EXECUTE passo;
DEALLOCATE PREPARE passo;

SET @falta := (SELECT COUNT(*) = 0 FROM information_schema.STATISTICS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'escolas' AND INDEX_NAME = 'uq_escolas_sigla');
SET @sql := IF(@falta,
  'ALTER TABLE escolas ADD UNIQUE KEY uq_escolas_sigla (sigla)',
  'SELECT ''uq_escolas_sigla já existe'' AS db45');
PREPARE passo FROM @sql;
EXECUTE passo;
DEALLOCATE PREPARE passo;

-- Só preenche a que está vazia: uma sigla já escolhida não é trocada. As
-- siglas são as dos códigos provisórios que já existem no banco.
UPDATE escolas SET sigla = 'ACM'   WHERE sigla IS NULL AND nome = 'ACM';
UPDATE escolas SET sigla = 'AD'    WHERE sigla IS NULL AND nome = 'ADELIETA RAMALHO';
UPDATE escolas SET sigla = 'CEBC'  WHERE sigla IS NULL AND nome = 'CEBC';
UPDATE escolas SET sigla = 'CEBN'  WHERE sigla IS NULL AND nome = 'CEBN';
UPDATE escolas SET sigla = 'CEJA'  WHERE sigla IS NULL AND nome = 'CEJA';
UPDATE escolas SET sigla = 'CETI'  WHERE sigla IS NULL AND nome = 'CETI';
UPDATE escolas SET sigla = 'CONV'  WHERE sigla IS NULL AND nome = 'Conveniada';
UPDATE escolas SET sigla = 'EZ'    WHERE sigla IS NULL AND nome = 'EMILIANO ZAPATA';
UPDATE escolas SET sigla = 'FA'    WHERE sigla IS NULL AND nome = 'FRANCISCO AMORIM';
UPDATE escolas SET sigla = 'JD'    WHERE sigla IS NULL AND nome = 'JOSE DIAS';
UPDATE escolas SET sigla = 'JL'    WHERE sigla IS NULL AND nome = 'JOSENILDO LEITE';
UPDATE escolas SET sigla = 'LR'    WHERE sigla IS NULL AND nome = 'LUCIA ROCHA';
UPDATE escolas SET sigla = 'MR'    WHERE sigla IS NULL AND nome = 'MANOEL RAMOS';
UPDATE escolas SET sigla = 'MG'    WHERE sigla IS NULL AND nome = 'MARIA DA GLORIA';
UPDATE escolas SET sigla = 'MS'    WHERE sigla IS NULL AND nome = 'MARLENE SANTANA';
UPDATE escolas SET sigla = 'PS'    WHERE sigla IS NULL AND nome = 'PORTAL DO SABER';
UPDATE escolas SET sigla = 'TL'    WHERE sigla IS NULL AND nome = 'TEODULO LEITE';
UPDATE escolas SET sigla = 'VL'    WHERE sigla IS NULL AND nome = 'VITORIA LIMA';

-- ---------------------------------------------------------------------
-- 4) Conferência: as colunas, as chaves, as escolas sem sigla (esperado 0 nas
--    18 escolas do evento) e quantas inscrições/atletas já vêm da mesa (0)
-- ---------------------------------------------------------------------
SELECT TABLE_NAME AS tabela, COLUMN_NAME AS coluna, COLUMN_TYPE AS tipo, IS_NULLABLE AS aceita_nulo
  FROM information_schema.COLUMNS
 WHERE TABLE_SCHEMA = DATABASE()
   AND ((TABLE_NAME IN ('inscricoes_atletas', 'atletas') AND COLUMN_NAME = 'criado_por')
     OR (TABLE_NAME = 'escolas' AND COLUMN_NAME = 'sigla'))
 ORDER BY TABLE_NAME;

SELECT TABLE_NAME AS tabela, CONSTRAINT_NAME AS chave, REFERENCED_TABLE_NAME AS aponta_para
  FROM information_schema.REFERENTIAL_CONSTRAINTS
 WHERE CONSTRAINT_SCHEMA = DATABASE() AND CONSTRAINT_NAME IN ('fk_inscricoes_criado_por', 'fk_atletas_criado_por');

SELECT COUNT(*) AS escolas, SUM(sigla IS NULL) AS escolas_sem_sigla FROM escolas;
SELECT (SELECT COUNT(*) FROM inscricoes_atletas WHERE criado_por IS NOT NULL) AS inscricoes_da_mesa,
       (SELECT COUNT(*) FROM atletas WHERE criado_por IS NOT NULL) AS atletas_da_mesa;
