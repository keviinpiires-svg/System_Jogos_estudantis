# Migração da produção — roteiro de execução

**Fatia 10.** Este é um roteiro **para você executar passo a passo**, não um comando automático:
foi decisão de 01/10/2026. Nenhum script deste repositório encosta na produção sozinho.

Leia inteiro antes de começar. Os passos 1 a 6 são reversíveis sem esforço; o 7 em diante mexe no
que está no ar.

---

## O que esta migração faz

A produção (Railway) ainda roda o **schema antigo**, registrado em `db/schema_producao_baseline.sql`.
O código novo não funciona com ele.

A virada **não apaga o banco antigo**. Cria um banco **novo, ao lado**, chamado `jogos_2026`, roda os
scripts nele e aponta o Render para o banco novo trocando uma variável de ambiente.

O banco antigo fica parado, intacto. É isso que torna a volta atrás barata: trocar a `DATABASE_URL`
de volta, em vez de restaurar um dump sob pressão. O backup continua sendo feito — ele só deixa de
ser a única rede.

---

## Antes de começar

**Precisa estar verdade:**

- [ ] Você tem acesso ao painel da **Railway**, do **Render** e da **Vercel**.
- [ ] Os scripts `00`–`06` foram validados no motor da produção. ✅ feito em 01/10/2026 — ver
      `db/VALIDACAO_MYSQL9.md` (MySQL 9.4.0, teste de fumaça com 21 conferências e 0 falhas).
- [ ] O código novo está na branch `feat/novo-escopo`, nos dois repositórios, e você decidiu que vai
      ao ar **sem o atletismo** (decisão de 01/10/2026; não há competição de atletismo cadastrada).
- [ ] Você tem as senhas que quer dar aos 3 administradores e às 4 contas de mesa. Escolha agora,
      fora deste documento.
- [ ] Você sabe a **URL exata do frontend na Vercel** — ela vira o `CORS_ORIGIN`, caractere por caractere.

**Quando fazer:** com folga, **semanas antes de 23/11**, nunca na véspera. Veja "Ponto sem retorno".

**Cliente MySQL local.** Os comandos abaixo usam o cliente instalado para a validação, que conversa
com o MySQL 9 da Railway sem problema:

    C:\Users\Kevin\mysql8-3307\mysql-8.0.46-winx64\bin\mysql.exe
    C:\Users\Kevin\mysql8-3307\mysql-8.0.46-winx64\bin\mysqldump.exe

**Nunca ponha a senha na linha de comando** — ela fica visível na lista de processos e no histórico
do terminal. Crie um arquivo de opções **fora dos repositórios**, por exemplo
`C:\Users\Kevin\railway.cnf`:

    [client]
    user=root
    password=A_SENHA_DA_RAILWAY
    host=HOST.proxy.rlwy.net
    port=PORTA
    protocol=TCP
    default-character-set=utf8mb4
    ssl-mode=REQUIRED

e passe `--defaults-extra-file=C:\Users\Kevin\railway.cnf` em todos os comandos.
**Apague esse arquivo no fim.** Os dados de conexão saem da aba Variables do serviço MySQL na Railway.

---

## Passo 1 — Backup (antes de qualquer outra coisa)

Duas camadas. Faça as duas.

**1.1 — Snapshot pelo painel da Railway.** No serviço MySQL, use o backup/snapshot da própria
plataforma. É o caminho mais rápido de volta se algo der muito errado.

**1.2 — Dump para a sua máquina:**

    mysqldump.exe --defaults-extra-file=C:\Users\Kevin\railway.cnf ^
      --single-transaction --routines --triggers --events ^
      --databases NOME_DO_BANCO_ANTIGO > F:\backups\producao_2026-11-XX.sql

**1.3 — Confira o dump. Um backup que ninguém abriu não é backup.**

- o arquivo tem tamanho plausível (não zero, não 2 KB);
- a última linha diz `-- Dump completed`;
- abrindo o arquivo, dá para ver o `CREATE TABLE` das tabelas que você espera.

## Passo 2 — Registrar o estado atual

