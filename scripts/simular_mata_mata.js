// Campeonato simulado do mata-mata cadastrado de antemão (db/28, 06/11/2026).
//
// Para uma competição de cada formato (A, B, C e D, este com "melhor 2º colocado"), cadastra
// os jogos do mata-mata com a ORIGEM de cada vaga (como o script dos 75 jogos fará), termina
// a fase de grupos pela API e confere:
//   * antes: a Agenda mostra a origem no lugar da escola e a súmula abre em branco com a origem;
//   * as vagas de GRUPO se preenchem quando o grupo fecha, a de MELHOR só quando todos fecham;
//   * a semifinal leva o vencedor (por W.O. ou nas cobranças) à final;
//   * a troca manual de uma vaga não é desfeita pelo automático, e "voltar ao automático" refaz;
//   * jogo iniciado ou encerrado não muda de equipe sem confirmação, nem pelo automático.
// Só roda em banco com "dev" no nome (use o jogos_fumaca_dev) e apaga o que criou.
//
// Uso (com a API de teste no ar, como o fumaca):
//   npm run fumaca:banco
//   PORT=3001 DB_NAME=jogos_fumaca_dev npm start
//   DB_NAME=jogos_fumaca_dev FUMACA_API=http://localhost:3001/api node scripts/simular_mata_mata.js
require('dotenv').config({ quiet: true });
const bcrypt = require('bcryptjs');
const db = require('../src/config/db');

const API = process.env.FUMACA_API || 'http://localhost:3000/api';
const EMAIL = 'simulacao-matamata@local';
const SENHA = 'simulacao-senha-longa';
const BASE_TABELA = 9000; // numero_tabela dos jogos simulados (fora da faixa real)

let ok = 0;
let falhas = 0;
const conferir = (certo, descricao, detalhe) => {
  if (certo) { ok += 1; console.log(`  ok    ${descricao}`); } else {
    falhas += 1; console.log(`  FALHA ${descricao}${detalhe ? `\n          ${detalhe}` : ''}`);
  }
};
const secao = (t) => console.log(`\n${t}`);

let token = null;
const chamar = async (metodo, caminho, corpo) => {
  const r = await fetch(`${API}${caminho}`, {
    method: metodo,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    ...(corpo ? { body: JSON.stringify(corpo) } : {})
  });
  return { status: r.status, corpo: await r.json().catch(() => ({})) };
};

