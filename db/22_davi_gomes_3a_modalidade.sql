-- =====================================================================
-- MIGRAÇÃO 22 — Davi Gomes Pereira (ACM) na 3ª modalidade coletiva (04/11/2026)
--
-- EXCEÇÃO AUTORIZADA PELO CHEFE: o aluno já está cadastrado (RG provisório
-- ACM-SRG-008, guardado normalizado como ACMSRG008) e já tem 2 inscrições em
-- competições coletivas. Esta migração acrescenta a 3ª, o Handebol Masculino
-- Sub 8 do ACM — uma única inscrição, sem camisa (numero_camisa NULL).
--
-- Por que um script, e não a importação por CSV: o importador PULA a linha de
-- RG já cadastrado, com ou sem a coluna "Exceção". A tela de inscrição recusaria
-- a 3ª competição coletiva. Aqui só o máximo de 2 coletivas é dispensado: sexo
-- do atleta × gênero da competição, escola da equipe e o teto de elenco da
-- modalidade (modalidades.max_atletas) são conferidos e valem. A idade da
-- categoria também não é conferida: faz parte da exceção do chefe.
--
-- Acha o atleta pelo RG normalizado + nome + escola ACM + sexo M, e a equipe
-- pela escola ACM + Handebol + Sub 8 + MASCULINO. Não escreve RG, nascimento
-- nem o nome em lugar nenhum (só no filtro que acha o atleta).
--
-- SEGURANÇA: uma transação só. Duas travas (CHECK em tabela temporária, erro
-- 3819 no MySQL e 4025 no MariaDB) param o script sem gravar nada:
--   davi_ou_equipe_nao_batem_com_a_descricao   (antes de qualquer escrita)
--   conferencia_do_db22_divergiu                (antes do COMMIT)
-- A primeira só deixa passar dois estados: INSCREVER (atleta com exatamente 2
-- inscrições, todas em competições coletivas, ainda sem esta, e equipe com vaga)
-- e JÁ INSCRITO (as 3 inscrições já existem: não grava nada). Qualquer outra
-- coisa — atleta não achado ou duplicado, equipe não achada, sexo ou escola
-- diferentes, atleta com outro número de inscrições, equipe sem vaga — para.
-- No cliente mysql o erro encerra a sessão e a transação é desfeita. No
-- DBeaver, se um comando falhar, rode ROLLBACK antes de qualquer outra coisa.
--
-- IDEMPOTENTE: rodado de novo, cai no estado JÁ INSCRITO e não grava nada.
--
-- Só dados. Rode depois do 21 (não depende dele). MySQL 8.0.16+ ou MariaDB
-- 10.2+ (CHECK de verdade). Faça o dump do banco antes, na produção.
-- =====================================================================

SET NAMES utf8mb4;

START TRANSACTION;

-- Trava a linha da equipe: duas inscrições ao mesmo tempo não furam o teto
SELECT e.id AS equipe_travada
  FROM equipes e
  INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'ACM'
  INNER JOIN competicoes c ON c.id = e.competicao_id AND c.genero = 'MASCULINO'
  INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.slug = 'handebol'
  INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = 'Sub 8'
 FOR UPDATE;

-- ---------------------------------------------------------------------
-- O que foi achado
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS alvo_db22;
CREATE TEMPORARY TABLE alvo_db22 (
  atletas_achados   INT NOT NULL,   -- esperado 1
  equipes_achadas   INT NOT NULL,   -- esperado 1
  atleta_id         INT NULL,
  equipe_id         INT NULL,
  escola_confere    TINYINT NOT NULL,   -- escola do atleta = escola da equipe
  ja_inscrito       TINYINT NOT NULL,   -- já tem inscrição nesta equipe
  inscricoes        INT NOT NULL,       -- todas as inscrições do atleta
  coletivas         INT NOT NULL,       -- as que são em modalidade COLETIVO
  inscritos_equipe  INT NOT NULL,
  max_atletas       INT NULL
);

INSERT INTO alvo_db22
  (atletas_achados, equipes_achadas, atleta_id, equipe_id, escola_confere,
   ja_inscrito, inscricoes, coletivas, inscritos_equipe, max_atletas)
