# Banco de dados — SGE Jogos Estudantis 2026

**Recomendado: MySQL 8.0.16 ou superior**, a mesma família da produção (Railway). As regras `CHECK` só são aplicadas a partir do MySQL 8.0.16 (no MySQL 5.7 elas são ignoradas em silêncio). MariaDB 10.4+ também roda os scripts (o XAMPP traz 10.4).

Os scripts **não fixam collation**: usam a padrão do servidor (no MySQL 8, `utf8mb4_0900_ai_ci`, igual à produção). Para saber a versão do seu servidor, rode `SELECT VERSION();`.

## Arquivos

| Arquivo | O que faz |
|---|---|
| `00_apagar_tudo.sql` | **Apaga todas as tabelas e dados** (antigas e novas). |
| `01_schema.sql` | Cria as 23 tabelas do schema novo, com chaves estrangeiras e restrições. |
| `02_carga_base.sql` | Dados fixos: configuração do evento, etapas de ensino, categorias, modalidades, pontuação da tabela geral e provas de atletismo. |
| `03_importar_grupos.sql` | Gerado da tabela de grupos: 18 escolas (+ grafias alternativas), 50 competições com a regra de classificação, 77 grupos e 240 equipes. Confira antes em `docs/CONFERENCIA_COMPETICOES.md`. |
| `schema_producao_baseline.sql` | Registro de como a produção estava em 28/09/2026. **Não execute.** |

Escolas, competições, grupos e equipes **não** estão na carga base: vêm de `03_importar_grupos.sql` (a partir de `docs/referencias/tabela_de_grupos.md`).

## Como aplicar

**Sempre primeiro num banco de desenvolvimento** (MySQL local ou um banco de teste), nunca direto na produção.

1. Crie um banco vazio, por exemplo: `CREATE DATABASE jogos_estudantis_dev CHARACTER SET utf8mb4;` (sem `COLLATE`).
2. Rode, nesta ordem: `00_apagar_tudo.sql` → `01_schema.sql` → `02_carga_base.sql` → `03_importar_grupos.sql`.
3. Confira: `SHOW TABLES;` deve listar 23 tabelas.

Na produção (Railway), só quando o código novo estiver pronto: **faça backup**, depois rode os mesmos três arquivos. Hoje a produção só tem dados de teste, então pode ser recriada do zero.

## Criar os usuários

A carga base não cria usuários, para não versionar senha. Gere o hash da senha com o `bcryptjs` do próprio projeto:

```bash
node -e "console.log(require('bcryptjs').hashSync('SENHA_AQUI', 10))"
```

E insira (um por administrador; perfil `PLACAR` para quem só lança súmula):

```sql
INSERT INTO usuarios (nome, email, senha, perfil)
VALUES ('Felipe', 'email@exemplo.com', '<hash gerado>', 'ADMIN');
```

## Regras de integridade

O próprio banco garante (chaves compostas):
- as equipes e o grupo de um jogo pertencem à competição do jogo;
- o grupo de uma equipe pertence à competição da equipe;
- o atleta inscrito numa equipe é da mesma escola da equipe;
- só entra na súmula quem está inscrito na equipe;
- RG único, e-mail de usuário único, número da camisa único na equipe, número do jogo único por competição.

Fica no código do backend (dentro de transação):
- máximo de 14 atletas por equipe (`modalidades.max_atletas`); abaixo do mínimo, só aviso;
- idade: `YEAR(data_nascimento) >= configuracao_evento.ano - categorias.idade_maxima` (Aberto sem limite);
- sexo do atleta × gênero da competição (`MISTO` aceita os dois);
- no máximo 2 modalidades do tipo `COLETIVO` por atleta;
- a equipe lançada na súmula é uma das duas do jogo;
- suspensões por cartão (calculadas a partir de `sumula_atletas`).

## Renumerar jogos ao excluir

A ordem ascendente evita conflito com o índice único durante a atualização:

```sql
DELETE FROM jogos WHERE id = ?;
UPDATE jogos SET numero_jogo = numero_jogo - 1
WHERE competicao_id = ? AND numero_jogo > ?
ORDER BY numero_jogo ASC;
```

## Nota sobre a validação

Este schema foi conferido por script (tabelas, colunas, tipos e alvos das chaves estrangeiras) e **executado com sucesso no banco de desenvolvimento `jogos_estudantis_dev` em 28/09/2026**, com a carga base e a importação dos grupos.

**Ainda não foi aplicado na produção** (Railway), que segue com o schema antigo do `schema_producao_baseline.sql`. A migração da produção só acontece quando o código novo estiver pronto, com backup antes.
