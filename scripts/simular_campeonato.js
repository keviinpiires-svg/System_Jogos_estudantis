// ============================================================================
// SIMULAÇÃO DO CAMPEONATO — lança, pela API e como ADMIN, resultados aleatórios
// (mas realistas) em todos os jogos, na ordem do numero_tabela, dia por dia, e
// confere a Tabela Geral por conta própria no fim.
//
// SÓ PARA CÓPIA LOCAL. A API precisa ser localhost (a trava abaixo recusa
// qualquer outro endereço): nunca aponte para a produção. Não há dado de aluno
// neste arquivo: nomes e atletas vêm da própria API, na hora.
//
// Uso (com a API local no ar):
//   SIMULACAO_EMAIL=... SIMULACAO_SENHA=... node scripts/simular_campeonato.js
//     [--api=http://localhost:3001/api] [--ate=2026-11-19] [--semente=123] [--wo=2]
//   --ate      simula só os jogos até esse dia (inclusive); atletismo e tabuleiro
//              só entram quando a simulação vai até o último dia
//   --semente  repete a mesma simulação
//   --wo       quantos jogos de grupo viram W.O. (padrão 2)
// ============================================================================

const argumentos = Object.fromEntries(process.argv.slice(2).map((a) => {
  const [chave, ...resto] = a.replace(/^--/, '').split('=');
  return [chave, resto.join('=') || true];
}));

const API = String(argumentos.api || process.env.SIMULACAO_API || 'http://localhost:3001/api').replace(/\/$/, '');
const EMAIL = argumentos.email || process.env.SIMULACAO_EMAIL;
const SENHA = argumentos.senha || process.env.SIMULACAO_SENHA;
const ATE = argumentos.ate || null;
const QTD_WO = argumentos.wo === undefined ? 2 : Number(argumentos.wo);
const SEMENTE = Number(argumentos.semente || Math.floor(Math.random() * 1e9));

// Trava: só cópia local
const host = new URL(API).hostname;
if (!['localhost', '127.0.0.1'].includes(host)) {
  console.error(`Recusado: a simulação só roda contra uma API local (recebi ${host}).`);
  process.exit(1);
}
if (!EMAIL || !SENHA) {
  console.error('Informe SIMULACAO_EMAIL e SIMULACAO_SENHA (o ADMIN da cópia local).');
  process.exit(1);
}
if (ATE && !/^\d{4}-\d{2}-\d{2}$/.test(ATE)) {
  console.error('--ate deve ser AAAA-MM-DD.');
  process.exit(1);
}

