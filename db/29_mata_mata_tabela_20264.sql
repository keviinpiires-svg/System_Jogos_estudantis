-- =====================================================================
-- MIGRAÇÃO 29 — mata-mata da tabela 20264 do chefe: 75 jogos com vagas (06/11/2026)
--
-- Roda DEPOIS do db/28 (jogo_vagas e equipes nulas) e do db/27.
-- Decisão do usuário (06/11/2026): o mata-mata segue a tabela do chefe à risca
-- (número, dia, hora, local e cruzamento). Fonte: docs/importacao/
-- mata_mata_tabela_20264.csv (fora do git): 32 semifinais e 43 finais, sem equipes.
-- Cada vaga guarda de onde a equipe virá ("1º do Grupo A", "Melhor 2º colocado",
-- "Vencedor do jogo 263"); o backend preenche as equipes sozinho quando os grupos
-- fecham e os jogos terminam (ver src/services/vagasMataMata.js).
--
-- O QUE O SCRIPT FAZ (uma transação):
--   1) AJUSTA A REGRA DE DISPUTA de 9 competições para a tabela (classificados por
--      grupo e próxima fase): ver a lista em "regras_db29" logo abaixo;
--   2) Baleado Sub 8 M: a tabela não traz final para ele; passa a "melhor de dois jogos" (turno
--      IDA_E_VOLTA, 0 classificados, sem fase seguinte), como as outras competições de 2 equipes
--      (decisão do usuário, 06/11/2026);
--      Futsal Sub 17 F (269) e Handebol Aberto M (301): a tabela diz "2º do Grupo B", mas a
--      competição tem grupo único; vale o 2º colocado (mesma leitura do jogo 309);
--      Vôlei Sub 17 Misto (294) e Society Sub 13 M (307): a final é 1º do Grupo A x 1º do Grupo B
--      (duas chaves, como mostram os jogos de grupo da tabela);
--   3) cria os 75 jogos (fase, número da tabela, dia, hora e local; equipe_1/2 vazias;
--      numero_jogo = depois do maior da competição, na ordem de data e hora);
--   4) cria as 150 vagas em jogo_vagas (115 de posição no grupo, 3 de melhor 2º,
--      32 de vencedor de jogo).
--
-- NÃO MEXE nas competições de ida e volta que já existem, nem no Futsal Sub 11 M (jogo 253:
-- "1º do Grupo B x 2º do Grupo C" fica como na tabela; a trava do backend impede a mesma equipe em duas vagas).
--
-- SEGURANÇA: duas travas (CHECK em tabela temporária, erro 3819 no MySQL e 4025 no
-- MariaDB) param o script sem gravar nada:
--   db29_tabela_ou_regra_nao_bate   (antes de qualquer escrita)
--   db29_grupos_ou_origens_nao_batem (antes de criar jogos e vagas)
--   db29_conferencia_divergiu        (antes do COMMIT)
-- No DBeaver, se um comando falhar, rode ROLLBACK antes de qualquer outra coisa.
-- IDEMPOTENTE: com os 75 jogos já criados, cai em "já feito" e não grava nada.
-- Um estado parcial (entre 1 e 74 jogos) para o script.
--
-- Só dados. MySQL 8.0.16+ ou MariaDB 10.2+. Faça o dump do banco antes, na produção.
-- =====================================================================

SET NAMES utf8mb4;

START TRANSACTION;

