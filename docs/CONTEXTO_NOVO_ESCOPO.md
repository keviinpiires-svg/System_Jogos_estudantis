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
   escola ou pela categoria (a JOSE DIAS joga do Sub 7 ao Sub 17, então dividir só por escola não funciona bem). **Resolvido em 06/10/2026: a divisão saiu, fica só a soma geral.**
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
semifinal, vale a classificação da fase classificatória. (Como saem 4º e 5º: regra **provisória** de 06/10/2026, aguardando confirmação do chefe — seção 12, item 5.)

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
| 5b | ↳ Jogos por competição | ✅ feito | Controller de jogos no schema novo, `numero_jogo` por competição, renumeração ao excluir, tabela de jogos na tela. **Acréscimo de 05/10/2026 — agenda de jogos:** dois jogos no mesmo local precisam de um intervalo mínimo entre os horários (decisão provisória 18, seção 12.1), checado em transação no `agendarJogo` e no `atualizarJogo`, com **409** que diz qual jogo ocupa o local; jogo em andamento, finalizado ou com W.O. não muda mais de data, hora nem local. Na tela, o ADMIN marca e edita data, hora e local de jogo AGENDADO pelo `FormAgendaJogo`, na tabela de jogos e no card do mata-mata (**fatia 7c**), cujos jogos nascem sem agenda — a chave do mata-mata passou a trazer o local; o que está vazio aparece como "A definir" e pode ser limpo. O `npm run fumaca` cobre os conflitos, a liberação pelo W.O., a limpeza da agenda e a corrida de dois agendamentos simultâneos. |
| 5c | ↳ Súmula e W.O. | ✅ feito | Súmula como única fonte do placar (em branco e preenchida, mesma rota), impressão da folha e `PUT /api/jogos/:id/wo` só de ADMIN. |
| 5d | ↳ Classificação e perfil PLACAR | ✅ feito (29/09/2026) | `GET /api/classificacao/competicao/:id` calcula a tabela a partir dos jogos da fase de grupos, com o desempate da modalidade (GOLS, PONTOS, SETS e ELIMINADOS) e marca quem ficou empatado até o sorteio. A tela da competição mostra a tabela por grupo, destaca quem avança e **avisa na própria tela os 2 casos de regra em aberto** (melhor segundo com grupos de tamanhos diferentes; "melhor de dois jogos" com mais de duas equipes). No frontend, `isAdmin`/`isPlacar`/`podeLancar` vêm do perfil e a `RotaPrivada` aceita a lista de perfis: a mesa entra na súmula, não no cadastro. |
| 5e | ↳ Suspensão por cartões | ✅ feito (29/09/2026) | Calculada das súmulas, nunca gravada: 2 amarelos = 1 jogo, amarelos zerados na 2ª fase, expulsão = 1 jogo, e a suspensão é cumprida no primeiro jogo seguinte em que o atleta não entra na súmula. As disciplinares da tabela `suspensoes` somam. `GET /api/suspensoes/competicao/:id` e `/jogo/:id`; a tela da competição lista cartões e pendências, e o preenchimento da súmula avisa quem não pode entrar. **Só futsal e society têm a regra escrita** — nas outras modalidades a tela mostra os cartões com aviso e não declara ninguém suspenso (pendência 13). |
| 6 | Demais modalidades coletivas | ✅ feito (30/09/2026) | Basquete, Vôlei e Baleado, além do handebol e do society que já usavam a folha do futsal. O desenho de cada folha está em **`src/config/folhasSumula.js`** — um objeto por modalidade, que o backend usa para validar e a tela usa para escolher a folha (`web-jogos/src/components/folhas/`). **Modelos de súmula** (`docs/referencias/sumulas_modelos.md`): **toda folha impressa tem 14 linhas por equipe** (decisão de 29/09/2026), inclusive basquete e vôlei, cujos papéis trazem 12 — o elenco do regulamento é 14. **Society e Handebol usam exatamente a folha do futsal**, só muda o título — ✅ **já impresso assim desde 29/09/2026** (a folha nova do futsal atende as três modalidades); Basquete tem folha própria (faltas individuais 0–5, grade de pontos, faltas acumulativas 1–7) e **já está pronta**: a coluna `sumula_atletas.faltas` (`db/05_faltas_basquete.sql`, aplicada no banco de desenvolvimento em 29/09/2026) passou a ser lida e gravada, o backend recusa cartão em basquete e a grade de PONTOS do papel é a pontuação corrida da equipe (2 a 97), com uma coluna "Pts" por atleta acrescentada pelo sistema; Vôlei tem folha própria (duas equipes lado a lado, controle dos 3 sets, sem gols nem cartões) e **já está pronta**: `jogo_sets` passou a ser gravado e lido, o set termina em 21 com 2 de vantagem, o jogo em 2 sets, e o placar do jogo são os sets. O título da folha ("SÚMULA DE VOLEIBOL", "SÚMULA DE BASQUETEBOL") sai de `src/config/folhasSumula.js`, sem mexer no nome da modalidade. **Baleado não tem modelo em papel:** por decisão provisória de 30/09/2026 usa a folha do futsal com coluna de eliminações, e a tela avisa que a folha é provisória. |
| 7 | Mata-mata configurável | ✅ feito (01/10/2026) | Formato por competição, 3º lugar calculado, pênaltis e prorrogação. **7a ✅ feito (30/09/2026):** os cinco formatos reais foram levantados no banco, o cruzamento vive em `src/config/chavesMataMata.js`, o `classificacaoController` exporta `montarClassificacao` e `compararEntreGrupos` (que aplica o corte do "melhor segundo"), e `GET /api/matamata/competicao/:id` devolve a chave, os classificados e as colocações calculadas. **7b ✅ feito (01/10/2026):** `POST /api/matamata/competicao/:id/gerar` cria os jogos da próxima fase (semifinal ou final) com o cruzamento da chave, numerando por competição sob trava da competição; `DELETE /api/matamata/competicao/:id/:fase` desfaz **só enquanto nada valeu**: recusa se algum jogo da fase estiver finalizado ou por W.O., se houver súmula lançada ou se a final já tiver nascido daquelas semifinais, e renumera o que sobra. No ida e volta, o `sumulaController` passa a exigir as cobranças no **segundo jogo quando a soma dos dois empata** — mesmo que esse jogo tenha vencedor —, seguindo a sequência da modalidade (handebol e basquete: prorrogação, segunda prorrogação e então 7 metros ou lances livres; futsal e society: pênaltis). **7c ✅ feito (01/10/2026):** o card `MataMataCompeticao` entra na página da competição, logo abaixo da classificação: mostra o formato em uma linha, o estado da fase de grupos, os confrontos — previstos (com a origem de cada lado, "1º A", "2º B") ou já gerados, com placar, cobranças e link para a súmula —, os botões de gerar e desfazer para o ADMIN, e o pódio com o porquê de cada colocação. Os avisos de regra provisória (comparação entre grupos e cruzamento) aparecem no próprio card. A tela global `/matamata`, do schema antigo, saiu. |
| 8 | Tabela geral e o que sobra | 🔄 em andamento | Pontuação 10/8/6/4/2 e ajuste de pontos, Atletismo, renumeração de jogos, técnicos e dirigentes (se entrarem). **8a ✅ feito (01/10/2026):** `GET /api/tabela-geral` soma, por escola, as colocações de cada competição encerrada (10/8/6 — 4º e 5º seguem sem regra, pendência 5), dividida nos três blocos pela categoria. Nada é gravado: sai dos jogos, como a classificação. A divisão categoria → bloco mora em `src/config/blocosTabelaGeral.js` e as demais decisões em `regrasProvisorias.tabelaGeral`; a resposta traz a abertura de onde veio cada ponto, as competições que ficaram de fora com o motivo, e as regras marcadas como provisórias. As punições já entram na conta, descontando da soma geral. **8b ✅ feito (01/10/2026):** `GET /api/ajustes-pontos` é público (a escola precisa poder conferir a própria soma) e `POST`/`DELETE` são de ADMIN — a mesa não aplica punição. O valor é limitado à faixa do regulamento (de −10 a −5, nada de bonificação), o motivo é obrigatório, e cada punição guarda quem aplicou e quando; a mesma escola pode ter mais de uma, e a resposta devolve o total já descontado. **8c ✅ feito (01/10/2026):** a tela `/tabela-geral` mostra a soma geral (com a coluna de punições), os três blocos, e abre a conta de cada escola ao clique — de qual competição veio cada ponto e qual punição tirou quanto. Os dois avisos de regra provisória ficam no topo: 4º e 5º sem regra, e a divisão dos blocos. Quem não está logado vê a tabela e os motivos das punições; só o ADMIN vê a coluna de ação, o botão de desfazer (com confirmação que repete o motivo) e o formulário, com motivo obrigatório e o desconto preso à faixa do regulamento. **Falta da fatia 8:** técnicos/dirigentes, se entrarem. O **atletismo saiu desta fatia** e virou a **fatia 11 — atletismo** (06/10/2026). A renumeração de jogos já tinha saído na 5b. **Padrões provisórios de 01/10/2026** para o que falta (ver 12.1, itens 13 a 15): atletismo vira **uma competição por categoria × gênero, com as provas dentro**; o **ADMIN digita a marca** e o sistema ordena; as **duas tentativas** do salto ficam guardadas, valendo a melhor; o atletismo **não pontua** na tabela geral; **Xadrez, Dama e Dominó ficam fora**; e o **técnico segue como nome digitado**, sem cadastro. **Acréscimo de 06/10/2026 (resposta do chefe):** a divisão em três blocos saiu — fica só a soma geral, e `blocosTabelaGeral.js` foi apagado —; o empate na soma divide a posição (1, 1, 3), sem desempate por medalhas; e a punição de 5 a 10 pontos e o "uma só inscrição não pontua" viraram definitivos. O 4º e o 5º lugar passaram a pontuar (4 e 2) por uma regra **provisória** (12.1, item 19). |
| 9 | Usuários e acabamento | ✅ feito (01/10/2026) | **9a ✅:** a tela `/usuarios` (só de ADMIN, inclusive a leitura: a lista revela quem tem acesso) lista, cria, edita, ativa/desativa e redefine senha. O backend já existia inteiro. A tela é feita para **várias contas de mesa** — uma por quadra, se for o caso —, mostra quantas contas de cada espécie existem hoje e **não apaga ninguém: desativa**, porque `usuarios` é referenciada por `suspensoes` e `ajustes_pontos_geral` e apagar a conta apagaria a autoria da punição. As travas do backend aparecem na tela: ninguém muda o próprio perfil nem desativa a própria conta. **9b ✅:** `GET /api/grupos` e `PUT /api/grupos/distribuicao` saíram — o controller consultava `grupos_escolas`, tabela que não existe no schema novo, e a rota respondia **500**. O painel de sorteio que a usava já tinha saído na fatia 2. `colocacoes_finais` segue **sem uso e documentada assim no schema**: as colocações são calculadas, e a tabela fica de pé para o dia em que a Comissão precisar gravar uma à mão. **9c ✅:** (1) `npm run fumaca` monta uma competição inteira pelas rotas da API — atletas, inscrições, jogos, súmulas, classificação, semifinal, final, pódio, tabela geral e punição —, confere cada passo e apaga tudo o que criou, provando que o banco voltou ao estado anterior; recusa-se a rodar fora de um banco com "dev" no nome. (2) **Fuso horário do evento:** `DATE` e `DATETIME` passam a viajar como texto (`dateStrings` no pool), porque são **hora de parede**; o fuso do evento mora em `src/config/evento.js` (`FUSO_EVENTO` no `.env`, padrão `America/Bahia`) e dá o "agora" que o painel usa no lugar de `NOW()`. No frontend, `src/services/datas.js` virou o único lugar que lê data. Isso **corrigiu um erro real**: o jogo gravado às 10:30 aparecia às 13:30 para quem rodava o sistema fora de UTC. (3) **CORS obrigatório em produção:** sem `CORS_ORIGIN`, o servidor não sobe — antes a API ficava aberta a qualquer site, sem aviso. O JWT segue no `localStorage`, por decisão de 01/10/2026. **9d ✅:** varredura das telas, deslogado e como ADMIN. Achados corrigidos: a edição de atleta em `/lista-atletas` **estava quebrada** (mandava `rg_ou_matricula`, campo do schema antigo, e não tinha o campo de sexo — toda gravação voltava "O RG é obrigatório"); a coluna de RG saiu da lista pública, que de propósito não recebe o RG; a barra de menu **cortava o último link** quando não cabia, e agora quebra em duas linhas; e a tela de login dizia "Acesso do Administrador", ignorando o perfil da mesa. |
| 10 | Migração da produção (colocar no ar) | ✅ executada (01/10/2026) | Até a virada, a produção rodava o schema antigo (ver fatia 3). Por decisão de 01/10/2026 a migração é **um roteiro passo a passo para o usuário executar**, não um comando automático, e o banco novo (`jogos_2026`) nasce **ao lado** do antigo em vez de substituí-lo — assim a volta atrás é trocar a `DATABASE_URL`, não restaurar um dump sob pressão. **10a ✅ feito (01/10/2026):** `criar_usuarios.sql` foi apagado — continuava na raiz do backend, versionado, com `admin@sge.com`, a senha padrão e o hash, apesar de a seção 11 afirmar que não existia mais. **10b ✅ feito (01/10/2026):** os scripts `00`–`06` foram validados no motor da produção, **MySQL 9.4.0** (e, de comparação, no 8.0.46): rodam limpos na ordem em banco vazio, todas as contagens batem, as `CHECK` e as chaves estrangeiras compostas recusam de verdade, a renumeração de jogos funciona sob o índice único e o `npm run fumaca` passa inteiro. O relatório é `db/VALIDACAO_MYSQL9.md`. Dois achados: a collation da produção (`utf8mb4_0900_ai_ci`) é **insensível a acento** e a do MariaDB do desenvolvimento não é — em produção "JOSÉ DIAS" e "JOSE DIAS" colidem no índice único (não morde na importação atual, conferido); e a trava do teste de fumaça olhava o `DB_NAME` enquanto o `db.js` prefere a `DATABASE_URL`, então uma URL de produção no `.env` passaria pela conferência — corrigida. **10c ✅ feito:** rota `GET /saude` (par controller + rota), que consulta o banco e devolve **503** quando ele não responde, para o Render recusar um deploy quebrado e para o ping de 5 em 5 minutos não deixar o serviço dormir. **10d ✅ feito (01/10/2026):** o roteiro `System_jogos/docs/MIGRACAO_PRODUCAO.md` — dez passos, do backup em duas camadas (snapshot da Railway + `mysqldump` conferido) até a checagem com o sistema no ar, passando pela criação do `jogos_2026` **ao lado** do banco antigo, pelos sete scripts, pelas conferências de carga, pelos 3 ADMIN e 4 contas de mesa (uma por local de disputa), pelas variáveis do Render (com `JWT_SECRET` novo, `/saude` como health check e o aviso do plano que dorme) e pela Vercel (onde nada muda se o serviço do Render for o mesmo, porque a `VITE_API_URL` está versionada e é resolvida no build). Traz o **plano de volta atrás em quatro níveis** — Vercel, Render, trocar a `DATABASE_URL` de volta, e só então restaurar o dump — e o **ponto sem retorno**: a primeira súmula de jogo real. **Execução ✅ (01/10/2026, entre 20:59 e 21:50):** o `jogos_2026` foi criado na Railway ao lado do `railway` antigo (que segue parado, com as 18 tabelas do schema antigo e a conta de teste `admin@sge.com`), com os scripts `01`–`06` em ordem; Render e Vercel publicam a `feat/novo-escopo`, e a `main` segue com o estado antigo. **Desvios do roteiro:** (1) a Vercel publicava a `main`, então o Branch Tracking de produção foi trocado para `feat/novo-escopo`, com Redeploy — o roteiro dizia que a Vercel não mudava; (2) o `00_apagar_tudo.sql` foi pulado, porque o banco novo estava vazio; (3) o `06` falhou na primeira vez por rodar no banco `railway` errado e foi refeito no `jogos_2026`; (4) só 1 ADMIN foi criado na virada, e 1 conta PLACAR veio depois, pela tela `/usuarios`. A Railway está hoje no **MySQL 9.7.2** (a validação foi no 9.4.0), **não tem backup automático** neste plano (há dumps manuais, fora do repositório) e o crédito gratuito acaba por volta de **18/10/2026**. A execução real está em `docs/MIGRACAO_PRODUCAO.md`, seção "Como foi de fato". |
| 11 | Atletismo | 📝 planejada (06/10/2026), nada implementado | **Padrões provisórios de 06/10/2026**, a confirmar antes de escrever código. **Competições:** uma por categoria × gênero, com as provas dentro (12.1, item 13). **Provas:** Sub 8 e Sub 9 só correm **50 m**; Sub 11, 13, 15 e 17 fazem **salto e 100 m**. **Inscrição:** **1 atleta por escola, por prova** (dentro da categoria × gênero). **Marcas:** o **ADMIN digita** cada marca — **tempo** na corrida (menor vence) e **distância** no salto (maior vence). No salto são **2 tentativas, vale a melhor**. **Pontuação por prova:** 1º = 10, 2º = 8, 3º = 6, 4º = 4, 5º = 2. **A soma das provas por escola**, dentro de cada categoria × gênero, define a **colocação final** da escola no atletismo daquela categoria × gênero, e essa colocação dá **10/8/6/4/2 na tabela geral** — o que muda o padrão de 01/10 (atletismo fora da tabela geral). **Dúvidas em aberto:** (1) **cálculo** — o atletismo usa o mesmo "uma só inscrição não pontua" das coletivas? uma escola que só tem atleta numa das provas soma só aquela? uma prova com menos de 5 atletas distribui só os pontos de quem participou?; (2) **desempate** — empate de marca dentro de uma prova (mesmo tempo ou mesma distância): divide a posição e os pontos, ou desempata pela segunda tentativa do salto?; empate na soma das provas: mesma colocação (como na soma geral, 1, 1, 3) ou outro critério?; (3) **digitação** — o formato do tempo (segundos com centésimos? cronômetro manual?) e da distância (metros com centímetros); o que se digita quando o atleta queima ou não completa a tentativa; e quem lança na pista: só o ADMIN, ou também a conta de mesa (PLACAR)? Quando for implementar: `regrasProvisorias.atletismo` passa a refletir este plano (hoje ainda diz que o atletismo não pontua), as competições de atletismo entram no banco por script numerado (`db/07` ou seguinte), e `provas_atletismo`/`resultados_atletismo` (já no schema) são revistas contra as duas tentativas e as marcas. |

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
- ~~`POST /api/diretores` grava senha em **texto puro**~~ — resolvido: a rota saiu na fatia 2.
- ~~CORS aberto quando `CORS_ORIGIN` está vazio~~ — resolvido na fatia 9c: em produção a variável é **obrigatória** e o servidor não sobe sem ela. Em desenvolvimento a abertura continua, para o Vite conversar com a API sem configuração.
- ~~Sem rate limit no login~~ — resolvido: `express-rate-limit` em `authRoutes`, com `trust proxy` para o Render enxergar o IP certo.
- **JWT em `localStorage`** — mantido por decisão de 01/10/2026: trocar por cookie `httpOnly` mexe no deploy e abre o assunto de CSRF, e não cabe no prazo.
- ~~Admin padrão `admin@sge.com`, com a senha padrão, no SQL versionado~~ — resolvido **de verdade na fatia 10** (01/10/2026).
  Esta linha dizia que `criar_usuarios.sql` "não existe mais", e **estava errada**: o arquivo continuava na raiz do backend e
  versionado, com o e-mail, a senha e o hash. Foi apagado. O hash segue no histórico do git — a garantia é outra: a carga base
  **não cria usuário nenhum**, `db/README.md` manda gerar o hash na hora, e essa senha deixa de existir junto com o banco antigo.
