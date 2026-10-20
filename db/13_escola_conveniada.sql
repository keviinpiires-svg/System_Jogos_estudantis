-- =====================================================================
-- MIGRAÇÃO 13 — escola "COVENIADA" passa a se chamar "Conveniada"
-- (tabela oficial de jogos do chefe, 20/10/2026)
--
-- Motivo: a tabela de jogos do chefe escreve "Conveniada", e o cadastro
-- (03_importar_grupos.sql) trazia "COVENIADA", sem o N. Decisão do usuário:
-- onde o cadastro e a tabela divergem, vale a tabela. O nome oficial passa
-- a ser "Conveniada" (com essa grafia, maiúscula só na inicial), e a grafia
-- antiga fica guardada como apelido, para continuar sendo reconhecida (na
-- importação de jogos, por exemplo).
--
-- O id da escola não muda: equipes, atletas e inscrições continuam
-- apontando para ela.
--
-- IDEMPOTENTE: depois da troca, nenhuma escola casa mais com 'COVENIADA'
-- (a grafia nova tem uma letra a mais, então nem a collation da produção,
-- que ignora maiúsculas e acentos, as confunde), e o apelido só entra se
-- ainda não existir. Rodar duas vezes não muda nada.
--
-- Rode depois do 12 e antes do 14 (a ordem entre os dois não importa: o 14
-- não mexe nesta escola). Só dados: o backend no ar não precisa mudar.
-- =====================================================================

SET NAMES utf8mb4;

UPDATE escolas
   SET nome = 'Conveniada'
 WHERE nome = 'COVENIADA';

INSERT INTO escola_apelidos (escola_id, apelido)
SELECT e.id, 'COVENIADA'
  FROM escolas e
 WHERE e.nome = 'Conveniada'
   AND NOT EXISTS (SELECT 1 FROM escola_apelidos a WHERE a.apelido = 'COVENIADA');

-- ---------------------------------------------------------------------
-- Conferência: a escola com o nome novo, o apelido apontando para ela, e
-- nenhuma escola sobrando com o nome antigo
-- ---------------------------------------------------------------------
SELECT e.id, e.nome, a.apelido
  FROM escolas e
  LEFT JOIN escola_apelidos a ON a.escola_id = e.id AND a.apelido = 'COVENIADA'
 WHERE e.nome IN ('Conveniada', 'COVENIADA');
SELECT COUNT(*) AS equipes_da_conveniada
  FROM equipes eq
  INNER JOIN escolas e ON e.id = eq.escola_id
 WHERE e.nome = 'Conveniada';
