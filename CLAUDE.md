# System_jogos — backend do SGE Jogos Estudantis 2026

API do **Sistema de Gestão Esportiva** dos Jogos Estudantis 2026 (Barra do Choça/BA,
**23 a 28 de novembro de 2026**): escolas, atletas, competições, grupos, jogos, súmulas,
classificação, mata-mata, suspensões e tabela geral.

Frontend no repositório separado **`F:\web-jogos`** (React + Vite, Vercel).

**Leia o contexto antes de qualquer tarefa de funcionalidade.** Regras do regulamento,
modelo de dados, fatias, pendências e decisões provisórias estão lá (idêntico nos dois repositórios):
@docs/CONTEXTO_NOVO_ESCOPO.md

Outros documentos: `db/README.md` (scripts do banco e como aplicar), `docs/MIGRACAO_PRODUCAO.md`
(roteiro da virada), `db/VALIDACAO_MYSQL9.md` (validação no motor da produção),
`docs/CONFERENCIA_COMPETICOES.md` (as 50 competições), `docs/referencias/` (regulamento, tabela de
grupos, modelos de súmula).

---

## Estado atual (atualizado em 05/10/2026)

- **A produção JÁ RODA O SISTEMA NOVO desde a noite de 01/10/2026** (virada entre ~20:59 e 21:50).
  Render publica a branch **`feat/novo-escopo`** (deploy `eaa50b6`, "Fatia 10d"), a Vercel também
  (Branch Tracking de produção trocado de `main` para `feat/novo-escopo`; a `main` segue com o
  sistema antigo) e o banco é **`jogos_2026`** na Railway. Tag do estado anterior:
  `v1-antes-do-novo-escopo`.
- ⚠️ **Push na `feat/novo-escopo` = deploy em produção** (Render e Vercel publicam essa branch;
  confirmar nos painéis se o auto-deploy está ligado e, na dúvida, assuma que está). Não dê push sem
  o usuário pedir e sem testar antes no banco de dev.
- Fatias (numeração oficial na seção 9 do contexto): 1–7, 9 e 10 ✅; **8 — tabela geral e o que
  sobra** 🔄 (falta técnicos/dirigentes, se entrarem); **11 — atletismo** 📝 só planejada (padrões
  provisórios e dúvidas em aberto no contexto, nada implementado). A fatia 10 foi executada com
  desvios do roteiro (ver "Histórico") e ainda tem pendências de produção (seção abaixo).
- **Commits locais ainda NÃO publicados** (confira `git log origin/feat/novo-escopo..`): a resposta
  do chefe de 06/10/2026 às regras provisórias (abaixo). O conflito de local, o `FormAgendaJogo` e o
  local na chave do mata-mata já foram publicados em 05/10/2026.
- **Regras respondidas pelo chefe em 06/10/2026** (seção 12.1 do contexto): viraram definitivas o
  Handebol Masculino Aberto em turno único, a 2ª prorrogação e depois 7 m ou lances livres, o W.O.
  1x0 declarado só pela Comissão, as cobranças no 2º jogo do ida e volta, "uma só equipe não pontua"
  e a punição de 5 a 10 pontos. A tabela geral perdeu os três blocos (só soma geral) e o empate na
  soma divide a posição (1, 1, 3). O "melhor segundo" não descarta mais jogos: usa os critérios
  normais, com aviso quando os jogos diferem. Numa segunda resposta, no mesmo dia: a **semifinal
  com 3 grupos** tem confrontos fixos (1ºA × melhor 2º, 1ºB × 1ºC) e o **3º lugar sem semifinal**
  (melhor 2º pela campanha) vale 6 pontos, ambos definitivos. **Seguem PENDENTES, sem
  implementar:** a revanche da fase de grupos na semifinal (a chave sai, com aviso na tela), o
  empate no mata-mata do baleado (regulamento omisso: a súmula avisa e não finaliza o empate, e não
  há cobrança genérica em modalidade nenhuma), atletismo (plano na fatia 11), xadrez/dama/dominó,
  número de contas de mesa e a súmula do baleado. **Provisório, aguardando o chefe:** 4º lugar
  (quem perdeu a semifinal para o vice) e 5º lugar (a melhor campanha entre quem não chegou à semifinal,
  só em competição com mais de 4 equipes), valendo 4 e 2 pontos, com aviso na tabela geral.