-- ---------------------------------------------------------------------
-- Os jogos e as vagas da tabela
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS mm_db29;
CREATE TEMPORARY TABLE mm_db29 (
  numero_tabela SMALLINT UNSIGNED NOT NULL,
  ordem         TINYINT UNSIGNED  NOT NULL,   -- ordem do jogo na competição (data, hora, nº da tabela)
  data_hora     DATETIME          NOT NULL,
  local_nome    VARCHAR(150)      NOT NULL,
  modalidade    VARCHAR(80)       NOT NULL,
  categoria     VARCHAR(40)       NOT NULL,
  genero        VARCHAR(20)       NOT NULL,
  fase          VARCHAR(20)       NOT NULL,
  PRIMARY KEY (numero_tabela)
);
INSERT INTO mm_db29 (numero_tabela, ordem, data_hora, local_nome, modalidade, categoria, genero, fase) VALUES
  (146, 1, '2026-11-20 18:40:00', 'Ginásio de Esportes', 'Futsal', 'Sub 17', 'MASCULINO', 'SEMIFINAL'),
  (147, 2, '2026-11-20 19:20:00', 'Ginásio de Esportes', 'Futsal', 'Sub 17', 'MASCULINO', 'SEMIFINAL'),
  (148, 1, '2026-11-20 20:00:00', 'Ginásio de Esportes', 'Futsal', 'Aberto', 'MASCULINO', 'SEMIFINAL'),
  (149, 2, '2026-11-20 20:40:00', 'Ginásio de Esportes', 'Futsal', 'Aberto', 'MASCULINO', 'SEMIFINAL'),
  (174, 1, '2026-11-20 15:20:00', 'Quadra do Maria da Glória', 'Handebol', 'Sub 11', 'MASCULINO', 'SEMIFINAL'),
  (175, 2, '2026-11-20 16:00:00', 'Quadra do Maria da Glória', 'Handebol', 'Sub 11', 'MASCULINO', 'SEMIFINAL'),
  (176, 1, '2026-11-20 16:40:00', 'Quadra do Maria da Glória', 'Handebol', 'Sub 13', 'MASCULINO', 'SEMIFINAL'),
  (198, 1, '2026-11-20 10:00:00', 'Quadra do CETI', 'Baleado', 'Sub 13', 'MASCULINO', 'SEMIFINAL'),
  (215, 1, '2026-11-20 15:20:00', 'Quadra do CEBC', 'Baleado', 'Sub 11', 'MASCULINO', 'SEMIFINAL'),
  (221, 1, '2026-11-21 09:20:00', 'Quadra do Maria da Glória', 'Baleado', 'Sub 9', 'MASCULINO', 'SEMIFINAL'),
  (222, 1, '2026-11-21 10:00:00', 'Quadra do Maria da Glória', 'Baleado', 'Sub 15', 'FEMININO', 'SEMIFINAL'),
  (223, 2, '2026-11-21 10:40:00', 'Quadra do Maria da Glória', 'Baleado', 'Sub 15', 'FEMININO', 'SEMIFINAL'),
  (224, 1, '2026-11-21 11:20:00', 'Quadra do Maria da Glória', 'Futsal', 'Sub 9', 'MASCULINO', 'SEMIFINAL'),
  (225, 2, '2026-11-21 12:00:00', 'Quadra do Maria da Glória', 'Futsal', 'Sub 9', 'MASCULINO', 'SEMIFINAL'),
  (226, 2, '2026-11-21 12:40:00', 'Quadra do Maria da Glória', 'Baleado', 'Sub 11', 'MASCULINO', 'SEMIFINAL'),
  (227, 3, '2026-11-21 13:20:00', 'Quadra do Maria da Glória', 'Handebol', 'Sub 13', 'MASCULINO', 'FINAL'),
  (228, 1, '2026-11-21 14:00:00', 'Quadra do Maria da Glória', 'Handebol', 'Sub 13', 'FEMININO', 'FINAL'),
  (229, 3, '2026-11-21 14:40:00', 'Quadra do Maria da Glória', 'Handebol', 'Sub 11', 'MASCULINO', 'FINAL'),
  (230, 1, '2026-11-21 15:20:00', 'Quadra do Maria da Glória', 'Handebol', 'Sub 15', 'MASCULINO', 'FINAL'),
  (236, 2, '2026-11-21 11:20:00', 'Quadra da Adelieta Ramalho', 'Baleado', 'Sub 9', 'MASCULINO', 'SEMIFINAL'),
  (237, 1, '2026-11-21 12:00:00', 'Quadra da Adelieta Ramalho', 'Handebol', 'Sub 11', 'FEMININO', 'SEMIFINAL'),
  (238, 2, '2026-11-21 12:40:00', 'Quadra da Adelieta Ramalho', 'Handebol', 'Sub 11', 'FEMININO', 'SEMIFINAL'),
  (239, 2, '2026-11-21 13:20:00', 'Quadra da Adelieta Ramalho', 'Baleado', 'Sub 13', 'MASCULINO', 'SEMIFINAL'),
  (240, 3, '2026-11-21 14:00:00', 'Quadra da Adelieta Ramalho', 'Baleado', 'Sub 15', 'FEMININO', 'FINAL'),
  (241, 3, '2026-11-21 14:40:00', 'Quadra da Adelieta Ramalho', 'Baleado', 'Sub 13', 'FEMININO', 'FINAL'),
  (242, 3, '2026-11-21 15:20:00', 'Quadra da Adelieta Ramalho', 'Handebol', 'Sub 11', 'FEMININO', 'FINAL'),
  (243, 3, '2026-11-21 16:00:00', 'Quadra da Adelieta Ramalho', 'Baleado', 'Sub 11', 'MASCULINO', 'FINAL'),
  (248, 2, '2026-11-21 10:40:00', 'Quadra do CEJA', 'Handebol', 'Sub 13', 'MASCULINO', 'SEMIFINAL'),
  (250, 1, '2026-11-21 12:00:00', 'Quadra do CEJA', 'Futsal', 'Sub 13', 'MASCULINO', 'SEMIFINAL'),
  (251, 2, '2026-11-21 12:40:00', 'Quadra do CEJA', 'Futsal', 'Sub 13', 'MASCULINO', 'SEMIFINAL'),
  (252, 1, '2026-11-21 13:20:00', 'Quadra do CEJA', 'Futsal', 'Sub 11', 'MASCULINO', 'SEMIFINAL'),
  (253, 2, '2026-11-21 14:00:00', 'Quadra do CEJA', 'Futsal', 'Sub 11', 'MASCULINO', 'SEMIFINAL'),
  (254, 1, '2026-11-21 14:40:00', 'Quadra do CEJA', 'Baleado', 'Sub 17', 'MASCULINO', 'FINAL'),
  (255, 1, '2026-11-21 15:20:00', 'Quadra do CEJA', 'Baleado', 'Sub 15', 'MASCULINO', 'FINAL'),
  (256, 3, '2026-11-21 16:00:00', 'Quadra do CEJA', 'Baleado', 'Sub 13', 'MASCULINO', 'FINAL'),
  (257, 1, '2026-11-21 16:40:00', 'Quadra do CEJA', 'Baleado', 'Sub 17', 'FEMININO', 'FINAL'),
  (258, 1, '2026-11-21 08:00:00', 'Quadra do CEBC', 'Baleado', 'Sub 13', 'FEMININO', 'SEMIFINAL'),
  (259, 2, '2026-11-21 08:40:00', 'Quadra do CEBC', 'Baleado', 'Sub 13', 'FEMININO', 'SEMIFINAL'),
  (260, 1, '2026-11-21 09:20:00', 'Quadra do CEBC', 'Baleado', 'Sub 11', 'FEMININO', 'SEMIFINAL'),
  (261, 1, '2026-11-21 10:00:00', 'Quadra do CEBC', 'Handebol', 'Sub 15', 'FEMININO', 'FINAL'),
  (262, 1, '2026-11-21 10:40:00', 'Quadra do CEBC', 'Basquete', 'Sub 15', 'FEMININO', 'FINAL'),
  (263, 1, '2026-11-21 11:00:00', 'Quadra do CEBC', 'Futsal', 'Sub 15', 'MASCULINO', 'SEMIFINAL'),
  (264, 2, '2026-11-21 11:40:00', 'Quadra do CEBC', 'Futsal', 'Sub 15', 'MASCULINO', 'SEMIFINAL'),
  (265, 1, '2026-11-21 12:20:00', 'Quadra do CEBC', 'Futsal', 'Sub 15', 'FEMININO', 'SEMIFINAL'),
  (266, 2, '2026-11-21 13:00:00', 'Quadra do CEBC', 'Futsal', 'Sub 15', 'FEMININO', 'SEMIFINAL'),
  (267, 1, '2026-11-21 13:40:00', 'Quadra do CEBC', 'Futsal', 'Sub 13', 'FEMININO', 'FINAL'),
  (268, 3, '2026-11-21 14:20:00', 'Quadra do CEBC', 'Futsal', 'Sub 9', 'MASCULINO', 'FINAL'),
  (269, 1, '2026-11-21 15:00:00', 'Quadra do CEBC', 'Futsal', 'Sub 17', 'FEMININO', 'FINAL'),
  (270, 3, '2026-11-21 15:40:00', 'Quadra do CEBC', 'Futsal', 'Sub 15', 'FEMININO', 'FINAL'),
  (271, 3, '2026-11-21 16:20:00', 'Quadra do CEBC', 'Futsal', 'Sub 11', 'MASCULINO', 'FINAL'),
  (280, 1, '2026-11-21 13:20:00', 'Quadra do CETI', 'Futsal', 'Sub 8', 'MASCULINO', 'FINAL'),
  (281, 1, '2026-11-21 14:00:00', 'Quadra do CETI', 'Handebol', 'Sub 8', 'MASCULINO', 'FINAL'),
  (283, 1, '2026-11-21 15:20:00', 'Quadra do CETI', 'Handebol', 'Sub 9', 'FEMININO', 'FINAL'),
  (284, 1, '2026-11-21 16:00:00', 'Quadra do CETI', 'Baleado', 'Sub 9', 'FEMININO', 'FINAL'),
  (285, 3, '2026-11-21 16:20:00', 'Quadra do CETI', 'Baleado', 'Sub 9', 'MASCULINO', 'FINAL'),
  (290, 2, '2026-11-21 10:00:00', 'Ginásio de Esportes', 'Baleado', 'Sub 11', 'FEMININO', 'SEMIFINAL'),
  (291, 1, '2026-11-21 10:40:00', 'Ginásio de Esportes', 'Futsal', 'Sub 7', 'MASCULINO', 'FINAL'),
  (292, 1, '2026-11-21 11:20:00', 'Ginásio de Esportes', 'Vôlei', 'Aberto', 'MASCULINO', 'FINAL'),
  (293, 1, '2026-11-21 12:00:00', 'Ginásio de Esportes', 'Vôlei', 'Sub 15', 'MISTO', 'FINAL'),
  (294, 1, '2026-11-21 12:40:00', 'Ginásio de Esportes', 'Vôlei', 'Sub 17', 'MISTO', 'FINAL'),
  (295, 1, '2026-11-21 13:20:00', 'Ginásio de Esportes', 'Basquete', 'Sub 17', 'FEMININO', 'FINAL'),
  (296, 1, '2026-11-21 14:00:00', 'Ginásio de Esportes', 'Basquete', 'Sub 15', 'MASCULINO', 'FINAL'),
  (297, 1, '2026-11-21 14:40:00', 'Ginásio de Esportes', 'Basquete', 'Sub 17', 'MASCULINO', 'FINAL'),
  (298, 3, '2026-11-21 15:20:00', 'Ginásio de Esportes', 'Baleado', 'Sub 11', 'FEMININO', 'FINAL'),
  (299, 1, '2026-11-21 16:00:00', 'Ginásio de Esportes', 'Handebol', 'Sub 17', 'FEMININO', 'FINAL'),
  (300, 1, '2026-11-21 16:40:00', 'Ginásio de Esportes', 'Handebol', 'Sub 17', 'MASCULINO', 'FINAL'),
  (301, 1, '2026-11-21 17:20:00', 'Ginásio de Esportes', 'Handebol', 'Aberto', 'MASCULINO', 'FINAL'),
  (302, 3, '2026-11-21 18:00:00', 'Ginásio de Esportes', 'Futsal', 'Sub 13', 'MASCULINO', 'FINAL'),
  (303, 3, '2026-11-21 18:40:00', 'Ginásio de Esportes', 'Futsal', 'Sub 15', 'MASCULINO', 'FINAL'),
  (304, 1, '2026-11-21 19:20:00', 'Ginásio de Esportes', 'Futsal', 'Aberto', 'FEMININO', 'FINAL'),
  (305, 3, '2026-11-21 20:00:00', 'Ginásio de Esportes', 'Futsal', 'Sub 17', 'MASCULINO', 'FINAL'),
  (306, 3, '2026-11-21 20:40:00', 'Ginásio de Esportes', 'Futsal', 'Aberto', 'MASCULINO', 'FINAL'),
  (307, 1, '2026-11-21 08:40:00', 'Quadra do CETI', 'Futebol Society', 'Sub 13', 'MASCULINO', 'FINAL'),
  (308, 1, '2026-11-21 09:20:00', 'Quadra do CETI', 'Futebol Society', 'Sub 15', 'MASCULINO', 'FINAL'),
  (309, 1, '2026-11-21 10:00:00', 'Quadra do CETI', 'Futebol Society', 'Sub 17', 'MASCULINO', 'FINAL');