const bancoAtual = () => {
  const url = process.env.DATABASE_URL || process.env.MYSQL_URL;
  if (url) return decodeURIComponent(new URL(url).pathname.replace(/^\//, ''));
  return process.env.DB_NAME || '';
};

// ---------------------------------------------------------------------------
// Montagem
// ---------------------------------------------------------------------------
const criados = { jogos: [] };
let numeroTabela = BASE_TABELA;

const competicaoDoFormato = async (qtdGrupos, classificados, melhores, proxima) => {
  const [[c]] = await db.query(
    `SELECT c.id, CONCAT(m.nome, ' ', cat.nome, ' ', c.genero) AS nome
       FROM competicoes c
       INNER JOIN modalidades m ON m.id = c.modalidade_id AND m.tipo_placar = 'GOLS'
       INNER JOIN categorias cat ON cat.id = c.categoria_id
      WHERE c.qtd_grupos = ? AND c.classificados_por_grupo = ? AND c.melhores_segundos = ? AND c.proxima_fase = ?
        AND NOT EXISTS (SELECT 1 FROM jogos j WHERE j.competicao_id = c.id)
      ORDER BY c.id LIMIT 1`,
    [qtdGrupos, classificados, melhores, proxima]
  );
  if (!c) throw new Error(`Sem competição livre no formato ${qtdGrupos}x${classificados}+${melhores} ${proxima}.`);

  const [grupos] = await db.query('SELECT id, nome FROM grupos WHERE competicao_id = ? ORDER BY nome', [c.id]);
  const [equipes] = await db.query(
    `SELECT e.id, e.grupo_id, esc.nome AS escola FROM equipes e INNER JOIN escolas esc ON esc.id = e.escola_id
      WHERE e.competicao_id = ? ORDER BY e.grupo_id, esc.nome`,
    [c.id]
  );
  return { ...c, grupos, equipes };
};

// Todos contra todos dentro de cada grupo, fase de grupos
const criarJogosDeGrupo = async (comp) => {
  const jogos = [];
  let numero = 1;
  for (const grupo of comp.grupos) {
    const doGrupo = comp.equipes.filter((e) => e.grupo_id === grupo.id);
    for (let i = 0; i < doGrupo.length; i += 1) {
      for (let j = i + 1; j < doGrupo.length; j += 1) {
        const [r] = await db.query(
          `INSERT INTO jogos (competicao_id, numero_jogo, fase, grupo_id, equipe_1_id, equipe_2_id)
           VALUES (?, ?, 'GRUPOS', ?, ?, ?)`,
          [comp.id, numero, grupo.id, doGrupo[i].id, doGrupo[j].id]
        );
        criados.jogos.push(r.insertId);
        jogos.push({ id: r.insertId, grupo_id: grupo.id, e1: doGrupo[i].id, e2: doGrupo[j].id });
        numero += 1;
      }
    }
  }
  comp.proximoNumero = numero;
  return jogos;
};

// Um jogo de mata-mata sem equipes, com a origem das duas vagas
const criarJogoMataMata = async (comp, fase, vaga1, vaga2, dia, hora) => {
  const [r] = await db.query(
    `INSERT INTO jogos (competicao_id, numero_jogo, numero_tabela, fase, data_hora, local_id, equipe_1_id, equipe_2_id)
     VALUES (?, ?, ?, ?, ?, 1, NULL, NULL)`,
    [comp.id, comp.proximoNumero, numeroTabela, fase, `2026-11-${dia} ${hora}:00`]
  );
  comp.proximoNumero += 1;
  const jogo = { id: r.insertId, numero_tabela: numeroTabela };
  numeroTabela += 1;
  criados.jogos.push(jogo.id);
  for (const [lado, v] of [[1, vaga1], [2, vaga2]]) {
    await db.query(
      `INSERT INTO jogo_vagas (jogo_id, lado, tipo, grupo_id, posicao, jogo_origem_id, rotulo) VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [jogo.id, lado, v.tipo, v.grupo_id ?? null, v.posicao ?? null, v.jogo_origem_id ?? null, v.rotulo]
    );
  }
  return jogo;
};

const grupo = (comp, nome, posicao) => {
  const g = comp.grupos.find((x) => x.nome === nome);
  return { tipo: 'GRUPO', grupo_id: g.id, posicao, rotulo: `${posicao}º do Grupo ${nome}` };
};
const vencedor = (jogo) => ({ tipo: 'VENCEDOR', jogo_origem_id: jogo.id, rotulo: `Vencedor do jogo ${jogo.numero_tabela}` });

// ---------------------------------------------------------------------------
// Ações pela API
// ---------------------------------------------------------------------------
const wo = (jogoId, vencedorId) => chamar('PUT', `/jogos/${jogoId}/wo`, {
  vencedor_equipe_id: vencedorId, motivo: 'simulação do mata-mata'
});

// Súmula sem atletas empatada em 0 x 0: no mata-mata decide nas cobranças
const cobrancas = (jogoId, comp, e1, e2, p1, p2) => chamar('POST', '/sumulas', {
  jogo_id: jogoId, finalizar: true, penaltis_1: p1, penaltis_2: p2, prorrogacao: false,
  equipes: [{ equipe_id: e1, atletas: [] }, { equipe_id: e2, atletas: [] }]
});

const jogoNaApi = async (jogoId) => (await chamar('GET', `/jogos/${jogoId}`)).corpo;
const equipesDoJogo = async (jogoId) => {
  const j = await jogoNaApi(jogoId);
  return [j.equipe_1_id, j.equipe_2_id];
};
const nomeEscola = (comp, id) => comp.equipes.find((e) => e.id === id)?.escola || String(id);

// Termina os jogos de um grupo, sempre com a equipe 1 vencendo (a de cima na lista)
const terminarGrupo = async (jogos, grupoId) => {
  for (const j of jogos.filter((x) => x.grupo_id === grupoId)) {
    const r = await wo(j.id, j.e1);
    if (r.status !== 200) throw new Error(`W.O. do jogo ${j.id} falhou: ${r.corpo.erro}`);
  }
};

const classificacao = async (compId) => (await chamar('GET', `/classificacao/competicao/${compId}`)).corpo;
const posicaoDoGrupo = (cl, nomeGrupo, posicao) => cl.grupos.find((g) => g.nome === nomeGrupo)?.equipes[posicao - 1]?.equipe_id;

const recalcular = (compId) => chamar('POST', `/matamata/competicao/${compId}/recalcular-vagas`);

// ---------------------------------------------------------------------------
const apagar = async () => {
  if (criados.jogos.length) {
    await db.query('DELETE FROM jogo_vagas WHERE jogo_id IN (?)', [criados.jogos]);
    await db.query('DELETE FROM sumula_atletas WHERE jogo_id IN (?)', [criados.jogos]);
    await db.query('DELETE FROM sumula_equipes WHERE jogo_id IN (?)', [criados.jogos]);
    await db.query('DELETE FROM jogo_sets WHERE jogo_id IN (?)', [criados.jogos]);
    await db.query('DELETE FROM jogos WHERE id IN (?)', [criados.jogos]);
    criados.jogos = [];
  }
  await db.query('DELETE FROM usuarios WHERE email = ?', [EMAIL]);
};

const rodar = async () => {
  const banco = bancoAtual();
  if (!/dev/i.test(banco)) throw new Error(`Só roda em banco com "dev" no nome; esta conexão cai em "${banco}".`);
  if (process.env.NODE_ENV === 'production') throw new Error('Não roda com NODE_ENV=production.');
  console.log(`Simulação do mata-mata — banco ${banco}, API ${API}`);

  await apagar();
  await db.query('INSERT INTO usuarios (nome, email, senha, perfil) VALUES (?, ?, ?, ?)',
    ['Simulação mata-mata', EMAIL, bcrypt.hashSync(SENHA, 10), 'ADMIN']);
  token = (await chamar('POST', '/login', { email: EMAIL, senha: SENHA })).corpo.token;
  conferir(Boolean(token), 'login do ADMIN de teste');

  // ------------------------------------------------------------------ formato C (semifinal)
  secao('-- Formato C: 2 grupos, 2 classificados, semifinal e final');
  const c = await competicaoDoFormato(2, 2, 0, 'SEMIFINAL');
  console.log(`  ${c.nome} (competição ${c.id})`);
  const gc = await criarJogosDeGrupo(c);
  const semi1 = await criarJogoMataMata(c, 'SEMIFINAL', grupo(c, 'A', 1), grupo(c, 'B', 2), '20', '10:00');
  const semi2 = await criarJogoMataMata(c, 'SEMIFINAL', grupo(c, 'B', 1), grupo(c, 'A', 2), '20', '10:40');
  const finalC = await criarJogoMataMata(c, 'FINAL', vencedor(semi1), vencedor(semi2), '21', '10:00');

  // Antes: a Agenda mostra a origem; a súmula abre em branco com a origem; não inicia nem lança
  const agenda = (await chamar('GET', '/agenda')).corpo;
  const naAgenda = agenda.find((j) => j.id === semi1.id);
  conferir(naAgenda && naAgenda.equipe_1.escola === null && naAgenda.equipe_1.origem === '1º do Grupo A'
    && naAgenda.equipe_2.origem === '2º do Grupo B' && naAgenda.numero_tabela === semi1.numero_tabela,
  'Agenda mostra a origem das vagas e o número da tabela enquanto não há equipe', JSON.stringify(naAgenda?.equipe_1));
  const detalhe = (await chamar('GET', `/agenda/jogos/${semi1.id}`)).corpo;
  conferir(detalhe.equipe_1?.atletas?.length === 0 && detalhe.equipe_1.origem === '1º do Grupo A',
    'detalhe público do jogo sem equipe: origem e nenhum atleta');
  const sumulaVazia = (await chamar('GET', `/sumulas/${semi1.id}`)).corpo;
  conferir(sumulaVazia.equipes?.[0]?.escola_nome === '1º do Grupo A' && sumulaVazia.equipes[0].a_definir === true
    && sumulaVazia.equipes[1].escola_nome === '2º do Grupo B',
  'súmula em branco abre com a origem no lugar do nome da equipe', JSON.stringify(sumulaVazia.equipes?.map((e) => e.escola_nome)));
  const lista = (await chamar('GET', `/jogos?competicao_id=${c.id}&fase=SEMIFINAL`)).corpo;
  conferir(lista.length === 2 && lista[0].equipe_1_nome === null && lista[0].origem_1 === '1º do Grupo A',
    'lista de jogos da competição traz a origem (tabela de jogos da tela)');
  const iniciaVazio = await chamar('PUT', `/jogos/${semi1.id}/iniciar`);
  const sumulaVazio = await cobrancas(semi1.id, c, 1, 2, 3, 1);
  conferir(iniciaVazio.status === 409 && sumulaVazio.status === 409, 'jogo sem equipes não inicia nem recebe súmula',
    `${iniciaVazio.status}/${sumulaVazio.status}`);
  const gerarVelho = await chamar('POST', `/matamata/competicao/${c.id}/gerar`);
  conferir(gerarVelho.status === 409, '"gerar" por classificação não se aplica a mata-mata cadastrado', `${gerarVelho.status}`);

  // Grupo A termina; o B ainda não
  const gA = c.grupos.find((g) => g.nome === 'A');
  const gB = c.grupos.find((g) => g.nome === 'B');
  await terminarGrupo(gc, gA.id);
  let [a1, a2] = await equipesDoJogo(semi1.id);
  let [b1, b2] = await equipesDoJogo(semi2.id);
  const clA = await classificacao(c.id);
  conferir(a1 === posicaoDoGrupo(clA, 'A', 1) && b2 === posicaoDoGrupo(clA, 'A', 2) && a2 === null && b1 === null,
    'ao fechar o grupo A, só as vagas do A (1º e 2º) se preenchem; as do B continuam abertas',
    `semi1=${a1}/${a2} semi2=${b1}/${b2}`);

  await terminarGrupo(gc, gB.id);
  [a1, a2] = await equipesDoJogo(semi1.id);
  [b1, b2] = await equipesDoJogo(semi2.id);
  const cl = await classificacao(c.id);
  conferir(a1 === posicaoDoGrupo(cl, 'A', 1) && a2 === posicaoDoGrupo(cl, 'B', 2)
    && b1 === posicaoDoGrupo(cl, 'B', 1) && b2 === posicaoDoGrupo(cl, 'A', 2),
  'ao fechar o grupo B, as semifinais saem cruzadas: 1ºA x 2ºB e 1ºB x 2ºA',
  `${nomeEscola(c, a1)} x ${nomeEscola(c, a2)} / ${nomeEscola(c, b1)} x ${nomeEscola(c, b2)}`);
  let [f1, f2] = await equipesDoJogo(finalC.id);
  conferir(f1 === null && f2 === null, 'a final continua sem equipes enquanto as semifinais não terminam');

  // Semifinal 1 por W.O.: o vencedor ocupa a vaga 1 da final
  await wo(semi1.id, a2);
  [f1, f2] = await equipesDoJogo(finalC.id);
  conferir(f1 === a2 && f2 === null, 'vencedor da semifinal 1 (por W.O.) vai sozinho para a final', `${f1}/${f2}`);

  // Semifinal 2 empatada, decidida nas cobranças
  const ini = await chamar('PUT', `/jogos/${semi2.id}/iniciar`);
  const cob = await cobrancas(semi2.id, c, b1, b2, 2, 4);
  conferir(ini.status === 200 && cob.status === 201 && cob.corpo.status === 'FINALIZADO',
    'semifinal 2 empata em 0 x 0 e termina nas cobranças', `${ini.status}/${cob.status} ${cob.corpo.erro || ''}`);
  [f1, f2] = await equipesDoJogo(finalC.id);
  conferir(f1 === a2 && f2 === b2, 'vencedor nas cobranças ocupa a outra vaga da final', `${f1}/${f2} (esperado ${a2}/${b2})`);

  // Troca manual: o ADMIN põe outra equipe na vaga 2 da final; recalcular não desfaz
  const outra = c.equipes.find((e) => e.id !== a2 && e.id !== b2);
  const manual = await chamar('PUT', `/jogos/${finalC.id}/vagas`, { lado: 2, equipe_id: outra.id });
  [f1, f2] = await equipesDoJogo(finalC.id);
  conferir(manual.status === 200 && f2 === outra.id, 'troca manual da vaga da final pelo ADMIN', `${manual.status} ${manual.corpo.erro || ''}`);
  const rec = await recalcular(c.id);
  [f1, f2] = await equipesDoJogo(finalC.id);
  conferir(rec.status === 200 && f2 === outra.id, '"recalcular vagas" não desfaz a troca manual', `${f2}`);
  const volta = await chamar('PUT', `/jogos/${finalC.id}/vagas`, { lado: 2, automatico: true });
  [f1, f2] = await equipesDoJogo(finalC.id);
  conferir(volta.status === 200 && f2 === b2, 'voltar ao automático refaz a vaga pela regra', `${volta.status} ${f2} (esperado ${b2})`);

  // Final iniciada: não muda de equipe sem confirmação, nem pelo automático
  await chamar('PUT', `/jogos/${finalC.id}/iniciar`);
  const semConfirmar = await chamar('PUT', `/jogos/${finalC.id}/vagas`, { lado: 1, equipe_id: outra.id });
  conferir(semConfirmar.status === 409, 'jogo iniciado: trocar a equipe pede confirmação', `${semConfirmar.status}`);
  const confirmada = await chamar('PUT', `/jogos/${finalC.id}/vagas`, { lado: 1, equipe_id: outra.id, confirmar: true });
  [f1, f2] = await equipesDoJogo(finalC.id);
  conferir(confirmada.status === 200 && f1 === outra.id, 'com confirmação, a troca vale', `${confirmada.status}`);
  await chamar('PUT', `/jogos/${finalC.id}/vagas`, { lado: 1, automatico: true, confirmar: true });
  [f1, f2] = await equipesDoJogo(finalC.id);
  conferir(f1 === a2, 'vaga solta de volta ao automático também refaz a equipe do jogo iniciado, com confirmação');
  // Muda o resultado de uma semifinal depois da final iniciada: o automático só avisa
  const antes = [f1, f2];
  await db.query('UPDATE jogos SET vencedor_equipe_id = ? WHERE id = ?', [a1, semi1.id]);
  const aviso = await recalcular(c.id);
  [f1, f2] = await equipesDoJogo(finalC.id);
  conferir(f1 === antes[0] && f2 === antes[1] && aviso.corpo.avisos?.length > 0,
    'final em andamento: o automático NÃO troca a equipe, só avisa', JSON.stringify(aviso.corpo.avisos));

  // ------------------------------------------------------------------ formato D (melhor 2º)
  secao('-- Formato D: 3 grupos, 1 classificado + melhor 2º colocado, semifinal e final');
  const d = await competicaoDoFormato(3, 1, 1, 'SEMIFINAL');
  console.log(`  ${d.nome} (competição ${d.id})`);
  const gd = await criarJogosDeGrupo(d);
  const dg = (n) => d.grupos.find((g) => g.nome === n);
  const melhor = { tipo: 'MELHOR', posicao: 2, rotulo: 'Melhor 2º colocado' };
  const dSemi1 = await criarJogoMataMata(d, 'SEMIFINAL', grupo(d, 'A', 1), melhor, '20', '11:20');
  const dSemi2 = await criarJogoMataMata(d, 'SEMIFINAL', grupo(d, 'B', 1), grupo(d, 'C', 1), '20', '12:00');
  const dFinal = await criarJogoMataMata(d, 'FINAL', vencedor(dSemi1), vencedor(dSemi2), '21', '11:20');

  await terminarGrupo(gd, dg('A').id);
  let [x1, x2] = await equipesDoJogo(dSemi1.id);
  let clD = await classificacao(d.id);
  conferir(x1 === posicaoDoGrupo(clD, 'A', 1) && x2 === null, 'só o grupo A fechou: 1ºA entra e o melhor 2º continua aberto', `${x1}/${x2}`);
  await terminarGrupo(gd, dg('B').id);
  [x1, x2] = await equipesDoJogo(dSemi1.id);
  conferir(x2 === null, 'faltando o grupo C, o melhor 2º ainda NÃO é decidido', `${x2}`);
  await terminarGrupo(gd, dg('C').id);
  [x1, x2] = await equipesDoJogo(dSemi1.id);
  const [y1, y2] = await equipesDoJogo(dSemi2.id);
  clD = await classificacao(d.id);
  const melhorEsperado = (await chamar('GET', `/matamata/competicao/${d.id}`)).corpo.melhores_segundos?.[0]?.equipe_id;
  conferir(x1 === posicaoDoGrupo(clD, 'A', 1) && x2 === melhorEsperado && y1 === posicaoDoGrupo(clD, 'B', 1)
    && y2 === posicaoDoGrupo(clD, 'C', 1),
  'com os 3 grupos fechados: 1ºA x melhor 2º e 1ºB x 1ºC',
  `${nomeEscola(d, x1)} x ${nomeEscola(d, x2)} / ${nomeEscola(d, y1)} x ${nomeEscola(d, y2)}; melhor 2º esperado ${nomeEscola(d, melhorEsperado)}`);
  // ---- Trava: dentro da competição e fase, uma equipe só ocupa UMA vaga (06/11/2026)
  secao('-- Trava: o melhor 2º pula quem já está numa vaga fixa da fase');
  const melhorA = melhorEsperado;
  const grupoDe = (equipeId) => d.equipes.find((e) => e.id === equipeId).grupo_id;
  const nomeDoGrupo = (gid) => d.grupos.find((g) => g.id === gid).nome;
  const gMelhor = grupoDe(melhorA);
  const segundosDosOutros = d.grupos.filter((g) => g.id !== gMelhor).map((g) => posicaoDoGrupo(clD, g.nome, 2));
  const primeiroDeOutro = d.grupos.find((g) => g.id !== gMelhor).nome;
  const extras = [];
  // Na FINAL (nenhuma vaga de vencedor resolvida ainda): J1 = melhor 2º x 1º de outro grupo; J2 = o 2º do grupo do melhor 2º (vaga fixa)
  const j1 = await criarJogoMataMata(d, 'FINAL', melhor, grupo(d, primeiroDeOutro, 1), '21', '17:00');
  const j2 = await criarJogoMataMata(d, 'FINAL',
    { tipo: 'GRUPO', grupo_id: gMelhor, posicao: 2, rotulo: `2º do Grupo ${nomeDoGrupo(gMelhor)}` },
    grupo(d, d.grupos.find((g) => g.id !== gMelhor && g.nome !== primeiroDeOutro).nome, 1), '21', '17:40');
  extras.push(j1, j2);
  const r1 = await recalcular(d.id);
  const [m1] = await equipesDoJogo(j1.id);
  const [m2] = await equipesDoJogo(j2.id);
  conferir(m2 === melhorA, 'a vaga fixa "2º do grupo" fica com a equipe que seria o melhor 2º', `${m2} (esperado ${melhorA})`);
  conferir(m1 !== melhorA && segundosDosOutros.includes(m1),
    'o melhor 2º pula a equipe que já está numa vaga fixa e entra o seguinte',
    `${nomeEscola(d, m1)} (melhor 2º original: ${nomeEscola(d, melhorA)})`);
  conferir((r1.corpo.avisos || []).some((x) => /já ocupa outra vaga/.test(x.motivo || '')), 'a troca de candidata vem como aviso para o ADMIN', JSON.stringify(r1.corpo.avisos));

  // Todas as segundas já em vagas fixas: a vaga do melhor 2º fica vazia, com aviso
  const outros = d.grupos.filter((g) => g.id !== gMelhor);
  const j3 = await criarJogoMataMata(d, 'FINAL',
    { tipo: 'GRUPO', grupo_id: outros[0].id, posicao: 2, rotulo: `2º do Grupo ${outros[0].nome}` },
    { tipo: 'GRUPO', grupo_id: outros[1].id, posicao: 2, rotulo: `2º do Grupo ${outros[1].nome}` }, '21', '18:20');
  extras.push(j3);
  const r2 = await recalcular(d.id);
  const [m1b] = await equipesDoJogo(j1.id);
  conferir(m1b === null && (r2.corpo.avisos || []).some((x) => /todas as candidatas/.test(x.motivo || '')),
    'sem candidata livre: a vaga do melhor 2º fica pendente, com aviso', `${m1b} ${JSON.stringify(r2.corpo.avisos)}`);

  // limpa os jogos extras antes de seguir
  await db.query('DELETE FROM jogo_vagas WHERE jogo_id IN (?)', [extras.map((x) => x.id)]);
  await db.query('DELETE FROM jogos WHERE id IN (?)', [extras.map((x) => x.id)]);
  criados.jogos = criados.jogos.filter((id) => !extras.some((x) => x.id === id));

  await wo(dSemi1.id, x2);
  await wo(dSemi2.id, y1);
  const [z1, z2] = await equipesDoJogo(dFinal.id);
  conferir(z1 === x2 && z2 === y1, 'as duas semifinais levam seus vencedores à final', `${z1}/${z2}`);

  // ------------------------------------------------------------------ formato B (final direta)
  secao('-- Formato B: 2 grupos, 1 classificado de cada, final');
  const b = await competicaoDoFormato(2, 1, 0, 'FINAL');
  console.log(`  ${b.nome} (competição ${b.id})`);
  const gb = await criarJogosDeGrupo(b);
  const bFinal = await criarJogoMataMata(b, 'FINAL', grupo(b, 'A', 1), grupo(b, 'B', 1), '21', '12:00');
  await terminarGrupo(gb, b.grupos[0].id);
  await terminarGrupo(gb, b.grupos[1].id);
  const clB = await classificacao(b.id);
  const [p1, p2] = await equipesDoJogo(bFinal.id);
  conferir(p1 === posicaoDoGrupo(clB, 'A', 1) && p2 === posicaoDoGrupo(clB, 'B', 1), 'final direta: 1ºA x 1ºB', `${p1}/${p2}`);

  // ------------------------------------------------------------------ formato A e grupo único
  secao('-- Formato A: grupo único, os 2 primeiros à final (1º x 2º)');
  const a = await competicaoDoFormato(1, 2, 0, 'FINAL');
  console.log(`  ${a.nome} (competição ${a.id})`);
  const ga = await criarJogosDeGrupo(a);
  const aFinal = await criarJogoMataMata(a, 'FINAL', grupo(a, a.grupos[0].nome, 1), grupo(a, a.grupos[0].nome, 2), '21', '12:40');
  await terminarGrupo(ga, a.grupos[0].id);
  const clA2 = await classificacao(a.id);
  const [q1, q2] = await equipesDoJogo(aFinal.id);
  conferir(q1 === posicaoDoGrupo(clA2, a.grupos[0].nome, 1) && q2 === posicaoDoGrupo(clA2, a.grupos[0].nome, 2), 'final do grupo único: 1º x 2º', `${q1}/${q2}`);

  // ------------------------------------------------------------------ impressão e ADMIN
  secao('-- Impressão e perfis');
  const sumulaFinal = (await chamar('GET', `/sumulas/${aFinal.id}`)).corpo;
  conferir(sumulaFinal.equipes?.every((e) => e.a_definir === false && e.equipe_id), 'com as equipes definidas, a súmula traz os nomes e os atletas inscritos');
  const semToken = token;
  token = null;
  const recSemLogin = await recalcular(a.id);
  const trocaSemLogin = await chamar('PUT', `/jogos/${aFinal.id}/vagas`, { lado: 1, equipe_id: q2 });
  token = semToken;
  conferir(recSemLogin.status === 401 && trocaSemLogin.status === 401, 'recalcular e trocar vaga exigem login de ADMIN', `${recSemLogin.status}/${trocaSemLogin.status}`);
  const geral = await chamar('POST', '/matamata/recalcular-vagas');
  conferir(geral.status === 200 && geral.corpo.competicoes >= 4, 'recalcular todas as competições com vagas', JSON.stringify(geral.corpo).slice(0, 160));
};

rodar()
  .catch((erro) => { falhas += 1; console.error('\nERRO:', erro.message); })
  .finally(async () => {
    try { await apagar(); } catch (e) { console.error('Falha ao limpar:', e.message); falhas += 1; }
    const [[sobra]] = await db.query('SELECT (SELECT COUNT(*) FROM jogos) AS jogos, (SELECT COUNT(*) FROM jogo_vagas) AS vagas');
    console.log(`\nDepois da limpeza: ${JSON.stringify(sobra)}`);
    console.log(falhas === 0 ? `\nTUDO PASSOU — ${ok} ok, 0 falhas` : `\n${falhas} FALHA(S) — ${ok} ok`);
    await db.end();
    process.exit(falhas === 0 ? 0 : 1);
  });
