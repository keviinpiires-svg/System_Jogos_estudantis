-- =====================================================================
-- ATENÇÃO: APAGA TODAS AS TABELAS DO SISTEMA (antigas e novas) E OS DADOS.
-- Use só em banco de desenvolvimento, ou em produção DEPOIS de backup e
-- com certeza de que os dados são descartáveis.
-- Depois rode 01_schema.sql e 02_carga_base.sql.
-- =====================================================================
SET FOREIGN_KEY_CHECKS = 0;

-- Tabelas do schema antigo (baseline de 28/09/2026)
DROP TABLE IF EXISTS alunos;
DROP TABLE IF EXISTS classificacao;
DROP TABLE IF EXISTS diretores;
DROP TABLE IF EXISTS grupos_escolas;
DROP TABLE IF EXISTS resultados_provas;
DROP TABLE IF EXISTS sumulas;
DROP TABLE IF EXISTS sumulas_jogadores;

-- Tabelas que existem nos dois schemas ou só no novo
DROP TABLE IF EXISTS resultados_atletismo;
DROP TABLE IF EXISTS provas_atletismo;
DROP TABLE IF EXISTS ajustes_pontos_geral;
DROP TABLE IF EXISTS colocacoes_finais;
DROP TABLE IF EXISTS pontuacao_geral;
DROP TABLE IF EXISTS suspensoes;
DROP TABLE IF EXISTS jogo_sets;
DROP TABLE IF EXISTS sumula_equipes;
DROP TABLE IF EXISTS sumula_atletas;
DROP TABLE IF EXISTS jogos;
DROP TABLE IF EXISTS locais_disputa;
DROP TABLE IF EXISTS inscricoes_atletas;
DROP TABLE IF EXISTS atletas;
DROP TABLE IF EXISTS equipes;
DROP TABLE IF EXISTS grupos;
DROP TABLE IF EXISTS competicoes;
DROP TABLE IF EXISTS categorias;
DROP TABLE IF EXISTS modalidades;
DROP TABLE IF EXISTS escola_apelidos;
DROP TABLE IF EXISTS escolas;
DROP TABLE IF EXISTS etapas_ensino;
DROP TABLE IF EXISTS usuarios;
DROP TABLE IF EXISTS configuracao_evento;

SET FOREIGN_KEY_CHECKS = 1;