DROP TEMPORARY TABLE IF EXISTS mmv_db29;
CREATE TEMPORARY TABLE mmv_db29 (
  numero_tabela SMALLINT UNSIGNED NOT NULL,
  lado          TINYINT           NOT NULL,
  tipo          VARCHAR(10)       NOT NULL,
  grupo_nome    VARCHAR(10)       NULL,
  posicao       TINYINT UNSIGNED  NULL,
  origem_tabela SMALLINT UNSIGNED NULL,       -- VENCEDOR: número (na tabela) do jogo de origem
  rotulo        VARCHAR(80)       NOT NULL
);
INSERT INTO mmv_db29 (numero_tabela, lado, tipo, grupo_nome, posicao, origem_tabela, rotulo) VALUES
  (146, 1, 'GRUPO', 'B', 1, NULL, '1º do Grupo B'),
  (146, 2, 'GRUPO', 'A', 2, NULL, '2º do Grupo A'),
  (147, 1, 'GRUPO', 'A', 1, NULL, '1º do Grupo A'),
  (147, 2, 'GRUPO', 'B', 2, NULL, '2º do Grupo B'),
  (148, 1, 'GRUPO', 'A', 1, NULL, '1º do Grupo A'),
  (148, 2, 'GRUPO', 'B', 2, NULL, '2º do Grupo B'),
  (149, 1, 'GRUPO', 'B', 1, NULL, '1º do Grupo B'),
  (149, 2, 'GRUPO', 'A', 2, NULL, '2º do Grupo A'),
  (174, 1, 'GRUPO', 'A', 1, NULL, '1º do Grupo A'),
  (174, 2, 'GRUPO', 'B', 2, NULL, '2º do Grupo B'),
  (175, 1, 'GRUPO', 'B', 1, NULL, '1º do Grupo B'),
  (175, 2, 'GRUPO', 'A', 2, NULL, '2º do Grupo A'),
  (176, 1, 'GRUPO', 'A', 1, NULL, '1º do Grupo A'),
  (176, 2, 'GRUPO', 'B', 2, NULL, '2º do Grupo B'),
  (198, 1, 'GRUPO', 'A', 1, NULL, '1º do Grupo A'),
  (198, 2, 'MELHOR', NULL, 2, NULL, 'Melhor 2º colocado'),
  (215, 1, 'GRUPO', 'A', 1, NULL, '1º do Grupo A'),
  (215, 2, 'GRUPO', 'B', 2, NULL, '2º do Grupo B'),
  (221, 1, 'GRUPO', 'A', 1, NULL, '1º do Grupo A'),
  (221, 2, 'GRUPO', 'B', 2, NULL, '2º do Grupo B'),
  (222, 1, 'GRUPO', 'A', 1, NULL, '1º do Grupo A'),
  (222, 2, 'GRUPO', 'B', 2, NULL, '2º do Grupo B'),
  (223, 1, 'GRUPO', 'B', 1, NULL, '1º do Grupo B'),
  (223, 2, 'GRUPO', 'A', 2, NULL, '2º do Grupo A'),
  (224, 1, 'GRUPO', 'A', 1, NULL, '1º do Grupo A'),
  (224, 2, 'GRUPO', 'B', 2, NULL, '2º do Grupo B'),
  (225, 1, 'GRUPO', 'B', 1, NULL, '1º do Grupo B'),
  (225, 2, 'GRUPO', 'A', 2, NULL, '2º do Grupo A'),
  (226, 1, 'GRUPO', 'B', 1, NULL, '1º do Grupo B'),
  (226, 2, 'GRUPO', 'A', 2, NULL, '2º do Grupo A'),
  (227, 1, 'VENCEDOR', NULL, NULL, 176, 'Vencedor do jogo 176'),
  (227, 2, 'VENCEDOR', NULL, NULL, 248, 'Vencedor do jogo 248'),
  (228, 1, 'GRUPO', 'A', 1, NULL, '1º colocado'),
  (228, 2, 'GRUPO', 'A', 2, NULL, '2º colocado'),
  (229, 1, 'VENCEDOR', NULL, NULL, 174, 'Vencedor do jogo 174'),
  (229, 2, 'VENCEDOR', NULL, NULL, 175, 'Vencedor do jogo 175'),
  (230, 1, 'GRUPO', 'A', 1, NULL, '1º colocado'),
  (230, 2, 'GRUPO', 'A', 2, NULL, '2º colocado'),
  (236, 1, 'GRUPO', 'B', 1, NULL, '1º do Grupo B'),
  (236, 2, 'GRUPO', 'A', 2, NULL, '2º do Grupo A'),
  (237, 1, 'GRUPO', 'A', 1, NULL, '1º do Grupo A'),
  (237, 2, 'GRUPO', 'B', 2, NULL, '2º do Grupo B'),
  (238, 1, 'GRUPO', 'B', 1, NULL, '1º do Grupo B'),
  (238, 2, 'GRUPO', 'A', 2, NULL, '2º do Grupo A'),
  (239, 1, 'GRUPO', 'B', 1, NULL, '1º do Grupo B'),
  (239, 2, 'GRUPO', 'C', 1, NULL, '1º do Grupo C'),
  (240, 1, 'VENCEDOR', NULL, NULL, 222, 'Vencedor do jogo 222'),
  (240, 2, 'VENCEDOR', NULL, NULL, 223, 'Vencedor do jogo 223'),
  (241, 1, 'VENCEDOR', NULL, NULL, 258, 'Vencedor do jogo 258'),
  (241, 2, 'VENCEDOR', NULL, NULL, 259, 'Vencedor do jogo 259'),
  (242, 1, 'VENCEDOR', NULL, NULL, 237, 'Vencedor do jogo 237'),
  (242, 2, 'VENCEDOR', NULL, NULL, 238, 'Vencedor do jogo 238'),
  (243, 1, 'VENCEDOR', NULL, NULL, 215, 'Vencedor do jogo 215'),
  (243, 2, 'VENCEDOR', NULL, NULL, 226, 'Vencedor do jogo 226'),
  (248, 1, 'GRUPO', 'B', 1, NULL, '1º do Grupo B'),
  (248, 2, 'GRUPO', 'A', 2, NULL, '2º do Grupo A'),
  (250, 1, 'GRUPO', 'A', 1, NULL, '1º do Grupo A'),
  (250, 2, 'GRUPO', 'B', 2, NULL, '2º do Grupo B'),
  (251, 1, 'GRUPO', 'B', 1, NULL, '1º do Grupo B'),
  (251, 2, 'GRUPO', 'A', 2, NULL, '2º do Grupo A'),
  (252, 1, 'GRUPO', 'A', 1, NULL, '1º do Grupo A'),
  (252, 2, 'MELHOR', NULL, 2, NULL, 'Melhor 2º colocado'),
  (253, 1, 'GRUPO', 'B', 1, NULL, '1º do Grupo B'),
  (253, 2, 'GRUPO', 'C', 2, NULL, '2º do Grupo C'),
  (254, 1, 'GRUPO', 'A', 1, NULL, '1º colocado'),
  (254, 2, 'GRUPO', 'A', 2, NULL, '2º colocado'),
  (255, 1, 'GRUPO', 'A', 1, NULL, '1º do Grupo A'),
  (255, 2, 'GRUPO', 'B', 2, NULL, '2º do Grupo B'),
  (256, 1, 'VENCEDOR', NULL, NULL, 198, 'Vencedor do jogo 198'),
  (256, 2, 'VENCEDOR', NULL, NULL, 239, 'Vencedor do jogo 239'),
  (257, 1, 'GRUPO', 'A', 1, NULL, '1º colocado'),
  (257, 2, 'GRUPO', 'A', 2, NULL, '2º colocado'),
  (258, 1, 'GRUPO', 'A', 1, NULL, '1º do Grupo A'),
  (258, 2, 'MELHOR', NULL, 2, NULL, 'Melhor 2º colocado'),
  (259, 1, 'GRUPO', 'B', 1, NULL, '1º do Grupo B'),
  (259, 2, 'GRUPO', 'C', 1, NULL, '1º do Grupo C'),
  (260, 1, 'GRUPO', 'A', 1, NULL, '1º do Grupo A'),
  (260, 2, 'GRUPO', 'B', 2, NULL, '2º do Grupo B'),
  (261, 1, 'GRUPO', 'A', 1, NULL, '1º colocado'),
  (261, 2, 'GRUPO', 'A', 2, NULL, '2º colocado'),
  (262, 1, 'GRUPO', 'A', 1, NULL, '1º colocado'),
  (262, 2, 'GRUPO', 'A', 2, NULL, '2º colocado'),
  (263, 1, 'GRUPO', 'A', 1, NULL, '1º do Grupo A'),
  (263, 2, 'GRUPO', 'B', 2, NULL, '2º do Grupo B'),
  (264, 1, 'GRUPO', 'B', 1, NULL, '1º do Grupo B'),
  (264, 2, 'GRUPO', 'A', 2, NULL, '2º do Grupo A'),
  (265, 1, 'GRUPO', 'A', 1, NULL, '1º do Grupo A'),
  (265, 2, 'GRUPO', 'B', 2, NULL, '2º do Grupo B'),
  (266, 1, 'GRUPO', 'B', 1, NULL, '1º do Grupo B'),
  (266, 2, 'GRUPO', 'A', 2, NULL, '2º do Grupo A'),
  (267, 1, 'GRUPO', 'A', 1, NULL, '1º colocado'),
  (267, 2, 'GRUPO', 'A', 2, NULL, '2º colocado'),
  (268, 1, 'VENCEDOR', NULL, NULL, 224, 'Vencedor do jogo 224'),
  (268, 2, 'VENCEDOR', NULL, NULL, 225, 'Vencedor do jogo 225'),
  (269, 1, 'GRUPO', 'A', 1, NULL, '1º colocado'),
  (269, 2, 'GRUPO', 'A', 2, NULL, '2º colocado'),
  (270, 1, 'VENCEDOR', NULL, NULL, 265, 'Vencedor do jogo 265'),
  (270, 2, 'VENCEDOR', NULL, NULL, 266, 'Vencedor do jogo 266'),
  (271, 1, 'VENCEDOR', NULL, NULL, 252, 'Vencedor do jogo 252'),
  (271, 2, 'VENCEDOR', NULL, NULL, 253, 'Vencedor do jogo 253'),
  (280, 1, 'GRUPO', 'A', 1, NULL, '1º do Grupo A'),
  (280, 2, 'GRUPO', 'B', 1, NULL, '1º do Grupo B'),
  (281, 1, 'GRUPO', 'A', 1, NULL, '1º colocado'),
  (281, 2, 'GRUPO', 'A', 2, NULL, '2º colocado'),
  (283, 1, 'GRUPO', 'A', 1, NULL, '1º colocado'),
  (283, 2, 'GRUPO', 'A', 2, NULL, '2º colocado'),
  (284, 1, 'GRUPO', 'A', 1, NULL, '1º do Grupo A'),
  (284, 2, 'GRUPO', 'B', 1, NULL, '1º do Grupo B'),
  (285, 1, 'VENCEDOR', NULL, NULL, 221, 'Vencedor do jogo 221'),
  (285, 2, 'VENCEDOR', NULL, NULL, 236, 'Vencedor do jogo 236'),
  (290, 1, 'GRUPO', 'B', 1, NULL, '1º do Grupo B'),
  (290, 2, 'GRUPO', 'A', 2, NULL, '2º do Grupo A'),
  (291, 1, 'GRUPO', 'A', 1, NULL, '1º colocado'),
  (291, 2, 'GRUPO', 'A', 2, NULL, '2º colocado'),
  (292, 1, 'GRUPO', 'A', 1, NULL, '1º colocado'),
  (292, 2, 'GRUPO', 'A', 2, NULL, '2º colocado'),
  (293, 1, 'GRUPO', 'A', 1, NULL, '1º colocado'),
  (293, 2, 'GRUPO', 'A', 2, NULL, '2º colocado'),
  (294, 1, 'GRUPO', 'A', 1, NULL, '1º do Grupo A'),
  (294, 2, 'GRUPO', 'B', 1, NULL, '1º do Grupo B'),
  (295, 1, 'GRUPO', 'A', 1, NULL, '1º colocado'),
  (295, 2, 'GRUPO', 'A', 2, NULL, '2º colocado'),
  (296, 1, 'GRUPO', 'A', 1, NULL, '1º colocado'),
  (296, 2, 'GRUPO', 'A', 2, NULL, '2º colocado'),
  (297, 1, 'GRUPO', 'A', 1, NULL, '1º colocado'),
  (297, 2, 'GRUPO', 'A', 2, NULL, '2º colocado'),
  (298, 1, 'VENCEDOR', NULL, NULL, 260, 'Vencedor do jogo 260'),
  (298, 2, 'VENCEDOR', NULL, NULL, 290, 'Vencedor do jogo 290'),
  (299, 1, 'GRUPO', 'A', 1, NULL, '1º colocado'),
  (299, 2, 'GRUPO', 'A', 2, NULL, '2º colocado'),
  (300, 1, 'GRUPO', 'A', 1, NULL, '1º do Grupo A'),
  (300, 2, 'GRUPO', 'B', 2, NULL, '2º do Grupo B'),
  (301, 1, 'GRUPO', 'A', 1, NULL, '1º colocado'),
  (301, 2, 'GRUPO', 'A', 2, NULL, '2º colocado'),
  (302, 1, 'VENCEDOR', NULL, NULL, 250, 'Vencedor do jogo 250'),
  (302, 2, 'VENCEDOR', NULL, NULL, 251, 'Vencedor do jogo 251'),
  (303, 1, 'VENCEDOR', NULL, NULL, 263, 'Vencedor do jogo 263'),
  (303, 2, 'VENCEDOR', NULL, NULL, 264, 'Vencedor do jogo 264'),
  (304, 1, 'GRUPO', 'A', 1, NULL, '1º colocado'),
  (304, 2, 'GRUPO', 'A', 2, NULL, '2º colocado'),
  (305, 1, 'VENCEDOR', NULL, NULL, 146, 'Vencedor do jogo 146'),
  (305, 2, 'VENCEDOR', NULL, NULL, 147, 'Vencedor do jogo 147'),
  (306, 1, 'VENCEDOR', NULL, NULL, 148, 'Vencedor do jogo 148'),
  (306, 2, 'VENCEDOR', NULL, NULL, 149, 'Vencedor do jogo 149'),
  (307, 1, 'GRUPO', 'A', 1, NULL, '1º do Grupo A'),
  (307, 2, 'GRUPO', 'B', 1, NULL, '1º do Grupo B'),
  (308, 1, 'GRUPO', 'A', 1, NULL, '1º do Grupo A'),
  (308, 2, 'GRUPO', 'B', 1, NULL, '1º do Grupo B'),
  (309, 1, 'GRUPO', 'A', 1, NULL, '1º colocado'),
  (309, 2, 'GRUPO', 'A', 2, NULL, '2º colocado');