- ~~Validação fraca: mesma escola nos dois lados, placar negativo~~ — resolvido pelo próprio banco (`CHECK (equipe_1_id <> equipe_2_id)` e `CHECK (placar >= 0)`); escola fora do grupo e geração de semifinal com a fase incompleta são barradas no código (fatias 5b e 7b).
- Duas fontes de verdade para o placar (súmula × finalizar manual) — o `finalizar` ficou só para W.O. e casos excepcionais (fatia 5c), mas as duas portas existem.
- ~~`excluirJogo` chama `getConnection()` fora do `try`~~ — resolvido na reescrita do controller de jogos (fatia 5b).
- ~~Fuso: datas de jogo tratadas como UTC no front e comparadas com `NOW()` no backend~~ — resolvido na fatia 9c, e **era um erro de verdade**: `DATE`/`DATETIME` agora viajam como texto (hora de parede), o front lê tudo por `src/services/datas.js` e o "agora" sai do fuso do evento (`src/config/evento.js`). Antes, o jogo das 10:30 aparecia às 13:30 para quem rodasse o sistema fora de UTC.
- ~~Nenhum teste automatizado~~ — há o **`npm run fumaca`** (fatia 9c), que percorre uma competição inteira pelas rotas da API e apaga o que criou. Não é uma suíte de testes de unidade: é a prova de que o caminho principal está de pé.

