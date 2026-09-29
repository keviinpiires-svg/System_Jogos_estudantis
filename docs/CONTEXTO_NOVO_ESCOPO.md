# Contexto do novo escopo — SGE Jogos Estudantis 2026

> Documento de contexto para o Claude (e para quem for mexer no código). Foi montado a partir de uma
> análise do projeto **como estava** + o PDF de ajustes + o regulamento + a tabela de grupos.
> Onde algo **não está confirmado** com o usuário, está marcado como **[PENDENTE]**. Não trate
> pendência como regra: pergunte ao usuário antes de implementar.
>
> Este arquivo é idêntico nos dois repositórios (`System_jogos` = backend, `web-jogos` = frontend).
> Fontes originais em texto: `docs/referencias/` (regulamento, tabela de grupos, imagem da súmula de futsal).

---

## 1. Objetivo e prazo

Sistema de gestão dos **Jogos Estudantis 2026** (Barra do Choça): escolas, atletas, grupos, jogos,
súmulas, classificação e tabela geral.

- **Data do evento: 23 a 28 de novembro de 2026.** O documento foi escrito em 28/09/2026, ~8 semanas antes.
- Prioridade: ter **futsal funcionando de ponta a ponta cedo** e usá-lo de molde para as demais modalidades.

## 2. Repositórios e estado ANTES da mudança

**Backend `System_jogos`** — Node 20+, Express 5, MySQL (`mysql2`), JWT (`jsonwebtoken`) + `bcryptjs`, CommonJS.
`server.js` monta as rotas em `/api`. Estrutura: `src/config/db.js`, `src/controllers/*`, `src/routes/*`,
`src/middlewares/authMiddleware.js` (`verificarToken`). Sem testes. **Não há arquivo com o schema do banco.**

**Frontend `web-jogos`** — React 19 + Vite 8, `react-router-dom` 7, `axios`, `react-to-print`, deploy na Vercel.
Navbar no topo, páginas em `src/pages`, chamadas à API em `src/services/*` (um arquivo por recurso),
sessão JWT em `localStorage` (`services/token.js`), `AuthContext`, `RotaPrivada`. CSS único em `src/index.css`.

Endpoints existentes (antes da mudança): `POST /api/login`; `escolas` (GET, POST, PUT); `atletas` (POST, PUT, DELETE,
GET por equipe); `jogos` (agendar, listar, buscar, finalizar, excluir); `sumulas` (registrar, buscar por jogo,
status de suspensão); `classificacao`; `artilharia`; `grupos` (listar, salvar distribuição); `matamata`
(listar, gerar semifinais, gerar final); `dashboard`; `campeonato/reset`; `locais`; `etapas-ensino`; e, soltos no
`server.js`: `diretores`, `inscricoes`, `sorteio/*`.

Convenções do código (mantenha): nomes em **português**; respostas de erro `{ erro: '...' }`; rotas protegidas
com `verificarToken`; operações com várias escritas em **transação** (`getConnection` + `beginTransaction`);
classificação **calculada a partir dos jogos** (não guardada); mensagens de erro do backend chegam ao usuário via
`error.mensagem` (interceptor do axios).

## 3. Decisão de abordagem

**Evoluir o projeto atual** (não recomeçar): auth, conexão com banco, CORS, `.env`, deploy, `api.js`, `token.js`, CSS,
cadastro de escola e impressão continuam. **O que muda é o domínio**: tudo passa a pertencer a uma *competição*
(modalidade × categoria × gênero). Isso significa **banco novo (schema versionado) + reescrita dos controllers/telas
de regras de campeonato**, na mesma base de código, em **branch nova** (com tag do estado anterior).

## 4. Escopo novo (pedido do usuário)

Fonte: PDF "Ajustes para o sistema" + respostas do usuário.

