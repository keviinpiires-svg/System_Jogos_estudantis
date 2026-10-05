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

- **Código novo** na branch **`feat/novo-escopo`** (nos dois repositórios). Tag do estado anterior:
  `v1-antes-do-novo-escopo`.
- Fatias (numeração oficial na seção 9 do contexto): 1–7 e 9 ✅ feitas;
  **8 — tabela geral e o que sobra** 🔄 (falta atletismo e, se entrarem, técnicos/dirigentes);
  **10 — migração da produção** 🔄 (roteiro pronto em `docs/MIGRACAO_PRODUCAO.md`, **falta o usuário executar**).
- **A produção ainda roda o sistema ANTIGO**: código antigo no Render, frontend antigo na Vercel e
  **schema antigo** no banco `railway` (registro em `db/schema_producao_baseline.sql`). O código novo
  **não funciona** com esse banco. A virada cria o banco novo `jogos_2026` **ao lado** do antigo.
- Ao corrigir um bug "da produção", confirme primeiro se ele é do sistema antigo (que vai ser
  substituído) ou do código novo.

## Infraestrutura

| Peça | Onde | Detalhe |
|---|---|---|
| Frontend | **Vercel** | https://sge-frontend-seven.vercel.app |
| Backend | **Render** (plano free) | https://system-jogos-estudantis.onrender.com — serviço `System_Jogos_estudantis`; start `npm start`; health check **`/saude`** |
| Banco produção | **Railway**, **MySQL 9.4.0** | banco atual `railway` (schema antigo); novo `jogos_2026` (a criar na fatia 10); collation `utf8mb4_0900_ai_ci` |
| Banco dev | MariaDB 10.4 (XAMPP), porta 3306 | `jogos_estudantis_dev` |
| Validação | MySQL 8.0.46 (3307) e 9.4.0 (3308), locais | ver `db/VALIDACAO_MYSQL9.md` |

- Plano free do Render dorme: a 1ª requisição leva ~50s. Mitigação: ping de 5 em 5 min em `/saude`
  ou plano pago no mês do evento.
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
src/config/blocosTabelaGeral.js   categoria → bloco da tabela geral
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

## Histórico de incidentes da produção (sistema antigo)

**Set–out/2026 — banco `railway` reimportado sem estrutura.** Depois do registro de 28/09
(`schema_producao_baseline.sql`, que tinha PK, `AUTO_INCREMENT` e defaults), o banco foi reimportado
e perdeu `PRIMARY KEY`, `AUTO_INCREMENT` e `DEFAULT`. Sintoma: "Falha ao salvar a súmula" — 500 por
`Field 'criado_em' doesn't have a default value` no `INSERT INTO sumulas`. Corrigido **à mão, pelo
DBeaver** (exceção à regra de script versionado, porque é o schema antigo que será aposentado):
PK + `AUTO_INCREMENT` no `id` de todas as tabelas, e
`DEFAULT CURRENT_TIMESTAMP` em `sumulas.criado_em`, `alunos.criado_em`, `usuarios.criado_em` e
`equipes.data_cadastro`. Restam sem default, de propósito: `alunos.data_nascimento`,
`atletas.data_nascimento`, `escolas.nome`, `jogos.data_hora`.

**Lição para a fatia 10:** o banco novo nasce dos scripts `00`–`06` (DDL completo), não de import de
dados. Backup é `mysqldump` com estrutura + dados, conferido antes de seguir.

<!-- deepspace:workspace-instructions:begin -->
Time preparado para entregar engenharia de produto com planejamento, implementação, revisão e validação independentes.
<!-- deepspace:workspace-instructions:end -->
