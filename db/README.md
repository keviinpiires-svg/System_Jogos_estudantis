# Banco de dados — SGE Jogos Estudantis 2026

**A produção (Railway) roda MySQL 9.7.2** (conferido em 05/10/2026). Os scripts foram validados numa
instância local de **MySQL 9.4.0** — ver `VALIDACAO_MYSQL9.md` — e rodaram na produção na virada de
01/10/2026. Rodam igualmente em MySQL 8.0.16+ (conferido no 8.0.46: o schema sai idêntico)
e em MariaDB 10.4+, que é o que o XAMPP traz. Abaixo do MySQL 8.0.16 **não**: as regras `CHECK` são
ignoradas em silêncio.

Os scripts **não fixam collation**: usam a padrão do servidor. Em MySQL 8 e 9 isso dá
`utf8mb4_0900_ai_ci`, igual à produção — que é **insensível a acento**, então "JOSÉ DIAS" e
"JOSE DIAS" contam como o mesmo nome nos índices únicos. O MariaDB do XAMPP usa
`utf8mb4_general_ci`, que **não** é: um banco de desenvolvimento em MariaDB aceita um par que a
produção recusa. Para saber a versão do seu servidor, rode `SELECT VERSION();`.

## Arquivos

| Arquivo | O que faz |
|---|---|
| `00_apagar_tudo.sql` | **Apaga todas as tabelas e dados** (antigas e novas). |
| `01_schema.sql` | Cria as 23 tabelas do schema novo, com chaves estrangeiras e restrições. |
| `02_carga_base.sql` | Dados fixos: configuração do evento, etapas de ensino, categorias, modalidades, pontuação da tabela geral e provas de atletismo. |
| `03_importar_grupos.sql` | Gerado da tabela de grupos: 18 escolas (+ grafias alternativas), 50 competições com a regra de classificação, 77 grupos e 240 equipes. Confira antes em `docs/CONFERENCIA_COMPETICOES.md`. |
| `04_locais.sql` | Locais de disputa (ginásios, quadras e campos). Rode uma vez, depois do 03. |
| `05_faltas_basquete.sql` | Migração: coluna `faltas` (0 a 5) em `sumula_atletas`, para as faltas individuais do basquete. Aplicada no `jogos_estudantis_dev` em 29/09/2026 e na produção (`jogos_2026`) na virada de 01/10/2026. Num banco novo entra na sequência, logo depois do `04` — conferido. |
| `06_ajustes_regras_provisorios.sql` | Ajusta a linha do Handebol Masculino Aberto (turno único, 1º e 2º à final). Aplicado no desenvolvimento e na produção (virada de 01/10/2026). |
| `07_baleados_por_equipe.sql` | Migração: coluna `baleados` (0 a 10, com `CHECK`) em `sumula_equipes`, para o contador de baleadas por equipe da súmula oficial do baleado. **Aplicada no `jogos_estudantis_dev` em 06/10/2026; falta na produção.** ⚠️ Precisa rodar no `jogos_2026` **antes** do deploy do backend que lê a coluna: sem ela, a leitura de qualquer súmula falha. Num banco novo entra depois do `06`. |
| `schema_producao_baseline.sql` | Registro de como a produção estava em 28/09/2026. **Não execute.** |

Escolas, competições, grupos e equipes **não** estão na carga base: vêm de `03_importar_grupos.sql` (a partir de `docs/referencias/tabela_de_grupos.md`).

## Como aplicar

**Sempre primeiro num banco de desenvolvimento** (MySQL local ou um banco de teste), nunca direto na produção.

1. Crie um banco vazio, por exemplo: `CREATE DATABASE jogos_estudantis_dev CHARACTER SET utf8mb4;` (sem `COLLATE`).
2. Rode, nesta ordem: `00_apagar_tudo.sql` → `01_schema.sql` → `02_carga_base.sql` → `03_importar_grupos.sql`.
3. Confira: `SHOW TABLES;` deve listar 23 tabelas.

Na produção (Railway), o schema novo já está no banco `jogos_2026` desde 01/10/2026 (ver `docs/MIGRACAO_PRODUCAO.md`). **A Railway não tem backup automático neste plano**: antes de qualquer script lá, faça um `mysqldump` e confira o arquivo.

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
- no máximo **2 competições coletivas** por atleta — conta competições de modalidade `COLETIVO`, não modalidades: Futsal Sub 13 e Futsal Sub 15 são duas. Atletismo é `INDIVIDUAL` e não entra na conta;
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

Em **01/10/2026** (fatia 10) a sequência inteira `00`–`06` foi rodada **do zero em MySQL 9.4.0** (a Railway roda MySQL 9.7.2), com todas as conferências de contagem, as restrições testadas uma a uma e o `npm run fumaca` passando. O relatório está em **`VALIDACAO_MYSQL9.md`**. Foi a primeira vez que o `05` aplicou sobre um `01` recém-criado, e funcionou.

**Aplicado na produção (Railway) em 01/10/2026**, na fatia 10: o banco novo `jogos_2026` nasceu **ao lado** do antigo, que segue parado com o schema do `schema_producao_baseline.sql`. Rodaram os scripts `01`–`06`; o `00` foi pulado porque o banco estava vazio. **Não há backup automático** na Railway neste plano; os dumps são manuais e ficam fora do repositório.
