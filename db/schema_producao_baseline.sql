-- REGISTRO do schema de produção (Railway) em 28/09/2026, exportado do DBeaver.
-- Só referência: NÃO execute. Todas as tabelas continham apenas dados de teste.

CREATE DATABASE `railway` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci */ /*!80016 DEFAULT ENCRYPTION='N' */;

CREATE TABLE `alunos` (
  `id` int NOT NULL AUTO_INCREMENT,
  `nome` varchar(100) DEFAULT NULL,
  `rg` varchar(20) DEFAULT NULL,
  `data_nascimento` date NOT NULL,
  `numero_camisa` int DEFAULT NULL,
  `escola_id` int DEFAULT NULL,
  `criado_em` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `atletas` (
  `id` int NOT NULL AUTO_INCREMENT,
  `escola_id` int DEFAULT NULL,
  `nome` varchar(150) DEFAULT NULL,
  `data_nascimento` date NOT NULL,
  `rg_ou_matricula` varchar(50) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=10 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `categorias` (
  `id` int NOT NULL AUTO_INCREMENT,
  `nome` varchar(50) DEFAULT NULL,
  `ano_base` int DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `classificacao` (
  `id` int NOT NULL AUTO_INCREMENT,
  `escola_id` int DEFAULT NULL,
  `grupo` varchar(1) DEFAULT NULL,
  `pontos` int DEFAULT NULL,
  `jogos` int DEFAULT NULL,
  `vitorias` int DEFAULT NULL,
  `empates` int DEFAULT NULL,
  `derrotas` int DEFAULT NULL,
  `gols_pro` int DEFAULT NULL,
  `gols_contra` int DEFAULT NULL,
  `saldo_gols` int DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `diretores` (
  `id` int NOT NULL AUTO_INCREMENT,
  `escola_id` int DEFAULT NULL,
  `nome` varchar(150) DEFAULT NULL,
  `cpf` varchar(15) DEFAULT NULL,
  `email` varchar(100) DEFAULT NULL,
  `senha` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `equipes` (
  `id` int NOT NULL AUTO_INCREMENT,
  `nome` varchar(100) DEFAULT NULL,
  `representante` varchar(100) DEFAULT NULL,
  `contato` varchar(20) DEFAULT NULL,
  `data_cadastro` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `escolas` (
  `id` int NOT NULL AUTO_INCREMENT,
  `nome` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
  `cnpj` varchar(20) DEFAULT NULL,
  `etapa_ensino_id` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_escolas_nome` (`nome`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `etapas_ensino` (
  `id` int NOT NULL AUTO_INCREMENT,
  `nome` varchar(100) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `grupos` (
  `id` int NOT NULL AUTO_INCREMENT,
  `modalidade_id` int DEFAULT NULL,
  `categoria_id` int DEFAULT NULL,
  `nome` varchar(10) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `grupos_escolas` (
  `grupo_id` int DEFAULT NULL,
  `escola_id` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `inscricoes_atletas` (
  `id` int NOT NULL AUTO_INCREMENT,
  `atleta_id` int DEFAULT NULL,
  `modalidade_id` int DEFAULT NULL,
  `categoria_id` int DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `jogos` (
  `id` int NOT NULL AUTO_INCREMENT,
  `numero_jogo` int DEFAULT NULL,
  `grupo_id` int DEFAULT NULL,
  `fase` varchar(50) DEFAULT NULL,
  `local_id` int DEFAULT NULL,
  `data_hora` datetime NOT NULL,
  `escola_1_id` int DEFAULT NULL,
  `escola_2_id` int DEFAULT NULL,
  `placar_escola_1` int DEFAULT NULL,
  `placar_escola_2` int DEFAULT NULL,
  `status` enum('AGENDADO','SÚMULA_PREENCHIDA','FINALIZADO') DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=10 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `locais_disputa` (
  `id` int NOT NULL AUTO_INCREMENT,
  `nome` varchar(100) DEFAULT NULL,
  `endereco` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `modalidades` (
  `id` int NOT NULL AUTO_INCREMENT,
  `nome` varchar(100) DEFAULT NULL,
  `tipo` enum('COLETIVO','INDIVIDUAL','INTERDISCIPLINAR') DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `resultados_provas` (
  `id` int NOT NULL AUTO_INCREMENT,
  `modalidade_id` int DEFAULT NULL,
  `categoria_id` int DEFAULT NULL,
  `atleta_id` int DEFAULT NULL,
  `escola_id` int DEFAULT NULL,
  `colocacao` int DEFAULT NULL,
  `pontos_gerados` int DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `sumulas` (
  `id` int NOT NULL AUTO_INCREMENT,
  `jogo_id` int DEFAULT NULL,
  `atleta_id` int DEFAULT NULL,
  `gols` int DEFAULT NULL,
  `cartoes_amarelos` int DEFAULT NULL,
  `cartao_vermelho` tinyint(1) DEFAULT NULL,
  `criado_em` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=13 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `sumulas_jogadores` (
  `id` int NOT NULL AUTO_INCREMENT,
  `jogo_id` int DEFAULT NULL,
  `atleta_id` int DEFAULT NULL,
  `numero_camisa` int DEFAULT NULL,
  `presente` tinyint(1) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `usuarios` (
  `id` int NOT NULL AUTO_INCREMENT,
  `nome` varchar(120) DEFAULT NULL,
  `email` varchar(160) DEFAULT NULL,
  `senha` varchar(255) DEFAULT NULL,
  `criado_em` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;