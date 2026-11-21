-- =====================================================================
-- MIGRAÇÃO 20 — evento de 18 a 21/11/2026 e os ajustes do chefe (03/11/2026)
--
-- O evento mudou de 25 a 28/11 para 18 a 21/11/2026: mesmos dias da semana,
-- sete dias antes. O chefe também mexeu em alguns jogos. O mapa jogo a jogo é
-- docs/importacao/mapa_jogos_18a21.csv (fora do git, como toda a pasta);
-- aqui entram só os números, sem nome de escola.
--
--   a) Os jogos AGENDADOS de 25 a 28/11/2026 vão sete dias para trás; hora e
--      local não mudam.
--   b) Saem os jogos de número da tabela 34, 143 e 208 (os três do FRANCISCO
--      AMORIM no Baleado M Sub 8 e no Futsal M Sub 8). O numero_jogo das duas
--      competições é compactado, como o excluirJogo faz (sem buracos).
--   c) Jogo 203 (Futsal M Sub 8): FRANCISCO AMORIM sai e JOSE DIAS entra no
--      mesmo lado: JOSE DIAS x ADELIETA RAMALHO.
--   d) Jogo 35 (Basquete F Sub 15, CEBC x CEJA): 17:50 passa a 17:10, a hora
--      do jogo 34, que saiu.
--   e) numero_tabela renumerado pelo mapa (204 mudanças), em duas fases por
--      causa do índice único: primeiro o número novo + 10000, depois - 10000.
--   f) Saem as equipes do FRANCISCO AMORIM no Baleado M Sub 8 e no Futsal M
--      Sub 8 — só se não tiverem mais jogo, súmula, atleta inscrito nem
--      colocação (senão ficam, e a conferência mostra "ficou").
--   +  configuracao_evento: de 2026-11-18 a 2026-11-21.
--   g) Conferências: 237 jogos; por dia 18/11 = 37, 19/11 = 95, 20/11 = 80 e
--      21/11 = 25; números da tabela únicos; nenhum jogo fora de 18 a 21/11.
--
-- ORDEM DE EXECUÇÃO: tudo o que depende do número antigo (b, d, e) acha o
-- jogo pelo NÚMERO + a DATA ANTIGA, e roda antes de a) mudar as datas. É isso
-- que torna o script IDEMPOTENTE: na segunda vez nenhum jogo casa com
-- "número X em 25 a 28/11", e c) e f) acham o jogo e a equipe pelos nomes.
--
-- SEGURANÇA: uma transação só. As travas (CHECK em tabela temporária, erro
-- 3819 no MySQL e 4025 no MariaDB) param o script sem gravar nada:
--   jogo_a_remover_tem_sumula_placar_ou_nao_esta_agendado  (antes de b)
--   conferencia_do_db20_divergiu                           (antes do COMMIT)
-- No cliente mysql o erro encerra a sessão e a transação é desfeita. No
-- DBeaver, se um comando falhar, rode ROLLBACK antes de qualquer outra coisa.
--
-- Só dados: não mexe em estrutura, e o backend no ar lê o resultado sem
-- mudar. Rode depois do 19. MySQL 8.0.16+ ou MariaDB 10.2+ (CHECK de verdade
-- e funções de janela).
-- =====================================================================

SET NAMES utf8mb4;

START TRANSACTION;

-- ---------------------------------------------------------------------
-- Os jogos que saem (número da tabela e data antiga)
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS remover_jogos_db20;
CREATE TEMPORARY TABLE remover_jogos_db20 (
  numero_tabela SMALLINT UNSIGNED NOT NULL PRIMARY KEY,
  data_antiga   DATE              NOT NULL
);
INSERT INTO remover_jogos_db20 (numero_tabela, data_antiga) VALUES
  (34, '2026-11-25'), (143, '2026-11-27'), (208, '2026-11-27');