-- Regra de disputa que a tabela exige (competições onde o banco diz outra coisa)
DROP TEMPORARY TABLE IF EXISTS regras_db29;
CREATE TEMPORARY TABLE regras_db29 (
  modalidade VARCHAR(80) NOT NULL, categoria VARCHAR(40) NOT NULL, genero VARCHAR(20) NOT NULL,
  c_antes TINYINT NOT NULL, pf_antes VARCHAR(12) NOT NULL,
  c_depois TINYINT NOT NULL, pf_depois VARCHAR(12) NOT NULL
);
INSERT INTO regras_db29 VALUES
  ('Baleado', 'Sub 9', 'MASCULINO', 1, 'FINAL', 2, 'SEMIFINAL'),
  ('Futsal', 'Sub 15', 'FEMININO', 1, 'FINAL', 2, 'SEMIFINAL'),
  ('Futsal', 'Aberto', 'MASCULINO', 1, 'FINAL', 2, 'SEMIFINAL'),
  ('Handebol', 'Sub 11', 'MASCULINO', 1, 'FINAL', 2, 'SEMIFINAL'),
  ('Handebol', 'Sub 11', 'FEMININO', 1, 'FINAL', 2, 'SEMIFINAL'),
  ('Handebol', 'Sub 13', 'MASCULINO', 1, 'FINAL', 2, 'SEMIFINAL'),
  ('Vôlei', 'Sub 17', 'MISTO', 2, 'SEMIFINAL', 1, 'FINAL'),
  ('Futsal', 'Sub 8', 'MASCULINO', 2, 'SEMIFINAL', 1, 'FINAL'),
  ('Futebol Society', 'Sub 15', 'MASCULINO', 2, 'SEMIFINAL', 1, 'FINAL');