É contra isto que você compara se precisar voltar. Salve a saída num arquivo:

    SELECT VERSION();
    SELECT @@character_set_server, @@collation_server;
    SHOW DATABASES;
    SHOW TABLES;
    SELECT TABLE_NAME, TABLE_ROWS FROM information_schema.tables
     WHERE table_schema = DATABASE() ORDER BY TABLE_NAME;

Anote também, do painel do Render, **o valor atual de cada variável de ambiente** e **qual deploy
está no ar** (o identificador do commit). Você vai querer os dois na volta atrás.

## Passo 3 — Criar o banco novo, ao lado

    CREATE DATABASE jogos_2026 CHARACTER SET utf8mb4;

**Sem `COLLATE`** — os scripts usam a padrão do servidor de propósito, que no MySQL 9 é
`utf8mb4_0900_ai_ci`, a mesma em que foram validados.

Se a Railway recusar a criação de um segundo banco (por plano ou permissão), **pare aqui** e me
avise: a estratégia muda para a destrutiva, e aí o roteiro passa a depender do backup do passo 1.

Confira que nasceu vazio e que o banco antigo continua lá, com `SHOW DATABASES;`.

## Passo 4 — Rodar os scripts no banco novo

> **Este é o passo perigoso.** O `00_apagar_tudo.sql` apaga tabelas. Num banco recém-criado ele é
> inofensivo (só emite avisos de "tabela não existe"), mas **apontado para o banco errado ele apaga
> a produção**. Antes de cada comando, confira que está escrito `-D jogos_2026`.

Um de cada vez, lendo a saída de cada um:

    mysql.exe --defaults-extra-file=C:\Users\Kevin\railway.cnf -D jogos_2026 -e "source F:\System_jogos\db\00_apagar_tudo.sql"
    mysql.exe --defaults-extra-file=C:\Users\Kevin\railway.cnf -D jogos_2026 -e "source F:\System_jogos\db\01_schema.sql"
    mysql.exe --defaults-extra-file=C:\Users\Kevin\railway.cnf -D jogos_2026 -e "source F:\System_jogos\db\02_carga_base.sql"
    mysql.exe --defaults-extra-file=C:\Users\Kevin\railway.cnf -D jogos_2026 -e "source F:\System_jogos\db\03_importar_grupos.sql"
    mysql.exe --defaults-extra-file=C:\Users\Kevin\railway.cnf -D jogos_2026 -e "source F:\System_jogos\db\04_locais.sql"
    mysql.exe --defaults-extra-file=C:\Users\Kevin\railway.cnf -D jogos_2026 -e "source F:\System_jogos\db\05_faltas_basquete.sql"
    mysql.exe --defaults-extra-file=C:\Users\Kevin\railway.cnf -D jogos_2026 -e "source F:\System_jogos\db\06_ajustes_regras_provisorios.sql"

Se algum falhar, **pare**. Não siga para o próximo. Nada foi ao ar ainda: o banco antigo segue
servindo o sistema atual.

## Passo 5 — Conferir a carga

    SELECT 'tabelas' AS conferencia, COUNT(*) AS valor, 23 AS esperado FROM information_schema.tables WHERE table_schema=DATABASE()
    UNION ALL SELECT 'chaves estrangeiras', COUNT(*), 33 FROM information_schema.referential_constraints WHERE constraint_schema=DATABASE()
    UNION ALL SELECT 'restricoes CHECK', COUNT(*), 16 FROM information_schema.check_constraints WHERE constraint_schema=DATABASE()
    UNION ALL SELECT 'escolas', COUNT(*), 18 FROM escolas
    UNION ALL SELECT 'apelidos', COUNT(*), 16 FROM escola_apelidos
    UNION ALL SELECT 'competicoes', COUNT(*), 50 FROM competicoes
    UNION ALL SELECT 'grupos', COUNT(*), 77 FROM grupos
    UNION ALL SELECT 'equipes', COUNT(*), 240 FROM equipes
    UNION ALL SELECT 'locais', COUNT(*), 4 FROM locais_disputa
    UNION ALL SELECT 'provas atletismo', COUNT(*), 3 FROM provas_atletismo
    UNION ALL SELECT 'usuarios (ainda 0)', COUNT(*), 0 FROM usuarios
    UNION ALL SELECT 'ano do evento', ano, 2026 FROM configuracao_evento
    UNION ALL SELECT 'tabelas fora da collation', COUNT(*), 0 FROM information_schema.tables WHERE table_schema=DATABASE() AND table_collation <> 'utf8mb4_0900_ai_ci';

