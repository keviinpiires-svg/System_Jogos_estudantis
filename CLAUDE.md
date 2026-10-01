# System_jogos — backend do SGE Jogos Estudantis 2026

API em Node 20+ / Express 5 / MySQL (`mysql2`) / JWT + bcryptjs (CommonJS). Frontend em `F:\web-jogos` (repositório separado).

**Antes de qualquer tarefa de funcionalidade, leia o contexto do novo escopo:**
@docs/CONTEXTO_NOVO_ESCOPO.md

Fontes originais em texto: `docs/referencias/` (regulamento, tabela de grupos, imagem da súmula de futsal).

## Comandos
- `npm run dev` — sobe com nodemon (porta 3000). `npm start` — produção.
- `npm run fumaca` — **teste de fumaça** (`scripts/fumaca.js`): com a API no ar, monta uma competição
  inteira pelas rotas (atletas, súmulas, classificação, mata-mata, tabela geral), confere cada passo e
  apaga o que criou. Só roda em banco com "dev" no nome. Rode-o antes de dar uma fatia por pronta.
- Não há testes de unidade (`npm test` não faz nada).
- Variáveis de ambiente: veja `.env.example`. `JWT_SECRET` é obrigatória; `CORS_ORIGIN` é obrigatória
  em produção; `FUSO_EVENTO` troca o fuso do evento (padrão `America/Bahia`).

## Estrutura
- `server.js` — monta as rotas em `/api`.
- `src/config/db.js` — pool MySQL. `src/middlewares/authMiddleware.js` — `verificarToken`.
- `src/controllers/*` (regras) e `src/routes/*` (rotas). Um par por recurso.

## Convenções (mantenha)
- Nomes de variáveis, funções e mensagens em **português**.
- Erros: `res.status(x).json({ erro: '...' })`. O front exibe `error.mensagem` vindo dessa chave.
- Rotas de escrita protegidas com `verificarToken`; leituras públicas.
- Várias escritas relacionadas = **transação** (`db.getConnection()`, `beginTransaction`, `commit`/`rollback`, `release` no `finally`).
- Classificação é **calculada a partir dos jogos**, não guardada.
- Mudanças de banco: **script SQL versionado** (`db/schema.sql`, `db/migracoes/`), nunca só manual.

## Regras de trabalho
- Não leia nem exiba `.env`. Nunca comite segredos.
- Não faça commit/push sem o usuário pedir. Trabalhe na branch de desenvolvimento.
- Regras do regulamento e decisões estão no contexto acima. Itens marcados **[PENDENTE]** exigem perguntar ao usuário antes de implementar.
- Dúvidas de negócio: pare e pergunte. Não invente regra.
- **Fatias:** a numeração válida é a da tabela da seção 9 do contexto. Cite número e nome ("fatia 5 — futsal completo") e atualize o estado ao concluir.
