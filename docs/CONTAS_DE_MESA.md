# Contas de mesa (PLACAR) — uma por local

Decisão do chefe (12/10/2026): **uma conta de mesa por local de jogo**. Desde o `db/18`
(28/10/2026), a conta PLACAR pode ser presa a um local (`usuarios.local_id`).

## O que a mesa pode fazer

| Ação | Mesa com local | Mesa sem local | ADMIN |
|---|---|---|---|
| Iniciar jogo (`PUT /api/jogos/:id/iniciar`) | só jogo do local dela | **bloqueada (403)** | qualquer jogo |
| Lançar súmula — placar, gols, cartões, sets, cobranças, finalizar (`POST /api/sumulas`) | só jogo do local dela | **bloqueada (403)** | qualquer jogo |
| Número da camisa na hora do jogo (`PUT /api/equipes/:id/camisas`) | só jogo do local dela | **bloqueada (403)** | qualquer jogo |
| Tabuleiro e Atletismo (`PUT /api/pontos-lancados`) | sim (não têm local) | sim | sim |
| Ler agenda, súmulas (`GET /api/sumulas/:jogo_id`, pública), classificação | tudo | tudo | tudo |

Em jogo de outro local (ou jogo ainda sem local), a mesa com local recebe **403**: "Esta mesa é do local X;
este jogo é do local Y." As demais escritas de jogo (agendar, editar, W.O., excluir, mata-mata) já são
só do ADMIN. Súmula finalizada só o ADMIN reabre, como antes.

A trava é um middleware só (`travarMesaPorLocal`, em `src/middlewares/authMiddleware.js`), nas três
rotas de escrita acima. O local é **relido do banco a cada escrita** (não vem do token): trocar o local de uma conta
vale na hora, sem a pessoa sair e entrar. A tela também relê a conta ao abrir (`GET /api/eu`).

**Mesa sem local = bloqueada** (desde 16/11/2026; antes ficava sem trava): o backend responde **403**
"Mesa sem local definido. Fale com o administrador." em todas as escritas acima, e a tela de súmula mostra
"Tela restrita" com a mesma frase. A tela `/usuarios` mostra "⚠️ sem local definido" nessas contas e um
aviso no topo; para liberar, **Editar** → escolha o local → **Salvar** (vale na hora).

## O que a mesa vê na tela

- **Cabeçalho:** "Mesa: <local>" (ou "Mesa sem local").
- **Agenda e tabela de jogos da competição:** por padrão só os jogos do local dela; o botão **"Ver todos
  os locais"** mostra os outros, **só para consultar horários e equipes**. Essa escolha não vai para a URL
  nem para o navegador: toda vez que a tela abre, a mesa volta a ver só o local dela (um `?local=todos`
  antigo é ignorado).
- **Súmula é só do local da mesa, também para ver e imprimir:** "Súmulas em branco" (Agenda), "Abrir/Continuar/
  Ver súmula" (tela do jogo, tabela de jogos e cartões do mata-mata), Iniciar e a impressão 🖨️ só aparecem nos
  jogos ou locais da mesa. **Imprimir Súmulas** (menu) lista só o local dela, mesmo que a URL peça outro.
- **`/preencher-sumula/:id` e `/detalhes-sumula/:id` de jogo de outro local:** "Tela restrita" (e mesa sem local
  também). Visitante e ADMIN seguem como estavam. Para a **escrita** quem vale é o 403 do backend; a **leitura**
  `GET /api/sumulas/:jogo_id` segue pública (alimenta a impressão e a tela pública), então a restrição de ver e
  imprimir é da tela, não do servidor.

## Duas etapas na súmula: preencher e iniciar

Na súmula (`/preencher-sumula/:id`), com o jogo **agendado**, o topo mostra **"Preencher súmula"** e **"Iniciar partida"**:

- **Preencher súmula** abre a tabela de atletas: camisas, "Adicionar atleta", presença e capitão. O placar
  (gols, cartões, faltas, sets, eliminadas, cobranças) fica bloqueado. "Salvar parcial" grava as camisas no servidor;
  presença e capitão ficam como rascunho neste navegador até a partida iniciar. **O nome do técnico não é mais
  digitado na tela** (a folha impressa tem a linha "Técnico:" em branco, para escrever à mão); o que já estava
  gravado em súmulas antigas não muda.