SELECT
  (SELECT COUNT(*) FROM atletas a INNER JOIN escolas s ON s.id = a.escola_id
    WHERE a.rg = 'ACMSRG008' AND a.nome = 'Davi Gomes Pereira' AND s.nome = 'ACM' AND a.sexo = 'M'),
  (SELECT COUNT(*) FROM equipes e
     INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'ACM'
     INNER JOIN competicoes c ON c.id = e.competicao_id AND c.genero = 'MASCULINO'
     INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.slug = 'handebol'
     INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = 'Sub 8'),
  (SELECT MAX(a.id) FROM atletas a INNER JOIN escolas s ON s.id = a.escola_id
    WHERE a.rg = 'ACMSRG008' AND a.nome = 'Davi Gomes Pereira' AND s.nome = 'ACM' AND a.sexo = 'M'),
  (SELECT MAX(e.id) FROM equipes e
     INNER JOIN escolas s ON s.id = e.escola_id AND s.nome = 'ACM'
     INNER JOIN competicoes c ON c.id = e.competicao_id AND c.genero = 'MASCULINO'
     INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.slug = 'handebol'
     INNER JOIN categorias cat ON cat.id = c.categoria_id AND cat.nome = 'Sub 8'),
  0, 0, 0, 0, 0, NULL;

-- A escola do atleta é a da equipe (o banco também garante, pela chave estrangeira composta)
UPDATE alvo_db22 t
   SET t.escola_confere = CASE WHEN t.atleta_id IS NOT NULL AND t.equipe_id IS NOT NULL
         AND (SELECT escola_id FROM atletas WHERE id = t.atleta_id)
           = (SELECT escola_id FROM equipes WHERE id = t.equipe_id) THEN 1 ELSE 0 END,
       t.ja_inscrito = (SELECT COUNT(*) FROM inscricoes_atletas i
                         WHERE i.atleta_id = t.atleta_id AND i.equipe_id = t.equipe_id),
       t.inscricoes = (SELECT COUNT(*) FROM inscricoes_atletas i WHERE i.atleta_id = t.atleta_id),
       t.coletivas = (SELECT COUNT(*) FROM inscricoes_atletas i
                        INNER JOIN equipes e ON e.id = i.equipe_id
                        INNER JOIN competicoes c ON c.id = e.competicao_id
                        INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.tipo = 'COLETIVO'
                       WHERE i.atleta_id = t.atleta_id),
       t.inscritos_equipe = (SELECT COUNT(*) FROM inscricoes_atletas i WHERE i.equipe_id = t.equipe_id),
       t.max_atletas = (SELECT m.max_atletas FROM equipes e
                          INNER JOIN competicoes c ON c.id = e.competicao_id
                          INNER JOIN modalidades m ON m.id = c.modalidade_id
                         WHERE e.id = t.equipe_id);

-- O que foi achado (antes da trava, para ver o motivo se ela parar)
SELECT atletas_achados, equipes_achadas, escola_confere, ja_inscrito, inscricoes, coletivas,
       inscritos_equipe, max_atletas
  FROM alvo_db22;

-- ---------------------------------------------------------------------
-- Trava 1: INSCREVER (2 inscrições coletivas, ainda sem esta, e vaga na
-- equipe) ou JÁ INSCRITO (as 3 já existem). Qualquer outra coisa para aqui.
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS trava_alvo_db22;
CREATE TEMPORARY TABLE trava_alvo_db22 (
  estado VARCHAR(40) NOT NULL,
  ok     TINYINT     NOT NULL,
  CONSTRAINT davi_ou_equipe_nao_batem_com_a_descricao CHECK (ok = 1)
);
INSERT INTO trava_alvo_db22 (estado, ok)
SELECT CASE
         WHEN atletas_achados = 1 AND equipes_achadas = 1 AND escola_confere = 1
              AND ja_inscrito = 0 AND inscricoes = 2 AND coletivas = 2
              AND max_atletas IS NOT NULL AND inscritos_equipe < max_atletas THEN 'inscrever'
         WHEN atletas_achados = 1 AND equipes_achadas = 1 AND escola_confere = 1
              AND ja_inscrito = 1 AND inscricoes = 3 AND coletivas = 3
              AND max_atletas IS NOT NULL AND inscritos_equipe <= max_atletas THEN 'já inscrito: nada a fazer'
         ELSE 'não bate' END,
       CASE
         WHEN atletas_achados = 1 AND equipes_achadas = 1 AND escola_confere = 1
              AND ja_inscrito = 0 AND inscricoes = 2 AND coletivas = 2
              AND max_atletas IS NOT NULL AND inscritos_equipe < max_atletas THEN 1
         WHEN atletas_achados = 1 AND equipes_achadas = 1 AND escola_confere = 1
              AND ja_inscrito = 1 AND inscricoes = 3 AND coletivas = 3
              AND max_atletas IS NOT NULL AND inscritos_equipe <= max_atletas THEN 1
         ELSE 0 END
  FROM alvo_db22;