-- ---------------------------------------------------------------------
-- Trava: os jogos que saem precisam estar AGENDADOS e intocados
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS trava_jogos_db20;
CREATE TEMPORARY TABLE trava_jogos_db20 (
  jogo  VARCHAR(40) NOT NULL,
  livre TINYINT     NOT NULL,
  CONSTRAINT jogo_a_remover_tem_sumula_placar_ou_nao_esta_agendado CHECK (livre = 1)
);

INSERT INTO trava_jogos_db20 (jogo, livre)
SELECT CONCAT('jogo nº ', j.numero_tabela, ' (id ', j.id, ')'),
       CASE WHEN j.status <> 'AGENDADO'
              OR j.placar_1 IS NOT NULL OR j.placar_2 IS NOT NULL
              OR j.penaltis_1 IS NOT NULL OR j.penaltis_2 IS NOT NULL
              OR j.vencedor_equipe_id IS NOT NULL OR j.baleou_primeiro_equipe_id IS NOT NULL
              OR EXISTS (SELECT 1 FROM sumula_atletas sa WHERE sa.jogo_id = j.id)
              OR EXISTS (SELECT 1 FROM sumula_equipes se WHERE se.jogo_id = j.id)
              OR EXISTS (SELECT 1 FROM jogo_sets js WHERE js.jogo_id = j.id)
              OR EXISTS (SELECT 1 FROM suspensoes su WHERE su.jogo_origem_id = j.id)
            THEN 0 ELSE 1 END
  FROM jogos j
  INNER JOIN remover_jogos_db20 r ON r.numero_tabela = j.numero_tabela
                                 AND DATE(j.data_hora) = r.data_antiga;

DROP TEMPORARY TABLE trava_jogos_db20;

-- ---------------------------------------------------------------------
-- b) Saem os jogos 34, 143 e 208, e o numero_jogo das competições deles é
-- compactado (o mesmo "sem buracos" do excluirJogo)
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS competicoes_mexidas_db20;
CREATE TEMPORARY TABLE competicoes_mexidas_db20 (competicao_id INT NOT NULL PRIMARY KEY);

-- As duas competições pelo nome, e não pelos jogos removidos: assim a
-- compactação também roda (e não faz nada) na segunda vez
INSERT INTO competicoes_mexidas_db20 (competicao_id)
SELECT c.id
  FROM competicoes c
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
 WHERE m.slug IN ('baleado', 'futsal') AND cat.nome = 'Sub 8' AND c.genero = 'MASCULINO';

DELETE j FROM jogos j
  INNER JOIN remover_jogos_db20 r ON r.numero_tabela = j.numero_tabela
                                 AND DATE(j.data_hora) = r.data_antiga;

DROP TEMPORARY TABLE remover_jogos_db20;

DROP TEMPORARY TABLE IF EXISTS numero_jogo_db20;
CREATE TEMPORARY TABLE numero_jogo_db20 (
  jogo_id     INT NOT NULL PRIMARY KEY,
  numero_novo INT NOT NULL
);
INSERT INTO numero_jogo_db20 (jogo_id, numero_novo)
SELECT id, ROW_NUMBER() OVER (PARTITION BY competicao_id ORDER BY numero_jogo)
  FROM jogos
 WHERE competicao_id IN (SELECT competicao_id FROM competicoes_mexidas_db20);

-- Duas fases, por causa do índice único (competicao_id, numero_jogo)
UPDATE jogos j INNER JOIN numero_jogo_db20 n ON n.jogo_id = j.id
   SET j.numero_jogo = n.numero_novo + 10000
 WHERE j.numero_jogo <> n.numero_novo;
UPDATE jogos j INNER JOIN numero_jogo_db20 n ON n.jogo_id = j.id
   SET j.numero_jogo = n.numero_novo
 WHERE j.numero_jogo = n.numero_novo + 10000;

DROP TEMPORARY TABLE numero_jogo_db20;
DROP TEMPORARY TABLE competicoes_mexidas_db20;