## 12. Pendências (perguntas em aberto para o usuário)

1. ~~**Tabela geral em 3 blocos**~~ — **resolvido (06/10/2026):** o chefe tirou a divisão; a tabela geral tem só a soma geral, e o empate na soma divide a posição (1, 1, 3). Ver 12.1, itens 9 e 12.
2. ~~**Limite de 2 modalidades coletivas**~~ — **resolvido (28/09/2026):** o limite conta **competições**, não modalidades. Futsal Sub 13 + Futsal Sub 15 são **duas**. Contam as inscrições em competições de modalidade `COLETIVO`; o atletismo (`INDIVIDUAL`) não entra.
3. **Atletismo:** (a) uma competição por categoria × gênero com as provas dentro, ou uma por prova? (b) como o resultado é lançado — o ADMIN digita a marca, ou chega a classificação já pronta? (c) pontua na tabela geral e, se sim, por prova ou pela modalidade inteira? (d) o salto guarda as duas tentativas ou só a melhor? (e) **Xadrez, Dama e Dominó entram?** Há **padrões provisórios de 01/10/2026** para todas elas (12.1, itens 13 e 14) — nada implementado ainda. **Segue PENDENTE (chefe, 06/10/2026):** o cálculo e a entrada das marcas do atletismo, e se xadrez, dama e dominó entram. O atletismo ganhou um plano com padrões provisórios na **fatia 11 — atletismo**, com as dúvidas em aberto listadas lá.
4. **Fase de grupos:** pontos por vitória e empate? (o regulamento cita uma "tabela" de sistema de disputa que não veio.)
5. **4º e 5º lugar** — **implementado de forma PROVISÓRIA em 06/10/2026, aguardando confirmação do chefe.** **4º** = o perdedor da disputa de 3º lugar, quando houver; como o regulamento não tem jogo de 3º lugar, hoje é sempre o semifinalista que perdeu para o vice. **5º** = a melhor equipe que **não chegou à semifinal**, pela campanha da fase de grupos, só quando a **competição tem mais de 4 equipes** (correção de 06/10/2026: a conta é das equipes da competição, não do mata-mata). Sem semifinal, não há 4º nem 5º. Valem **4 e 2 pontos** na tabela geral, e a tela marca esses pontos como provisórios (12.1, item 19).
6. Ambiguidades da tabela de grupos (seção 6) e a interpretação "frase vale para a tabela abaixo". Resolvidos em 06/10/2026: o "melhor segundo" (critérios normais, sem descartar jogos) e o Handebol Masculino Aberto (turno único). Também em 06/10/2026: a semifinal com 3 grupos (1ºA × melhor 2º, 1ºB × 1ºC) e o 3º lugar sem semifinal (vale 6 pontos) — 12.1, itens 6 e 8. **Segue PENDENTE:** se a revanche da fase de grupos na semifinal (1ºA contra um 2º do grupo A) pode acontecer; hoje a chave sai e a tela avisa.
7. **Súmula:** gols por clique em caixa ou campo numérico? Faltas/tempo técnico lançados ou em branco? Cabeçalho fixo ou por jogo?
8. **Empate no mata-mata do Baleado:** o regulamento diz quem vence (quem balear todos ou, acabado o tempo, quem eliminou mais), mas não o que fazer se as eliminações empatarem. **PENDENTE (06/10/2026):** não há cobrança genérica; a súmula avisa e não finaliza o jogo empatado (12.1, item 3). Também em aberto: **gênero do Baleado** (o regulamento não diz; a tabela de grupos tem masculino e feminino) e **como o placar é lançado** (eliminados).
9. **Numeração dos jogos:** por competição (assumido no schema) ou global?
10. ~~Schema do banco~~ — **resolvido** (ver seção 8).
11. ~~Limpeza: destino do reset de campeonato, do `finalizar` manual e da suspensão~~ — **resolvido** (ver seção 10).
12. **Súmula do Baleado** — **segue PENDENTE (chefe, 06/10/2026)**; até lá vale a folha provisória de 30/09/2026: folha no estilo da do futsal, com a linha do atleta contando **eliminações**, **14 caixas** na grade (uma por adversário possível) e o rodapé **sem as faltas acumuladas**, que o baleado não usa. O chefe ainda vai revisar (ver 12.1).
13. **Suspensão por cartões nas outras modalidades:** o regulamento só escreve a regra para futsal e society. Handebol, basquete, vôlei e baleado usam cartões — vale a mesma regra (2 amarelos = 1 jogo, expulsão = 1 jogo)? Hoje o sistema mostra os cartões dessas modalidades mas não declara ninguém suspenso.
14. **Técnicos e dirigentes entram no sistema?** Hoje o técnico é só um nome digitado na equipe e na súmula. Se entrarem: cadastro próprio, os **10 dirigentes por escola** do regulamento e a checagem de que **professor/monitor não pode ser atleta**. Padrão provisório de 01/10/2026: fica como está (12.1, item 15).
15. **Migração da produção:** quando migrar, e confirma-se que **tudo o que está lá é teste** e pode ser recriado do zero com `00`/`01`/`02` + importação dos grupos? Por decisão de 01/10/2026 isso é a **fatia 10**, e sai como **roteiro passo a passo**, não como comando automático.
16. **Número de contas de mesa (PLACAR):** quantas criar? **PENDENTE (chefe, 06/10/2026).** Hoje existe 1.