SELECT estado AS db22 FROM trava_alvo_db22;
DROP TEMPORARY TABLE trava_alvo_db22;

-- Guarda os ids em variáveis: tabela temporária não pode aparecer duas vezes
-- na mesma consulta (erro 1137), e as conferências abaixo usam mais de uma.
SET @atleta_db22 = (SELECT atleta_id FROM alvo_db22);
SET @equipe_db22 = (SELECT equipe_id FROM alvo_db22);
SET @max_db22 = (SELECT max_atletas FROM alvo_db22);

-- ---------------------------------------------------------------------
-- A inscrição (só no estado INSCREVER: no "já inscrito" não entra nada).
-- Sem camisa; a equipe e o atleta já são da mesma escola (conferido acima).
-- ---------------------------------------------------------------------
INSERT INTO inscricoes_atletas (equipe_id, atleta_id, escola_id, numero_camisa)
SELECT t.equipe_id, t.atleta_id, a.escola_id, NULL
  FROM alvo_db22 t
  INNER JOIN atletas a ON a.id = t.atleta_id
 WHERE t.ja_inscrito = 0 AND t.inscricoes = 2 AND t.coletivas = 2;

-- ---------------------------------------------------------------------
-- Conferências. A tabela mostra o esperado e o encontrado; a trava logo
-- depois desfaz tudo se alguma divergir.
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS conferencia_db22;
CREATE TEMPORARY TABLE conferencia_db22 (
  item       VARCHAR(90) NOT NULL,
  esperado   INT         NOT NULL,
  encontrado INT         NOT NULL
);

INSERT INTO conferencia_db22 (item, esperado, encontrado)
SELECT 'inscrições do atleta (todas)', 3, COUNT(*)
  FROM inscricoes_atletas i WHERE i.atleta_id = @atleta_db22
UNION ALL SELECT 'inscrições do atleta em competições coletivas', 3, COUNT(*)
  FROM inscricoes_atletas i
  INNER JOIN equipes e ON e.id = i.equipe_id
  INNER JOIN competicoes c ON c.id = e.competicao_id
  INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.tipo = 'COLETIVO'
 WHERE i.atleta_id = @atleta_db22
UNION ALL SELECT 'atleta inscrito no Handebol M Sub 8 do ACM (uma vez só)', 1, COUNT(*)
  FROM inscricoes_atletas i WHERE i.atleta_id = @atleta_db22 AND i.equipe_id = @equipe_db22
UNION ALL SELECT 'elenco da equipe acima do máximo da modalidade (0 = respeitou)', 0,
       CASE WHEN COUNT(*) > @max_db22 THEN 1 ELSE 0 END
  FROM inscricoes_atletas i WHERE i.equipe_id = @equipe_db22;

SELECT item, esperado, encontrado,
       CASE WHEN esperado = encontrado THEN 'ok' ELSE 'DIVERGE' END AS situacao
  FROM conferencia_db22;

-- Trava 2: qualquer divergência para aqui, antes do COMMIT
DROP TEMPORARY TABLE IF EXISTS trava_conferencia_db22;
CREATE TEMPORARY TABLE trava_conferencia_db22 (
  item VARCHAR(90) NOT NULL,
  ok   TINYINT     NOT NULL,
  CONSTRAINT conferencia_do_db22_divergiu CHECK (ok = 1)
);
INSERT INTO trava_conferencia_db22 (item, ok)
SELECT item, CASE WHEN esperado = encontrado THEN 1 ELSE 0 END FROM conferencia_db22;

DROP TEMPORARY TABLE trava_conferencia_db22;
DROP TEMPORARY TABLE conferencia_db22;
DROP TEMPORARY TABLE alvo_db22;

COMMIT;

-- ---------------------------------------------------------------------
-- Depois do COMMIT, só leitura: as inscrições do atleta e o elenco da equipe
-- ---------------------------------------------------------------------
SELECT m.nome AS modalidade, cat.nome AS categoria, c.genero, i.numero_camisa,
       (SELECT COUNT(*) FROM inscricoes_atletas x WHERE x.equipe_id = i.equipe_id) AS elenco_da_equipe,
       m.max_atletas
  FROM inscricoes_atletas i
  INNER JOIN atletas a ON a.id = i.atleta_id AND a.rg = 'ACMSRG008'
  INNER JOIN equipes e ON e.id = i.equipe_id
  INNER JOIN competicoes c ON c.id = e.competicao_id
  INNER JOIN modalidades m ON m.id = c.modalidade_id
  INNER JOIN categorias cat ON cat.id = c.categoria_id
 ORDER BY m.nome, cat.nome;