-- ---------------------------------------------------------------------
-- c) Jogo 203: FRANCISCO AMORIM x ADELIETA RAMALHO vira JOSE DIAS x ADELIETA
-- RAMALHO (Futsal M Sub 8). Pelos nomes: na segunda vez não acha nada.
-- JOSE DIAS precisa estar no mesmo grupo do jogo.
-- ---------------------------------------------------------------------
UPDATE jogos j
  INNER JOIN competicoes c ON c.id = j.competicao_id
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
  INNER JOIN equipes sai ON sai.id = j.equipe_1_id
  INNER JOIN escolas es_sai ON es_sai.id = sai.escola_id
  INNER JOIN equipes outra ON outra.id = j.equipe_2_id
  INNER JOIN escolas es_outra ON es_outra.id = outra.escola_id
  INNER JOIN escolas es_entra ON es_entra.nome = 'JOSE DIAS'
  INNER JOIN equipes entra ON entra.competicao_id = c.id AND entra.escola_id = es_entra.id
                          AND entra.grupo_id <=> j.grupo_id
   SET j.equipe_1_id = entra.id
 WHERE m.slug = 'futsal' AND cat.nome = 'Sub 8' AND c.genero = 'MASCULINO'
   AND es_sai.nome = 'FRANCISCO AMORIM' AND es_outra.nome = 'ADELIETA RAMALHO'
   AND j.status = 'AGENDADO';

-- ---------------------------------------------------------------------
-- d) Jogo 35: 17:50 passa a 17:10, no mesmo dia
-- ---------------------------------------------------------------------
UPDATE jogos
   SET data_hora = TIMESTAMP(DATE(data_hora), '17:10:00')
 WHERE numero_tabela = 35 AND DATE(data_hora) = '2026-11-25' AND TIME(data_hora) = '17:50:00';