- **Iniciar partida** pede confirmação ("Iniciar a partida agora?"), **salva antes as camisas digitadas e ainda não
  salvas** (se der erro, por exemplo número repetido, a partida não inicia), inicia o jogo (só no local da mesa) e
  libera o placar e o "Finalizar súmula". O botão vira "Partida em andamento". Camisas e "Adicionar atleta" seguem
  liberados. Os números aparecem na coluna Nº ao abrir ou recarregar a súmula, e valem para os próximos jogos da
  equipe; números digitados e não salvos voltam aos campos se a página for recarregada.
- **Finalizado ou W.O.:** nenhum dos dois botões. A mesa só consulta (e imprime); o ADMIN pode reabrir e corrigir.
- Só a tela muda: o backend segue aceitando placar em jogo agendado (e isso inicia o jogo), por isso o fluxo
  acima é o caminho normal e não uma trava.

### Súmula no celular

No celular (até 640 px) cada atleta aparece como um cartão: Nº e nome em cima, e embaixo Gols, Faltas, Amarelos,
Vermelho, Capitão e (no pré-jogo) Presente, cada um com o seu rótulo e botões grandes. Não há rolagem lateral, e os
botões "Preencher súmula", "Iniciar partida", "Salvar parcial" e "Finalizar súmula" ocupam a largura da tela.

### Menu da mesa

"Tabela Geral" e "Artilharia" não aparecem no menu da conta de mesa (nem no menu do celular). Visitante e ADMIN continuam
vendo os dois, e as páginas seguem públicas (quem digitar o endereço ainda as abre).

### Faltas, elenco e cartões

- **Elenco e camisas só no pré-jogo:** "Adicionar atleta", "Remover" (do atleta que a mesa colocou), "Salvar camisas" e
  "Editar camisas" ficam na etapa "Preencher súmula". Depois de "Iniciar partida" os números das camisas ficam só
  leitura (o Iniciar salva antes as camisas digitadas e ainda não salvas).
- **Futsal e society — faltas por atleta:** depois de iniciar, a coluna "Faltas" tem − / + por atleta (0 a 20) e o botão **"Iniciar 2º tempo"**
  ao lado do indicador "▶ Partida em andamento" (pede confirmação e não volta; o indicador passa a "▶ 2º tempo").
  Até o clique toda falta conta no 1º tempo, depois no 2º. Abaixo de cada equipe aparece "Faltas da equipe:
  1º T n · 2º T n" (calculado). A partir de 5 num tempo aparece "Próxima falta: tiro livre", sem travar. O "−"
  só desconta do tempo atual. O tempo do jogo fica guardado neste navegador (e é deduzido de faltas do 2º tempo já
  gravadas): limpar os dados do navegador antes de gravar qualquer falta do 2º tempo volta o jogo ao 1º tempo. Sem os campos "Faltas 1º/2º tempo" e "Tempo técnico" no rodapé (a impressão
  continua preenchendo as faltas acumuladas; as caixas de tempo técnico saem em branco). **Exige o `db/46`** (aplicado em produção em 16/11/2026, junto com o `db/45`).
- **Presença:** a coluna "Presente" só existe no pré-jogo. Depois de "Iniciar partida" ela some e a tabela mostra só os
  atletas presentes; a presença segue gravada na súmula e a impressão não muda. **"Iniciar partida" já grava a
  súmula parcial** (presença, capitão e camisas), então a presença não se perde se a página for recarregada; se essa
  gravação falhar, a partida iniciou e a tela avisa para usar "Salvar parcial".
- **2º amarelo = vermelho (futsal, society e handebol):** o 2º amarelo marca o vermelho sozinho; voltar para 1 desmarca
  só o vermelho automático. A suspensão calculada vale só para futsal e society.
- **Basquete** não mudou: faltas por atleta de 0 a 5 e faltas/tempo técnico da equipe digitados à mão.

### Colunas de placar, camisas e baleado

- **Antes de iniciar a partida**, a tabela de atletas só mostra **Nº, Atleta, Cap. e Presente**; Gols, Faltas,
  Amarelos, 🟥, "Eliminou" (baleado), os campos do rodapé da equipe e os sets ficam escondidos. O placar do topo
  continua visível. Ao iniciar, tudo aparece sem recarregar e sem perder o que foi digitado.
