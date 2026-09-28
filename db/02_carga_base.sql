-- =====================================================================
-- Carga base: dados fixos do evento. Rode depois do 01_schema.sql.
-- NÃO inclui escolas, competições, grupos nem usuários:
--   * escolas/competições/grupos: virão da importação da tabela de grupos
--     (próximo passo, depois de fechar a lista oficial de escolas);
--   * usuários: criados com senha em hash (ver db/README.md).
-- =====================================================================
SET NAMES utf8mb4;

INSERT INTO configuracao_evento (id, nome_evento, ano, cidade, estado, data_inicio, data_fim)
VALUES (1, 'Jogos Estudantis 2026', 2026, 'Barra do Choça', 'BA', '2026-11-23', '2026-11-28');

-- Os 3 blocos da tabela geral
INSERT INTO etapas_ensino (nome, ordem) VALUES
  ('Anos Iniciais', 1),
  ('Anos Finais',   2),
  ('Ensino Médio',  3);

-- Categorias do regulamento. idade_maxima NULL = Aberto.
-- Em 2026: Sub 7=2019, Sub 8=2018, Sub 9=2017, Sub 11=2015, Sub 13=2013,
-- Sub 15=2011, Sub 17=2009 (nascido nesse ano ou depois).
-- etapa_ensino_id fica NULL até decidir como a tabela geral é dividida.
INSERT INTO categorias (nome, idade_maxima, ordem) VALUES
  ('Sub 7',   7, 1),
  ('Sub 8',   8, 2),
  ('Sub 9',   9, 3),
  ('Sub 11', 11, 4),
  ('Sub 13', 13, 5),
  ('Sub 15', 15, 6),
  ('Sub 17', 17, 7),
  ('Aberto', NULL, 8);

-- Modalidades. Máximo de 14 atletas (decisão do usuário); mínimo só gera aviso.
-- Xadrez, Dama e Dominó: [PENDENTE] se entram no sistema.
INSERT INTO modalidades (nome, slug, tipo, tipo_placar, min_atletas, max_atletas, ordem) VALUES
  ('Futsal',          'futsal',          'COLETIVO',   'GOLS',       8,    14,   1),
  ('Futebol Society', 'futebol-society', 'COLETIVO',   'GOLS',       8,    14,   2),
  ('Handebol',        'handebol',        'COLETIVO',   'GOLS',       10,   14,   3),
  ('Baleado',         'baleado',         'COLETIVO',   'ELIMINADOS', 10,   14,   4),
  ('Vôlei',           'volei',           'COLETIVO',   'SETS',       8,    14,   5),
  ('Basquete',        'basquete',        'COLETIVO',   'PONTOS',     8,    14,   6),
  ('Atletismo',       'atletismo',       'INDIVIDUAL', 'MARCA',      NULL, NULL, 7);

-- Pontos da tabela geral por colocação (regulamento)
INSERT INTO pontuacao_geral (posicao, pontos) VALUES
  (1, 10), (2, 8), (3, 6), (4, 4), (5, 2);

-- Provas de atletismo (Sub 8/9: só 50 m; Sub 11 a 17: 100 m e salto)
INSERT INTO provas_atletismo (nome, tipo_resultado, tentativas) VALUES
  ('Corrida 50 metros',  'TEMPO',     1),
  ('Corrida 100 metros', 'TEMPO',     1),
  ('Salto em distância', 'DISTANCIA', 2);