-- ---------------------------------------------------------------------
-- Estado: nada feito, tudo feito, ou parcial (para)
-- ---------------------------------------------------------------------
SET @ja := (SELECT COUNT(*) FROM jogos j WHERE j.fase <> 'GRUPOS' AND j.numero_tabela IN (SELECT numero_tabela FROM mm_db29));
SET @estado := CASE WHEN @ja = 0 THEN 'aplica' WHEN @ja = 75 THEN 'já feito' ELSE 'parcial' END;
SET @aplica := (@estado = 'aplica');

-- Baleado Sub 8 M: de FINAL para "melhor de dois jogos"
SET @bal := (SELECT c.id FROM competicoes c
               INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.nome = 'Baleado'
               INNER JOIN categorias k ON k.id = c.categoria_id AND k.nome = 'Sub 8'
              WHERE c.genero = 'MASCULINO');
SET @bal_estado := CASE
  WHEN (SELECT COUNT(*) FROM competicoes WHERE id = @bal AND qtd_grupos = 1 AND classificados_por_grupo = 2
              AND melhores_segundos = 0 AND proxima_fase = 'FINAL' AND turno = 'UNICO') = 1 THEN 'antes'
  WHEN (SELECT COUNT(*) FROM competicoes WHERE id = @bal AND qtd_grupos = 1 AND classificados_por_grupo = 0
              AND melhores_segundos = 0 AND proxima_fase = 'NENHUMA' AND turno = 'IDA_E_VOLTA') = 1 THEN 'depois'
  ELSE 'não bate' END;