1. **Menu lateral com as modalidades.** Ao clicar numa modalidade abre um submenu com as categorias (sub). Dentro da
   categoria: tabela de jogos, iniciar jogo, lançar/verificar/**imprimir súmula**.
2. **Modalidades:** Futsal, Futebol Society, Handebol, Baleado (= "queimada/queimado"), Vôlei, Basquete e **Atletismo**.
   Xadrez, Dama e Dominó (regulamento) — **[PENDENTE]** se entram.
3. **Categorias: vale o regulamento** (não o PDF): Sub 7, 8, 9, 11, 13, 15, 17 e Aberto — mas cada modalidade só tem as
   que aparecem na tabela de grupos. Categoria vale pelo **ano de nascimento** (ver seção 5).
4. **Gênero:** masculino/feminino; **Vôlei Sub 15/17 é MISTO**. O **atleta precisa ter o sexo cadastrado**.
5. **Idade:** atleta não joga em categoria abaixo da sua idade (regra do ano de nascimento; usar atleta acima do limite é infração).
6. **Perfis:** administradores (Felipe, Kevin e Aelson) e um perfil **apenas para placar** (só lança placar/súmula).
7. **Tabela geral** dividida em **anos iniciais / anos finais / ensino médio**, pontuada pelas colocações por modalidade
   (10/8/6/4/2). Havia pedido de "seletor na hora de cadastrar a escola". **[PENDENTE]** se a divisão é pela etapa da
   escola ou pela categoria (a JOSE DIAS joga do Sub 7 ao Sub 17, então dividir só por escola não funciona bem).
8. **Súmulas:** ajustar para impressão e preenchimento conforme a ocasião. O modelo de **futsal** (imagem em
   `docs/referencias/sumula_futsal_modelo.png`) serve para **Futsal e Futebol Society**. Para as outras modalidades, criar
   layouts no mesmo estilo.
9. **Atleta em no máximo 2 competições coletivas**; **RG obrigatório** no cadastro do atleta.
10. **Renumerar os jogos** quando um for excluído (sem buracos na numeração).
11. **Cadastro:** escolas e grupos **já existem em documento** (tabela de grupos). O que falta é **cadastrar os
    atletas nas suas escolas, dentro das modalidades em que a escola joga**. O sorteio de grupos **deixa de existir**.
12. **Elenco: máximo de 14 atletas** por equipe; pode ter menos (mínimo vira **aviso**, não bloqueio).

## 5. Regras do regulamento que afetam o sistema

(Texto completo em `docs/referencias/regulamento_2026.md`. Abaixo, só o que vira regra de código.)

**Categorias por ano de nascimento (2026):** Sub 7=2019, Sub 8=2018, Sub 9=2017, Sub 11=2015, Sub 13=2013,
Sub 15=2011, Sub 17=2009, Aberto=sem limite. Ou seja, `Sub N` → nascido em `2026 − N` **ou depois**. Guardar o "ano do
campeonato" como configuração.

**Elenco/inscrição:** RG obrigatório (cópia da identidade). Mínimo 8 e máximo 14 em Futsal, Vôlei, Basquete e Society;
mínimo 10 e máximo 14 em Handebol e Baleado (**decisão do usuário: limite 14, mínimo só aviso**). Até 10 dirigentes por
escola. Professor/monitor não pode ser atleta. Cada atleta: no máximo **2 competições coletivas** por atleta (competições de modalidade `COLETIVO`: Futsal Sub 13 e Futsal Sub 15 contam como duas; atletismo não conta).

**Tempos de jogo:** Futsal/Handebol — Sub 7 a Sub 13: 2×12 min (intervalo 5); Sub 15, Sub 17 e Aberto: 2×15 min;
**final** de Sub 15/17/Aberto: 2×20 min. Society Sub 13 e 17: 2×20 min. Baleado: 4 áreas, 15 min, vence quem
baleia todos; se acabar o tempo, vence quem eliminou mais. Vôlei: melhor de 3 sets (2 vencedores), set de 21 pontos.

**Vôlei misto:** mínimo 2 atletas do sexo feminino em quadra o tempo todo. Vôlei Aberto é masculino/feminino.

**Empate a partir da 2ª fase:** Futsal e Society → **pênaltis 3x1x1**; Basquete e Handebol → **prorrogação**.

**Cartões e suspensão (Futsal e Society):** 2 amarelos = 1 jogo de suspensão; **amarelos zerados na 2ª fase**.
Qualquer expulsão = 1 jogo de suspensão automática + julgamento posterior. Suspensão disciplinar escolar após 13/07
impede a participação. Comissão Disciplinar pode aplicar perda de **5 a 10 pontos** na soma geral.

**W.O.:** só a Comissão Organizadora declara. Tolerância de 15 min; o time ausente é considerado perdedor.
Camisas devem ser numeradas e apresentadas antes da partida.

**Desempate na classificação** (ordem importa):
- **Futsal, Handebol, Futebol Society:** saldo de gols → confronto direto → mais vitórias na fase → mais gols marcados
  → menos vermelhos → menos amarelos → sorteio.
- **Basquete:** confronto direto → saldo de pontos entre empatadas → mais pontos marcados → menos desqualificações → sorteio.
- **Vôlei:** saldo de sets entre empatadas → confronto direto → saldo de pontos → menos vermelhos → menos amarelos.
- **Baleado:** confronto direto → mais vitórias → menos vermelhos → menos amarelos → sorteio.

**Pontuação do campeão geral (por modalidade, igual para masculino e feminino):** 1º=10, 2º=8, 3º=6, 4º=4, 5º=2.
Modalidade com **uma só inscrição não conta pontos nem premia**.

**3º lugar:** **não existe jogo de 3º lugar.** O 3º é a equipe que perdeu a semifinal **para o campeão**. Se não houver
semifinal, vale a classificação da fase classificatória. (Como saem 4º e 5º: **[PENDENTE]**.)

**Atletismo:** Sub 8 e Sub 9: só corrida de 50 m. Sub 11/13/15/17: salto e corrida de 100 m. Masculino e feminino.
**1 atleta por escola, por categoria, gênero e prova.** Salto: 2 tentativas, vale a melhor. (Como o resultado é lançado:
**[PENDENTE]**.)

## 6. Tabela de grupos (`docs/referencias/tabela_de_grupos.md`)

- **50 competições** no total (modalidade × categoria × gênero). Aprox. **18 escolas**, escritas de muitas formas
  (`JOSE DIAS`/`J. DIAS`; `ADELIETA RAMALHO`/`ADELIETA`/`ADELIATA`; `MARLENA`/`MARLENE SANTANA`/`M. SANTANA`;
  `EMILIANO`/`EMILIANO ZAPATA`; `TEODULO`/`TODULO LEITE`; `FRANCISCO AMORIM`/`F. AMORIM`; `MARIA`/`MARIA DA GLORIA`/
  `MERIA DA GLORIA`; `MANOEL`/`MANOEL RAMOS`; `JOSENILDO`/`JOSENILDO LEITE`; `V. LIMA`/`VITORIA LIMA`; `PORTAL`/
  `PORTAL DO SABER`; e siglas `ACM`, `CEBC`, `CEBN`, `CEJA`, `CETI`, `COVENIADA`, `LUCIA ROCHA`). **A importação precisa de
  lista oficial de escolas + apelidos**, senão nascem duplicatas.
- **O formato de disputa varia por competição** (não há um mata-mata único):
  - grupo único, os 2 primeiros vão **direto à final**;
  - dois grupos, 2 primeiros de cada → **semifinal**; ou só o 1º de cada → **final**;
  - três grupos: 3 primeiros + **"segundo mais bem colocado"** → semifinal;
  - grupo único de 2 ou 3 equipes: **"melhor de dois jogos"**.
  Cada competição precisa guardar sua regra (nº de grupos, quantos classificam, se há semifinal, se é melhor de dois jogos).
- Interpretação usada: a frase de classificação vale para a **tabela logo abaixo**. **[CONFIRMAR]**.
- **Ambiguidades [PENDENTE]:** (a) "melhor de dois jogos" com 3 equipes (todos contra todos, ida e volta?);
  (b) critério para o "segundo mais bem colocado" com grupos de tamanhos diferentes; (c) Vôlei Sub 17 Misto (2 grupos):
  "dois de cada grupo para a Final" = 4 finalistas? seria semifinal?; (d) Handebol Masculino Sub 17 tem dois grupos sem
  rótulo A/B.

## 7. Súmula (modelo de futsal — vale para Futsal e Society)

> **Todas as modalidades:** `docs/referencias/sumulas_modelos.md` descreve as quatro folhas oficiais (futsal/society, handebol,
> basquete e vôlei), com os PDFs ao lado e as lacunas do schema para atendê-las (falta de faltas individuais no basquete,
> contadores até 7, 12 linhas no papel contra 14 do regulamento). O Baleado não tem modelo em papel.

Imagem: `docs/referencias/sumula_futsal_modelo.png`. Folha A4 retrato, duas equipes empilhadas. Campos:
- **Cabeçalho:** Campeonato, Chave, Rodada, Ginásio, Cidade, Estado, Categoria, Data, Horário; Árbitro 1, Árbitro 2, Anotador;
  caixas de placar entre EQUIPE A e EQUIPE B.
- **Por equipe:** linhas de atletas com **Cartões (amarelo, amarelo, vermelho)**, **Nº** da camisa, **Atleta**, **grade de Gols**,
  **Capitão**; rodapé com **Faltas acumuladas** (1º T: 1–5; 2º T: 1–5), **Tempo técnico** (1º T, 2º T) e **Técnico**.
  O modelo tem 12 linhas; o limite de elenco do sistema é **14** → usar 14 linhas.
- Linha separadora "fim da 1ª fase".
- Precisa haver **duas versões de impressão:** súmula **em branco** (cabeçalho e elenco preenchidos, para levar à quadra) e
  súmula **preenchida** (gols, cartões, faltas já lançados).
- **[PENDENTE]** se cada gol é uma marca em caixa (fiel ao papel) ou um campo numérico com a grade só na impressão; se faltas/tempo
  técnico são lançados no sistema ou ficam em branco na impressão; se campeonato/cidade/estado/árbitros são fixos do evento ou por jogo.

## 8. Modelo de dados (DEFINIDO — ver `System_jogos/db/`)

> O schema novo está em **`System_jogos/db/01_schema.sql`** (23 tabelas, 33 chaves estrangeiras), com
> `00_apagar_tudo.sql`, `02_carga_base.sql` e `db/README.md` (como aplicar, criar usuários, regras).
> O schema antigo de produção ficou registrado em `db/schema_producao_baseline.sql` (não executar).
> **Executado no banco de desenvolvimento `jogos_estudantis_dev` em 28/09/2026**, com a carga base e a importação dos grupos.
> A produção ainda roda o schema antigo: a migração só acontece quando o código novo estiver pronto.

**Decisões do usuário (28/09):** todos os dados atuais são de teste e podem ser apagados; o banco é recriado do zero;
chaves estrangeiras em tudo; `rg_ou_matricula` vira **`rg`** (obrigatório e único — todos os alunos têm RG, e a idade é
conferida pela data de nascimento).

**O que o schema antigo tinha de errado:** nenhuma chave estrangeira; quase nenhum índice único (só `uq_escolas_nome`);
tabelas órfãs (`alunos`, `classificacao`, `diretores`, `sumulas_jogadores`, `equipes` sem ligação com nada);
`status` do jogo com valor acentuado e sem W.O. Tudo isso foi descartado.

**Tabelas novas (resumo):**
- `configuracao_evento` (ano, cidade, estado, datas — o ano entra na regra de idade).
- `usuarios` (+ `perfil` ADMIN/PLACAR, e-mail único).
- `etapas_ensino` (3 blocos), `escolas` (+ `escola_apelidos` para as grafias da tabela de grupos).
- `modalidades` (+ `slug` para as rotas, `tipo` COLETIVO/INDIVIDUAL, `tipo_placar` GOLS/PONTOS/SETS/ELIMINADOS/MARCA, mín./máx. de atletas).
- `categorias` (+ `idade_maxima`; NULL = Aberto; `etapa_ensino_id` opcional).
- `competicoes` (modalidade × categoria × gênero; regra de disputa como **dado**: grupos, classificados, melhores segundos,
  próxima fase, turno/ida e volta, tempos, pontos por vitória/empate/derrota).
- `grupos` (por competição), `equipes` (escola na competição, com grupo e técnico).
- `atletas` (+ `sexo`, `rg` único), `inscricoes_atletas` (atleta ↔ equipe, número da camisa; mesma escola garantida pelo banco).
- `jogos` (por competição; equipes em vez de escolas; rodada, árbitros, anotador, pênaltis, prorrogação, W.O., vencedor;
  `numero_jogo` único por competição).
- `sumula_atletas` (substitui `sumulas`: gols/pontos, 0–2 amarelos, vermelho, capitão, presença, desqualificação),
  `sumula_equipes` (técnico, faltas 1º/2º T, tempo técnico), `jogo_sets` (vôlei).
- `suspensoes` (só as disciplinares; as de cartão são calculadas), `pontuacao_geral` (10/8/6/4/2), `colocacoes_finais`,
  `ajustes_pontos_geral` (punições com motivo).
- `provas_atletismo` e `resultados_atletismo` (rascunho — forma de lançar ainda **[PENDENTE]**).

**Validações que ficam no código** (em transação): máx. 14 por equipe; idade pela categoria; sexo × gênero (MISTO aceita os
dois); máx. 2 competições coletivas; equipe da súmula é uma das duas do jogo; suspensões por cartão.

**Pressupostos até o usuário confirmar:** numeração de jogos **por competição**; fase de grupos **3/1/0** (guardado por competição,
fácil de mudar).

## 9. Fatias (lista única — fonte de verdade da ordem)

> **Esta tabela é a única numeração válida das fatias.** Ao citar uma fatia em conversa, commit, comentário de código
> ou em qualquer outra seção deste documento, use o número e o nome daqui ("fatia 5 — futsal completo"). Se a ordem
> mudar, **mude primeiro aqui** e depois ajuste as referências. Não numere fatias de cabeça.

| # | Fatia | Estado | O que inclui |
|---|---|---|---|
| 1 | Preparar | ✅ feito | Tag do estado anterior e branch `feat/novo-escopo` nos dois repositórios. |
| 2 | Limpeza | ✅ feito (28/09/2026) | Código morto removido, rotas soltas do `server.js` viraram rota + controller, reset adaptado. Ver seção 10. |
| 3 | Modelo de dados novo | ✅ feito | Schema em `db/`, aplicado no `jogos_estudantis_dev` com carga base e importação dos grupos; as 50 competições foram conferidas (`docs/CONFERENCIA_COMPETICOES.md`). **2 pontos de regra seguem abertos** (seção 6): "melhor de dois jogos" com 3 equipes e o critério do "segundo mais bem colocado". Falta a migração da produção. |
| 4 | Atleta e inscrição | ✅ feito (28/09/2026) | Sexo, RG obrigatório e único, ano de nascimento × categoria, máximo de 14, limite de 2 competições coletivas, número da camisa. Cadastro de atleta e inscrição são só de ADMIN. |
| 5 | Futsal completo | ✅ feito (29/09/2026) | Ponta a ponta, em cinco sub-fatias (abaixo). **Modelo de súmula: `sumula_futsal_modelo.pdf`** — 14 linhas por equipe, cartões (A, A, V), nº, atleta, grade de gols, capitão; rodapé com faltas 1º/2º T (1 a 5), tempo técnico e técnico. A mesma folha vale para o **Futebol Society** (só muda o título). |
| 5a | ↳ Menu e competições | ✅ feito | Menu lateral por modalidade, lista de competições e o detalhe da competição. `GET /api/modalidades` e `/api/competicoes`. |
| 5b | ↳ Jogos por competição | ✅ feito | Controller de jogos no schema novo, `numero_jogo` por competição, renumeração ao excluir, tabela de jogos na tela. |
| 5c | ↳ Súmula e W.O. | ✅ feito | Súmula como única fonte do placar (em branco e preenchida, mesma rota), impressão da folha e `PUT /api/jogos/:id/wo` só de ADMIN. |
| 5d | ↳ Classificação e perfil PLACAR | ✅ feito (29/09/2026) | `GET /api/classificacao/competicao/:id` calcula a tabela a partir dos jogos da fase de grupos, com o desempate da modalidade (GOLS, PONTOS, SETS e ELIMINADOS) e marca quem ficou empatado até o sorteio. A tela da competição mostra a tabela por grupo, destaca quem avança e **avisa na própria tela os 2 casos de regra em aberto** (melhor segundo com grupos de tamanhos diferentes; "melhor de dois jogos" com mais de duas equipes). No frontend, `isAdmin`/`isPlacar`/`podeLancar` vêm do perfil e a `RotaPrivada` aceita a lista de perfis: a mesa entra na súmula, não no cadastro. |
| 5e | ↳ Suspensão por cartões | ✅ feito (29/09/2026) | Calculada das súmulas, nunca gravada: 2 amarelos = 1 jogo, amarelos zerados na 2ª fase, expulsão = 1 jogo, e a suspensão é cumprida no primeiro jogo seguinte em que o atleta não entra na súmula. As disciplinares da tabela `suspensoes` somam. `GET /api/suspensoes/competicao/:id` e `/jogo/:id`; a tela da competição lista cartões e pendências, e o preenchimento da súmula avisa quem não pode entrar. **Só futsal e society têm a regra escrita** — nas outras modalidades a tela mostra os cartões com aviso e não declara ninguém suspenso (pendência 13). |
| 6 | Demais modalidades coletivas | ⬜ a fazer | Handebol, Society e Basquete (reaproveitam o futsal); depois Vôlei (sets) e Baleado (eliminados). **Modelos de súmula** (`docs/referencias/sumulas_modelos.md`): **toda folha impressa tem 14 linhas por equipe** (decisão de 29/09/2026), inclusive basquete e vôlei, cujos papéis trazem 12 — o elenco do regulamento é 14. **Society e Handebol usam exatamente a folha do futsal**, só muda o título; Basquete tem folha própria (faltas individuais 1–5, grade de pontos, faltas acumulativas 1–7); Vôlei tem folha própria (controle de sets, sem gols nem cartões). **Baleado não tem modelo em papel — [PENDENTE]**. |
| 7 | Mata-mata configurável | ⬜ a fazer | Formato por competição, 3º lugar calculado, pênaltis e prorrogação. |
| 8 | Tabela geral e o que sobra | ⬜ a fazer | Pontuação 10/8/6/4/2 e ajuste de pontos, Atletismo, renumeração de jogos, técnicos e dirigentes (se entrarem). |

## 10. Limpeza do código antigo

~~**Seguro remover**~~ (feito): `main.js`; `src/pages/Home.jsx`; README padrão do Vite (reescrito);
`alunoController.js` + `alunoRoutes.js`; `criar_grupos.sql`; rotas `/api/sorteio/*` e `/api/diretores` do `server.js`;
painel de sorteio de `FaseGrupos.jsx` (e `salvarDistribuicao` em `services/grupos.js`);
`limpar_escolas_duplicadas.sql` → arquivado em `db/arquivo/`.

~~**Reorganizar**~~ (feito): `/api/locais`, `/api/etapas-ensino` e `/api/inscricoes` saíram do `server.js` para rota + controller
(`localRoutes`/`localController`, `etapaEnsinoRoutes`/`etapaEnsinoController`, `inscricaoRoutes`/`inscricaoController`).
O `server.js` não fala mais direto com o banco. A inscrição foi adaptada ao schema novo (equipe + atleta + camisa, escola vinda
do atleta); as regras de elenco (14, idade, sexo, 2 competições coletivas) entraram na **fatia 4 — atleta e inscrição**.

**Decidido com o usuário (28/09/2026):**
- **Reiniciar campeonato:** mantido e **adaptado ao schema novo**. Apaga só o que o evento produz — `sumula_atletas`,
  `sumula_equipes`, `jogo_sets`, `suspensoes`, `colocacoes_finais`, `ajustes_pontos_geral`, `resultados_atletismo` e `jogos`.
  **Preserva** a base importada (escolas, competições, grupos, equipes), atletas, inscrições e cadastros fixos: nada precisa ser reimportado.
- **`PUT /api/jogos/finalizar/:id`:** fica **só para W.O.** e casos excepcionais, com motivo obrigatório; o placar normal passa a sair
  da súmula. **A reescrita acontece na fatia 5 — futsal completo**, junto com o controller de jogos do schema novo — hoje a rota ainda é a antiga.
- **`verificarSuspensao`:** **refeito na fatia 5 — futsal completo**, conforme o regulamento (2 amarelos = 1 jogo, amarelos zerados na 2ª fase,
  expulsão = 1 jogo). Até lá continua o cálculo antigo, que **não** segue o regulamento.

**Já sabemos que muda:** o `TERCEIRO_LUGAR` esperado pelo front **não deve ser criado** (o 3º é calculado); `FaseGrupos` tem A/B fixos; o
mata-mata fixo (1ºA×2ºB) cobre só um dos formatos.

## 11. Problemas conhecidos no código atual

- ~~Todo usuário logado é tratado como admin~~ — resolvido: perfis ADMIN e PLACAR no backend e no frontend (fatia 5d).
- `POST /api/diretores` grava senha em **texto puro** (será removido).
- CORS aberto quando `CORS_ORIGIN` está vazio; sem rate limit no login; JWT em `localStorage`.
- Admin padrão `admin@sge.com` / `admin123` está no SQL versionado (`criar_usuarios.sql`) — trocar antes de produção.
- Validação fraca: jogo com a mesma escola nos dois lados, placar negativo, escola fora do grupo; gerar semifinais sem a fase de grupos completa.
- Duas fontes de verdade para o placar (súmula × finalizar manual).
- `excluirJogo` chama `getConnection()` fora do `try`.
- Fuso: datas de jogo tratadas como UTC no front (`timeZone: 'UTC'`) e comparadas com `NOW()` no backend — cuidado ao mexer.
- Nenhum teste automatizado.

## 12. Pendências (perguntas em aberto para o usuário)

1. **Tabela geral em 3 blocos:** por etapa da escola ou por categoria? Se por categoria, quais subs entram em cada bloco?
2. ~~**Limite de 2 modalidades coletivas**~~ — **resolvido (28/09/2026):** o limite conta **competições**, não modalidades. Futsal Sub 13 + Futsal Sub 15 são **duas**. Contam as inscrições em competições de modalidade `COLETIVO`; o atletismo (`INDIVIDUAL`) não entra.
3. **Atletismo:** como o resultado é lançado (tempo/distância, 2 tentativas)? Xadrez, Dama e Dominó entram?
4. **Fase de grupos:** pontos por vitória e empate? (o regulamento cita uma "tabela" de sistema de disputa que não veio.)
5. **4º e 5º lugar:** como saem?
6. Ambiguidades da tabela de grupos (seção 6) e a interpretação "frase vale para a tabela abaixo".
7. **Súmula:** gols por clique em caixa ou campo numérico? Faltas/tempo técnico lançados ou em branco? Cabeçalho fixo ou por jogo?
8. **Gênero do Baleado** (o regulamento não diz; a tabela de grupos tem masculino e feminino) e **como o placar é lançado** (eliminados).
9. **Numeração dos jogos:** por competição (assumido no schema) ou global?
10. ~~Schema do banco~~ — **resolvido** (ver seção 8).
11. ~~Limpeza: destino do reset de campeonato, do `finalizar` manual e da suspensão~~ — **resolvido** (ver seção 10).
12. **Súmula do Baleado:** não há folha oficial entre os modelos recebidos. Criar uma no estilo das outras, e definir o que a linha do atleta registra (eliminados?).
13. **Suspensão por cartões nas outras modalidades:** o regulamento só escreve a regra para futsal e society. Handebol, basquete, vôlei e baleado usam cartões — vale a mesma regra (2 amarelos = 1 jogo, expulsão = 1 jogo)? Hoje o sistema mostra os cartões dessas modalidades mas não declara ninguém suspenso.

## 13. Como trabalhar neste projeto

- **Código é escrito aqui (VS Code)**; **dúvidas de regra/negócio são tiradas com o usuário** (numa conversa à parte). Diante de uma
  **[PENDENTE]**, pare e pergunte — não invente regra do regulamento.
- Não leia nem imprima os arquivos `.env`. Nunca comite segredos.
- Não faça commit/push sem o usuário pedir. Trabalhe na branch nova.
- Mudanças de banco: sempre por **script SQL versionado** (crie `db/schema.sql` e `db/migracoes/`), nunca só à mão.
- Antes de mexer em regra de classificação, releia a seção 5 (desempate por modalidade).
- **Numeração das fatias: só a tabela da seção 9 vale.** Ao concluir uma fatia, atualize o estado dela ali no mesmo commit.
- Prefira reaproveitar padrões existentes (services no front, controllers/rotas no back, transações, mensagens `{ erro }`).
