-- =====================================================================
-- MIGRAÇÃO 17 — histórico das correções dos pontos lançados (21/10/2026)
--
-- Motivo: a correção de um ponto lançado era edição no lugar, e o valor
-- anterior se perdia (só ficava quem alterou por último). Agora cada
-- alteração ou exclusão grava aqui o valor de antes, quem o tinha digitado,
-- o valor novo, quem mudou e quando. O ADMIN consulta na tela.
--
-- Ações:
--   ALTERACAO             — a mesa ou o ADMIN trocou os pontos/colocação
--   EXCLUSAO              — a escola saiu do lançamento (campo apagado)
--   EXCLUSAO_LANCAMENTO   — o ADMIN apagou o lançamento inteiro
--
-- Sem chave para pontos_lancados: a linha pode ter sido apagada, e o
-- histórico fica. O reset do campeonato apaga as duas tabelas.
--
-- IDEMPOTENTE: CREATE TABLE IF NOT EXISTS. Compatível com o backend que está
-- no ar (ele não lê nem grava a tabela). O backend novo grava nela ao
-- corrigir: rode ANTES do push dele.
-- Rode depois do 16. A trava de mesa por local passa a ser o 18.
-- =====================================================================

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS pontos_lancados_historico (
  id               INT              NOT NULL AUTO_INCREMENT,
  modalidade_id    INT              NOT NULL,
  categoria_id     INT              NOT NULL,
  genero           ENUM('MASCULINO','FEMININO') NOT NULL,
  prova_id         INT              NULL,       -- só no atletismo (db/16)
  escola_id        INT              NOT NULL,
  acao             ENUM('ALTERACAO','EXCLUSAO','EXCLUSAO_LANCAMENTO') NOT NULL,
  pontos_antes     TINYINT UNSIGNED NOT NULL,
  colocacao_antes  TINYINT UNSIGNED NULL,
  anterior_por     INT              NULL,       -- quem tinha digitado o valor de antes
  anterior_em      TIMESTAMP        NULL DEFAULT NULL,
  pontos_depois    TINYINT UNSIGNED NULL,       -- NULL nas exclusões
  colocacao_depois TINYINT UNSIGNED NULL,
  usuario_id       INT              NOT NULL,   -- quem fez a correção
  feito_em         TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_historico_lancamento (modalidade_id, categoria_id, genero, prova_id),
  KEY ix_historico_escola (escola_id),
  CONSTRAINT fk_historico_modalidade FOREIGN KEY (modalidade_id) REFERENCES modalidades (id) ON DELETE RESTRICT,
  CONSTRAINT fk_historico_categoria FOREIGN KEY (categoria_id) REFERENCES categorias (id) ON DELETE RESTRICT,
  CONSTRAINT fk_historico_prova FOREIGN KEY (prova_id) REFERENCES provas_atletismo (id) ON DELETE RESTRICT,
  CONSTRAINT fk_historico_escola FOREIGN KEY (escola_id) REFERENCES escolas (id) ON DELETE RESTRICT,
  CONSTRAINT fk_historico_anterior_por FOREIGN KEY (anterior_por) REFERENCES usuarios (id) ON DELETE RESTRICT,
  CONSTRAINT fk_historico_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios (id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Conferência: a tabela existe e começa vazia
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS linhas_no_historico FROM pontos_lancados_historico;