// ---------------------------------------------------------------- sorteio com semente
let estado = SEMENTE >>> 0;
const aleatorio = () => {
  estado = (estado + 0x6D2B79F5) >>> 0;
  let t = estado;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const inteiro = (min, max) => min + Math.floor(aleatorio() * (max - min + 1));
const chance = (p) => aleatorio() < p;
const escolher = (lista) => lista[Math.floor(aleatorio() * lista.length)];
const embaralhar = (lista) => {
  const a = [...lista];
  for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(aleatorio() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; }
  return a;
};

// ---------------------------------------------------------------- API
let token = null;
const chamar = async (metodo, rota, corpo) => {
  const r = await fetch(`${API}${rota}`, {
    method: metodo,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: corpo === undefined ? undefined : JSON.stringify(corpo)
  });
  let dados = null;
  try { dados = await r.json(); } catch { dados = null; }
  return { status: r.status, dados };
};
const ler = async (rota) => {
  const r = await chamar('GET', rota);
  if (r.status !== 200) throw new Error(`GET ${rota}: ${r.status} ${r.dados?.erro || ''}`);
  return r.dados;
};

// ---------------------------------------------------------------- registro do que aconteceu
const sorteios = [];
const wos = [];
const problemas = [];

// ---------------------------------------------------------------- placares por modalidade
const golsDoJogo = (slug) => {
  if (slug === 'handebol') return inteiro(3, 16);
  if (slug === 'futebol-society') return escolher([0, 0, 1, 1, 1, 2, 2, 3, 4]);
  return escolher([0, 0, 1, 1, 2, 2, 3, 3, 4, 5, 6]); // futsal
};

// Reparte um total entre os atletas presentes (alguns marcam mais)
const repartir = (total, atletas, passo = 1, teto = Infinity) => {
  const valores = new Map(atletas.map((a) => [a.atleta_id, 0]));
  if (!atletas.length) return valores;
  let resta = total;
  let guarda = 0;
  while (resta > 0 && guarda++ < 10000) {
    const a = escolher(atletas.slice(0, Math.max(3, Math.ceil(atletas.length * 0.6))));
    const v = Math.min(passo, resta);
    if (valores.get(a.atleta_id) + v > teto) continue;
    valores.set(a.atleta_id, valores.get(a.atleta_id) + v);
    resta -= v;
  }
  return valores;
};

const setsAleatorios = () => {
  const vence1 = chance(0.5);
  const tres = chance(0.35);
  const set = (ganha1) => {
    const perdedor = inteiro(8, 19);
    const prorrogado = chance(0.12);
    const [v, p] = prorrogado ? [22 + inteiro(0, 3), 0] : [21, perdedor];
    const pontosPerdedor = prorrogado ? v - 2 : p;
    return ganha1 ? [v, pontosPerdedor] : [pontosPerdedor, v];
  };
  const lista = tres ? [set(vence1), set(!vence1), set(vence1)] : [set(vence1), set(vence1)];
  return lista.map(([p1, p2], i) => ({ numero_set: i + 1, pontos_1: p1, pontos_2: p2 }));
};

// Monta a súmula de uma equipe: presença (suspensos fora), capitão, estatística e cartões
const montarEquipe = (equipe, folha, slug, suspensos, alvo) => {
  const inscritos = equipe.atletas.slice(0, folha.linhasMaximas || 14);
  const presentes = inscritos.filter((a) => !suspensos.has(a.atleta_id));
  const linhas = inscritos.map((a) => ({
    atleta_id: a.atleta_id, presente: !suspensos.has(a.atleta_id), capitao: false,
    gols: 0, amarelos: 0, vermelho: false, faltas: 0, desqualificado: false
  }));
  const daLinha = new Map(linhas.map((l) => [l.atleta_id, l]));
  if (presentes[0]) daLinha.get(presentes[0].atleta_id).capitao = true;

  const corpo = { equipe_id: equipe.equipe_id, faltas_1t: 0, faltas_2t: 0 };
  let placar = 0;

  if (slug === 'baleado') {
    const total = Math.min(10, alvo);
    if (presentes.length) {
      const porAtleta = repartir(total, presentes, 1, 10);
      for (const [id, v] of porAtleta) daLinha.get(id).gols = v;
    } else {
      corpo.baleados = total; // equipe sem atleta: só o contador da equipe
    }
    placar = total;
  } else if (slug === 'basquete') {
    if (presentes.length) {
      const porAtleta = repartir(alvo, presentes, escolher([2, 2, 2, 3, 1]));
      for (const [id, v] of porAtleta) daLinha.get(id).gols = v;
      placar = alvo;
      for (const l of linhas) if (l.presente) l.faltas = Math.min(5, escolher([0, 0, 1, 1, 2, 3, 4, 5]));
      const soma = linhas.reduce((s, l) => s + l.faltas, 0);
      corpo.faltas_1t = Math.min(7, Math.floor(soma / 2));
      corpo.faltas_2t = Math.min(7, soma - Math.floor(soma / 2));
    }
  } else if (slug !== 'volei') {
    if (presentes.length) {
      const porAtleta = repartir(alvo, presentes);
      for (const [id, v] of porAtleta) daLinha.get(id).gols = v;
      placar = alvo;
    }
    if (folha.cartoes) {
      for (const l of linhas) {
        if (!l.presente) continue;
        if (chance(0.10)) l.amarelos = 1;
        if (l.amarelos && folha.maxAmarelos >= 2 && chance(0.12)) { l.amarelos = 2; l.vermelho = true; }
        if (!l.vermelho && chance(0.012)) l.vermelho = true;
      }
    }
    if (folha.faltasPorAtleta) {
      for (const l of linhas) if (l.presente) l.faltas = escolher([0, 0, 0, 1, 1, 2]);
      const soma = linhas.reduce((s, l) => s + l.faltas, 0);
      corpo.faltas_1t = inteiro(0, soma);
      corpo.faltas_2t = soma - corpo.faltas_1t;
    }
  }
  corpo.atletas = linhas;
  return { corpo, placar };
};

// Lança a súmula de um jogo (ADMIN, finalizando). Empate que precisa de dono: resolve pela modalidade.
const lancarJogo = async (jogoId) => {
  const sumula = await ler(`/sumulas/${jogoId}`);
  const { jogo, folha } = sumula;
  const slug = jogo.modalidade_slug || sumula.jogo.slug || '';
  const susp = await ler(`/suspensoes/jogo/${jogoId}`);
  const suspensos = new Set((susp.suspensos || []).map((s) => s.atleta_id));

  const alvo = () => (slug === 'baleado' ? inteiro(2, 10) : slug === 'basquete' ? 2 * inteiro(10, 30) : golsDoJogo(slug));
  const [a, b] = sumula.equipes;
  const ea = montarEquipe(a, folha, slug, suspensos, alvo());
  const eb = montarEquipe(b, folha, slug, suspensos, alvo());
  const corpo = { jogo_id: jogoId, finalizar: true, equipes: [ea.corpo, eb.corpo] };
  if (folha.sets) corpo.sets = setsAleatorios();

  let r = await chamar('POST', '/sumulas', corpo);
  for (let tentativa = 0; tentativa < 4 && r.status === 400; tentativa++) {
    const erro = r.dados?.erro || '';
    if (/prorroga/i.test(erro) && !corpo.prorrogacao) {
      corpo.prorrogacao = true;
      // a prorrogação às vezes decide: um gol (ou cesta) a mais para um lado
      if (chance(0.5)) {
        const lado = chance(0.5) ? 0 : 1;
        const eq = corpo.equipes[lado];
        const quem = eq.atletas.find((l) => l.presente);
        if (quem) quem.gols += slug === 'basquete' ? 2 : 1;
      }
    } else if (/balear|baleou/i.test(erro)) {
      corpo.baleou_primeiro_equipe_id = escolher([a.equipe_id, b.equipe_id]);
    } else if (/pênaltis|cobran|7 metros|lances|com um vencedor/i.test(erro)) {
      const p1 = inteiro(2, 5);
      let p2 = inteiro(2, 5);
      if (p2 === p1) p2 = p1 === 5 ? 4 : p1 + 1;
      corpo.penaltis_1 = p1; corpo.penaltis_2 = p2;
    } else break;
    r = await chamar('POST', '/sumulas', corpo);
  }
  if (r.status !== 201) {
    problemas.push(`jogo nº ${jogo.numero_tabela}: ${r.status} ${r.dados?.erro || ''}`);
    return false;
  }
  return true;
};

// ---------------------------------------------------------------- vagas pendentes (sorteio)
const nomeDaVaga = (j, lado) => (lado === 1 ? j.equipe_1 : j.equipe_2);

const resolverVagasPendentes = async (jogoAgenda) => {
  const comp = jogoAgenda.competicao.id;
  const rec = await chamar('POST', `/matamata/competicao/${comp}/recalcular-vagas`);
  const pendentes = (rec.dados?.pendentes || []).filter((p) => p.jogo_id === jogoAgenda.id && /sorteio/.test(p.motivo));
  if (!pendentes.length) return false;
  const cl = await ler(`/classificacao/competicao/${comp}`);
  const agenda = await ler('/agenda');
  const daFase = agenda.filter((j) => j.competicao.id === comp && j.fase === jogoAgenda.fase);
  const ocupadas = new Set(daFase.flatMap((j) => [j.equipe_1.id, j.equipe_2.id]).filter(Boolean));
  for (const p of pendentes) {
    let candidatas = [];
    const entre = /\(([^)]+)\)\s*$/.exec(p.motivo);
    const grupoNome = /grupo ([A-Z])/i.exec(p.motivo)?.[1] || /Grupo ([A-Z])/.exec(p.origem)?.[1];
    if (entre) {
      const nomes = entre[1].split(',').map((s) => s.trim());
      candidatas = cl.grupos.flatMap((g) => g.equipes).filter((e) => nomes.includes(e.escola_nome));
    } else {
      const grupo = cl.grupos.find((g) => g.nome === grupoNome) || cl.grupos[0];
      candidatas = grupo.equipes.filter((e) => e.sorteio);
    }
    candidatas = candidatas.filter((e) => !ocupadas.has(e.equipe_id));
    if (!candidatas.length) { problemas.push(`vaga do jogo nº ${p.numero_tabela} (${p.origem}): sorteio sem candidata livre`); continue; }
    const escolhida = escolher(candidatas);
    const r = await chamar('PUT', `/jogos/${p.jogo_id}/vagas`, { lado: p.lado, equipe_id: escolhida.equipe_id });
    if (r.status === 200) {
      ocupadas.add(escolhida.equipe_id);
      sorteios.push(`${jogoAgenda.competicao.modalidade} ${jogoAgenda.competicao.categoria} ${jogoAgenda.competicao.genero}: jogo nº ${p.numero_tabela}, "${p.origem}" = ${escolhida.escola_nome} (sorteada entre ${candidatas.map((c) => c.escola_nome).join(', ')})`);
    } else {
      problemas.push(`vaga do jogo nº ${p.numero_tabela}: ${r.status} ${r.dados?.erro || ''}`);
    }
  }
  return true;
};

