# System_jogos — backend do SGE Jogos Estudantis 2026

Node 20+ / Express 5 / MySQL (`mysql2`) / JWT + bcryptjs, CommonJS. `server.js` monta as rotas
em `/api`. Frontend no repositório separado `F:\web-jogos`.

**Leia o contexto antes de qualquer tarefa de funcionalidade.** Estrutura, convenções, regras do
regulamento, decisões provisórias e o estado das fatias estão lá — não os repita aqui:
@docs/CONTEXTO_NOVO_ESCOPO.md

Banco: scripts versionados em `db/` (ordem e como aplicar em `db/README.md`).

## Comandos
- `npm run dev` — nodemon na porta 3000. `npm start` — produção.
- `npm run fumaca` — teste de fumaça: com a API no ar, monta uma competição inteira pelas rotas,
  confere cada passo e apaga o que criou. Só roda em banco com "dev" no nome. **Rode antes de dar
  uma fatia por pronta.** Não há testes de unidade (`npm test` não faz nada).
- Variáveis: veja `.env.example`. `JWT_SECRET` é obrigatória; `CORS_ORIGIN` é obrigatória em
  produção (sem ela o servidor não sobe); `FUSO_EVENTO` padrão `America/Bahia`.

## Regras de trabalho
- Não leia nem exiba `.env`. Nunca comite segredos.
- Não faça commit/push sem o usuário pedir. Trabalhe na branch de desenvolvimento.
- **Não mexa na produção** (Railway/Render) sem ordem explícita: nada de script, migração ou
  comando apontado para lá. Teste sempre no banco de desenvolvimento primeiro.
- Mudança de banco é **sempre script SQL versionado** em `db/`, numerado, nunca alteração manual.
- Dúvida de regra do campeonato: **pare e pergunte**. Itens **[PENDENTE]** (seção 12 do contexto)
  não se implementam por conta própria. Decisão provisória mora em `src/config/` e na seção 12.1 —
  nunca copiada dentro de um controller.
- **Fatias:** só a tabela da seção 9 do contexto numera. Cite número e nome ("fatia 5 — futsal
  completo") e atualize o estado dela no mesmo commit que conclui a fatia.
- Nomes e mensagens em **português**; erro é `res.status(x).json({ erro: '...' })`.
- Várias escritas relacionadas = **transação**, com `release` no `finally`.