-- Conferências ANTES de escrever: esperado x encontrado
DROP TEMPORARY TABLE IF EXISTS checagem1_db29;
CREATE TEMPORARY TABLE checagem1_db29 (item VARCHAR(110) NOT NULL, esperado INT NOT NULL, encontrado INT NOT NULL);
INSERT INTO checagem1_db29 (item, esperado, encontrado)
SELECT 'estado do script (aplica ou já feito)', 1, CASE WHEN @estado = 'parcial' THEN 0 ELSE 1 END;
INSERT INTO checagem1_db29 (item, esperado, encontrado)
SELECT 'linhas da tabela com competição no banco', 75, COUNT(*) FROM mm_db29 t
           INNER JOIN modalidades m ON m.nome = t.modalidade
           INNER JOIN categorias k ON k.nome = t.categoria
           INNER JOIN competicoes c ON c.modalidade_id = m.id AND c.categoria_id = k.id AND c.genero = t.genero;
INSERT INTO checagem1_db29 (item, esperado, encontrado)
SELECT 'linhas da tabela com local no banco', 75, COUNT(*) FROM mm_db29 t
           INNER JOIN locais_disputa l ON l.nome = t.local_nome;
INSERT INTO checagem1_db29 (item, esperado, encontrado)
SELECT 'números da tabela JÁ usados por jogo de grupo (esperado 0)', 0, COUNT(*) FROM jogos j
           WHERE j.fase = 'GRUPOS' AND j.numero_tabela IN (SELECT numero_tabela FROM mm_db29);
INSERT INTO checagem1_db29 (item, esperado, encontrado)
SELECT 'competições da regra (ajuste) achadas', 9, COUNT(*) FROM regras_db29 r
           INNER JOIN modalidades m ON m.nome = r.modalidade
           INNER JOIN categorias k ON k.nome = r.categoria
           INNER JOIN competicoes c ON c.modalidade_id = m.id AND c.categoria_id = k.id AND c.genero = r.genero;