// ---------------------------------------------------------------- atletismo e tabuleiro
const lancarIndividuais = async () => {
  const escolas = await ler('/escolas');
  const atl = await ler('/atletismo-colocacoes');
  let n = 0;
  for (const cat of atl.configuracao.categorias) {
    for (const prova of atl.configuracao.provas_por_categoria[cat.nome] || []) {
      for (const genero of atl.configuracao.generos) {
        const tres = embaralhar(escolas).slice(0, 3);
        const r = await chamar('PUT', '/atletismo-colocacoes/podio', {
          prova, categoria_id: cat.id, genero,
          linhas: tres.map((e, i) => ({ colocacao: i + 1, escola_id: e.id, atleta_nome: `Atleta simulado ${i + 1}` }))
        });
        if (r.status === 200) n++; else problemas.push(`atletismo ${prova} ${cat.nome} ${genero}: ${r.status} ${r.dados?.erro || ''}`);
      }
    }
  }
  const tab = await ler('/tabuleiro-colocacoes');
  let m = 0;
  for (const jogo of tab.configuracao.jogos) {
    for (const cat of tab.configuracao.categorias) {
      const tres = embaralhar(escolas).slice(0, 3);
      const r = await chamar('PUT', '/tabuleiro-colocacoes/podio', {
        jogo: jogo.slug, categoria_id: cat.id,
        linhas: tres.map((e, i) => ({ colocacao: i + 1, escola_id: e.id, atleta_nome: `Jogador simulado ${i + 1}` }))
      });
      if (r.status === 200) m++; else problemas.push(`tabuleiro ${jogo.nome} ${cat.nome}: ${r.status} ${r.dados?.erro || ''}`);
    }
  }
  return { atletismo: n, tabuleiro: m };
};

