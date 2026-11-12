-- =====================================================================
-- Importação da tabela de grupos (fonte: docs/referencias/tabela_de_grupos.md)
-- GERADO por script a partir do documento — confira docs/CONFERENCIA_COMPETICOES.md
-- antes de rodar. Rode UMA vez, depois de 01_schema.sql e 02_carga_base.sql,
-- no banco de desenvolvimento. Para repetir, refaça 00 -> 01 -> 02 -> 03.
--
-- Cria: 18 escolas (+ grafias alternativas), 50 competições com a sua regra de
-- classificação, os grupos e as equipes (escola dentro de cada competição).
-- NÃO cria atletas, jogos nem usuários.
-- =====================================================================
SET NAMES utf8mb4;

-- 1) Escolas (nome oficial, sem etapa de ensino por enquanto)
INSERT INTO escolas (nome) VALUES
  ('ACM'),
  ('ADELIETA RAMALHO'),
  ('CEBC'),
  ('CEBN'),
  ('CEJA'),
  ('CETI'),
  ('COVENIADA'),
  ('EMILIANO ZAPATA'),
  ('FRANCISCO AMORIM'),
  ('JOSE DIAS'),
  ('JOSENILDO LEITE'),
  ('LUCIA ROCHA'),
  ('MANOEL RAMOS'),
  ('MARIA DA GLORIA'),
  ('MARLENE SANTANA'),
  ('PORTAL DO SABER'),
  ('TEODULO LEITE'),
  ('VITORIA LIMA');

-- 2) Grafias alternativas que aparecem na tabela de grupos
INSERT INTO escola_apelidos (escola_id, apelido)
SELECT e.id, v.apelido FROM (
  SELECT 'ADELIATA' AS apelido, 'ADELIETA RAMALHO' AS escola
  UNION ALL
  SELECT 'ADELIETA' AS apelido, 'ADELIETA RAMALHO' AS escola
  UNION ALL
  SELECT 'EMILIANO' AS apelido, 'EMILIANO ZAPATA' AS escola
  UNION ALL
  SELECT 'F. AMORIM' AS apelido, 'FRANCISCO AMORIM' AS escola
  UNION ALL
  SELECT 'J. DIAS' AS apelido, 'JOSE DIAS' AS escola
  UNION ALL
  SELECT 'JOSENILDO' AS apelido, 'JOSENILDO LEITE' AS escola
  UNION ALL
  SELECT 'M. SANTANA' AS apelido, 'MARLENE SANTANA' AS escola
  UNION ALL
  SELECT 'MANOEL' AS apelido, 'MANOEL RAMOS' AS escola
  UNION ALL
  SELECT 'MARIA' AS apelido, 'MARIA DA GLORIA' AS escola
  UNION ALL
  SELECT 'MARIA GLORIA' AS apelido, 'MARIA DA GLORIA' AS escola
  UNION ALL
  SELECT 'MARLENA' AS apelido, 'MARLENE SANTANA' AS escola
  UNION ALL
  SELECT 'MARLENA SANTANA' AS apelido, 'MARLENE SANTANA' AS escola
  UNION ALL
  SELECT 'MERIA DA GLORIA' AS apelido, 'MARIA DA GLORIA' AS escola
  UNION ALL
  SELECT 'PORTAL' AS apelido, 'PORTAL DO SABER' AS escola
  UNION ALL
  SELECT 'TODULO LEITE' AS apelido, 'TEODULO LEITE' AS escola
  UNION ALL
  SELECT 'V. LIMA' AS apelido, 'VITORIA LIMA' AS escola
) v JOIN escolas e ON e.nome = v.escola;

