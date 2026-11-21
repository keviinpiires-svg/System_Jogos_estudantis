-- =====================================================================
-- MIGRAÇÃO 37 — Atletismo por colocação (12/11/2026)
--
-- O atletismo passa a ser lançado por COLOCAÇÃO: chega a folha do juiz
-- ("1º, atleta X, escola Y; 2º, ...") e o ADMIN lança o 1º, o 2º e o 3º de
-- cada prova + categoria + gênero. Na Tabela Geral, cada colocação vale a
-- mesma pontuação das coletivas (pontuacao_geral: 10, 8 e 6) e conta como
-- 1º, 2º ou 3º lugar. Substitui os pontos digitados por escola
-- (pontos_lancados) SÓ no atletismo; xadrez, dama e dominó seguem iguais.
--
-- Cria a tabela atletismo_colocacoes:
--   - prova é TEXTO (as provas do regulamento são sugestão; aceita outra);
--   - o atleta é um nome digitado (os atletas do atletismo não estão
--     cadastrados), opcional;
--   - uma colocação por prova + categoria + gênero (sem empate), e uma
--     escola só aparece uma vez em cada prova + categoria + gênero
--     (regulamento: 1 atleta por escola, por categoria, gênero e prova).
--
-- SÓ CRIAÇÃO e IDEMPOTENTE (CREATE TABLE IF NOT EXISTS): não altera nenhuma
-- tabela existente e pode rodar de novo. O backend que está no ar não lê
-- nada disto; o backend novo PRECISA da tabela (a Tabela Geral, pública,
-- responde 500 sem ela): rode ANTES do deploy. Rode depois do 36.
-- MySQL 8.0.16+ ou MariaDB 10.2+. Faça o dump antes.
-- =====================================================================

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS atletismo_colocacoes (
  id            INT              NOT NULL AUTO_INCREMENT,
  prova         VARCHAR(80)      NOT NULL,            -- como foi digitada ("100 m rasos")
  categoria_id  INT              NOT NULL,
  genero        ENUM('MASCULINO','FEMININO') NOT NULL,
  colocacao     TINYINT UNSIGNED NOT NULL,            -- 1, 2 ou 3
  escola_id     INT              NOT NULL,
  atleta_nome   VARCHAR(150)     NULL,                -- texto livre: o atleta não é cadastrado
  criado_por    INT              NOT NULL,
  criado_em     TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  alterado_por  INT              NULL,
  alterado_em   TIMESTAMP        NULL DEFAULT NULL,
  PRIMARY KEY (id),
  -- sem empate: uma escola por colocação
  UNIQUE KEY uq_atletismo_col_colocacao (prova, categoria_id, genero, colocacao),
  -- 1 atleta por escola em cada prova + categoria + gênero
  UNIQUE KEY uq_atletismo_col_escola (prova, categoria_id, genero, escola_id),
  KEY ix_atletismo_col_escola (escola_id),
  CONSTRAINT fk_atletismo_col_categoria FOREIGN KEY (categoria_id)
    REFERENCES categorias (id) ON DELETE RESTRICT,
  CONSTRAINT fk_atletismo_col_escola FOREIGN KEY (escola_id)
    REFERENCES escolas (id) ON DELETE RESTRICT,
  CONSTRAINT fk_atletismo_col_criado_por FOREIGN KEY (criado_por)
    REFERENCES usuarios (id) ON DELETE RESTRICT,
  CONSTRAINT fk_atletismo_col_alterado_por FOREIGN KEY (alterado_por)
    REFERENCES usuarios (id) ON DELETE RESTRICT,
  CONSTRAINT chk_atletismo_col_colocacao CHECK (colocacao BETWEEN 1 AND 3)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Conferência: a tabela, os dois índices únicos e os pontos antigos de
-- atletismo (esperado 0: se houver algum, ele deixa de somar na Tabela Geral)
SELECT COUNT(*) AS atletismo_colocacoes FROM atletismo_colocacoes;
SELECT INDEX_NAME, GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS colunas
  FROM information_schema.STATISTICS
 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'atletismo_colocacoes' AND NON_UNIQUE = 0
 GROUP BY INDEX_NAME;
SELECT COUNT(*) AS pontos_antigos_de_atletismo
  FROM pontos_lancados p
  INNER JOIN modalidades m ON m.id = p.modalidade_id
 WHERE m.slug = 'atletismo';
