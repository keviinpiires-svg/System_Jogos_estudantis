-- =====================================================================
-- INVENTÁRIO DA PRODUÇÃO — SÓ LEITURA (nenhum comando altera nada)
--
-- Para rodar no DBeaver, na conexão `railway`, com o banco `jogos_2026`
-- ativo. Execute UM COMANDO POR VEZ (Ctrl+Enter), na ordem. Todos os nomes
-- vêm prefixados com `jogos_2026.`, para não cair no banco antigo `railway`.
--
-- O que ele responde:
--   0. em que banco e versão você está;
--   1. quantas linhas há em cada tabela de dados do evento;
--   2. se as equipes que o db/14 remove têm algo ligado a elas;
--   3. se os scripts 12, 13 e 14 já rodaram.
-- =====================================================================

-- 0) Banco e versão (esperado: jogos_2026 e 9.7.x)
SELECT DATABASE() AS banco_ativo, VERSION() AS versao;

-- 1) Linhas por tabela de dados do evento
SELECT 'jogos'                AS tabela, COUNT(*) AS linhas FROM jogos_2026.jogos
UNION ALL SELECT 'sumula_equipes',       COUNT(*) FROM jogos_2026.sumula_equipes
UNION ALL SELECT 'sumula_atletas',       COUNT(*) FROM jogos_2026.sumula_atletas
UNION ALL SELECT 'jogo_sets',            COUNT(*) FROM jogos_2026.jogo_sets
UNION ALL SELECT 'colocacoes_finais',    COUNT(*) FROM jogos_2026.colocacoes_finais
UNION ALL SELECT 'ajustes_pontos_geral', COUNT(*) FROM jogos_2026.ajustes_pontos_geral
UNION ALL SELECT 'suspensoes',           COUNT(*) FROM jogos_2026.suspensoes
UNION ALL SELECT 'resultados_atletismo', COUNT(*) FROM jogos_2026.resultados_atletismo
UNION ALL SELECT 'atletas',              COUNT(*) FROM jogos_2026.atletas
UNION ALL SELECT 'inscricoes_atletas',   COUNT(*) FROM jogos_2026.inscricoes_atletas
UNION ALL SELECT 'usuarios (fica)',      COUNT(*) FROM jogos_2026.usuarios;

-- 1b) Pontos lançados, à parte: a tabela nasce no db/11. Se este comando der
--     o erro 1146 ("Table doesn't exist"), o db/11 não rodou na produção.
SELECT 'pontos_lancados' AS tabela, COUNT(*) AS linhas FROM jogos_2026.pontos_lancados;

-- 2) Equipes que o db/14 remove: LUCIA ROCHA no Baleado F Sub 17 e CETI no
--    Handebol F Sub 17. Tudo precisa dar 0 para o db/14 rodar; se não der,
--    a limpeza (limpar_dados_de_teste.sql) zera jogos, súmulas e colocações,
--    e a parte opcional dela zera as inscrições.
SELECT es.nome AS escola, CONCAT(m.nome, ' ', cat.nome, ' ', c.genero) AS competicao, e.id AS equipe_id,
       (SELECT COUNT(*) FROM jogos_2026.jogos j
         WHERE e.id IN (j.equipe_1_id, j.equipe_2_id)
            OR j.vencedor_equipe_id = e.id OR j.baleou_primeiro_equipe_id = e.id) AS jogos,
       (SELECT COUNT(*) FROM jogos_2026.sumula_equipes s WHERE s.equipe_id = e.id) AS sumula_equipes,
       (SELECT COUNT(*) FROM jogos_2026.sumula_atletas s WHERE s.equipe_id = e.id) AS sumula_atletas,
       (SELECT COUNT(*) FROM jogos_2026.inscricoes_atletas i WHERE i.equipe_id = e.id) AS inscritos,
       (SELECT COUNT(*) FROM jogos_2026.colocacoes_finais cf WHERE cf.equipe_id = e.id) AS colocacoes
  FROM jogos_2026.equipes e
  INNER JOIN jogos_2026.competicoes c ON c.id = e.competicao_id
  INNER JOIN jogos_2026.modalidades m ON m.id = c.modalidade_id
  INNER JOIN jogos_2026.categorias cat ON cat.id = c.categoria_id
  INNER JOIN jogos_2026.escolas es ON es.id = e.escola_id
 WHERE (m.slug = 'baleado' AND cat.nome = 'Sub 17' AND c.genero = 'FEMININO' AND es.nome = 'LUCIA ROCHA')
    OR (m.slug = 'handebol' AND cat.nome = 'Sub 17' AND c.genero = 'FEMININO' AND es.nome = 'CETI');

-- 3) Os scripts 12, 13 e 14 já rodaram? (antes deles: 5 locais, escola
--    COVENIADA, 50 competições; depois: 8 locais, escola Conveniada, 51)
SELECT (SELECT COUNT(*) FROM jogos_2026.locais_disputa) AS locais,
       (SELECT GROUP_CONCAT(nome) FROM jogos_2026.escolas WHERE nome IN ('COVENIADA', 'Conveniada')) AS escola_conveniada,
       (SELECT COUNT(*) FROM jogos_2026.competicoes) AS competicoes;