-- 3) Competições (modalidade x categoria x gênero) com a regra de disputa.
--    classificados: por grupo; melhores2: quantos "melhores segundos" entram;
--    fase: primeira fase eliminatória (SEMIFINAL/FINAL/NENHUMA);
--    turno: IDA_E_VOLTA = "melhor de dois jogos".
CREATE TEMPORARY TABLE _imp_competicoes (
  slug VARCHAR(50), categoria VARCHAR(50), genero VARCHAR(10),
  qtd_grupos TINYINT, classificados TINYINT, melhores2 TINYINT,
  fase VARCHAR(10), turno VARCHAR(12), min_tempo TINYINT NULL, min_final TINYINT NULL
);
INSERT INTO _imp_competicoes VALUES
  ('futsal','Sub 7','MASCULINO',1,2,0,'FINAL','UNICO',12,NULL),
  ('futsal','Sub 8','MASCULINO',2,2,0,'SEMIFINAL','UNICO',12,NULL),
  ('futsal','Sub 9','MASCULINO',2,2,0,'SEMIFINAL','UNICO',12,NULL),
  ('futsal','Sub 11','MASCULINO',3,1,1,'SEMIFINAL','UNICO',12,NULL),
  ('futsal','Sub 13','MASCULINO',2,2,0,'SEMIFINAL','UNICO',12,NULL),
  ('futsal','Sub 15','MASCULINO',2,2,0,'SEMIFINAL','UNICO',15,20),
  ('futsal','Sub 17','MASCULINO',2,2,0,'SEMIFINAL','UNICO',15,20),
  ('futsal','Aberto','MASCULINO',2,1,0,'FINAL','UNICO',15,20),
  ('futsal','Sub 8','FEMININO',1,0,0,'NENHUMA','IDA_E_VOLTA',12,NULL),
  ('futsal','Sub 9','FEMININO',1,0,0,'NENHUMA','IDA_E_VOLTA',12,NULL),
  ('futsal','Sub 11','FEMININO',1,0,0,'NENHUMA','IDA_E_VOLTA',12,NULL),
  ('futsal','Sub 13','FEMININO',1,2,0,'FINAL','UNICO',12,NULL),
  ('futsal','Sub 15','FEMININO',2,1,0,'FINAL','UNICO',15,20),
  ('futsal','Sub 17','FEMININO',1,2,0,'FINAL','UNICO',15,20),
  ('futsal','Aberto','FEMININO',1,2,0,'FINAL','UNICO',15,20),
  ('futebol-society','Sub 13','MASCULINO',2,1,0,'FINAL','UNICO',20,NULL),
  ('futebol-society','Sub 15','MASCULINO',2,2,0,'SEMIFINAL','UNICO',NULL,NULL),
  ('futebol-society','Sub 17','MASCULINO',2,1,0,'FINAL','UNICO',20,NULL),
  ('handebol','Sub 8','MASCULINO',1,2,0,'FINAL','UNICO',12,NULL),
  ('handebol','Sub 11','MASCULINO',2,1,0,'FINAL','UNICO',12,NULL),
  ('handebol','Sub 13','MASCULINO',2,1,0,'FINAL','UNICO',12,NULL),
  ('handebol','Sub 15','MASCULINO',1,2,0,'FINAL','UNICO',15,20),
  ('handebol','Sub 17','MASCULINO',2,1,0,'FINAL','UNICO',15,20),
  ('handebol','Aberto','MASCULINO',1,0,0,'NENHUMA','IDA_E_VOLTA',15,20),
  ('handebol','Sub 8','FEMININO',1,0,0,'NENHUMA','IDA_E_VOLTA',12,NULL),
  ('handebol','Sub 9','FEMININO',1,2,0,'FINAL','UNICO',12,NULL),
  ('handebol','Sub 11','FEMININO',2,1,0,'FINAL','UNICO',12,NULL),
  ('handebol','Sub 13','FEMININO',1,2,0,'FINAL','UNICO',12,NULL),
  ('handebol','Sub 15','FEMININO',1,2,0,'FINAL','UNICO',15,20),
  ('handebol','Sub 17','FEMININO',1,2,0,'FINAL','UNICO',15,20),
  ('handebol','Aberto','FEMININO',1,0,0,'NENHUMA','IDA_E_VOLTA',15,20),
  ('baleado','Sub 8','MASCULINO',1,2,0,'FINAL','UNICO',15,NULL),
  ('baleado','Sub 9','MASCULINO',2,1,0,'FINAL','UNICO',15,NULL),
  ('baleado','Sub 11','MASCULINO',2,2,0,'SEMIFINAL','UNICO',15,NULL),
  ('baleado','Sub 13','MASCULINO',3,1,1,'SEMIFINAL','UNICO',15,NULL),
  ('baleado','Sub 15','MASCULINO',2,1,0,'FINAL','UNICO',15,NULL),
  ('baleado','Sub 17','MASCULINO',1,2,0,'FINAL','UNICO',15,NULL),
  ('baleado','Sub 8','FEMININO',1,0,0,'NENHUMA','IDA_E_VOLTA',15,NULL),
  ('baleado','Sub 9','FEMININO',2,1,0,'FINAL','UNICO',15,NULL),
  ('baleado','Sub 11','FEMININO',2,2,0,'SEMIFINAL','UNICO',15,NULL),
  ('baleado','Sub 13','FEMININO',3,1,1,'SEMIFINAL','UNICO',15,NULL),
  ('baleado','Sub 15','FEMININO',2,2,0,'SEMIFINAL','UNICO',15,NULL),
  ('baleado','Sub 17','FEMININO',1,2,0,'FINAL','UNICO',15,NULL),
  ('volei','Sub 15','MISTO',1,2,0,'FINAL','UNICO',NULL,NULL),
  ('volei','Sub 17','MISTO',2,2,0,'SEMIFINAL','UNICO',NULL,NULL),
  ('volei','Aberto','MASCULINO',1,2,0,'FINAL','UNICO',NULL,NULL),
  ('basquete','Sub 15','FEMININO',1,2,0,'FINAL','UNICO',NULL,NULL),
  ('basquete','Sub 17','FEMININO',1,2,0,'FINAL','UNICO',NULL,NULL),
  ('basquete','Sub 15','MASCULINO',1,2,0,'FINAL','UNICO',NULL,NULL),
  ('basquete','Sub 17','MASCULINO',1,2,0,'FINAL','UNICO',NULL,NULL);