-- ---------------------------------------------------------------------
-- e) Renumeração pelo mapa: (número atual, data antiga, número novo).
-- Só as 204 mudanças; os outros 33 jogos mantêm o número.
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS mapa_db20;
CREATE TEMPORARY TABLE mapa_db20 (
  numero_atual SMALLINT UNSIGNED NOT NULL PRIMARY KEY,
  data_antiga  DATE              NOT NULL,
  numero_novo  SMALLINT UNSIGNED NOT NULL UNIQUE
);
INSERT INTO mapa_db20 (numero_atual, data_antiga, numero_novo) VALUES
  (35, '2026-11-25', 34), (36, '2026-11-25', 35), (37, '2026-11-25', 36), (38, '2026-11-25', 37), (39, '2026-11-26', 38), (40, '2026-11-26', 39),
  (41, '2026-11-26', 40), (42, '2026-11-26', 41), (43, '2026-11-26', 42), (44, '2026-11-26', 43), (45, '2026-11-26', 44), (46, '2026-11-26', 45),
  (47, '2026-11-26', 46), (48, '2026-11-26', 47), (49, '2026-11-26', 48), (50, '2026-11-26', 49), (51, '2026-11-26', 50), (52, '2026-11-26', 51),
  (53, '2026-11-26', 52), (54, '2026-11-26', 53), (55, '2026-11-26', 54), (56, '2026-11-26', 55), (57, '2026-11-26', 56), (58, '2026-11-26', 57),
  (59, '2026-11-26', 58), (60, '2026-11-26', 59), (61, '2026-11-26', 60), (62, '2026-11-26', 61), (63, '2026-11-26', 62), (64, '2026-11-26', 63),
  (65, '2026-11-26', 64), (66, '2026-11-26', 65), (67, '2026-11-26', 66), (68, '2026-11-26', 67), (69, '2026-11-26', 68), (70, '2026-11-26', 69),
  (71, '2026-11-26', 70), (72, '2026-11-26', 71), (73, '2026-11-26', 72), (74, '2026-11-26', 73), (75, '2026-11-26', 74), (76, '2026-11-26', 75),
  (77, '2026-11-26', 76), (78, '2026-11-26', 77), (79, '2026-11-26', 78), (80, '2026-11-26', 79), (81, '2026-11-26', 80), (82, '2026-11-26', 81),
  (83, '2026-11-26', 82), (84, '2026-11-26', 83), (85, '2026-11-26', 84), (86, '2026-11-26', 85), (87, '2026-11-26', 86), (88, '2026-11-26', 87),
  (89, '2026-11-26', 88), (90, '2026-11-26', 89), (91, '2026-11-26', 90), (92, '2026-11-26', 91), (93, '2026-11-26', 92), (94, '2026-11-26', 93),
  (95, '2026-11-26', 94), (96, '2026-11-26', 95), (97, '2026-11-26', 96), (98, '2026-11-26', 97), (99, '2026-11-26', 98), (100, '2026-11-26', 99),
  (101, '2026-11-26', 100), (102, '2026-11-26', 101), (103, '2026-11-26', 102), (104, '2026-11-26', 103), (105, '2026-11-26', 104), (106, '2026-11-26', 105),
  (107, '2026-11-26', 106), (108, '2026-11-26', 107), (109, '2026-11-26', 108), (110, '2026-11-26', 109), (111, '2026-11-26', 110), (112, '2026-11-26', 111),
  (113, '2026-11-26', 112), (114, '2026-11-26', 113), (115, '2026-11-26', 114), (116, '2026-11-26', 115), (117, '2026-11-26', 116), (118, '2026-11-26', 117),
  (119, '2026-11-26', 118), (120, '2026-11-26', 119), (121, '2026-11-26', 120), (122, '2026-11-26', 121), (123, '2026-11-26', 122), (124, '2026-11-26', 123),
  (125, '2026-11-26', 124), (126, '2026-11-26', 125), (127, '2026-11-26', 126), (128, '2026-11-26', 127), (129, '2026-11-26', 128), (130, '2026-11-26', 129),
  (131, '2026-11-26', 130), (132, '2026-11-26', 131), (133, '2026-11-26', 132), (134, '2026-11-27', 133), (135, '2026-11-27', 134), (136, '2026-11-27', 135),
  (137, '2026-11-27', 136), (138, '2026-11-27', 137), (139, '2026-11-27', 138), (140, '2026-11-27', 139), (141, '2026-11-27', 140), (142, '2026-11-27', 141),
  (144, '2026-11-27', 142), (145, '2026-11-27', 143), (146, '2026-11-27', 144), (147, '2026-11-27', 145), (148, '2026-11-27', 146), (149, '2026-11-27', 147),
  (154, '2026-11-27', 152), (155, '2026-11-27', 153), (156, '2026-11-27', 154), (157, '2026-11-27', 155), (158, '2026-11-27', 156), (159, '2026-11-27', 157),
  (160, '2026-11-27', 158), (161, '2026-11-27', 159), (162, '2026-11-27', 160), (163, '2026-11-27', 161), (164, '2026-11-27', 162), (165, '2026-11-27', 163),
  (166, '2026-11-27', 164), (167, '2026-11-27', 165), (168, '2026-11-27', 166), (169, '2026-11-27', 167), (170, '2026-11-27', 168), (171, '2026-11-27', 169),
  (172, '2026-11-27', 170), (173, '2026-11-27', 171), (174, '2026-11-27', 172), (175, '2026-11-27', 173), (176, '2026-11-27', 174), (177, '2026-11-27', 175),
  (181, '2026-11-27', 179), (182, '2026-11-27', 180), (183, '2026-11-27', 181), (184, '2026-11-27', 182), (185, '2026-11-27', 183), (186, '2026-11-27', 184),
  (187, '2026-11-27', 185), (188, '2026-11-27', 186), (189, '2026-11-27', 187), (190, '2026-11-27', 188), (191, '2026-11-27', 189), (192, '2026-11-27', 190),
  (193, '2026-11-27', 191), (194, '2026-11-27', 192), (195, '2026-11-27', 193), (196, '2026-11-27', 194), (197, '2026-11-27', 195), (198, '2026-11-27', 196),
  (199, '2026-11-27', 197), (202, '2026-11-27', 200), (203, '2026-11-27', 201), (204, '2026-11-27', 202), (206, '2026-11-27', 204), (207, '2026-11-27', 205),
  (209, '2026-11-27', 206), (210, '2026-11-27', 207), (211, '2026-11-27', 208), (212, '2026-11-27', 209), (213, '2026-11-27', 210), (214, '2026-11-27', 211),
  (215, '2026-11-27', 212), (216, '2026-11-27', 213), (217, '2026-11-27', 214), (218, '2026-11-27', 215), (219, '2026-11-27', 216), (220, '2026-11-27', 217),
  (221, '2026-11-27', 218), (222, '2026-11-27', 219), (224, '2026-11-27', 221), (225, '2026-11-27', 222), (226, '2026-11-27', 223), (227, '2026-11-28', 224),
  (228, '2026-11-28', 225), (241, '2026-11-28', 236), (242, '2026-11-28', 237), (243, '2026-11-28', 238), (244, '2026-11-28', 239), (245, '2026-11-28', 240),
  (254, '2026-11-28', 249), (255, '2026-11-28', 250), (256, '2026-11-28', 251), (257, '2026-11-28', 252), (259, '2026-11-28', 254), (271, '2026-11-28', 266),
  (283, '2026-11-28', 278), (284, '2026-11-28', 279), (285, '2026-11-28', 280), (286, '2026-11-28', 281), (287, '2026-11-28', 282), (288, '2026-11-28', 283),
  (289, '2026-11-28', 284), (290, '2026-11-28', 285), (293, '2026-11-28', 288), (298, '2026-11-28', 293), (299, '2026-11-28', 294), (300, '2026-11-28', 295);