**Todas as linhas têm de bater.** Se alguma não bater, pare.

## Passo 6 — Criar os usuários

A carga base **não cria usuário nenhum**, de propósito: nenhuma senha entra em arquivo versionado.

Gere um hash por pessoa, com o `bcryptjs` do próprio projeto:

    cd F:\System_jogos
    node -e "console.log(require('bcryptjs').hashSync(process.argv[1], 10))" "A_SENHA_ESCOLHIDA"

**Administradores** (Felipe, Kevin e Aelson) — podem tudo:

    INSERT INTO usuarios (nome, email, senha, perfil) VALUES
      ('Felipe', 'felipe@exemplo.com', '<hash>', 'ADMIN'),
      ('Kevin',  'kevin@exemplo.com',  '<hash>', 'ADMIN'),
      ('Aelson', 'aelson@exemplo.com', '<hash>', 'ADMIN');

**Contas de mesa**, uma por local de disputa — só lançam súmula e placar, não cadastram nem punem.
Os nomes são os mesmos dos locais em `04_locais.sql`:

    INSERT INTO usuarios (nome, email, senha, perfil) VALUES
      ('Mesa - Ginásio de Esportes',        'mesa.ginasio@exemplo.com', '<hash>', 'PLACAR'),
      ('Mesa - Quadra do Maria da Glória',  'mesa.gloria@exemplo.com',  '<hash>', 'PLACAR'),
      ('Mesa - Quadra do CEJA',             'mesa.ceja@exemplo.com',    '<hash>', 'PLACAR'),
      ('Mesa - Campo Society Arena Social', 'mesa.society@exemplo.com', '<hash>', 'PLACAR');

Depois da primeira conta ADMIN existir, o resto pode ser criado pela tela `/usuarios`, sem SQL.

Confira que nenhuma senha ficou em texto puro:

    SELECT nome, email, perfil, ativo, LEFT(senha, 4) AS inicio_do_hash FROM usuarios;

Todo `inicio_do_hash` deve ser `$2a$` ou `$2b$`. Se algum não for, apague a linha e refaça.

## Passo 7 — Render (backend)

No serviço do backend, aba **Environment**:

| Variável | Valor | Observação |
|---|---|---|
| `NODE_ENV` | `production` | liga a validação estrita e torna o `CORS_ORIGIN` obrigatório |
| `DATABASE_URL` | URL do banco **`jogos_2026`** | **o passo da virada**; confira que o caminho termina em `/jogos_2026` |
| `DB_SSL` | `true` | banco em nuvem |
| `JWT_SECRET` | **um valor novo** | ver abaixo |
| `CORS_ORIGIN` | a URL exata do frontend na Vercel | sem ela o servidor **não sobe** |
| `FUSO_EVENTO` | `America/Bahia` | é o padrão, mas explícito evita surpresa |
| `PORT` | — | **não definir**: o Render injeta |

**Gere um `JWT_SECRET` novo**, não reaproveite o atual:

    node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"

Trocar o segredo invalida todos os tokens antigos — que é exatamente o que se quer numa virada de
schema: ninguém continua logado com uma sessão do sistema velho.

**Configurações do serviço:**

- Build: `npm ci` · Start: `npm start` · Node 20+
- **Health Check Path: `/saude`** — a rota consulta o banco e devolve **503** se ele não responder,
  então um deploy que suba sem alcançar o MySQL é recusado em vez de entrar no ar quebrado.
- **Plano:** no gratuito o serviço dorme, e a primeira requisição do dia leva perto de um minuto —
  na mesa isso parece "o sistema travou". Use plano pago no mês do evento, ou mantenha o ping do passo 9.

Publique o código novo (branch `feat/novo-escopo`) e acompanhe o log da subida.

