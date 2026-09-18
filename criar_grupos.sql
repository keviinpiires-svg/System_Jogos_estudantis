-- ---------------------------------------------------------------------
-- Cria o Grupo A e o Grupo B da fase de grupos (Futsal / Sub-17)
-- Pode rodar mais de uma vez: não duplica.
-- ---------------------------------------------------------------------
INSERT INTO grupos (nome, modalidade_id, categoria_id)
SELECT 'A', 1, 1 FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM grupos WHERE nome = 'A');

INSERT INTO grupos (nome, modalidade_id, categoria_id)
SELECT 'B', 1, 1 FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM grupos WHERE nome = 'B');

SELECT * FROM grupos;
