-- =====================================================================
-- MIGRAÇÃO 11 — pontos lançados pela mesa (atletismo, xadrez, dama, dominó)
--
-- Motivo (chefe, 12/10/2026): atletismo, xadrez, dama e dominó funcionam
-- FORA do sistema, sem súmula e sem cálculo de colocação. O juiz entrega a
-- folha, e a mesa (ou o ADMIN) digita os pontos de cada escola por
-- modalidade × categoria × gênero. Os pontos somam na Tabela Geral.
--
-- O que faz:
--   1) cadastra Xadrez, Dama e Dominó em `modalidades` (o Atletismo já
--      existe desde o 02). Sem competição, elas não aparecem no menu lateral;
--   2) cria `pontos_lancados`: uma linha por escola em cada lançamento, com
--      quem digitou e quando, e quem alterou por último e quando.
--
-- O que NÃO muda: `provas_atletismo` e `resultados_atletismo` ficam como
-- estão, sem uso (eram para lançar marca por atleta, o que saiu do escopo).
--
-- Idempotente: as modalidades só entram se não existirem, e a tabela é
-- CREATE TABLE IF NOT EXISTS. Só acrescenta: o backend que está no ar não
-- lê nada disto. Rode depois do 10.
-- =====================================================================

SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- 1) Modalidades. tipo_placar não se aplica (não há súmula); PONTOS é o
--    valor mais próximo do que a mesa lança.
-- ---------------------------------------------------------------------
INSERT INTO modalidades (nome, slug, tipo, tipo_placar, min_atletas, max_atletas, ordem)
SELECT 'Xadrez', 'xadrez', 'INDIVIDUAL', 'PONTOS', NULL, NULL, 8 FROM DUAL
 WHERE NOT EXISTS (SELECT 1 FROM modalidades WHERE slug = 'xadrez');

INSERT INTO modalidades (nome, slug, tipo, tipo_placar, min_atletas, max_atletas, ordem)
SELECT 'Dama', 'dama', 'INDIVIDUAL', 'PONTOS', NULL, NULL, 9 FROM DUAL
 WHERE NOT EXISTS (SELECT 1 FROM modalidades WHERE slug = 'dama');

INSERT INTO modalidades (nome, slug, tipo, tipo_placar, min_atletas, max_atletas, ordem)
SELECT 'Dominó', 'domino', 'INDIVIDUAL', 'PONTOS', NULL, NULL, 10 FROM DUAL
 WHERE NOT EXISTS (SELECT 1 FROM modalidades WHERE slug = 'domino');

-- ---------------------------------------------------------------------
-- 2) Pontos lançados. Uma linha por escola em cada modalidade × categoria
--    × gênero: corrigir é editar a linha, nunca lançar de novo.
--    Escola fora do lançamento = sem linha; 0 = participou e não pontuou.
--    O teto de 99 barra erro de digitação; o limite esperado (10 ou 20) é
--    só aviso, e mora em src/config/regrasProvisorias.js.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pontos_lancados (
  id            INT              NOT NULL AUTO_INCREMENT,
  modalidade_id INT              NOT NULL,
  categoria_id  INT              NOT NULL,
  genero        ENUM('MASCULINO','FEMININO') NOT NULL,
  escola_id     INT              NOT NULL,
  pontos        TINYINT UNSIGNED NOT NULL,
  colocacao     TINYINT UNSIGNED NULL,      -- só informação: não desempata
  criado_por    INT              NOT NULL,
  criado_em     TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  alterado_por  INT              NULL,
  alterado_em   TIMESTAMP        NULL DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_pontos_lancados (modalidade_id, categoria_id, genero, escola_id),
  KEY ix_pontos_lancados_escola (escola_id),
  CONSTRAINT fk_pontos_lancados_modalidade FOREIGN KEY (modalidade_id)
    REFERENCES modalidades (id) ON DELETE RESTRICT,
  CONSTRAINT fk_pontos_lancados_categoria FOREIGN KEY (categoria_id)
    REFERENCES categorias (id) ON DELETE RESTRICT,
  CONSTRAINT fk_pontos_lancados_escola FOREIGN KEY (escola_id)
    REFERENCES escolas (id) ON DELETE RESTRICT,
  CONSTRAINT fk_pontos_lancados_criado_por FOREIGN KEY (criado_por)
    REFERENCES usuarios (id) ON DELETE RESTRICT,
  CONSTRAINT fk_pontos_lancados_alterado_por FOREIGN KEY (alterado_por)
    REFERENCES usuarios (id) ON DELETE RESTRICT,
  CONSTRAINT chk_pontos_lancados_pontos CHECK (pontos <= 99),
  CONSTRAINT chk_pontos_lancados_colocacao CHECK (colocacao IS NULL OR colocacao BETWEEN 1 AND 99)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- 3) Conferência: as quatro modalidades e a tabela vazia
-- ---------------------------------------------------------------------
SELECT id, nome, slug, tipo FROM modalidades
 WHERE slug IN ('atletismo', 'xadrez', 'dama', 'domino') ORDER BY ordem;
SELECT COUNT(*) AS pontos_lancados FROM pontos_lancados;