## Passo 8 — Vercel (frontend)

O endereço da API está **versionado** em `web-jogos/.env.production`:

    VITE_API_URL=https://system-jogos-estudantis.onrender.com

**Se o serviço do Render continuar o mesmo, não há nada a mudar aqui.** Só publique a branch nova.

Dois cuidados:

- `VITE_API_URL` é resolvida **no build**, não em tempo de execução. Trocar o endereço exige **build
  novo**, não só redeploy de cache.
- **Não crie a mesma variável no painel da Vercel.** Ela ganharia do arquivo versionado, e passariam
  a existir duas fontes para o mesmo valor, uma delas invisível no código. Deixe só o arquivo.

O `vercel.json` já tem o rewrite de SPA. Nada a ajustar.

## Passo 9 — Manter o serviço acordado

Se o Render ficar no plano gratuito, configure um ping de **5 em 5 minutos** para:

    https://system-jogos-estudantis.onrender.com/saude

Serve qualquer monitor externo (UptimeRobot, cron-job.org). A rota é pública, barata e não devolve
dado nenhum do evento — só diz se o serviço está de pé.

## Passo 10 — Conferir com o sistema no ar

Sem lançar nada de verdade:

- [ ] `/saude` responde **200**.
- [ ] Login como **ADMIN** entra e mostra o menu de cadastro.
- [ ] Login como **mesa (PLACAR)** entra e **não** vê as telas de cadastro nem de usuários.
- [ ] O menu lateral lista as modalidades e abre uma competição.
- [ ] A competição mostra os grupos e as equipes importadas.
- [ ] `/tabela-geral` abre, vazia, sem erro.
- [ ] Deslogado, o sistema mostra a tabela e a classificação, e **não** vaza RG de atleta.

Se tudo isso passa, a virada está feita.

---

## Plano de volta atrás

**A ordem é a inversa da subida.** O código novo só funciona com o banco novo: os dois voltam juntos
ou nenhum volta.

**Nível 1 — Frontend (segundos).** Vercel → Deployments → o deploy anterior → **Instant Rollback**.

**Nível 2 — Backend (um a dois minutos).** Render → Deploys → **Rollback** para o deploy anterior.
Se o rollback não estiver disponível, publique a tag `v1-antes-do-novo-escopo`, que existe nos dois
repositórios e marca o estado anterior a toda esta reescrita.

**Nível 3 — Banco (segundos).** Volte a `DATABASE_URL` do Render para o **banco antigo**, aquele cujo
valor você anotou no passo 2, e redeploy. O banco antigo nunca foi tocado: não há o que restaurar.

**Nível 4 — Só se o banco antigo tiver sido danificado**, o que este roteiro evita: restaure o dump
do passo 1.2, ou o snapshot da Railway, e confira as contagens contra o que você registrou no passo 2.

**O que NÃO fazer na volta atrás:** apagar o `jogos_2026`. Parado ele não atrapalha nada, e se o
problema for passageiro você reaproveita tudo em vez de rodar os sete scripts de novo.

## Ponto sem retorno

Enquanto ninguém lançou **súmula de jogo real** no sistema novo, voltar não custa dado nenhum.

A partir da primeira súmula de verdade, o banco novo tem informação que o antigo não tem, e voltar
significa **perdê-la**. Daí em diante, problema se resolve corrigindo para frente, não voltando.

Por isso a virada é com folga: dias de uso real antes de 23/11, para que qualquer defeito apareça
enquanto voltar atrás ainda é barato.

---

## O que este roteiro não cobre

- **Atletismo** — não entra nesta subida (decisão de 01/10/2026). Não há competição de atletismo
  cadastrada; as 3 provas vêm na carga base e ficam paradas.
- **Domínio próprio** — por ora fica na URL da Vercel. Se mudar, o `CORS_ORIGIN` do Render e o
  `.env.production` do frontend mudam junto.
- **Importar atletas** — escolas, competições, grupos e equipes vêm nos scripts. Os **atletas** são
  cadastrados pela tela, por escola, como sempre foi o plano (seção 4, item 11 do contexto).