- O banco antigo **`railway`** (18 tabelas do schema antigo, só dados de teste) continua parado e
  intacto no mesmo servidor, como âncora de volta atrás. **Não é o banco do sistema no ar.**

## Infraestrutura

| Peça | Onde | Detalhe |
|---|---|---|
| Frontend | **Vercel** | https://sge-frontend-seven.vercel.app — Branch Tracking de produção = `feat/novo-escopo` |
| Backend | **Render** (plano free) | https://system-jogos-estudantis.onrender.com — serviço `System_Jogos_estudantis`; publica `feat/novo-escopo`; start `npm start`; health check **`/saude`** (confirmar que ficou salvo no painel) |
| Banco produção | **Railway**, **MySQL 9.7.2** (era 9.4.0 até a Railway atualizar num "security patch"; conferido com `SELECT VERSION()` em 05/10) | **`jogos_2026`** = banco do sistema no ar (23 tabelas, schema novo); `railway` = banco antigo, parado; collation `utf8mb4_0900_ai_ci` |
| Banco dev | MariaDB 10.4 (XAMPP), porta 3306 | `jogos_estudantis_dev` |
| Validação | MySQL 8.0.46 (3307) e 9.4.0 (3308), locais | ver `db/VALIDACAO_MYSQL9.md` (feita em 9.4.0; produção hoje é 9.7.2) |

- Plano free do Render dorme: a 1ª requisição leva ~50s. Mitigação: ping de 5 em 5 min em `/saude`
  ou plano pago no mês do evento. **Hoje não há ping configurado.**
- **A Railway NÃO oferece backup neste plano** (criar backup e PITR só no Pro). Só existe um
  "Pre-Security-Patch Backup" da própria plataforma. **Backup é por `mysqldump`, por nossa conta.**
- **Crédito gratuito da Railway acaba por volta de 18/10/2026** (lembrete em 12/10, segundo o chat
  que fez a virada; confirmar em Usage/Billing). Sem plano pago, o banco pode parar e o sistema cai.
- TLS com a Railway: `DB_SSL=true` → `ssl: { rejectUnauthorized: false }` (certificado autoassinado).
- Cliente usado para acessar os bancos: **DBeaver** (conexões `localhost` e `railway`) e o `mysql.exe`
  em `C:\Users\Kevin\mysql8-3307\...` com arquivo de opções **fora do repositório**.

## Stack e estrutura

Node 20+, **Express 5**, **mysql2/promise** (pool), **jsonwebtoken** + **bcryptjs**,
`express-rate-limit` (login), `cors`, `dotenv`. **CommonJS**. Sem ORM: SQL escrito à mão, sempre com `?`.

```
server.js                 monta as rotas em /api (e /saude fora de /api)
src/config/db.js          pool MySQL (DATABASE_URL ou DB_*; dateStrings para DATE/DATETIME)
src/config/evento.js      fuso do evento (FUSO_EVENTO, padrão America/Bahia) e "agora" do evento
src/config/regrasProvisorias.js   decisões provisórias de regra (seção 12.1 do contexto)
src/config/chavesMataMata.js      cruzamentos do mata-mata por formato
src/config/folhasSumula.js        desenho da súmula por modalidade (validação + tela)
src/controllers/*         um controller por recurso
src/routes/*              um arquivo de rotas por recurso
src/middlewares/authMiddleware.js verificarToken + exigirPerfil(...perfis)
scripts/fumaca.js         teste de fumaça ponta a ponta
db/                       scripts SQL versionados e numerados
```

## API (prefixo `/api`)

Leituras são **públicas**; escrita exige token. `somenteAdmin` = `ADMIN`; `mesaOuAdmin` = `ADMIN` ou `PLACAR`.