INSERT INTO competicoes (modalidade_id, categoria_id, genero, qtd_grupos, classificados_por_grupo,
                         melhores_segundos, proxima_fase, turno, minutos_por_tempo, minutos_por_tempo_final)
SELECT m.id, c.id, i.genero, i.qtd_grupos, i.classificados, i.melhores2, i.fase, i.turno, i.min_tempo, i.min_final
FROM _imp_competicoes i
JOIN modalidades m ON m.slug = i.slug
JOIN categorias  c ON c.nome = i.categoria;

-- 4) Equipes por grupo: (modalidade, categoria, gênero, grupo, escola)
CREATE TEMPORARY TABLE _imp_equipes (
  slug VARCHAR(50), categoria VARCHAR(50), genero VARCHAR(10), grupo VARCHAR(10), escola VARCHAR(150)
);
INSERT INTO _imp_equipes VALUES
  ('futsal','Sub 7','MASCULINO','A','JOSE DIAS'),
  ('futsal','Sub 7','MASCULINO','A','ACM'),
  ('futsal','Sub 7','MASCULINO','A','TEODULO LEITE'),
  ('futsal','Sub 7','MASCULINO','A','ADELIETA RAMALHO'),
  ('futsal','Sub 8','MASCULINO','A','ADELIETA RAMALHO'),
  ('futsal','Sub 8','MASCULINO','A','JOSE DIAS'),
  ('futsal','Sub 8','MASCULINO','A','FRANCISCO AMORIM'),
  ('futsal','Sub 8','MASCULINO','B','MARLENE SANTANA'),
  ('futsal','Sub 8','MASCULINO','B','ACM'),
  ('futsal','Sub 8','MASCULINO','B','TEODULO LEITE'),
  ('futsal','Sub 9','MASCULINO','A','ADELIETA RAMALHO'),
  ('futsal','Sub 9','MASCULINO','A','FRANCISCO AMORIM'),
  ('futsal','Sub 9','MASCULINO','A','MARLENE SANTANA'),
  ('futsal','Sub 9','MASCULINO','A','PORTAL DO SABER'),
  ('futsal','Sub 9','MASCULINO','B','TEODULO LEITE'),
  ('futsal','Sub 9','MASCULINO','B','JOSE DIAS'),
  ('futsal','Sub 9','MASCULINO','B','MARIA DA GLORIA'),
  ('futsal','Sub 9','MASCULINO','B','EMILIANO ZAPATA'),
  ('futsal','Sub 11','MASCULINO','A','CEJA'),
  ('futsal','Sub 11','MASCULINO','A','PORTAL DO SABER'),
  ('futsal','Sub 11','MASCULINO','A','ADELIETA RAMALHO'),
  ('futsal','Sub 11','MASCULINO','A','EMILIANO ZAPATA'),
  ('futsal','Sub 11','MASCULINO','B','JOSENILDO LEITE'),
  ('futsal','Sub 11','MASCULINO','B','MARIA DA GLORIA'),
  ('futsal','Sub 11','MASCULINO','B','FRANCISCO AMORIM'),
  ('futsal','Sub 11','MASCULINO','C','MARLENE SANTANA'),
  ('futsal','Sub 11','MASCULINO','C','CEBC'),
  ('futsal','Sub 11','MASCULINO','C','JOSE DIAS'),
  ('futsal','Sub 13','MASCULINO','A','EMILIANO ZAPATA'),
  ('futsal','Sub 13','MASCULINO','A','JOSENILDO LEITE'),
  ('futsal','Sub 13','MASCULINO','A','CEBC'),
  ('futsal','Sub 13','MASCULINO','A','CEJA'),
  ('futsal','Sub 13','MASCULINO','B','CEBN'),
  ('futsal','Sub 13','MASCULINO','B','COVENIADA'),
  ('futsal','Sub 13','MASCULINO','B','JOSE DIAS'),
  ('futsal','Sub 15','MASCULINO','A','MANOEL RAMOS'),
  ('futsal','Sub 15','MASCULINO','A','EMILIANO ZAPATA'),
  ('futsal','Sub 15','MASCULINO','A','CEBC'),
  ('futsal','Sub 15','MASCULINO','A','CETI'),
  ('futsal','Sub 15','MASCULINO','B','CEJA'),
  ('futsal','Sub 15','MASCULINO','B','JOSE DIAS'),
  ('futsal','Sub 15','MASCULINO','B','JOSENILDO LEITE'),
  ('futsal','Sub 15','MASCULINO','B','COVENIADA'),
  ('futsal','Sub 17','MASCULINO','A','JOSE DIAS'),
  ('futsal','Sub 17','MASCULINO','A','EMILIANO ZAPATA'),
  ('futsal','Sub 17','MASCULINO','A','CEJA'),
  ('futsal','Sub 17','MASCULINO','A','JOSENILDO LEITE'),
  ('futsal','Sub 17','MASCULINO','B','VITORIA LIMA'),
  ('futsal','Sub 17','MASCULINO','B','CEBC'),
  ('futsal','Sub 17','MASCULINO','B','LUCIA ROCHA'),
  ('futsal','Sub 17','MASCULINO','B','CETI'),
  ('futsal','Aberto','MASCULINO','A','VITORIA LIMA'),
  ('futsal','Aberto','MASCULINO','A','MANOEL RAMOS'),
  ('futsal','Aberto','MASCULINO','A','CETI'),
  ('futsal','Aberto','MASCULINO','B','LUCIA ROCHA'),
  ('futsal','Aberto','MASCULINO','B','CEBC'),
  ('futsal','Aberto','MASCULINO','B','CEJA'),
  ('futsal','Sub 8','FEMININO','A','JOSE DIAS'),
  ('futsal','Sub 8','FEMININO','A','EMILIANO ZAPATA'),
  ('futsal','Sub 9','FEMININO','A','MARLENE SANTANA'),
  ('futsal','Sub 9','FEMININO','A','JOSE DIAS'),
  ('futsal','Sub 11','FEMININO','A','MARLENE SANTANA'),
  ('futsal','Sub 11','FEMININO','A','JOSE DIAS'),
  ('futsal','Sub 13','FEMININO','A','EMILIANO ZAPATA'),
  ('futsal','Sub 13','FEMININO','A','CEJA'),
  ('futsal','Sub 13','FEMININO','A','CEBN'),
  ('futsal','Sub 15','FEMININO','A','EMILIANO ZAPATA'),
  ('futsal','Sub 15','FEMININO','A','CEJA'),
  ('futsal','Sub 15','FEMININO','A','CEBN'),
  ('futsal','Sub 15','FEMININO','B','JOSE DIAS'),
  ('futsal','Sub 15','FEMININO','B','CEBC'),
  ('futsal','Sub 15','FEMININO','B','COVENIADA'),
  ('futsal','Sub 17','FEMININO','A','CEBC'),
  ('futsal','Sub 17','FEMININO','A','CEJA'),
  ('futsal','Sub 17','FEMININO','A','VITORIA LIMA'),
  ('futsal','Sub 17','FEMININO','A','CETI'),
  ('futsal','Aberto','FEMININO','A','LUCIA ROCHA'),
  ('futsal','Aberto','FEMININO','A','VITORIA LIMA'),
  ('futsal','Aberto','FEMININO','A','CETI'),
  ('futebol-society','Sub 13','MASCULINO','A','CEJA'),
  ('futebol-society','Sub 13','MASCULINO','A','CEBC'),
  ('futebol-society','Sub 13','MASCULINO','A','COVENIADA'),
  ('futebol-society','Sub 13','MASCULINO','B','MARIA DA GLORIA'),
  ('futebol-society','Sub 13','MASCULINO','B','CEBN'),
  ('futebol-society','Sub 15','MASCULINO','A','EMILIANO ZAPATA'),
  ('futebol-society','Sub 15','MASCULINO','A','COVENIADA'),
  ('futebol-society','Sub 15','MASCULINO','A','CEJA'),
  ('futebol-society','Sub 15','MASCULINO','A','JOSE DIAS'),
  ('futebol-society','Sub 15','MASCULINO','B','CEBN'),
  ('futebol-society','Sub 15','MASCULINO','B','CETI'),
  ('futebol-society','Sub 15','MASCULINO','B','CEBC'),
  ('futebol-society','Sub 17','MASCULINO','A','CEJA'),
  ('futebol-society','Sub 17','MASCULINO','A','CEBN'),
  ('futebol-society','Sub 17','MASCULINO','A','CEBC'),
  ('futebol-society','Sub 17','MASCULINO','B','VITORIA LIMA'),
  ('futebol-society','Sub 17','MASCULINO','B','CETI'),
  ('handebol','Sub 8','MASCULINO','A','ACM'),
  ('handebol','Sub 8','MASCULINO','A','ADELIETA RAMALHO'),
  ('handebol','Sub 8','MASCULINO','A','JOSE DIAS'),
  ('handebol','Sub 11','MASCULINO','A','ADELIETA RAMALHO'),
  ('handebol','Sub 11','MASCULINO','A','MARIA DA GLORIA'),
  ('handebol','Sub 11','MASCULINO','A','CEJA'),
  ('handebol','Sub 11','MASCULINO','B','FRANCISCO AMORIM'),
  ('handebol','Sub 11','MASCULINO','B','CEBC'),
  ('handebol','Sub 11','MASCULINO','B','JOSE DIAS'),
  ('handebol','Sub 13','MASCULINO','A','CEBN'),
  ('handebol','Sub 13','MASCULINO','A','JOSE DIAS'),
  ('handebol','Sub 13','MASCULINO','A','COVENIADA'),
  ('handebol','Sub 13','MASCULINO','B','CEBC'),
  ('handebol','Sub 13','MASCULINO','B','CEJA'),
  ('handebol','Sub 13','MASCULINO','B','ADELIETA RAMALHO'),
  ('handebol','Sub 15','MASCULINO','A','CEBC'),
  ('handebol','Sub 15','MASCULINO','A','CEJA'),
  ('handebol','Sub 15','MASCULINO','A','COVENIADA'),
  ('handebol','Sub 15','MASCULINO','A','CEBN'),
  ('handebol','Sub 17','MASCULINO','A','CEBN'),
  ('handebol','Sub 17','MASCULINO','A','COVENIADA'),
  ('handebol','Sub 17','MASCULINO','A','CEJA'),
  ('handebol','Sub 17','MASCULINO','B','CEBC'),
  ('handebol','Sub 17','MASCULINO','B','CETI'),
  ('handebol','Aberto','MASCULINO','A','CETI'),
  ('handebol','Aberto','MASCULINO','A','CEJA'),
  ('handebol','Aberto','MASCULINO','A','LUCIA ROCHA'),
  ('handebol','Sub 8','FEMININO','A','JOSE DIAS'),
  ('handebol','Sub 8','FEMININO','A','ACM'),
  ('handebol','Sub 9','FEMININO','A','FRANCISCO AMORIM'),
  ('handebol','Sub 9','FEMININO','A','MARIA DA GLORIA'),
  ('handebol','Sub 9','FEMININO','A','ADELIETA RAMALHO'),
  ('handebol','Sub 11','FEMININO','A','FRANCISCO AMORIM'),
  ('handebol','Sub 11','FEMININO','A','CEJA'),
  ('handebol','Sub 11','FEMININO','A','MARIA DA GLORIA'),
  ('handebol','Sub 11','FEMININO','B','ADELIETA RAMALHO'),
  ('handebol','Sub 11','FEMININO','B','JOSE DIAS'),
  ('handebol','Sub 11','FEMININO','B','MARLENE SANTANA'),
  ('handebol','Sub 13','FEMININO','A','CEBN'),
  ('handebol','Sub 13','FEMININO','A','CEBC'),
  ('handebol','Sub 13','FEMININO','A','CEJA'),
  ('handebol','Sub 15','FEMININO','A','CEJA'),
  ('handebol','Sub 15','FEMININO','A','CEBC'),
  ('handebol','Sub 15','FEMININO','A','CEBN'),
  ('handebol','Sub 15','FEMININO','A','COVENIADA'),
  ('handebol','Sub 17','FEMININO','A','CEJA'),
  ('handebol','Sub 17','FEMININO','A','CEBN'),
  ('handebol','Sub 17','FEMININO','A','CETI'),
  ('handebol','Aberto','FEMININO','A','CETI'),
  ('handebol','Aberto','FEMININO','A','LUCIA ROCHA'),
  ('baleado','Sub 8','MASCULINO','A','FRANCISCO AMORIM'),
  ('baleado','Sub 8','MASCULINO','A','ACM'),
  ('baleado','Sub 8','MASCULINO','A','MARLENE SANTANA'),
  ('baleado','Sub 9','MASCULINO','A','ADELIETA RAMALHO'),
  ('baleado','Sub 9','MASCULINO','A','MARLENE SANTANA'),
  ('baleado','Sub 9','MASCULINO','A','JOSE DIAS'),
  ('baleado','Sub 9','MASCULINO','B','TEODULO LEITE'),
  ('baleado','Sub 9','MASCULINO','B','MARIA DA GLORIA'),
  ('baleado','Sub 9','MASCULINO','B','FRANCISCO AMORIM'),
  ('baleado','Sub 11','MASCULINO','A','MANOEL RAMOS'),
  ('baleado','Sub 11','MASCULINO','A','MARLENE SANTANA'),
  ('baleado','Sub 11','MASCULINO','A','ADELIETA RAMALHO'),
  ('baleado','Sub 11','MASCULINO','A','JOSE DIAS'),
  ('baleado','Sub 11','MASCULINO','B','MARIA DA GLORIA'),
  ('baleado','Sub 11','MASCULINO','B','FRANCISCO AMORIM'),
  ('baleado','Sub 11','MASCULINO','B','EMILIANO ZAPATA'),
  ('baleado','Sub 13','MASCULINO','A','CEBC'),
  ('baleado','Sub 13','MASCULINO','A','CEJA'),
  ('baleado','Sub 13','MASCULINO','A','JOSENILDO LEITE'),
  ('baleado','Sub 13','MASCULINO','B','CEBN'),
  ('baleado','Sub 13','MASCULINO','B','COVENIADA'),
  ('baleado','Sub 13','MASCULINO','B','ADELIETA RAMALHO'),
  ('baleado','Sub 13','MASCULINO','C','MARIA DA GLORIA'),
  ('baleado','Sub 13','MASCULINO','C','EMILIANO ZAPATA'),
  ('baleado','Sub 13','MASCULINO','C','MANOEL RAMOS'),
  ('baleado','Sub 15','MASCULINO','A','CEBN'),
  ('baleado','Sub 15','MASCULINO','A','CEJA'),
  ('baleado','Sub 15','MASCULINO','A','CEBC'),
  ('baleado','Sub 15','MASCULINO','B','COVENIADA'),
  ('baleado','Sub 15','MASCULINO','B','MANOEL RAMOS'),
  ('baleado','Sub 17','MASCULINO','A','CETI'),
  ('baleado','Sub 17','MASCULINO','A','JOSENILDO LEITE'),
  ('baleado','Sub 17','MASCULINO','A','CEBC'),
  ('baleado','Sub 17','MASCULINO','A','CEJA'),
  ('baleado','Sub 8','FEMININO','A','ACM'),
  ('baleado','Sub 8','FEMININO','A','JOSE DIAS'),
  ('baleado','Sub 9','FEMININO','A','PORTAL DO SABER'),
  ('baleado','Sub 9','FEMININO','A','FRANCISCO AMORIM'),
  ('baleado','Sub 9','FEMININO','A','MARIA DA GLORIA'),
  ('baleado','Sub 9','FEMININO','B','EMILIANO ZAPATA'),
  ('baleado','Sub 9','FEMININO','B','ADELIETA RAMALHO'),
  ('baleado','Sub 11','FEMININO','A','ADELIETA RAMALHO'),
  ('baleado','Sub 11','FEMININO','A','PORTAL DO SABER'),
  ('baleado','Sub 11','FEMININO','A','JOSENILDO LEITE'),
  ('baleado','Sub 11','FEMININO','A','FRANCISCO AMORIM'),
  ('baleado','Sub 11','FEMININO','B','MARIA DA GLORIA'),
  ('baleado','Sub 11','FEMININO','B','CEJA'),
  ('baleado','Sub 11','FEMININO','B','JOSE DIAS'),
  ('baleado','Sub 11','FEMININO','B','EMILIANO ZAPATA'),
  ('baleado','Sub 13','FEMININO','A','CEBN'),
  ('baleado','Sub 13','FEMININO','A','PORTAL DO SABER'),
  ('baleado','Sub 13','FEMININO','A','COVENIADA'),
  ('baleado','Sub 13','FEMININO','A','ADELIETA RAMALHO'),
  ('baleado','Sub 13','FEMININO','B','CEBC'),
  ('baleado','Sub 13','FEMININO','B','EMILIANO ZAPATA'),
  ('baleado','Sub 13','FEMININO','B','JOSE DIAS'),
  ('baleado','Sub 13','FEMININO','C','MARIA DA GLORIA'),
  ('baleado','Sub 13','FEMININO','C','CEJA'),
  ('baleado','Sub 13','FEMININO','C','MANOEL RAMOS'),
  ('baleado','Sub 15','FEMININO','A','JOSENILDO LEITE'),
  ('baleado','Sub 15','FEMININO','A','CEBN'),
  ('baleado','Sub 15','FEMININO','A','CEBC'),
  ('baleado','Sub 15','FEMININO','B','EMILIANO ZAPATA'),
  ('baleado','Sub 15','FEMININO','B','CEJA'),
  ('baleado','Sub 15','FEMININO','B','COVENIADA'),
  ('baleado','Sub 17','FEMININO','A','CEJA'),
  ('baleado','Sub 17','FEMININO','A','LUCIA ROCHA'),
  ('baleado','Sub 17','FEMININO','A','CEBC'),
  ('baleado','Sub 17','FEMININO','A','CETI'),
  ('volei','Sub 15','MISTO','A','EMILIANO ZAPATA'),
  ('volei','Sub 15','MISTO','A','CEBC'),
  ('volei','Sub 15','MISTO','A','CEJA'),
  ('volei','Sub 15','MISTO','A','CEBN'),
  ('volei','Sub 17','MISTO','A','EMILIANO ZAPATA'),
  ('volei','Sub 17','MISTO','A','CETI'),
  ('volei','Sub 17','MISTO','A','CEBN'),
  ('volei','Sub 17','MISTO','B','LUCIA ROCHA'),
  ('volei','Sub 17','MISTO','B','CEBC'),
  ('volei','Aberto','MASCULINO','A','LUCIA ROCHA'),
  ('volei','Aberto','MASCULINO','A','CEBC'),
  ('volei','Aberto','MASCULINO','A','CETI'),
  ('basquete','Sub 15','FEMININO','A','COVENIADA'),
  ('basquete','Sub 15','FEMININO','A','CEBC'),
  ('basquete','Sub 15','FEMININO','A','CEJA'),
  ('basquete','Sub 17','FEMININO','A','CETI'),
  ('basquete','Sub 17','FEMININO','A','CEJA'),
  ('basquete','Sub 17','FEMININO','A','CEBC'),
  ('basquete','Sub 15','MASCULINO','A','CEJA'),
  ('basquete','Sub 15','MASCULINO','A','COVENIADA'),
  ('basquete','Sub 15','MASCULINO','A','CEBC'),
  ('basquete','Sub 15','MASCULINO','A','CEBN'),
  ('basquete','Sub 17','MASCULINO','A','CETI'),
  ('basquete','Sub 17','MASCULINO','A','CEBC'),
  ('basquete','Sub 17','MASCULINO','A','CEJA');