// ---------------------------------------------------------------- conferência da Tabela Geral
const conferirTabelaGeral = async () => {
  const PONTOS = { 1: 10, 2: 8, 3: 6, 4: 4, 5: 2 };
  const competicoes = await ler('/competicoes');
  const soma = new Map();
  const somar = (nome, pos) => {
    if (!soma.has(nome)) soma.set(nome, { pontos: 0, p1: 0, p2: 0, p3: 0 });
    const s = soma.get(nome);
    s.pontos += PONTOS[pos] || 0;
    if (pos === 1) s.p1++; if (pos === 2) s.p2++; if (pos === 3) s.p3++;
  };
  const campeoes = [];
  for (const c of competicoes) {
    const mm = await ler(`/matamata/competicao/${c.id}`);
    for (const col of mm.colocacoes || []) somar(col.escola_nome, col.posicao);
    const campeao = (mm.colocacoes || []).find((x) => x.posicao === 1);
    campeoes.push({ c, campeao: campeao?.escola_nome || null, pendentes: mm.colocacoes_pendentes || [] });
  }
  for (const r of (await ler('/atletismo-colocacoes')).resultados) somar(r.escola_nome, r.colocacao);
  for (const r of (await ler('/tabuleiro-colocacoes')).resultados) somar(r.escola_nome, r.colocacao);
  const ajustes = await ler('/ajustes-pontos');
  for (const a of (ajustes.ajustes || ajustes || [])) {
    if (!soma.has(a.escola_nome)) soma.set(a.escola_nome, { pontos: 0, p1: 0, p2: 0, p3: 0 });
    soma.get(a.escola_nome).pontos += Number(a.pontos);
  }
  const ordem = [...soma.entries()].sort((x, y) => y[1].pontos - x[1].pontos || y[1].p1 - x[1].p1 || y[1].p2 - x[1].p2 || y[1].p3 - x[1].p3);
  const posicao = new Map();
  ordem.forEach(([nome, s], i) => {
    const ant = ordem[i - 1];
    const igual = ant && ant[1].pontos === s.pontos && ant[1].p1 === s.p1 && ant[1].p2 === s.p2 && ant[1].p3 === s.p3;
    posicao.set(nome, igual ? posicao.get(ant[0]) : i + 1);
  });
  const tg = await ler('/tabela-geral');
  const divergencias = [];
  for (const [nome, s] of soma) {
    const l = tg.geral.find((x) => x.escola_nome === nome);
    if (!l) { if (s.pontos) divergencias.push(`${nome}: fora da tabela`); continue; }
    if (l.pontos !== s.pontos || l.primeiros !== s.p1 || l.segundos !== s.p2 || l.terceiros !== s.p3 || l.posicao !== posicao.get(nome)) {
      divergencias.push(`${nome}: esperado ${posicao.get(nome)}º ${s.pontos} pts (${s.p1}/${s.p2}/${s.p3}), API ${l.posicao}º ${l.pontos} (${l.primeiros}/${l.segundos}/${l.terceiros})`);
    }
  }
  return { tg, divergencias, campeoes };
};