| Recurso | Rotas |
|---|---|
| auth | `POST /login` (com rate limit) |
| usuarios | `GET/POST /`, `PUT /:id`, `PUT /:id/senha` — tudo ADMIN (não se apaga: desativa) |
| escolas | `GET /`; `POST /`, `PUT /:id` (ADMIN) |
| modalidades / competicoes | `GET /modalidades`; `GET /competicoes`, `GET /competicoes/:id` |
| equipes | `GET /`, `GET /:id/atletas-elegiveis` |
| atletas | `GET /escola/:escola_id`; `POST`, `GET/PUT/DELETE /:id` (ADMIN) |
| inscricoes | `GET /equipe/:equipe_id`; `POST /`, `DELETE /:id` (ADMIN) |
| jogos | `GET /`, `GET /:id`; `POST`, `PUT /:id`, `PUT /:id/wo`, `DELETE /:id` (ADMIN); `PUT /:id/iniciar` (mesa) |
| sumulas | `GET /:jogo_id`; `POST /` (mesa ou ADMIN) — a súmula é a **única fonte do placar** |
| classificacao | `GET /competicao/:id` (calculada dos jogos, nunca gravada) |
| matamata | `GET /competicao/:id`; `POST /competicao/:id/gerar`, `DELETE /competicao/:id/:fase` (ADMIN) |
| suspensoes | `GET /competicao/:id`, `GET /jogo/:id` (calculadas das súmulas) |
| artilharia | `GET /lideres`, `GET /competicao/:id` |
| tabela-geral | `GET /` (calculada) |
| ajustes-pontos | `GET /`; `POST /`, `DELETE /:id` (ADMIN; punição de −5 a −10 com motivo) |
| locais / etapas-ensino / dashboard | `GET /` |
| campeonato | `DELETE /reset` (ADMIN; apaga só o que o evento produz) |
| `/saude` | fora de `/api`; 200 com banco de pé, **503** sem banco |

Erro sempre como `res.status(x).json({ erro: '...' })`; o frontend mostra `erro` direto ao usuário.

## Banco de dados

- **23 tabelas** do schema novo (`db/01_schema.sql`): `configuracao_evento`, `usuarios`, `etapas_ensino`,
  `escolas`, `escola_apelidos`, `modalidades`, `categorias`, `competicoes`, `grupos`, `equipes`,
  `atletas`, `inscricoes_atletas`, `locais_disputa`, `jogos`, `sumula_atletas`, `sumula_equipes`,
  `jogo_sets`, `suspensoes`, `pontuacao_geral`, `colocacoes_finais`, `ajustes_pontos_geral`,
  `provas_atletismo`, `resultados_atletismo`. 33 chaves estrangeiras, 16 `CHECK`.
- Ordem dos scripts: `00_apagar_tudo` → `01_schema` → `02_carga_base` → `03_importar_grupos` →
  `04_locais` → `05_faltas_basquete` → `06_ajustes_regras_provisorios`.
  ⚠️ `00` **apaga tudo**: confira o banco de destino antes de rodar.
- Usuários **não** vêm na carga: hash com `bcryptjs` na hora (ver `db/README.md`).
- Scripts **sem `COLLATE`**: usam a padrão do servidor. Produção (`utf8mb4_0900_ai_ci`) é
  **insensível a acento** ("JOSÉ" = "JOSE" nos índices únicos); o MariaDB do dev **não** é.
- `DATE`/`DATETIME` são **hora de parede** e viajam como texto (`dateStrings`); `TIMESTAMP`
  (`criado_em`) é instante e vem como `Date`. Para "agora", use `agoraNoFusoDoEvento()`, nunca `NOW()`.
- MySQL de produção roda em **modo estrito**: `INSERT` sem coluna `NOT NULL` sem default falha
  (`ER_NO_DEFAULT_FOR_FIELD`, 1364). O que passa no MariaDB local pode falhar lá.

## Comandos

- `npm run dev` — nodemon na porta 3000. `npm start` — produção.
- `npm run fumaca` — com a API no ar, monta uma competição inteira pelas rotas, confere cada passo e
  apaga o que criou. **Só roda em banco com "dev" no nome** (a trava lê o alvo real, inclusive
  `DATABASE_URL`). **Rode antes de dar uma fatia por pronta.** Não há testes de unidade.

## Variáveis de ambiente (ver `.env.example`)

`PORT` (Render injeta; não definir na nuvem) · `DATABASE_URL` **ou** `DB_HOST/DB_PORT/DB_USER/DB_PASSWORD/DB_NAME`
· `DB_SSL` · `DB_POOL_LIMIT` · **`JWT_SECRET`** (obrigatória; sem ela não sobe) · **`CORS_ORIGIN`**
(obrigatória com `NODE_ENV=production`; vírgula separa domínios) · `FUSO_EVENTO` · `NODE_ENV`.