INSERT INTO checagem1_db29 (item, esperado, encontrado)
SELECT 'competições da regra no estado de antes OU de depois', 9, COUNT(*) FROM regras_db29 r
           INNER JOIN modalidades m ON m.nome = r.modalidade
           INNER JOIN categorias k ON k.nome = r.categoria
           INNER JOIN competicoes c ON c.modalidade_id = m.id AND c.categoria_id = k.id AND c.genero = r.genero
           WHERE c.qtd_grupos = 2 AND c.melhores_segundos = 0
             AND ((c.classificados_por_grupo = r.c_antes AND c.proxima_fase = r.pf_antes)
               OR (c.classificados_por_grupo = r.c_depois AND c.proxima_fase = r.pf_depois));
INSERT INTO checagem1_db29 (item, esperado, encontrado)
SELECT 'Baleado Sub 8 M: FINAL como antes OU melhor de dois jogos como depois', 1, CASE WHEN @bal_estado = 'não bate' THEN 0 ELSE 1 END;
INSERT INTO checagem1_db29 (item, esperado, encontrado)
SELECT 'vagas de vencedor com o jogo de origem na tabela', 32, COUNT(*) FROM mmv_db29 v
           WHERE v.tipo = 'VENCEDOR' AND v.origem_tabela IN (SELECT numero_tabela FROM mm_db29);

SELECT @estado AS estado, @bal_estado AS baleado_sub8_m;
SELECT item, esperado, encontrado, CASE WHEN esperado = encontrado THEN 'ok' ELSE 'DIVERGE' END AS situacao FROM checagem1_db29;

DROP TEMPORARY TABLE IF EXISTS trava1_db29;
CREATE TEMPORARY TABLE trava1_db29 (
  item VARCHAR(110) NOT NULL, ok TINYINT NOT NULL,
  CONSTRAINT db29_tabela_ou_regra_nao_bate CHECK (ok = 1)
);
INSERT INTO trava1_db29 (item, ok) SELECT item, CASE WHEN esperado = encontrado THEN 1 ELSE 0 END FROM checagem1_db29;
DROP TEMPORARY TABLE trava1_db29;

-- ---------------------------------------------------------------------
-- 1) Regra de disputa das competições que a tabela contradiz (só no "aplica")
-- ---------------------------------------------------------------------
UPDATE competicoes c
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias k ON k.id = c.categoria_id
  INNER JOIN regras_db29 r ON r.modalidade = m.nome AND r.categoria = k.nome AND r.genero = c.genero
   SET c.classificados_por_grupo = r.c_depois, c.proxima_fase = r.pf_depois
 WHERE @aplica AND c.classificados_por_grupo = r.c_antes AND c.proxima_fase = r.pf_antes;

-- ---------------------------------------------------------------------
-- 2) Baleado Sub 8 M vira "melhor de dois jogos" (turno IDA_E_VOLTA, 0 classificados, sem fase seguinte)
-- ---------------------------------------------------------------------
UPDATE competicoes
   SET classificados_por_grupo = 0, proxima_fase = 'NENHUMA', turno = 'IDA_E_VOLTA'
 WHERE id = @bal AND @aplica AND @bal_estado = 'antes';

-- ---------------------------------------------------------------------
-- Trava 2: os grupos das vagas existem (agora, com as regras ajustadas)
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS checagem2_db29;
CREATE TEMPORARY TABLE checagem2_db29 (item VARCHAR(110) NOT NULL, esperado INT NOT NULL, encontrado INT NOT NULL);
INSERT INTO checagem2_db29 (item, esperado, encontrado)
SELECT 'vagas de grupo com o grupo existente na competição', 115, COUNT(*) FROM mmv_db29 v
  INNER JOIN mm_db29 t ON t.numero_tabela = v.numero_tabela
  INNER JOIN modalidades m ON m.nome = t.modalidade
  INNER JOIN categorias k ON k.nome = t.categoria
  INNER JOIN competicoes c ON c.modalidade_id = m.id AND c.categoria_id = k.id AND c.genero = t.genero
  INNER JOIN grupos g ON g.competicao_id = c.id AND g.nome = v.grupo_nome
 WHERE v.tipo = 'GRUPO';
SELECT item, esperado, encontrado, CASE WHEN esperado = encontrado THEN 'ok' ELSE 'DIVERGE' END AS situacao FROM checagem2_db29;

DROP TEMPORARY TABLE IF EXISTS trava2_db29;
CREATE TEMPORARY TABLE trava2_db29 (
  item VARCHAR(110) NOT NULL, ok TINYINT NOT NULL,
  CONSTRAINT db29_grupos_ou_origens_nao_batem CHECK (ok = 1)
);
INSERT INTO trava2_db29 (item, ok) SELECT item, CASE WHEN esperado = encontrado THEN 1 ELSE 0 END FROM checagem2_db29;
DROP TEMPORARY TABLE trava2_db29;

-- ---------------------------------------------------------------------
-- 3) Os 75 jogos (só no "aplica"); equipes vazias
-- ---------------------------------------------------------------------
INSERT INTO jogos (competicao_id, numero_jogo, numero_tabela, fase, rodada, grupo_id, local_id, data_hora,
                   equipe_1_id, equipe_2_id, status)
SELECT c.id,
       (SELECT COALESCE(MAX(x.numero_jogo), 0) FROM jogos x WHERE x.competicao_id = c.id) + t.ordem,
       t.numero_tabela, t.fase, NULL, NULL, l.id, t.data_hora, NULL, NULL, 'AGENDADO'
  FROM mm_db29 t
  INNER JOIN modalidades m ON m.nome = t.modalidade
  INNER JOIN categorias k ON k.nome = t.categoria
  INNER JOIN competicoes c ON c.modalidade_id = m.id AND c.categoria_id = k.id AND c.genero = t.genero
  INNER JOIN locais_disputa l ON l.nome = t.local_nome
 WHERE @aplica
 ORDER BY c.id, t.ordem;

-- ---------------------------------------------------------------------
-- 4) As vagas: GRUPO e MELHOR (posição), depois VENCEDOR (precisa dos jogos já criados)
-- ---------------------------------------------------------------------
INSERT INTO jogo_vagas (jogo_id, lado, tipo, grupo_id, posicao, jogo_origem_id, rotulo)
SELECT j.id, v.lado, v.tipo, g.id, v.posicao, NULL, v.rotulo
  FROM mmv_db29 v
  INNER JOIN jogos j ON j.numero_tabela = v.numero_tabela
  LEFT JOIN grupos g ON g.competicao_id = j.competicao_id AND g.nome = v.grupo_nome
 WHERE @aplica AND v.tipo IN ('GRUPO', 'MELHOR');