-- Fase 1: número novo + 10000, só nos jogos ainda com o número e a data antigos
UPDATE jogos j
  INNER JOIN mapa_db20 m ON m.numero_atual = j.numero_tabela AND DATE(j.data_hora) = m.data_antiga
   SET j.numero_tabela = m.numero_novo + 10000;

-- Fase 2: tira os 10000
UPDATE jogos SET numero_tabela = numero_tabela - 10000 WHERE numero_tabela >= 10000;

DROP TEMPORARY TABLE mapa_db20;

-- ---------------------------------------------------------------------
-- a) Sete dias para trás: AGENDADOS de 25 a 28/11/2026, hora e local iguais
-- ---------------------------------------------------------------------
UPDATE jogos
   SET data_hora = data_hora - INTERVAL 7 DAY
 WHERE status = 'AGENDADO'
   AND data_hora >= '2026-11-25 00:00:00' AND data_hora < '2026-11-29 00:00:00';

-- O período do evento (a importação avisa data fora dele)
UPDATE configuracao_evento
   SET data_inicio = '2026-11-18', data_fim = '2026-11-21'
 WHERE id = 1;

-- ---------------------------------------------------------------------
-- f) Saem as equipes do FRANCISCO AMORIM no Baleado M Sub 8 e no Futsal M
-- Sub 8, se estiverem vazias
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS equipes_fa_db20;
CREATE TEMPORARY TABLE equipes_fa_db20 (
  equipe_id INT          NOT NULL PRIMARY KEY,
  nome      VARCHAR(160) NOT NULL,
  vazia     TINYINT      NOT NULL
);
INSERT INTO equipes_fa_db20 (equipe_id, nome, vazia)
SELECT e.id, CONCAT(es.nome, ' em ', m.nome, ' ', cat.nome, ' ', c.genero),
       CASE WHEN EXISTS (SELECT 1 FROM jogos j
                          WHERE e.id IN (j.equipe_1_id, j.equipe_2_id)
                             OR j.vencedor_equipe_id = e.id
                             OR j.baleou_primeiro_equipe_id = e.id)
              OR EXISTS (SELECT 1 FROM sumula_equipes s WHERE s.equipe_id = e.id)
              OR EXISTS (SELECT 1 FROM inscricoes_atletas i WHERE i.equipe_id = e.id)
              OR EXISTS (SELECT 1 FROM colocacoes_finais cf WHERE cf.equipe_id = e.id)
            THEN 0 ELSE 1 END
  FROM equipes e
  INNER JOIN competicoes c ON c.id = e.competicao_id
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
  INNER JOIN escolas es ON es.id = e.escola_id
 WHERE m.slug IN ('baleado', 'futsal') AND cat.nome = 'Sub 8' AND c.genero = 'MASCULINO'
   AND es.nome = 'FRANCISCO AMORIM';

