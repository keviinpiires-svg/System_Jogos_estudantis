-- =====================================================================
-- SGE Jogos Estudantis 2026 — schema do banco (MySQL 8.0.16+ ou MariaDB 10.4+)
--
-- Não fixa collation: usa a padrão do servidor/banco. Crie o banco com
--   CREATE DATABASE nome CHARACTER SET utf8mb4;
-- (no MySQL 8 a collation padrão é utf8mb4_0900_ai_ci, a mesma da produção).
--
-- Cria todas as tabelas num banco VAZIO. Para um banco que já tem as
-- tabelas antigas, rode antes o 00_apagar_tudo.sql (apaga tudo!).
-- Ordem: 00_apagar_tudo.sql -> 01_schema.sql -> 02_carga_base.sql
--
-- Ideia central: a unidade do campeonato é a COMPETIÇÃO
-- (modalidade x categoria x gênero). Grupos, equipes, jogos e súmulas
-- pertencem a uma competição.
--
-- Integridade garantida pelo banco (chaves compostas):
--   * a equipe de um jogo e o grupo do jogo são da MESMA competição do jogo;
--   * o grupo de uma equipe é da mesma competição da equipe;
--   * o atleta inscrito numa equipe é da MESMA escola da equipe;
--   * só aparece na súmula quem está inscrito na equipe.
-- Validações que ficam no CÓDIGO (dentro de transação):
--   * máximo de atletas por equipe (modalidades.max_atletas = 14);
--   * idade pela categoria: ano de nascimento >= ano do evento - idade_maxima;
--   * sexo do atleta x gênero da competição (MISTO aceita os dois);
--   * limite de 2 modalidades COLETIVAS por atleta;
--   * equipe da súmula é uma das duas equipes do jogo.
-- =====================================================================

SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- Configuração do evento (uma linha só, id = 1)
-- O ano é usado na regra de idade e no cabeçalho da súmula.
-- ---------------------------------------------------------------------
CREATE TABLE configuracao_evento (
  id          TINYINT      NOT NULL,
  nome_evento VARCHAR(150) NOT NULL,
  ano         SMALLINT     NOT NULL,
  cidade      VARCHAR(100) NOT NULL,
  estado      CHAR(2)      NOT NULL,
  data_inicio DATE         NULL,
  data_fim    DATE         NULL,
  PRIMARY KEY (id),
  CHECK (id = 1)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Usuários do sistema: ADMIN (tudo) e PLACAR (só lança súmula/placar)
-- ---------------------------------------------------------------------
CREATE TABLE usuarios (
  id        INT          NOT NULL AUTO_INCREMENT,
  nome      VARCHAR(120) NOT NULL,
  email     VARCHAR(160) NOT NULL,
  senha     VARCHAR(255) NOT NULL,              -- hash bcrypt, nunca texto puro
  perfil    ENUM('ADMIN','PLACAR') NOT NULL DEFAULT 'PLACAR',
  ativo     BOOLEAN      NOT NULL DEFAULT TRUE,
  criado_em TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_usuarios_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Etapas de ensino: os 3 blocos da tabela geral
-- ---------------------------------------------------------------------
CREATE TABLE etapas_ensino (
  id    INT          NOT NULL AUTO_INCREMENT,
  nome  VARCHAR(100) NOT NULL,
  ordem TINYINT      NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_etapas_nome (nome)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Escolas. O nome é gravado normalizado (maiúsculas, sem espaços duplos)
-- e a collation padrão do servidor ignora acento e caixa (no MySQL 8 é a
-- utf8mb4_0900_ai_ci): "José Dias" = "JOSE DIAS".
-- etapa_ensino_id: bloco da escola na tabela geral [PENDENTE: se a divisão
-- for por categoria, usa-se categorias.etapa_ensino_id].
-- ---------------------------------------------------------------------
CREATE TABLE escolas (
  id              INT          NOT NULL AUTO_INCREMENT,
  nome            VARCHAR(150) NOT NULL,
  cnpj            VARCHAR(20)  NULL,
  etapa_ensino_id INT          NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_escolas_nome (nome),
  UNIQUE KEY uq_escolas_cnpj (cnpj),
  CONSTRAINT fk_escolas_etapa FOREIGN KEY (etapa_ensino_id)
    REFERENCES etapas_ensino (id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Outras grafias da mesma escola (ex.: "J. DIAS" -> JOSE DIAS).
-- Usada na importação da tabela de grupos para não criar duplicatas.
CREATE TABLE escola_apelidos (
  id        INT          NOT NULL AUTO_INCREMENT,
  escola_id INT          NOT NULL,
  apelido   VARCHAR(150) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_apelidos_apelido (apelido),
  CONSTRAINT fk_apelidos_escola FOREIGN KEY (escola_id)
    REFERENCES escolas (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Modalidades
-- tipo: COLETIVO conta no limite de 2 modalidades por atleta.
-- tipo_placar define súmula, placar e desempate:
--   GOLS (futsal, society, handebol), PONTOS (basquete), SETS (vôlei),
--   ELIMINADOS (baleado), MARCA (atletismo: tempo/distância).
-- slug: usado nas rotas do menu lateral (/modalidade/futsal/...).
-- ---------------------------------------------------------------------
CREATE TABLE modalidades (
  id          INT          NOT NULL AUTO_INCREMENT,
  nome        VARCHAR(100) NOT NULL,
  slug        VARCHAR(50)  NOT NULL,
  tipo        ENUM('COLETIVO','INDIVIDUAL','INTERDISCIPLINAR') NOT NULL,
  tipo_placar ENUM('GOLS','PONTOS','SETS','ELIMINADOS','MARCA') NOT NULL,
  min_atletas TINYINT      NULL,                -- abaixo disso: só AVISO
  max_atletas TINYINT      NULL,                -- limite duro (14)
  ordem       TINYINT      NOT NULL DEFAULT 0,  -- ordem no menu lateral
  PRIMARY KEY (id),
  UNIQUE KEY uq_modalidades_nome (nome),
  UNIQUE KEY uq_modalidades_slug (slug)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Categorias. idade_maxima NULL = Aberto (sem limite).
-- Regra (regulamento): Sub N -> nascido em (ano do evento - N) ou depois.
--   Ex. 2026: Sub 15 -> nascido em 2011 ou depois.
-- etapa_ensino_id: opcional, caso a tabela geral seja dividida por categoria.
-- ---------------------------------------------------------------------
CREATE TABLE categorias (
  id              INT         NOT NULL AUTO_INCREMENT,
  nome            VARCHAR(50) NOT NULL,
  idade_maxima    TINYINT     NULL,
  ordem           TINYINT     NOT NULL DEFAULT 0,
  etapa_ensino_id INT         NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_categorias_nome (nome),
  CONSTRAINT fk_categorias_etapa FOREIGN KEY (etapa_ensino_id)
    REFERENCES etapas_ensino (id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Competições = modalidade x categoria x gênero (ex.: Futsal Sub 13 Fem.)
-- A regra de disputa é DADO, porque varia por competição:
--   qtd_grupos, classificados_por_grupo, melhores_segundos (o "segundo
--   mais bem colocado"), proxima_fase (SEMIFINAL, FINAL ou NENHUMA) e
--   turno (IDA_E_VOLTA = "melhor de dois jogos").
-- Pontos da fase de grupos também são dado [PENDENTE: 3/1/0 assumido].
-- ---------------------------------------------------------------------
CREATE TABLE competicoes (
  id                      INT     NOT NULL AUTO_INCREMENT,
  modalidade_id           INT     NOT NULL,
  categoria_id            INT     NOT NULL,
  genero                  ENUM('MASCULINO','FEMININO','MISTO') NOT NULL,
  qtd_grupos              TINYINT NOT NULL DEFAULT 1,
  classificados_por_grupo TINYINT NOT NULL DEFAULT 2,
  melhores_segundos       TINYINT NOT NULL DEFAULT 0,
  proxima_fase            ENUM('SEMIFINAL','FINAL','NENHUMA') NOT NULL DEFAULT 'FINAL',
  turno                   ENUM('UNICO','IDA_E_VOLTA') NOT NULL DEFAULT 'UNICO',
  minutos_por_tempo       TINYINT NULL,
  minutos_por_tempo_final TINYINT NULL,
  pontos_vitoria          TINYINT NOT NULL DEFAULT 3,
  pontos_empate           TINYINT NOT NULL DEFAULT 1,
  pontos_derrota          TINYINT NOT NULL DEFAULT 0,
  status                  ENUM('INSCRICOES','GRUPOS','MATA_MATA','ENCERRADA') NOT NULL DEFAULT 'INSCRICOES',
  PRIMARY KEY (id),
  UNIQUE KEY uq_competicoes (modalidade_id, categoria_id, genero),
  CONSTRAINT fk_competicoes_modalidade FOREIGN KEY (modalidade_id)
    REFERENCES modalidades (id) ON DELETE RESTRICT,
  CONSTRAINT fk_competicoes_categoria FOREIGN KEY (categoria_id)
    REFERENCES categorias (id) ON DELETE RESTRICT,
  CHECK (qtd_grupos BETWEEN 1 AND 8),
  CHECK (classificados_por_grupo BETWEEN 0 AND 8),
  CHECK (melhores_segundos BETWEEN 0 AND 8)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Grupos de uma competição (A, B, C...)
-- ---------------------------------------------------------------------
CREATE TABLE grupos (
  id            INT         NOT NULL AUTO_INCREMENT,
  competicao_id INT         NOT NULL,
  nome          VARCHAR(10) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_grupos_nome (competicao_id, nome),
  UNIQUE KEY uq_grupos_id_competicao (id, competicao_id),   -- alvo de FK composta
  CONSTRAINT fk_grupos_competicao FOREIGN KEY (competicao_id)
    REFERENCES competicoes (id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Equipes: a escola dentro de uma competição, no seu grupo.
-- (Substitui a antiga grupos_escolas; a tabela "equipes" antiga foi descartada.)
-- ---------------------------------------------------------------------
CREATE TABLE equipes (
  id            INT          NOT NULL AUTO_INCREMENT,
  competicao_id INT          NOT NULL,
  escola_id     INT          NOT NULL,
  grupo_id      INT          NULL,
  tecnico_nome  VARCHAR(150) NULL,
  criado_em     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_equipes (competicao_id, escola_id),
  UNIQUE KEY uq_equipes_id_competicao (id, competicao_id), -- alvo de FK composta
  UNIQUE KEY uq_equipes_id_escola (id, escola_id),         -- alvo de FK composta
  CONSTRAINT fk_equipes_competicao FOREIGN KEY (competicao_id)
    REFERENCES competicoes (id) ON DELETE RESTRICT,
  CONSTRAINT fk_equipes_escola FOREIGN KEY (escola_id)
    REFERENCES escolas (id) ON DELETE RESTRICT,
  -- o grupo precisa ser da mesma competição da equipe
  CONSTRAINT fk_equipes_grupo FOREIGN KEY (grupo_id, competicao_id)
    REFERENCES grupos (id, competicao_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Atletas. RG obrigatório e único; a idade vem de data_nascimento.
-- ---------------------------------------------------------------------
CREATE TABLE atletas (
  id              INT          NOT NULL AUTO_INCREMENT,
  escola_id       INT          NOT NULL,
  nome            VARCHAR(150) NOT NULL,
  rg              VARCHAR(20)  NOT NULL,
  data_nascimento DATE         NOT NULL,
  sexo            ENUM('M','F') NOT NULL,
  criado_em       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_atletas_rg (rg),
  UNIQUE KEY uq_atletas_id_escola (id, escola_id),              -- alvo de FK composta
  UNIQUE KEY uq_atletas_id_escola_sexo (id, escola_id, sexo),   -- alvo de FK composta (atletismo)
  CONSTRAINT fk_atletas_escola FOREIGN KEY (escola_id)
    REFERENCES escolas (id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Inscrição do atleta numa equipe (= numa competição).
-- escola_id repetido de propósito: garante pelo banco que atleta e
-- equipe são da mesma escola. Número da camisa único dentro da equipe.
-- ---------------------------------------------------------------------
CREATE TABLE inscricoes_atletas (
  id            INT       NOT NULL AUTO_INCREMENT,
  equipe_id     INT       NOT NULL,
  atleta_id     INT       NOT NULL,
  escola_id     INT       NOT NULL,
  numero_camisa TINYINT UNSIGNED NULL,
  criado_em     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_inscricoes (equipe_id, atleta_id),     -- também alvo da FK da súmula
  UNIQUE KEY uq_inscricoes_camisa (equipe_id, numero_camisa),
  KEY ix_inscricoes_atleta (atleta_id),
  CONSTRAINT fk_inscricoes_equipe FOREIGN KEY (equipe_id, escola_id)
    REFERENCES equipes (id, escola_id) ON DELETE RESTRICT,
  CONSTRAINT fk_inscricoes_atleta FOREIGN KEY (atleta_id, escola_id)
    REFERENCES atletas (id, escola_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Locais de disputa (ginásios, quadras)
-- ---------------------------------------------------------------------
CREATE TABLE locais_disputa (
  id       INT          NOT NULL AUTO_INCREMENT,
  nome     VARCHAR(100) NOT NULL,
  endereco VARCHAR(255) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_locais_nome (nome)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Jogos. Equipes e grupo presos à competição do jogo (FKs compostas).
-- numero_jogo é único POR COMPETIÇÃO. Renumeração após exclusão, sem
-- conflito com o índice único (a ORDER BY faz a atualização em ordem):
--   UPDATE jogos SET numero_jogo = numero_jogo - 1
--   WHERE competicao_id = ? AND numero_jogo > ? ORDER BY numero_jogo ASC;
-- placar_1/placar_2: gols, pontos, sets vencidos ou eliminados, conforme
-- modalidades.tipo_placar. Pênaltis (futsal/society) e prorrogação
-- (basquete/handebol) só a partir da 2ª fase.
-- vencedor_equipe_id: preenchido ao finalizar (necessário em W.O. e pênaltis).
-- ---------------------------------------------------------------------
CREATE TABLE jogos (
  id                 INT          NOT NULL AUTO_INCREMENT,
  competicao_id      INT          NOT NULL,
  numero_jogo        INT          NOT NULL,
  fase               ENUM('GRUPOS','SEMIFINAL','FINAL') NOT NULL DEFAULT 'GRUPOS',
  rodada             TINYINT      NULL,
  grupo_id           INT          NULL,
  local_id           INT          NULL,
  data_hora          DATETIME     NULL,
  equipe_1_id        INT          NOT NULL,
  equipe_2_id        INT          NOT NULL,
  placar_1           INT          NULL,
  placar_2           INT          NULL,
  penaltis_1         TINYINT      NULL,
  penaltis_2         TINYINT      NULL,
  prorrogacao        BOOLEAN      NOT NULL DEFAULT FALSE,
  status             ENUM('AGENDADO','EM_ANDAMENTO','FINALIZADO','WO') NOT NULL DEFAULT 'AGENDADO',
  vencedor_equipe_id INT          NULL,
  arbitro_1          VARCHAR(150) NULL,
  arbitro_2          VARCHAR(150) NULL,
  anotador           VARCHAR(150) NULL,
  observacoes        TEXT         NULL,
  criado_em          TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_jogos_numero (competicao_id, numero_jogo),
  KEY ix_jogos_data (data_hora),
  CONSTRAINT fk_jogos_competicao FOREIGN KEY (competicao_id)
    REFERENCES competicoes (id) ON DELETE RESTRICT,
  CONSTRAINT fk_jogos_grupo FOREIGN KEY (grupo_id, competicao_id)
    REFERENCES grupos (id, competicao_id) ON DELETE RESTRICT,
  CONSTRAINT fk_jogos_local FOREIGN KEY (local_id)
    REFERENCES locais_disputa (id) ON DELETE RESTRICT,
  CONSTRAINT fk_jogos_equipe_1 FOREIGN KEY (equipe_1_id, competicao_id)
    REFERENCES equipes (id, competicao_id) ON DELETE RESTRICT,
  CONSTRAINT fk_jogos_equipe_2 FOREIGN KEY (equipe_2_id, competicao_id)
    REFERENCES equipes (id, competicao_id) ON DELETE RESTRICT,
  CONSTRAINT fk_jogos_vencedor FOREIGN KEY (vencedor_equipe_id, competicao_id)
    REFERENCES equipes (id, competicao_id) ON DELETE RESTRICT,
  CHECK (equipe_1_id <> equipe_2_id),
  CHECK (placar_1 IS NULL OR placar_1 >= 0),
  CHECK (placar_2 IS NULL OR placar_2 >= 0),
  CHECK (numero_jogo > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Súmula — linhas por atleta (substitui a antiga "sumulas").
-- O atleta precisa estar inscrito na equipe (FK para inscricoes_atletas).
-- gols: gols (futsal/society/handebol) ou pontos (basquete).
-- amarelos: 0 a 2 (as duas caixas "A" da súmula); vermelho: caixa "V".
-- desqualificado: critério de desempate do basquete.
-- Apagar o jogo apaga a súmula junto (CASCADE).
-- ---------------------------------------------------------------------
CREATE TABLE sumula_atletas (
  id             INT       NOT NULL AUTO_INCREMENT,
  jogo_id        INT       NOT NULL,
  equipe_id      INT       NOT NULL,
  atleta_id      INT       NOT NULL,
  numero_camisa  TINYINT UNSIGNED NULL,
  presente       BOOLEAN   NOT NULL DEFAULT TRUE,
  capitao        BOOLEAN   NOT NULL DEFAULT FALSE,
  gols           SMALLINT  NOT NULL DEFAULT 0,
  amarelos       TINYINT   NOT NULL DEFAULT 0,
  vermelho       BOOLEAN   NOT NULL DEFAULT FALSE,
  desqualificado BOOLEAN   NOT NULL DEFAULT FALSE,
  criado_em      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_sumula_atleta (jogo_id, atleta_id),
  KEY ix_sumula_atleta (atleta_id),
  CONSTRAINT fk_sumula_jogo FOREIGN KEY (jogo_id)
    REFERENCES jogos (id) ON DELETE CASCADE,
  CONSTRAINT fk_sumula_inscricao FOREIGN KEY (equipe_id, atleta_id)
    REFERENCES inscricoes_atletas (equipe_id, atleta_id) ON DELETE RESTRICT,
  CHECK (gols >= 0),
  CHECK (amarelos BETWEEN 0 AND 2)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Súmula — dados por equipe no jogo (rodapé de cada equipe na folha)
-- ---------------------------------------------------------------------
CREATE TABLE sumula_equipes (
  id                INT          NOT NULL AUTO_INCREMENT,
  jogo_id           INT          NOT NULL,
  equipe_id         INT          NOT NULL,
  tecnico_nome      VARCHAR(150) NULL,
  faltas_1t         TINYINT      NOT NULL DEFAULT 0,
  faltas_2t         TINYINT      NOT NULL DEFAULT 0,
  tempo_tecnico_1t  BOOLEAN      NOT NULL DEFAULT FALSE,
  tempo_tecnico_2t  BOOLEAN      NOT NULL DEFAULT FALSE,
  PRIMARY KEY (id),
  UNIQUE KEY uq_sumula_equipe (jogo_id, equipe_id),
  CONSTRAINT fk_sumula_equipes_jogo FOREIGN KEY (jogo_id)
    REFERENCES jogos (id) ON DELETE CASCADE,
  CONSTRAINT fk_sumula_equipes_equipe FOREIGN KEY (equipe_id)
    REFERENCES equipes (id) ON DELETE RESTRICT,
  CHECK (faltas_1t >= 0),
  CHECK (faltas_2t >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Sets do vôlei (melhor de 3, set de 21 pontos)
-- ---------------------------------------------------------------------
CREATE TABLE jogo_sets (
  id         INT     NOT NULL AUTO_INCREMENT,
  jogo_id    INT     NOT NULL,
  numero_set TINYINT NOT NULL,
  pontos_1   TINYINT NOT NULL DEFAULT 0,
  pontos_2   TINYINT NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uq_jogo_sets (jogo_id, numero_set),
  CONSTRAINT fk_sets_jogo FOREIGN KEY (jogo_id)
    REFERENCES jogos (id) ON DELETE CASCADE,
  CHECK (numero_set BETWEEN 1 AND 5),
  CHECK (pontos_1 >= 0),
  CHECK (pontos_2 >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Suspensões DISCIPLINARES aplicadas pela Comissão.
-- As suspensões automáticas por cartão (vermelho = 1 jogo; 2 amarelos =
-- 1 jogo; amarelos zeram na 2ª fase) são CALCULADAS da súmula, não gravadas.
-- ---------------------------------------------------------------------
CREATE TABLE suspensoes (
  id             INT          NOT NULL AUTO_INCREMENT,
  atleta_id      INT          NOT NULL,
  jogo_origem_id INT          NULL,
  qtd_jogos      TINYINT      NULL,          -- NULL = até decisão da Comissão
  motivo         VARCHAR(255) NOT NULL,
  usuario_id     INT          NULL,
  criado_em      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  CONSTRAINT fk_suspensoes_atleta FOREIGN KEY (atleta_id)
    REFERENCES atletas (id) ON DELETE RESTRICT,
  CONSTRAINT fk_suspensoes_jogo FOREIGN KEY (jogo_origem_id)
    REFERENCES jogos (id) ON DELETE RESTRICT,
  CONSTRAINT fk_suspensoes_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuarios (id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Tabela geral
-- pontuacao_geral: pontos por colocação (1º=10, 2º=8, 3º=6, 4º=4, 5º=2).
-- colocacoes_finais: resultado final de cada competição (1º ao 5º).
--   Competição com uma só equipe inscrita não pontua (regra no código).
-- ajustes_pontos_geral: punições da Comissão (-5 a -10) com motivo.
-- ---------------------------------------------------------------------
CREATE TABLE pontuacao_geral (
  posicao TINYINT NOT NULL,
  pontos  TINYINT NOT NULL,
  PRIMARY KEY (posicao)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE colocacoes_finais (
  id            INT     NOT NULL AUTO_INCREMENT,
  competicao_id INT     NOT NULL,
  equipe_id     INT     NOT NULL,
  posicao       TINYINT NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_colocacao_posicao (competicao_id, posicao),
  UNIQUE KEY uq_colocacao_equipe (competicao_id, equipe_id),
  CONSTRAINT fk_colocacoes_equipe FOREIGN KEY (equipe_id, competicao_id)
    REFERENCES equipes (id, competicao_id) ON DELETE RESTRICT,
  CONSTRAINT fk_colocacoes_posicao FOREIGN KEY (posicao)
    REFERENCES pontuacao_geral (posicao) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE ajustes_pontos_geral (
  id         INT          NOT NULL AUTO_INCREMENT,
  escola_id  INT          NOT NULL,
  pontos     SMALLINT     NOT NULL,          -- negativo para punição
  motivo     VARCHAR(255) NOT NULL,
  usuario_id INT          NULL,
  criado_em  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  CONSTRAINT fk_ajustes_escola FOREIGN KEY (escola_id)
    REFERENCES escolas (id) ON DELETE RESTRICT,
  CONSTRAINT fk_ajustes_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuarios (id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Atletismo — RASCUNHO [PENDENTE: forma de lançar o resultado e se
-- pontua na tabela geral]. Substitui a antiga resultados_provas.
-- 1 atleta por escola, por prova, categoria e sexo (regulamento).
-- Salto: 2 tentativas, vale a melhor (resultado = melhor marca).
-- ---------------------------------------------------------------------
CREATE TABLE provas_atletismo (
  id              INT         NOT NULL AUTO_INCREMENT,
  nome            VARCHAR(80) NOT NULL,
  tipo_resultado  ENUM('TEMPO','DISTANCIA') NOT NULL,  -- tempo: menor vence; distância: maior vence
  tentativas      TINYINT     NOT NULL DEFAULT 1,
  PRIMARY KEY (id),
  UNIQUE KEY uq_provas_nome (nome)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE resultados_atletismo (
  id           INT           NOT NULL AUTO_INCREMENT,
  prova_id     INT           NOT NULL,
  categoria_id INT           NOT NULL,
  atleta_id    INT           NOT NULL,
  escola_id    INT           NOT NULL,
  sexo         ENUM('M','F') NOT NULL,
  tentativa_1  DECIMAL(7,2)  NULL,          -- segundos ou metros
  tentativa_2  DECIMAL(7,2)  NULL,
  resultado    DECIMAL(7,2)  NULL,          -- marca que conta
  colocacao    TINYINT       NULL,
  criado_em    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_atletismo_escola (prova_id, categoria_id, sexo, escola_id),
  UNIQUE KEY uq_atletismo_atleta (prova_id, categoria_id, atleta_id),
  CONSTRAINT fk_atletismo_prova FOREIGN KEY (prova_id)
    REFERENCES provas_atletismo (id) ON DELETE RESTRICT,
  CONSTRAINT fk_atletismo_categoria FOREIGN KEY (categoria_id)
    REFERENCES categorias (id) ON DELETE RESTRICT,
  -- escola e sexo precisam bater com o cadastro do atleta
  CONSTRAINT fk_atletismo_atleta FOREIGN KEY (atleta_id, escola_id, sexo)
    REFERENCES atletas (id, escola_id, sexo) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