INSERT INTO jogo_vagas (jogo_id, lado, tipo, grupo_id, posicao, jogo_origem_id, rotulo)
SELECT j.id, v.lado, v.tipo, NULL, NULL, o.id, v.rotulo
  FROM mmv_db29 v
  INNER JOIN jogos j ON j.numero_tabela = v.numero_tabela
  INNER JOIN jogos o ON o.numero_tabela = v.origem_tabela AND o.competicao_id = j.competicao_id
 WHERE @aplica AND v.tipo = 'VENCEDOR';

-- ---------------------------------------------------------------------
-- Conferências finais (e a trava que desfaz tudo se algo divergir)
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS conferencia_db29;
CREATE TEMPORARY TABLE conferencia_db29 (item VARCHAR(110) NOT NULL, esperado INT NOT NULL, encontrado INT NOT NULL);
INSERT INTO conferencia_db29 (item, esperado, encontrado)
SELECT 'jogos de mata-mata da tabela', 75, COUNT(*) FROM jogos j
  WHERE j.fase <> 'GRUPOS' AND j.numero_tabela IN (SELECT numero_tabela FROM mm_db29);
INSERT INTO conferencia_db29 (item, esperado, encontrado)
SELECT '  semifinais', 32, COUNT(*) FROM jogos j
  WHERE j.fase = 'SEMIFINAL' AND j.numero_tabela IN (SELECT numero_tabela FROM mm_db29);
INSERT INTO conferencia_db29 (item, esperado, encontrado)
SELECT '  finais', 43, COUNT(*) FROM jogos j
  WHERE j.fase = 'FINAL' AND j.numero_tabela IN (SELECT numero_tabela FROM mm_db29);
INSERT INTO conferencia_db29 (item, esperado, encontrado)
SELECT 'vagas cadastradas nesses jogos', 150, COUNT(*) FROM jogo_vagas v
  INNER JOIN jogos j ON j.id = v.jogo_id WHERE j.numero_tabela IN (SELECT numero_tabela FROM mm_db29);
INSERT INTO conferencia_db29 (item, esperado, encontrado)
SELECT '  vagas de posição no grupo', 115, COUNT(*) FROM jogo_vagas v
  INNER JOIN jogos j ON j.id = v.jogo_id WHERE v.tipo = 'GRUPO' AND j.numero_tabela IN (SELECT numero_tabela FROM mm_db29);
INSERT INTO conferencia_db29 (item, esperado, encontrado)
SELECT '  vagas de melhor 2º', 3, COUNT(*) FROM jogo_vagas v
  INNER JOIN jogos j ON j.id = v.jogo_id WHERE v.tipo = 'MELHOR' AND j.numero_tabela IN (SELECT numero_tabela FROM mm_db29);
INSERT INTO conferencia_db29 (item, esperado, encontrado)
SELECT '  vagas de vencedor de jogo', 32, COUNT(*) FROM jogo_vagas v
  INNER JOIN jogos j ON j.id = v.jogo_id WHERE v.tipo = 'VENCEDOR' AND j.numero_tabela IN (SELECT numero_tabela FROM mm_db29);
INSERT INTO conferencia_db29 (item, esperado, encontrado)
SELECT 'Baleado Sub 8 M em melhor de dois jogos (IDA_E_VOLTA, 0 classificados, NENHUMA)', 1, COUNT(*) FROM competicoes
  WHERE id = @bal AND classificados_por_grupo = 0 AND proxima_fase = 'NENHUMA' AND turno = 'IDA_E_VOLTA';
INSERT INTO conferencia_db29 (item, esperado, encontrado)
SELECT 'jogos de mata-mata já com equipe (esperado 0)', 0, COUNT(*) FROM jogos j
  WHERE j.fase <> 'GRUPOS' AND (j.equipe_1_id IS NOT NULL OR j.equipe_2_id IS NOT NULL)
    AND j.numero_tabela IN (SELECT numero_tabela FROM mm_db29);
INSERT INTO conferencia_db29 (item, esperado, encontrado)
SELECT 'jogos de mata-mata sem dia, hora ou local (esperado 0)', 0, COUNT(*) FROM jogos j
  WHERE j.fase <> 'GRUPOS' AND (j.data_hora IS NULL OR j.local_id IS NULL)
    AND j.numero_tabela IN (SELECT numero_tabela FROM mm_db29);
INSERT INTO conferencia_db29 (item, esperado, encontrado)
SELECT 'competições com semifinal na tabela e regra SEMIFINAL', 16, COUNT(*) FROM competicoes c
  WHERE c.proxima_fase = 'SEMIFINAL' AND EXISTS (SELECT 1 FROM jogos j WHERE j.competicao_id = c.id AND j.fase = 'SEMIFINAL'
        AND j.numero_tabela IN (SELECT numero_tabela FROM mm_db29));
INSERT INTO conferencia_db29 (item, esperado, encontrado)
SELECT 'competições só com final na tabela e regra FINAL', 27, COUNT(*) FROM competicoes c
  WHERE c.proxima_fase = 'FINAL' AND qtd_grupos IN (1, 2)
    AND EXISTS (SELECT 1 FROM jogos j WHERE j.competicao_id = c.id AND j.fase = 'FINAL' AND j.numero_tabela IN (SELECT numero_tabela FROM mm_db29))
    AND NOT EXISTS (SELECT 1 FROM jogos j WHERE j.competicao_id = c.id AND j.fase = 'SEMIFINAL');

SELECT item, esperado, encontrado, CASE WHEN esperado = encontrado THEN 'ok' ELSE 'DIVERGE' END AS situacao FROM conferencia_db29;

DROP TEMPORARY TABLE IF EXISTS trava3_db29;
CREATE TEMPORARY TABLE trava3_db29 (
  item VARCHAR(110) NOT NULL, ok TINYINT NOT NULL,
  CONSTRAINT db29_conferencia_divergiu CHECK (ok = 1)
);
INSERT INTO trava3_db29 (item, ok) SELECT item, CASE WHEN esperado = encontrado THEN 1 ELSE 0 END FROM conferencia_db29;
DROP TEMPORARY TABLE trava3_db29;

COMMIT;
