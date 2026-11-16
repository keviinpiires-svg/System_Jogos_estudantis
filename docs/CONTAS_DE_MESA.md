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
  os locais"** mostra os outros, só para consultar horários (na Agenda a escolha vai na URL, `?local=todos`).
- **Botões Iniciar, Súmula e Abrir/Continuar súmula:** só nos jogos do local dela, na tabela de jogos e na
  tela do jogo da Agenda. A impressão/leitura da súmula (`/detalhes-sumula/:id`) segue pública.
- **`/preencher-sumula/:id` de jogo de outro local:** "Tela restrita". É só a tela: quem vale é o 403 do
  backend.

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