## 12.1 Decisões provisórias (30/09 a 05/10/2026) e a resposta do chefe (06/10/2026)

> **Só as linhas marcadas com ✅ são definitivas.** São decisões tomadas para o sistema poder andar, e vivem em
> **dois arquivos só**: **`System_jogos/src/config/regrasProvisorias.js`** (regras de jogo) e
> **`System_jogos/src/config/chavesMataMata.js`** (quem enfrenta quem). Trocar uma regra é editar
> esse arquivo — nenhum controller guarda cópia dela. Ao confirmar com o chefe, mude
> `provisorio` para `false` e o aviso some das telas.
>
> **Resposta do chefe (06/10/2026):** confirmou as linhas 2, 3, 4, 7, 10 e 11; trocou a 1 (sem
> descarte de jogos), a 9 (sem blocos) e o empate da 12 (mesma posição); numa segunda resposta, no mesmo dia,
> decidiu a 6 (confrontos fixos) e a 8 (3º lugar vale 6 pontos). Deixou **PENDENTES** as
> linhas 5, 13 e 14, a revanche na semifinal (linha 6), o 4º e 5º lugar e o número de contas de mesa (seção 12). O que
> ele confirmou ou trocou está com `provisorio: false` no config.

| # | Assunto | Decisão provisória | Onde está implementada |
|---|---|---|---|
| 1 | "Melhor segundo" com grupos de tamanhos diferentes (pendência 6) — ✅ **decidido pelo chefe em 06/10/2026** | ~~Descartar os jogos contra o último colocado dos grupos maiores~~ — **recusado**. Os segundos são comparados pelos **critérios normais da modalidade, com todos os jogos**, sem descartar nenhum. Quando as equipes comparadas têm **números de jogos diferentes**, a tela mostra um aviso (a conta não muda) | `regrasProvisorias.melhorSegundo` (`provisorio: false`), consumida por `classificacaoController.compararEntreGrupos`; o aviso sai em `GET /api/classificacao/competicao/:id` (`avisos`) e em `GET /api/matamata/competicao/:id` (`comparacao_entre_grupos.aviso_jogos_diferentes`) |
| 2 | Handebol Masculino Aberto (pendência 6) — ✅ **confirmado pelo chefe em 06/10/2026** | Todos contra todos em **turno único**; 1º e 2º vão à final | `db/06_ajustes_regras_provisorios.sql` — é **dado**, não código: mora na linha da competição |
| 3 | Empate após a prorrogação no handebol e no basquete — ✅ **confirmado pelo chefe em 06/10/2026**. Não há desempate genérico: cada modalidade segue o regulamento (futsal e society, pênaltis 3x1x1; vôlei não empata), e o **baleado**, onde ele é omisso, fica ⏳ **PENDENTE**, sem cobrança | **Segunda prorrogação** e, persistindo, cobranças: **7 metros** no handebol, **lances livres** no basquete | `regrasProvisorias.desempateMataMata`, consumida por `sumulaController` ao finalizar súmula empatada fora da fase de grupos |
| 4 | Placar de um W.O. — ✅ **confirmado pelo chefe em 06/10/2026: 1×0, declarado só pela Comissão Organizadora** (no sistema, o ADMIN) | **1×0**, editável pelo ADMIN na hora de declarar | `regrasProvisorias.wo`, consumida por `jogoController.declararWO`; a tela já abre com o placar sugerido |
| 5 | Súmula do baleado (pendência 12) — ⏳ **segue PENDENTE** (chefe, 06/10/2026) | Folha no **estilo da do futsal**, com uma coluna de **eliminações por atleta** no lugar dos gols — 14 caixas na grade e sem as faltas acumuladas do rodapé | `regrasProvisorias.baleado`; o placar continua sendo a soma da coluna, que é o que `sumula_atletas.gols` guarda quando `tipo_placar = ELIMINADOS` |
| 6 | Semifinal com 3 grupos e o melhor 2º (pendência 6) — ✅ **decidido pelo chefe em 06/10/2026** | **Confrontos fixos: 1ºA × melhor 2º colocado e 1ºB × 1ºC.** O melhor 2º é escolhido pela campanha, pelos critérios de desempate da modalidade (linha 1). ~~O melhor primeiro enfrenta o melhor segundo, com troca de pares se forem do mesmo grupo~~ — substituído. Se o melhor 2º for do grupo A, a semifinal repete um jogo da fase de grupos: **não é bloqueada**, e a tela do mata-mata mostra o aviso "Revanche de fase de grupos: regra pendente de confirmação com a organização" — ⏳ **essa parte segue PENDENTE** | `chavesMataMata.cruzamentoTresGruposComMelhorSegundo` (`provisorio: false`) e `chavesMataMata.revancheNaSemifinal` (`provisorio: true`, o texto do aviso). O aviso sai em `chave.semifinal.observacao` de `GET /api/matamata/competicao/:id`, antes e depois de a semifinal ser gerada. Vale nas 3 competições do formato: Futsal Sub 11 M e Baleado Sub 13 M e F |
| 7 | Empate na soma dos dois jogos (ida e volta com 2 equipes) — ✅ **confirmado pelo chefe em 06/10/2026** | Campeão é quem **soma mais nos dois jogos**; empatada a soma, decide nas **cobranças lançadas na súmula do segundo jogo** | `chavesMataMata.somaDosDoisJogos`, consumida por `mataMataController.colocacoesFinais` e, desde a **fatia 7b**, por `sumulaController.registrarSumula`, que exige as cobranças ao finalizar o segundo jogo com a soma empatada. Vale nas 6 competições de ida e volta |
| 8 | 3º lugar sem semifinal (pendência 5, em parte) — ✅ **decidido pelo chefe em 06/10/2026** | **Não há jogo de 3º lugar** (regulamento). Sem semifinal, o 3º é o **3º do grupo único** ou, com dois grupos, o **melhor dos dois segundos pela campanha**, e **vale 6 pontos** na tabela geral, como qualquer 3º lugar | `chavesMataMata.terceiroSemSemifinal` (`provisorio: false`), consumida por `mataMataController.colocacoesFinais`; a marca "regra provisória" saiu da colocação na tela. Vale nas 31 competições dos formatos A e B |
| 9 | Blocos da tabela geral (pendência 1) — ✅ **decidido pelo chefe em 06/10/2026** | ~~Divisão em anos iniciais, anos finais e ensino médio~~ — **removida**. A tabela geral tem **só a soma geral** | `src/config/blocosTabelaGeral.js` foi **apagado**; `GET /api/tabela-geral` não devolve mais `blocos`, e a tela `/tabela-geral` mostra só a soma geral |
| 10 | "Uma só inscrição não conta pontos nem premia" — ✅ **confirmado pelo chefe em 06/10/2026** | Vale **por competição** (modalidade × categoria × gênero), não pela modalidade inteira | `regrasProvisorias.tabelaGeral.minimoDeEquipes`, consumida pelo `tabelaGeralController`. Hoje não morde: nenhuma das 50 competições tem menos de duas equipes |
| 11 | Punição da Comissão Disciplinar (5 a 10 pontos) — ✅ **confirmado pelo chefe em 06/10/2026** | Desconta da **soma geral da escola**, não de um bloco. Pode haver **mais de uma por escola**, e cada uma guarda **motivo e data** | `regrasProvisorias.tabelaGeral.ajuste` e a tabela `ajustes_pontos_geral`. A leitura já entrou na 8a; a escrita é a 8b |
| 12 | Detalhes da soma da tabela geral — empate ✅ **decidido pelo chefe em 06/10/2026**; o resto segue provisório | Masculino e feminino **somam juntos** para a escola; uma competição **só conta quando tem campeão**; ~~empate na soma desempata por mais 1ºs, depois 2ºs, depois 3ºs~~ — **trocado pelo chefe em 06/10/2026: escolas com a mesma soma ficam na mesma posição**, em qualquer colocação, com numeração de competição (1, 1, 3), e empatadas em 1º são todas campeãs gerais; **atletismo fica de fora** (sem competição cadastrada e sem regra de lançamento, pendência 3) | `regrasProvisorias.tabelaGeral`, consumida pelo `tabelaGeralController` |
| 13 | Atletismo (pendência 3) — decidido em **01/10/2026**; ⏳ **substituído pelo plano da fatia 11 (06/10/2026)**, que muda a pontuação: o atletismo passa a pontuar na tabela geral — ⏳ **segue PENDENTE** (chefe, 06/10/2026) | **Uma competição por categoria × gênero, com as provas dentro** (e não uma competição por prova, que triplicaria a lista do menu); o **ADMIN digita a marca** e o sistema ordena (tempo: menor vence; distância: maior vence); as **duas tentativas do salto ficam guardadas**, valendo a melhor; e o atletismo **não pontua na tabela geral** | `regrasProvisorias.atletismo`. **Nada implementado ainda** — é a parte que falta da fatia 8. Hoje não há nenhuma competição de atletismo no banco; as 3 provas (50 m, 100 m e salto) já vêm na carga base |
| 14 | Xadrez, Dama e Dominó (pendência 3) — decidido em **01/10/2026** — ⏳ **segue PENDENTE** (chefe, 06/10/2026) | **Ficam fora** do sistema enquanto o chefe não confirmar que entram. O regulamento as cita, a tabela de grupos não traz nenhuma competição delas | `regrasProvisorias.modalidadesForaDoSistema`. Nada a implementar: não há competição dessas modalidades cadastrada |
| 15 | Técnicos e dirigentes (pendência 14) — decidido em **01/10/2026** | O técnico **continua só como nome digitado**, na equipe e na súmula. Sem cadastro próprio, sem tabela de dirigentes, sem o limite de 10 por escola e sem a checagem de "professor/monitor não pode ser atleta" | `regrasProvisorias.tecnicos`; os campos são `equipes.tecnico_nome` e `sumula_equipes.tecnico_nome` |
| 16 | JWT no `localStorage` (fatia 9c) — decidido em **01/10/2026** | **Fica como está.** Trocar por cookie `httpOnly` mexe no deploy e abre o assunto de CSRF, e não cabe no prazo até novembro | `services/token.js` no frontend; `authController` continua devolvendo o token no corpo |
| 17 | Fuso horário do evento (fatia 9c) — decidido em **01/10/2026** | As datas de jogo são **hora de parede** (10:30 é 10:30 em Barra do Choça, não um instante num fuso) e viajam como texto. O fuso do evento, usado para saber que horas são "agora", é **`America/Bahia`** | `src/config/evento.js` (`FUSO_EVENTO` no `.env` troca sem mexer no código) e `dateStrings` no pool de `src/config/db.js`; no frontend, `src/services/datas.js` |
| 18 | Dois jogos no mesmo local — decidido em **05/10/2026** | Dois jogos no **mesmo local** conflitam se os **horários de início** têm **menos de 10 minutos** de diferença, mesmo sendo de competições diferentes. A **duração das partidas fica em aberto**, por decisão do chefe (varia muito, e o vôlei é por sets): o sistema **não estima duração** nem usa `minutos_por_tempo`, só compara os inícios. (O primeiro valor, também de 05/10, era 60 minutos.) Jogo sem local ou sem horário fica fora da conta; **AGENDADO, EM_ANDAMENTO e FINALIZADO ocupam** o local e o **W.O. libera**. A trava é **só no código**, em transação com o local travado, sem índice único: um `UNIQUE (local_id, data_hora)` não pegaria a sobreposição e impediria o W.O. de liberar o horário. Jogo **em andamento**, finalizado ou com W.O. não muda mais de data, hora nem local (árbitros e observações seguem editáveis) | `regrasProvisorias.conflitoDeLocal` (`intervaloMinutos`, `statusQueOcupam`), consumida por `jogoController.agendarJogo` e `jogoController.atualizarJogo`, que respondem **409** dizendo qual jogo ocupa o local |
| 19 | 4º e 5º lugar (pendência 5) — decidido em **06/10/2026**, ⏳ **aguardando confirmação do chefe** | **4º** = perdedor da disputa de 3º lugar, quando houver; sem disputa (o caso de sempre, porque não há jogo de 3º lugar), o outro semifinalista que não foi 3º — quem perdeu a semifinal para o vice. **5º** = a melhor equipe que não chegou à semifinal, pela campanha da fase de grupos, só quando a competição tem mais de 4 equipes. Sem semifinal, não há 4º nem 5º. Valem 4 e 2 pontos | `chavesMataMata.quartoEQuinto` (`provisorio: true`; o limite de equipes é `equipesNaCompeticaoParaQuinto`), consumida por `mataMataController.colocacoesFinais`; `regrasProvisorias.tabelaGeral.posicoesQuePontuam` vai do 1º ao 5º. A tela da tabela geral mostra o aviso e marca esses pontos como provisórios; a colocação no card do mata-mata vem com "regra provisória" |

