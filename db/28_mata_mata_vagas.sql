-- =====================================================================
-- MIGRAÇÃO 28 — vagas do mata-mata (06/11/2026)
--
-- Decisão do usuário (06/11/2026): o mata-mata segue a tabela do chefe à
-- risca (número, dia, hora, local e cruzamento de cada jogo). Os 75 jogos
-- (semifinais e finais) precisam existir ANTES de as equipes serem conhecidas,
-- para aparecerem na Agenda e na impressão com a "origem" de cada vaga:
-- "1º do Grupo A", "Melhor 2º colocado", "Vencedor do jogo 263".
--
-- Esta migração só prepara o banco (estrutura); os 75 jogos entram num script
-- de dados à parte.
--
--   1) jogos.equipe_1_id e jogos.equipe_2_id passam a aceitar NULL (vaga ainda
--      sem equipe). A chave estrangeira composta e o CHECK de equipes
--      diferentes continuam valendo para quem tem equipe.
--   2) Tabela nova jogo_vagas: uma linha por vaga (jogo + lado 1 ou 2) com a
--      ORIGEM da vaga:
--        GRUPO     -> a posição (1º, 2º...) de um grupo;
--        MELHOR    -> o melhor 2º (3º...) colocado entre os grupos;
--        VENCEDOR  -> o vencedor de outro jogo (jogo_origem_id).
--      `manual` = 1 quando o ADMIN escolheu a equipe à mão: o preenchimento
--      automático nunca mexe nessa vaga.
--
-- IDEMPOTENTE: cada parte só entra se faltar (consulta ao information_schema +
-- PREPARE), igual no MySQL 8 e no MariaDB. Rodado de novo, não muda nada.
-- Compatível com o backend no ar? Quem lê jogos com INNER JOIN de equipes
-- passa a ignorar os jogos sem equipe; o backend novo trata (LEFT JOIN). Rode
-- ANTES do deploy do backend novo.
--
-- Só estrutura. Rode depois do 27. MySQL 8.0.16+ ou MariaDB 10.2+.
-- =====================================================================

SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- 1) As duas equipes do jogo aceitam NULL
-- ---------------------------------------------------------------------
SET @falta := (SELECT COUNT(*) FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jogos'
                  AND COLUMN_NAME = 'equipe_1_id' AND IS_NULLABLE = 'NO');
SET @sql := IF(@falta > 0,
  'ALTER TABLE jogos MODIFY equipe_1_id INT NULL',
  'SELECT ''jogos.equipe_1_id já aceita nulo'' AS db28');
PREPARE passo FROM @sql;
EXECUTE passo;
DEALLOCATE PREPARE passo;

SET @falta := (SELECT COUNT(*) FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jogos'
                  AND COLUMN_NAME = 'equipe_2_id' AND IS_NULLABLE = 'NO');
SET @sql := IF(@falta > 0,
  'ALTER TABLE jogos MODIFY equipe_2_id INT NULL',
  'SELECT ''jogos.equipe_2_id já aceita nulo'' AS db28');
PREPARE passo FROM @sql;
EXECUTE passo;
DEALLOCATE PREPARE passo;

-- ---------------------------------------------------------------------
-- 2) A origem de cada vaga
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS jogo_vagas (
  id             INT          NOT NULL AUTO_INCREMENT,
  jogo_id        INT          NOT NULL,
  lado           TINYINT      NOT NULL,            -- 1 = equipe 1, 2 = equipe 2
  tipo           ENUM('GRUPO', 'MELHOR', 'VENCEDOR') NOT NULL,
  grupo_id       INT          NULL,                -- GRUPO: de que grupo
  posicao        TINYINT UNSIGNED NULL,            -- GRUPO e MELHOR: 1 = primeiro, 2 = segundo...
  jogo_origem_id INT          NULL,                -- VENCEDOR: o jogo cujo vencedor ocupa a vaga
  rotulo         VARCHAR(80)  NOT NULL,            -- como a tabela do chefe escreve ("1º do Grupo A")
  manual         TINYINT(1)   NOT NULL DEFAULT 0,  -- 1 = escolhida à mão pelo ADMIN: o automático não mexe
  criado_em      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_vaga_jogo_lado (jogo_id, lado),
  KEY ix_vaga_origem (jogo_origem_id),
  KEY ix_vaga_grupo (grupo_id),
  CONSTRAINT fk_vaga_jogo FOREIGN KEY (jogo_id) REFERENCES jogos (id) ON DELETE CASCADE,
  CONSTRAINT fk_vaga_grupo FOREIGN KEY (grupo_id) REFERENCES grupos (id) ON DELETE RESTRICT,
  CONSTRAINT fk_vaga_origem FOREIGN KEY (jogo_origem_id) REFERENCES jogos (id) ON DELETE RESTRICT,
  CONSTRAINT ck_vaga_lado CHECK (lado IN (1, 2)),
  CONSTRAINT ck_vaga_tipo CHECK (
       (tipo = 'GRUPO'    AND grupo_id IS NOT NULL AND posicao IS NOT NULL AND jogo_origem_id IS NULL)
    OR (tipo = 'MELHOR'   AND grupo_id IS NULL     AND posicao IS NOT NULL AND jogo_origem_id IS NULL)
    OR (tipo = 'VENCEDOR' AND grupo_id IS NULL     AND posicao IS NULL     AND jogo_origem_id IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- 3) Conferência: as duas colunas aceitam nulo e a tabela existe
-- ---------------------------------------------------------------------
SELECT COLUMN_NAME AS coluna, IS_NULLABLE AS aceita_nulo
  FROM information_schema.COLUMNS
 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jogos' AND COLUMN_NAME IN ('equipe_1_id', 'equipe_2_id');

SELECT TABLE_NAME AS tabela
  FROM information_schema.TABLES
 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jogo_vagas';