SELECT nome AS equipe_do_francisco_amorim, equipe_id,
       CASE WHEN vazia = 1 THEN 'removida' ELSE 'ficou: tem jogo, súmula, atleta ou colocação' END AS resultado
  FROM equipes_fa_db20;

DELETE e FROM equipes e
  INNER JOIN equipes_fa_db20 f ON f.equipe_id = e.id AND f.vazia = 1;

DROP TEMPORARY TABLE equipes_fa_db20;

-- ---------------------------------------------------------------------
-- g) Conferências. A tabela abaixo mostra o esperado e o encontrado; a trava
-- logo depois desfaz tudo se alguma divergir.
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS conferencia_db20;
CREATE TEMPORARY TABLE conferencia_db20 (
  item       VARCHAR(80) NOT NULL,
  esperado   INT         NOT NULL,
  encontrado INT         NOT NULL
);

INSERT INTO conferencia_db20 (item, esperado, encontrado)
SELECT 'jogos no total', 237, COUNT(*) FROM jogos
UNION ALL SELECT 'jogos em 18/11', 37, COUNT(*) FROM jogos WHERE DATE(data_hora) = '2026-11-18'
UNION ALL SELECT 'jogos em 19/11', 95, COUNT(*) FROM jogos WHERE DATE(data_hora) = '2026-11-19'
UNION ALL SELECT 'jogos em 20/11', 80, COUNT(*) FROM jogos WHERE DATE(data_hora) = '2026-11-20'
UNION ALL SELECT 'jogos em 21/11', 25, COUNT(*) FROM jogos WHERE DATE(data_hora) = '2026-11-21'
UNION ALL SELECT 'jogos com data fora de 18 a 21/11', 0, COUNT(*) FROM jogos
           WHERE data_hora IS NOT NULL
             AND (data_hora < '2026-11-18 00:00:00' OR data_hora >= '2026-11-22 00:00:00')
UNION ALL SELECT 'números da tabela repetidos', 0, COUNT(*) - COUNT(DISTINCT numero_tabela) FROM jogos
           WHERE numero_tabela IS NOT NULL
UNION ALL SELECT 'números da tabela distintos (o mapa vai de 1 a 295)', 237, COUNT(DISTINCT numero_tabela) FROM jogos
UNION ALL SELECT 'números da tabela fora de 1 a 295', 0, COUNT(*) FROM jogos
           WHERE numero_tabela IS NULL OR numero_tabela > 295
UNION ALL SELECT 'jogo 34 é CEBC x CEJA às 17:10 de 18/11', 1, COUNT(*) FROM jogos j
           INNER JOIN equipes e1 ON e1.id = j.equipe_1_id INNER JOIN escolas s1 ON s1.id = e1.escola_id
           INNER JOIN equipes e2 ON e2.id = j.equipe_2_id INNER JOIN escolas s2 ON s2.id = e2.escola_id
           WHERE j.numero_tabela = 34 AND j.data_hora = '2026-11-18 17:10:00'
             AND s1.nome = 'CEBC' AND s2.nome = 'CEJA'
