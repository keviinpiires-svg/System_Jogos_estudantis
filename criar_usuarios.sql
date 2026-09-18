-- ---------------------------------------------------------------------
-- Autenticação do SGE: tabela de usuários + administrador padrão
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS usuarios (
  id    INT AUTO_INCREMENT PRIMARY KEY,
  nome  VARCHAR(120)  NOT NULL,
  email VARCHAR(160)  NOT NULL UNIQUE,
  senha VARCHAR(255)  NOT NULL,
  criado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- Administrador padrão: admin@sge.com / admin123
-- A senha abaixo é o hash bcrypt de "admin123" (custo 10). Nunca guarde a senha em texto puro.
INSERT INTO usuarios (nome, email, senha)
VALUES ('Administrador', 'admin@sge.com', '$2b$10$vtqgVVqK2YU.awRv0cRs1eLJ21UNAq8CALcX9rqcaqFWtohe7cOkq')
ON DUPLICATE KEY UPDATE email = email;