// ---------------------------------------------------------------- principal
(async () => {
  const login = await chamar('POST', '/login', { email: EMAIL, senha: SENHA });
  if (login.status !== 200) throw new Error(`login: ${login.status} ${login.dados?.erro || ''}`);
  if (login.dados.usuario?.perfil && login.dados.usuario.perfil !== 'ADMIN') throw new Error('a conta precisa ser ADMIN');
  token = login.dados.token;
  console.log(`Simulação contra ${API} (semente ${SEMENTE}${ATE ? `, até ${ATE}` : ', até o fim'})`);

  let agenda = await ler('/agenda');
  const dentro = (j) => j.data && (!ATE || j.data <= ATE);
  const ultimoDia = agenda.reduce((m, j) => (j.data && j.data > m ? j.data : m), '');

  // W.O.: alguns jogos de grupo ainda agendados, com as duas equipes
  const candidatosWO = embaralhar(agenda.filter((j) => dentro(j) && j.fase === 'GRUPOS' && j.status === 'AGENDADO' && j.equipe_1.id && j.equipe_2.id));
  const viramWO = new Set(candidatosWO.slice(0, QTD_WO).map((j) => j.id));

  let feitos = 0;
  for (let volta = 0; volta < 8; volta++) {
    agenda = await ler('/agenda');
    const restantes = agenda.filter((j) => dentro(j) && ['AGENDADO', 'EM_ANDAMENTO'].includes(j.status))
      .sort((x, y) => x.numero_tabela - y.numero_tabela);
    if (!restantes.length) break;
    let progresso = false;
    for (const j of restantes) {
      let atual = (await ler(`/agenda/jogos/${j.id}`));
      if (!atual.equipe_1?.id || !atual.equipe_2?.id) {
        await resolverVagasPendentes(j);
        atual = await ler(`/agenda/jogos/${j.id}`);
        if (!atual.equipe_1?.id || !atual.equipe_2?.id) continue; // a origem ainda não terminou
      }
      if (viramWO.has(j.id)) {
        const vencedor = escolher([atual.equipe_1.id, atual.equipe_2.id]);
        const r = await chamar('PUT', `/jogos/${j.id}/wo`, { vencedor_equipe_id: vencedor, motivo: 'Simulação: a outra equipe não compareceu' });
        if (r.status === 200) {
          wos.push(`jogo nº ${j.numero_tabela} (${j.competicao.modalidade} ${j.competicao.categoria} ${j.competicao.genero}): W.O. para ${vencedor === atual.equipe_1.id ? atual.equipe_1.escola : atual.equipe_2.escola}`);
          feitos++; progresso = true;
        } else problemas.push(`W.O. do jogo nº ${j.numero_tabela}: ${r.status} ${r.dados?.erro || ''}`);
        continue;
      }
      if (await lancarJogo(j.id)) { feitos++; progresso = true; }
    }
    if (!progresso) break;
  }

  // 3º lugar empatado até o sorteio: o ADMIN escolhe
  for (const c of await ler('/competicoes')) {
    const mm = await ler(`/matamata/competicao/${c.id}`);
    for (const p of mm.colocacoes_pendentes || []) {
      const e = escolher(p.candidatas);
      const r = await chamar('PUT', `/matamata/competicao/${c.id}/colocacao`, { posicao: p.posicao, equipe_id: e.equipe_id });
      if (r.status === 200) sorteios.push(`${c.modalidade_nome} ${c.categoria_nome} ${c.genero}: ${p.posicao}º lugar = ${e.escola_nome} (sorteada entre ${p.candidatas.map((x) => x.escola_nome).join(', ')})`);
      else problemas.push(`colocação ${c.id}: ${r.status} ${r.dados?.erro || ''}`);
    }
  }

  let individuais = null;
  if (!ATE || ATE >= ultimoDia) individuais = await lancarIndividuais();

  // Relatório
  agenda = await ler('/agenda');
  const semResultado = agenda.filter((j) => !['FINALIZADO', 'WO'].includes(j.status));
  const motivo = (j) => (!dentro(j) ? 'depois do --ate' : (!j.equipe_1.id || !j.equipe_2.id) ? `equipe a definir (${j.equipe_1.escola || j.equipe_1.origem} x ${j.equipe_2.escola || j.equipe_2.origem})` : 'não lançado (ver problemas)');
  console.log(`\nJogos lançados nesta execução: ${feitos} (W.O.: ${wos.length})`);
  wos.forEach((w) => console.log(`  W.O. ${w}`));
  console.log(`\nSorteios decididos pelo ADMIN (${sorteios.length}):`);
  sorteios.forEach((s) => console.log(`  - ${s}`));
  if (individuais) console.log(`\nPódios lançados: atletismo ${individuais.atletismo}, tabuleiro ${individuais.tabuleiro}`);
  console.log(`\nJogos sem resultado: ${semResultado.length}`);
  const porMotivo = {};
  for (const j of semResultado) { const m = motivo(j); (porMotivo[m] = porMotivo[m] || []).push(j.numero_tabela); }
  for (const [m, nums] of Object.entries(porMotivo)) console.log(`  - ${nums.length}: ${m.startsWith('equipe') ? 'equipe a definir' : m}${nums.length <= 12 ? ` (nº ${nums.join(', ')})` : ''}`);
  if (problemas.length) { console.log(`\nProblemas (${problemas.length}):`); problemas.forEach((p) => console.log(`  - ${p}`)); }

  const { tg, divergencias, campeoes } = await conferirTabelaGeral();
  console.log('\nTabela Geral (top 5):');
  tg.geral.slice(0, 5).forEach((l) => console.log(`  ${l.posicao}º ${l.escola_nome}: ${l.pontos} pts (ouro ${l.primeiros}, prata ${l.segundos}, bronze ${l.terceiros})`));
  console.log(divergencias.length
    ? `\nCONFERÊNCIA DA TABELA GERAL: ${divergencias.length} divergência(s)\n  - ${divergencias.join('\n  - ')}`
    : '\nConferência da Tabela Geral: bate escola a escola (pontos 10/8/6/4/2 + atletismo e tabuleiro 10/8/6, medalhas e posições).');
  console.log('\nCampeões por competição:');
  for (const { c, campeao, pendentes } of campeoes) {
    console.log(`  ${c.modalidade_nome} ${c.categoria_nome} ${c.genero}: ${campeao || '—'}${pendentes.length ? ' (pódio com sorteio pendente)' : ''}`);
  }
  process.exit(divergencias.length || problemas.length ? 1 : 0);
})().catch((e) => { console.error('Falhou:', e.message); process.exit(1); });
