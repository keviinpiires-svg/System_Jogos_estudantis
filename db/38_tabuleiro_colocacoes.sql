-- =====================================================================
-- MIGRAÇÃO 38 — Tabuleiro (xadrez, dama e dominó) por colocação (12/11/2026)
--
-- Como o atletismo (db/37): chega a folha do juiz e o ADMIN lança o 1º, o 2º
-- e o 3º de cada JOGO (Xadrez, Dama ou Dominó) + categoria. Pelo
-- regulamento o tabuleiro é MISTO (não separa masculino e feminino) e todos
-- os jogos são individuais, inclusive o dominó: por isso NÃO há coluna de
-- gênero (é sempre misto) e o atleta é um nome só. Na Tabela Geral, cada
-- colocação vale a pontuação das coletivas (pontuacao_geral: 10, 8 e 6) e
-- conta como 1º, 2º ou 3º lugar. Substitui os pontos digitados por escola
-- (pontos_lancados) no xadrez, na dama e no dominó.
--
-- Cria a tabela tabuleiro_colocacoes (irmã de atletismo_colocacoes, que NÃO
-- é alterada):
--   - o jogo é a modalidade (modalidades: xadrez, dama e dominó, do db/11);
--     o backend só aceita esses três;
--   - o atleta é um nome digitado, opcional;
--   - uma colocação por jogo + categoria (sem empate), e uma escola só
--     aparece uma vez em cada jogo + categoria.
--
-- SÓ CRIAÇÃO e IDEMPOTENTE (CREATE TABLE IF NOT EXISTS): não altera nenhuma
-- tabela existente e pode rodar de novo. O backend novo PRECISA da tabela (a
-- Tabela Geral, pública, responde 500 sem ela): rode ANTES do deploy. Rode
-- depois do 37. MySQL 8.0.16+ ou MariaDB 10.2+. Faça o dump antes.
-- =====================================================================

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS tabuleiro_colocacoes (
  id            INT              NOT NULL AUTO_INCREMENT,
  modalidade_id INT              NOT NULL,            -- o jogo: Xadrez, Dama ou Dominó
  categoria_id  INT              NOT NULL,
  colocacao     TINYINT UNSIGNED NOT NULL,            -- 1, 2 ou 3
  escola_id     INT              NOT NULL,
  atleta_nome   VARCHAR(150)     NULL,                -- texto livre: o atleta não é cadastrado
  criado_por    INT              NOT NULL,
  criado_em     TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  alterado_por  INT              NULL,
  alterado_em   TIMESTAMP        NULL DEFAULT NULL,
  PRIMARY KEY (id),
  -- sem empate: uma escola por colocação
  UNIQUE KEY uq_tabuleiro_col_colocacao (modalidade_id, categoria_id, colocacao),
  -- uma escola só uma vez em cada jogo + categoria
  UNIQUE KEY uq_tabuleiro_col_escola (modalidade_id, categoria_id, escola_id),
  KEY ix_tabuleiro_col_escola (escola_id),
  CONSTRAINT fk_tabuleiro_col_modalidade FOREIGN KEY (modalidade_id)
    REFERENCES modalidades (id) ON DELETE RESTRICT,
  CONSTRAINT fk_tabuleiro_col_categoria FOREIGN KEY (categoria_id)
    REFERENCES categorias (id) ON DELETE RESTRICT,
  CONSTRAINT fk_tabuleiro_col_escola FOREIGN KEY (escola_id)
    REFERENCES escolas (id) ON DELETE RESTRICT,
  CONSTRAINT fk_tabuleiro_col_criado_por FOREIGN KEY (criado_por)
    REFERENCES usuarios (id) ON DELETE RESTRICT,
  CONSTRAINT fk_tabuleiro_col_alterado_por FOREIGN KEY (alterado_por)
    REFERENCES usuarios (id) ON DELETE RESTRICT,
  CONSTRAINT chk_tabuleiro_col_colocacao CHECK (colocacao BETWEEN 1 AND 3)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Conferência: a tabela, os dois índices únicos, os três jogos cadastrados
-- (esperado 3) e os pontos antigos do tabuleiro (esperado 0: se houver
-- algum, ele deixa de somar na Tabela Geral)
SELECT COUNT(*) AS tabuleiro_colocacoes FROM tabuleiro_colocacoes;
SELECT INDEX_NAME, GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS colunas
  FROM information_schema.STATISTICS
 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'tabuleiro_colocacoes' AND NON_UNIQUE = 0
 GROUP BY INDEX_NAME;
SELECT COUNT(*) AS jogos_do_tabuleiro FROM modalidades WHERE slug IN ('xadrez', 'dama', 'domino');
SELECT COUNT(*) AS pontos_antigos_do_tabuleiro
  FROM pontos_lancados p
  INNER JOIN modalidades m ON m.id = p.modalidade_id
 WHERE m.slug IN ('xadrez', 'dama', 'domino');