UNION ALL SELECT 'jogo 201 é JOSE DIAS x ADELIETA RAMALHO às 08:40 de 20/11', 1, COUNT(*) FROM jogos j
           INNER JOIN equipes e1 ON e1.id = j.equipe_1_id INNER JOIN escolas s1 ON s1.id = e1.escola_id
           INNER JOIN equipes e2 ON e2.id = j.equipe_2_id INNER JOIN escolas s2 ON s2.id = e2.escola_id
           WHERE j.numero_tabela = 201 AND j.data_hora = '2026-11-20 08:40:00'
             AND s1.nome = 'JOSE DIAS' AND s2.nome = 'ADELIETA RAMALHO'
UNION ALL SELECT 'jogos do FRANCISCO AMORIM no Baleado M e Futsal M Sub 8', 0, COUNT(*) FROM jogos j
           INNER JOIN competicoes c ON c.id = j.competicao_id
           INNER JOIN modalidades m ON m.id = c.modalidade_id
           INNER JOIN categorias cat ON cat.id = c.categoria_id
           INNER JOIN equipes e ON e.id IN (j.equipe_1_id, j.equipe_2_id)
           INNER JOIN escolas s ON s.id = e.escola_id
           WHERE m.slug IN ('baleado', 'futsal') AND cat.nome = 'Sub 8' AND c.genero = 'MASCULINO'
             AND s.nome = 'FRANCISCO AMORIM'
UNION ALL SELECT 'período do evento é 18 a 21/11/2026', 1, COUNT(*) FROM configuracao_evento
           WHERE id = 1 AND data_inicio = '2026-11-18' AND data_fim = '2026-11-21';

SELECT item, esperado, encontrado,
       CASE WHEN esperado = encontrado THEN 'ok' ELSE 'DIVERGE' END AS situacao
  FROM conferencia_db20;

-- Trava: qualquer divergência para aqui, antes do COMMIT
DROP TEMPORARY TABLE IF EXISTS trava_conferencia_db20;
CREATE TEMPORARY TABLE trava_conferencia_db20 (
  item VARCHAR(80) NOT NULL,
  ok   TINYINT     NOT NULL,
  CONSTRAINT conferencia_do_db20_divergiu CHECK (ok = 1)
);
INSERT INTO trava_conferencia_db20 (item, ok)
SELECT item, CASE WHEN esperado = encontrado THEN 1 ELSE 0 END FROM conferencia_db20;

DROP TEMPORARY TABLE trava_conferencia_db20;
DROP TEMPORARY TABLE conferencia_db20;

COMMIT;

-- ---------------------------------------------------------------------
-- Depois do COMMIT, só leitura: os jogos por dia, e as competições mexidas
--   Baleado M Sub 8: ACM e MARLENE SANTANA, 1 jogo
--   Futsal M Sub 8:  grupo A com ADELIETA RAMALHO e JOSE DIAS (2 jogos entre
--                    elas), grupo B com ACM, MARLENE SANTANA e TEODULO LEITE
-- ---------------------------------------------------------------------
SELECT DATE(data_hora) AS dia, COUNT(*) AS jogos
  FROM jogos GROUP BY DATE(data_hora) ORDER BY dia;

SELECT m.nome AS modalidade, cat.nome AS categoria, c.genero, j.numero_tabela, j.numero_jogo,
       j.data_hora, s1.nome AS equipe_1, s2.nome AS equipe_2
  FROM jogos j
  INNER JOIN competicoes c ON c.id = j.competicao_id
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
  INNER JOIN equipes e1 ON e1.id = j.equipe_1_id INNER JOIN escolas s1 ON s1.id = e1.escola_id
  INNER JOIN equipes e2 ON e2.id = j.equipe_2_id INNER JOIN escolas s2 ON s2.id = e2.escola_id
 WHERE m.slug IN ('baleado', 'futsal') AND cat.nome = 'Sub 8' AND c.genero = 'MASCULINO'
 ORDER BY m.nome, j.numero_jogo;
