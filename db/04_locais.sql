-- Locais de disputa (ginásios, quadras e campos). Rode uma vez, depois do 03.
-- Endereço fica em branco por enquanto; dá para preencher depois com UPDATE.
SET NAMES utf8mb4;
INSERT INTO locais_disputa (nome) VALUES
  ('Ginásio de Esportes'),
  ('Quadra do Maria da Glória'),
  ('Quadra do CEJA'),
  ('Campo Society Arena Social');
SELECT id, nome FROM locais_disputa ORDER BY id;