## Regras de trabalho

- **Não leia nem exiba `.env`.** Nunca comite segredos (nem host/senha da Railway).
- Não faça commit/push sem o usuário pedir. Trabalhe na branch `feat/novo-escopo`.
- **Não mexa na produção** (Railway/Render/Vercel) sem ordem explícita: nada de script, migração,
  deploy ou comando apontado para lá. Teste sempre no banco de desenvolvimento primeiro.
- **`jogos_2026` é o banco do sistema no ar. NUNCA rode `00_apagar_tudo.sql` nele** (nem qualquer
  script de escrita) sem ordem explícita e sem dump conferido antes. Na conexão `railway` do DBeaver,
  só `SELECT`/`SHOW` por padrão; confira o banco ativo antes de executar qualquer coisa.
- Mudança de banco é **sempre script SQL versionado e numerado** em `db/` (o próximo é `07`),
  nunca alteração manual.
- Dúvida de regra do campeonato: **pare e pergunte**. Itens **[PENDENTE]** (seção 12 do contexto) não
  se implementam por conta própria. Decisão provisória mora em `src/config/` e na seção 12.1, nunca
  copiada dentro de um controller.
- **Fatias:** só a tabela da seção 9 do contexto numera. Cite número e nome ("fatia 8 — tabela geral
  e o que sobra") e atualize o estado dela no mesmo commit que conclui a fatia.
- Nomes, comentários e mensagens em **português**.
- Várias escritas relacionadas = **transação** (`getConnection` + `beginTransaction`), com `release`
  no `finally`.
- Classificação, suspensões por cartão, colocações e tabela geral são **calculadas**, nunca gravadas.
- Todo `catch` de controller faz `console.error('<contexto>:', erro)` antes de responder 500: é o que
  aparece nos logs do Render.
- Perfis: `ADMIN` (cadastra, pune, gerencia usuários) e `PLACAR` (mesa: só inicia jogo e lança súmula).
  `exigirPerfil` relê o perfil do banco a cada escrita.

## Como depurar um erro em produção

1. DevTools → **Rede** → requisição com erro → abas **Requisição** e **Resposta**.
2. 500 = erro no backend. Render → serviço → **Logs** (não "Deploys"), em tempo real, e reproduza o
   erro. O log traz `code`, `sqlMessage` e o SQL executado.
3. Colunas obrigatórias sem default (causa de erro 1364):
   ```sql
   SELECT TABLE_NAME, COLUMN_NAME, COLUMN_TYPE FROM information_schema.COLUMNS
   WHERE TABLE_SCHEMA = DATABASE() AND IS_NULLABLE = 'NO' AND COLUMN_DEFAULT IS NULL
     AND EXTRA NOT LIKE '%auto_increment%' AND TABLE_NAME NOT LIKE '%\_bkp'
   ORDER BY TABLE_NAME;
   ```
4. No DBeaver, execute **um comando por vez** (Ctrl+Enter), nunca o script inteiro (Alt+X).

## Histórico de produção

**01/10/2026, noite — virada para o sistema novo (fatia 10).** Feita pelo usuário no DBeaver, guiada
por outro chat. Passos: dump do banco antigo (`C:\Users\Kevin\dump-railway-202610012059.sql`, 17.618
bytes, completo), registro da versão (9.4.0 na época), criação do `jogos_2026`, scripts `01`–`06`
(o `00` foi pulado porque o banco estava vazio; o `06` falhou na primeira tentativa por ter sido
rodado no banco errado, `railway`, sem escrever nada, e foi refeito no `jogos_2026`), conferência
das contagens, **1 usuário ADMIN** (SemedAdmin, id 1) e, no Render, troca de `DB_NAME` para
`jogos_2026`, novo `JWT_SECRET` e health check `/saude`. Só se testou `/saude` (status ok, banco ok).
**Desvios do roteiro `docs/MIGRACAO_PRODUCAO.md`:** (1) a Vercel publicava a `main` (frontend
antigo), então o Branch Tracking de produção foi trocado para `feat/novo-escopo` e feito Redeploy,
ao contrário do que o roteiro dizia; (2) só 1 ADMIN criado e **nenhuma conta de mesa (PLACAR)**;
(3) **o `jogos_2026` nunca foi copiado em backup**.

**05/10/2026 — conferência (esta sessão).** `SELECT VERSION()` na produção = **9.7.2**. O
`jogos_2026` tem as 23 tabelas, a carga base (18 escolas, 16 apelidos, 50 competições, 77 grupos, 240
equipes, 4 locais, 3 provas) e **dados de uso criados depois da virada**: 15 atletas, 24 inscrições,
17 jogos, 41 `sumula_atletas`, 32 `sumula_equipes`, 2 usuários. **Ainda não confirmado se são
testes** (o usuário deve dizer). Dump do banco antigo refeito em `F:\backups\producao_2026-10-05.sql`.

**Set/2026 — incidente do sistema antigo (banco `railway`).** Banco reimportado sem estrutura: perdeu
`PRIMARY KEY`, `AUTO_INCREMENT` e `DEFAULT`. Sintoma: "Falha ao salvar a súmula", 500 por
`Field 'criado_em' doesn't have a default value` no `INSERT INTO sumulas`. Corrigido à mão pelo
DBeaver (PK + `AUTO_INCREMENT` e `DEFAULT CURRENT_TIMESTAMP` em `sumulas.criado_em`,
`alunos.criado_em`, `usuarios.criado_em`, `equipes.data_cadastro`). Esse schema foi aposentado na
virada; a lição valeu: o banco novo nasce dos scripts `00`–`06` (DDL completo), nunca de import só
de dados.

## Pendências de produção (05/10/2026)

1. **Backup do `jogos_2026`:** feito em 05/10, repetir antes do evento e depois de cada dia de
   jogos. Comando: `mysqldump --single-transaction --routines --triggers --events
   --set-gtid-purged=OFF --databases jogos_2026 --result-file=...` com `--defaults-extra-file` fora
   dos repositórios; conferir tamanho, `-- Dump completed` e a contagem de `CREATE TABLE` (23);
   guardar uma cópia fora do disco `F:`.
2. **Crédito da Railway acaba ~18/10**: decidir plano pago (o Pro também libera backups).
3. **Senha do root da Railway foi exposta em print**: ordem segura = criar usuário só da aplicação
   (permissão apenas em `jogos_2026`), trocar no Render, testar, e só então trocar a senha do root.
4. **Confirmar no painel do Render** (valores cobertos): se a conexão usa `DATABASE_URL` ou `DB_*`
   (o `db.js` dá prioridade à `DATABASE_URL`, e trocar só `DB_NAME` não teria efeito), qual usuário do
   banco ela usa, e se `NODE_ENV=production`, `CORS_ORIGIN`, `JWT_SECRET` novo e `FUSO_EVENTO`
   estão definidos. Conferir também se o health check `/saude` foi salvo.
5. Conferir no `jogos_2026`: coluna `sumula_atletas.faltas` (script 05), `competicoes` id 24
   (script 06: 1 grupo, 2 classificados, 0 melhores segundos, próxima fase FINAL, turno único),
   `SELECT COUNT(*) FROM configuracao_evento` (esperado 1) e a lista de usuários (sem a coluna `senha`).
6. **Contas:** já existem **1 ADMIN** (criado na virada) e **1 conta PLACAR** (mesa), criada depois
   pela tela `/usuarios`. Faltam os ADMIN **Felipe** e **Aelson** e as **demais contas de mesa**.
   Criar pela tela `/usuarios`.
7. **Ping em `/saude`** (5 em 5 min) ou plano pago do Render.
8. O banco antigo `railway` ainda tem a conta de teste `admin@sge.com` (senha padrão antiga): remover o banco
   (ou a conta) quando a volta atrás deixar de ser necessária.
9. Atualizar `db/README.md` e `db/VALIDACAO_MYSQL9.md` (versão 9.7.2) e o `docs/MIGRACAO_PRODUCAO.md`
   (desvio da Vercel e a execução real).

<!-- deepspace:workspace-instructions:begin -->
Time preparado para entregar engenharia de produto com planejamento, implementação, revisão e validação independentes.
<!-- deepspace:workspace-instructions:end -->