- **Camisa salva fica travada.** "Editar camisas" (por equipe) destrava; ao salvar trava de novo; "Cancelar" devolve ao
  que está salvo. Campo vazio e atleta recém-adicionado pela mesa ficam editáveis até salvar. Jogo finalizado: tudo travado.
- **Baleado:** coluna "Eliminou" por atleta (0 a 10). O total da equipe é a soma, só leitura, no máximo 10 (com 10 os
  "+" da equipe travam). Súmulas antigas, gravadas só com o total da equipe, continuam valendo com esse total.
  Essas eliminações não entram na artilharia nem no card "Balançaram a Rede".

## Adicionar atleta na hora do jogo (`db/45`)

Na tela da súmula (`/preencher-sumula/:id`), a mesa tem **"Adicionar atleta"** em cada equipe, só no jogo do
local dela e enquanto o jogo está **agendado ou em andamento** (some com o jogo finalizado ou em W.O.).

- **Atleta já cadastrado na escola:** busca por nome. A lista mostra só o nome e as equipes em que o atleta já
  está (modalidade, categoria e gênero), para distinguir homônimos. A mesa **nunca vê RG, CPF nem nascimento**.
- **Atleta novo:** nome, nascimento, sexo e documento (opcional). Sem documento, o sistema gera o código
  provisório da escola (`<SIGLA>SRG<NNN>`, próximo número livre); o administrador completa em Listar Atletas.
- **Regras:** as mesmas do cadastro normal, conferidas no backend (idade da categoria, sexo × gênero, máximo de
  14 por equipe e de 2 competições coletivas). **A mesa não abre exceção**: se uma regra barrar, aparece
  "Precisa de autorização do administrador." com o motivo, e o administrador resolve pelas telas de sempre.
- **Remover:** só o atleta que a própria mesa colocou (marcado "adicionado pela mesa"), antes do jogo terminar. Se
  a mesa tinha cadastrado o atleta e ele fica sem equipe, o cadastro também sai. A ficha e o que outra mesa colocou
  continuam só com o ADMIN. Quem já aparece em súmula não sai.
- **Conferência (ADMIN):** `/atletas-das-mesas` ("Atletas das Mesas" na barra) lista data, mesa, escola, equipe e
  atleta, com a marca "novo" nos que a mesa cadastrou.
- A impressão das súmulas não muda: o atleta colocado pela mesa sai na folha como os demais.

## Como criar uma conta por local (ADMIN)

Depois do `db/18` e do backend novo no ar:

1. Entre como ADMIN e abra **Usuários** (`/usuarios`).
2. Em **Nova conta**: nome que diga o local (ex.: "Mesa — Ginásio de Esportes"), e-mail, perfil
   **Mesa (placar)**, **Local da mesa** = o local, e uma senha de pelo menos 8 caracteres.
3. **Criar conta**, e entregue e-mail e senha à pessoa da mesa daquele local.
4. Repita para cada local (8 hoje: `SELECT id, nome FROM locais_disputa`).
5. A conta PLACAR que já existia fica **sem local**: **Editar** → escolha o local → **Salvar**.
6. Confira a lista: cada mesa com o seu local, nenhuma com "sem local definido".

Na **Agenda**, a mesa com local vê um aviso com o local dela, os jogos dele primeiro em cada dia
(marcados "sua mesa") e o botão **Só o meu local**; os outros locais continuam visíveis.

Trocar a mesa de local (ex.: a pessoa mudou de quadra): **Editar** → outro local → **Salvar**. Vale na
hora. Promover a conta a ADMIN tira o local (o ADMIN nunca é travado).

## Reiniciar Campeonato em produção

`DELETE /api/campeonato/reset` responde **403** com `NODE_ENV=production`, a não ser que o servidor tenha
`PERMITIR_REINICIAR=true`. Em desenvolvimento segue como sempre. A confirmação digitada ("REINICIAR")
continua exigida. O `/saude` diz se está permitido (`reiniciar_permitido`), e a Início só mostra o botão
quando está — além disso, o botão segue desligado na tela pela constante `REINICIAR_CAMPEONATO_ATIVO`
(pedido de 07/10/2026). Para reiniciar de propósito em produção: defina `PERMITIR_REINICIAR=true` no
Render, faça o dump, reinicie, e **tire a variável** em seguida.