**Decisão de 30/09/2026 que NÃO é provisória:** com 2 grupos e 2 classificados de cada, a semifinal é
**cruzada — 1ºA × 2ºB e 1ºB × 2ºA** (`chavesMataMata.cruzamentoDoisGrupos`). É o padrão do futebol e
vale nas 10 competições do formato; duas equipes do mesmo grupo só se reencontram na final.

**Limitação conhecida da decisão 3:** o schema tem `jogos.prorrogacao` como booleano, então o sistema
registra *que houve* prorrogação, mas não distingue a primeira da segunda. Se o chefe quiser esse
detalhe registrado, vira uma migração (`db/07`) trocando o booleano por um contador.

## 13. Como trabalhar neste projeto

- **Código é escrito aqui (VS Code)**; **dúvidas de regra/negócio são tiradas com o usuário** (numa conversa à parte). Diante de uma
  **[PENDENTE]**, pare e pergunte — não invente regra do regulamento.
- Não leia nem imprima os arquivos `.env`. Nunca comite segredos.
- Não faça commit/push sem o usuário pedir. Trabalhe na branch nova.
- Mudanças de banco: sempre por **script SQL versionado** (crie `db/schema.sql` e `db/migracoes/`), nunca só à mão.
- Antes de mexer em regra de classificação, releia a seção 5 (desempate por modalidade).
- **Numeração das fatias: só a tabela da seção 9 vale.** Ao concluir uma fatia, atualize o estado dela ali no mesmo commit.
- Prefira reaproveitar padrões existentes (services no front, controllers/rotas no back, transações, mensagens `{ erro }`).