INSERT INTO grupos (competicao_id, nome)
SELECT DISTINCT co.id, t.grupo
FROM _imp_equipes t
JOIN modalidades m  ON m.slug = t.slug
JOIN categorias  c  ON c.nome = t.categoria
JOIN competicoes co ON co.modalidade_id = m.id AND co.categoria_id = c.id AND co.genero = t.genero;

INSERT INTO equipes (competicao_id, escola_id, grupo_id)
SELECT co.id, e.id, g.id
FROM _imp_equipes t
JOIN modalidades m  ON m.slug = t.slug
JOIN categorias  c  ON c.nome = t.categoria
JOIN competicoes co ON co.modalidade_id = m.id AND co.categoria_id = c.id AND co.genero = t.genero
JOIN grupos g       ON g.competicao_id = co.id AND g.nome = t.grupo
JOIN escolas e      ON e.nome = t.escola;

DROP TEMPORARY TABLE _imp_equipes;
DROP TEMPORARY TABLE _imp_competicoes;

-- 5) Conferência: deve dar escolas=18, competicoes=50, grupos=77, equipes=240
SELECT (SELECT COUNT(*) FROM escolas)      AS escolas,
       (SELECT COUNT(*) FROM competicoes)  AS competicoes,
       (SELECT COUNT(*) FROM grupos)       AS grupos,
       (SELECT COUNT(*) FROM equipes)      AS equipes;
