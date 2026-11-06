// ============================================================================
// VAGAS DO MATA-MATA — quem ocupa cada lado de um jogo cadastrado "a definir".
//
// Decisão do usuário (06/11/2026): o mata-mata segue a tabela do chefe à
// risca. Os jogos existem antes de as equipes serem conhecidas, e cada vaga
// guarda a sua ORIGEM em `jogo_vagas` (db/28):
//   GRUPO    -> a posição (1º, 2º...) de um grupo, quando o grupo fecha;
//   MELHOR   -> o melhor 2º (3º...) colocado entre os grupos, quando TODOS fecham;
//   VENCEDOR -> o vencedor de outro jogo, quando ele termina (inclusive nas
//               cobranças, no desempate ou por W.O.).
//
// Este módulo é quem preenche as vagas. Chamado depois que uma súmula é salva ou
// um W.O. é declarado, e pelo botão "recalcular vagas" do ADMIN. Regras:
//   * vaga escolhida à mão pelo ADMIN (`manual = 1`) nunca é tocada;
//   * jogo que já começou ou terminou NÃO muda de equipe por conta própria: o
//     que o automático teria feito vira aviso na resposta;
//   * dentro de uma competição e fase, UMA EQUIPE SÓ OCUPA UMA VAGA (06/11/2026): o "melhor 2º" pula quem
//     já está numa vaga fixa da mesma fase (ex.: o 2º do Grupo C, que já é uma vaga de 1ºB x 2ºC); se não
//     sobrar ninguém, a vaga fica pendente com aviso para o ADMIN. Qualquer outra repetição também
//     não é gravada e vira aviso;
//   * grupo que não fechou, ou empate sem critério (sorteio), deixa a vaga como
//     está e aparece em `pendentes`.
// Os dados vêm da classificação (a mesma da tela), então o preenchimento nunca
// diverge do que o usuário vê.
// ============================================================================

const db = require('../config/db');
const {
  montarClassificacao,
  compararEntreGrupos,
  ordenarPorCampanha
} = require('../controllers/classificacaoController');

const RESOLVIDO = ['FINALIZADO', 'WO'];

// Erro de regra com status HTTP, para as rotas responderem direito
class ErroDeVaga extends Error {
  constructor(status, mensagem) {
    super(mensagem);
    this.status = status;
  }
}

const textoDaOrigem = (vaga) => vaga.rotulo;

// Vagas da competição, com o estado do jogo em que ficam
const carregarVagas = async (conexao, competicaoId) => {
  const [vagas] = await conexao.query(
    `SELECT v.id, v.jogo_id, v.lado, v.tipo, v.grupo_id, v.posicao, v.jogo_origem_id, v.rotulo, v.manual,
            j.status, j.fase, j.equipe_1_id, j.equipe_2_id, j.numero_tabela
       FROM jogo_vagas v
       INNER JOIN jogos j ON j.id = v.jogo_id
      WHERE j.competicao_id = ?
      ORDER BY j.numero_tabela, j.id, v.lado`,
    [competicaoId]
  );
  return vagas;
};

// Quem ocupa a posição de um grupo (ou null com o motivo), olhando a classificação
const equipeDaPosicao = (grupo, posicao, ctx) => {
  const equipe = grupo.equipes[posicao - 1];
  if (!equipe) return { motivo: `o grupo ${grupo.nome} não tem ${posicao}º colocado` };

  const empatada = ctx.empatadas.has(equipe.equipe_id);
  if (empatada) return { motivo: `empate sem critério (sorteio) na posição ${posicao} do grupo ${grupo.nome}` };

  return { equipe_id: equipe.equipe_id };
};

// Os grupos que já fecharam (todos os jogos de grupo resolvidos)
const gruposFechados = async (conexao, competicaoId, grupos) => {
  const [jogos] = await conexao.query(
    `SELECT grupo_id, status FROM jogos WHERE competicao_id = ? AND fase = 'GRUPOS'`,
    [competicaoId]
  );

  const unico = grupos.length === 1;
  const fechado = new Map();
  for (const grupo of grupos) {
    const doGrupo = jogos.filter((j) => (unico ? true : j.grupo_id === grupo.id));
    fechado.set(grupo.id, doGrupo.length > 0 && doGrupo.every((j) => RESOLVIDO.includes(j.status)));
  }
  const todosFechados = jogos.length > 0 && jogos.every((j) => RESOLVIDO.includes(j.status));
  return { fechado, todosFechados };
};

// Equipes que empataram em TODOS os critérios (vão a sorteio): a vaga espera o ADMIN
const empatadasAteOFim = (dados) => {
  const ids = new Set();
  const { competicao, criterios, jogos, grupos } = dados;
  const unico = grupos.length === 1;

  for (const grupo of grupos) {
    ordenarPorCampanha(grupo.equipes.map((e) => ({ ...e })), criterios, {
      competicao,
      jogos: unico ? jogos : jogos.filter((j) => j.grupo_id === grupo.id),
      aoEmpatarAteOFim: (bloco) => bloco.forEach((e) => ids.add(e.equipe_id))
    });
  }
  return ids;
};

// ---------------------------------------------------------------------------
// resolverVagas — preenche o que já dá para preencher numa competição
// ---------------------------------------------------------------------------
// `forcarJogoId`: um jogo cuja troca o ADMIN já confirmou (jogo iniciado ou encerrado também muda).
// Devolve { competicao_id, preenchidas, limpas, avisos, pendentes }.
const resolverVagas = async (competicaoId, { forcarJogoId = null } = {}) => {
  const conexao = await db.getConnection();
  try {
    await conexao.beginTransaction();

    // Uma resolução por vez por competição
    const [[existe]] = await conexao.query('SELECT id FROM competicoes WHERE id = ? FOR UPDATE', [competicaoId]);
    if (!existe) {
      await conexao.rollback();
      throw new ErroDeVaga(404, 'Competição não encontrada.');
    }

    const vagas = await carregarVagas(conexao, competicaoId);
    const resultado = { competicao_id: competicaoId, preenchidas: 0, limpas: 0, avisos: [], pendentes: [] };

    if (vagas.length === 0) {
      await conexao.commit();
      return resultado;
    }

    // A classificação só é necessária para vagas de grupo e de melhor colocado
    const precisaDeGrupos = vagas.some((v) => v.tipo !== 'VENCEDOR');
    let dados = null;
    let fechamento = null;
    let ctx = null;
    if (precisaDeGrupos) {
      dados = await montarClassificacao(competicaoId);
      fechamento = await gruposFechados(conexao, competicaoId, dados.grupos);
      ctx = { empatadas: empatadasAteOFim(dados) };
    }

    // Os vencedores dos jogos de origem
    const origens = [...new Set(vagas.filter((v) => v.tipo === 'VENCEDOR').map((v) => v.jogo_origem_id))];
    const doJogo = new Map();
    if (origens.length) {
      const [jogos] = await conexao.query(
        'SELECT id, status, vencedor_equipe_id FROM jogos WHERE id IN (?)',
        [origens]
      );
      jogos.forEach((j) => doJogo.set(j.id, j));
    }

    // Equipes que já são de uma vaga FIXA da fase (posição de grupo resolvida, ou escolha à mão do ADMIN):
    // o "melhor colocado" não pode ser uma delas
    const reservadasDaFase = (fase) => {
      const ids = new Set();
      for (const v of vagas) {
        if (v.fase !== fase) continue;
        if (v.manual) {
          const escolhida = v.lado === 1 ? v.equipe_1_id : v.equipe_2_id;
          if (escolhida) ids.add(escolhida);
        } else if (v.tipo === 'GRUPO') {
          const g = dados.grupos.find((x) => x.id === v.grupo_id);
          if (g && fechamento.fechado.get(g.id)) {
            const r = equipeDaPosicao(g, v.posicao, ctx);
            if (r.equipe_id) ids.add(r.equipe_id);
          }
        }
      }
      return ids;
    };

    // Quem a regra manda pôr em cada vaga
    const alvoDaVaga = (vaga) => {
      if (vaga.tipo === 'GRUPO') {
        const grupo = dados.grupos.find((g) => g.id === vaga.grupo_id);
        if (!grupo) return { motivo: 'grupo da vaga não encontrado' };
        if (!fechamento.fechado.get(grupo.id)) return { motivo: `o grupo ${grupo.nome} ainda não terminou` };
        return equipeDaPosicao(grupo, vaga.posicao, ctx);
      }

      if (vaga.tipo === 'MELHOR') {
        if (!fechamento.todosFechados) return { motivo: 'a fase de grupos ainda não terminou' };
        const comparacao = compararEntreGrupos(vaga.posicao, dados);
        if (comparacao.ordenadas.length === 0) return { motivo: `nenhum grupo tem ${vaga.posicao}º colocado` };
        const reservadas = reservadasDaFase(vaga.fase);
        const livres = comparacao.ordenadas.filter((e) => !reservadas.has(e.equipe_id));
        const [melhor] = livres;
        if (!melhor) {
          return {
            motivo: `todas as candidatas ao melhor ${vaga.posicao}º colocado já ocupam outra vaga desta fase: escolha a equipe à mão`,
            aviso: true
          };
        }
        const pulou = comparacao.ordenadas[0].equipe_id !== melhor.equipe_id;
        if (ctx.empatadas.has(melhor.equipe_id)) {
          return { motivo: `empate sem critério (sorteio) no melhor ${vaga.posicao}º colocado` };
        }
        return {
          equipe_id: melhor.equipe_id,
          nota: pulou
            ? `o melhor ${vaga.posicao}º colocado (${comparacao.ordenadas[0].escola_nome}) já ocupa outra vaga desta fase; entrou o seguinte (${melhor.escola_nome})`
            : null
        };
      }

      const origem = doJogo.get(vaga.jogo_origem_id);
      if (!origem) return { motivo: 'jogo de origem não encontrado' };
      if (!RESOLVIDO.includes(origem.status) || !origem.vencedor_equipe_id) {
        return { motivo: 'o jogo de origem ainda não terminou' };
      }
      return { equipe_id: origem.vencedor_equipe_id };
    };

    // Quem ocupa cada vaga agora, por fase: uma equipe só pode estar numa vaga da fase
    const ocupacao = new Map(); // fase -> Map(equipe_id -> Set('jogo:lado'))
    const marcar = (fase, equipeId, chave) => {
      if (!equipeId) return;
      if (!ocupacao.has(fase)) ocupacao.set(fase, new Map());
      const m = ocupacao.get(fase);
      if (!m.has(equipeId)) m.set(equipeId, new Set());
      m.get(equipeId).add(chave);
    };
    const soltar = (fase, equipeId, chave) => ocupacao.get(fase)?.get(equipeId)?.delete(chave);
    for (const v of vagas) marcar(v.fase, v.lado === 1 ? v.equipe_1_id : v.equipe_2_id, v.jogo_id + ':' + v.lado);
    const ocupadaPorOutra = (fase, equipeId, chave) => {
      const set = ocupacao.get(fase)?.get(equipeId);
      return set ? [...set].some((c) => c !== chave) : false;
    };

    // Aplica jogo a jogo: os dois lados juntos, para o CHECK de equipes diferentes
    const porJogo = new Map();
    for (const vaga of vagas) {
      if (!porJogo.has(vaga.jogo_id)) porJogo.set(vaga.jogo_id, []);
      porJogo.get(vaga.jogo_id).push(vaga);
    }

    for (const [jogoId, doLado] of porJogo) {
      const jogo = doLado[0];
      const novo = { 1: jogo.equipe_1_id, 2: jogo.equipe_2_id };
      let mudou = false;

      for (const vaga of doLado) {
        if (vaga.manual) continue; // escolhida à mão: o automático não mexe

        const alvo = alvoDaVaga(vaga);
        const atual = novo[vaga.lado];

        if (!alvo.equipe_id) {
          if (alvo.aviso) {
            resultado.avisos.push({ jogo_id: jogoId, numero_tabela: jogo.numero_tabela, lado: vaga.lado, origem: textoDaOrigem(vaga), motivo: alvo.motivo });
          }
          // Origem ainda não decidida (ou voltou a ficar): limpa só se o jogo ainda não começou
          if (atual !== null && alvo.motivo && (jogo.status === 'AGENDADO' || jogoId === forcarJogoId)) {
            soltar(vaga.fase, atual, jogoId + ':' + vaga.lado);
            novo[vaga.lado] = null;
            resultado.limpas += 1;
            mudou = true;
          } else if (atual === null) {
            resultado.pendentes.push({ jogo_id: jogoId, numero_tabela: jogo.numero_tabela, lado: vaga.lado, origem: textoDaOrigem(vaga), motivo: alvo.motivo });
          }
          continue;
        }

        if (alvo.equipe_id === atual) continue;

        if (jogo.status !== 'AGENDADO' && jogoId !== forcarJogoId) {
          resultado.avisos.push({
            jogo_id: jogoId,
            numero_tabela: jogo.numero_tabela,
            lado: vaga.lado,
            origem: textoDaOrigem(vaga),
            motivo: `o jogo já está ${jogo.status === 'EM_ANDAMENTO' ? 'em andamento' : 'encerrado'}: `
              + 'a equipe da vaga não foi trocada. Confira e, se for o caso, troque à mão.'
          });
          continue;
        }

        // Rede de segurança: a equipe já está em outra vaga desta fase
        if (ocupadaPorOutra(vaga.fase, alvo.equipe_id, jogoId + ':' + vaga.lado)) {
          resultado.avisos.push({
            jogo_id: jogoId,
            numero_tabela: jogo.numero_tabela,
            lado: vaga.lado,
            origem: textoDaOrigem(vaga),
            motivo: 'a equipe que a regra manda pôr aqui já ocupa outra vaga desta fase: vaga não preenchida. Escolha a equipe à mão.'
          });
          continue;
        }

        if (atual) soltar(vaga.fase, atual, jogoId + ':' + vaga.lado);
        marcar(vaga.fase, alvo.equipe_id, jogoId + ':' + vaga.lado);
        if (alvo.nota) {
          resultado.avisos.push({ jogo_id: jogoId, numero_tabela: jogo.numero_tabela, lado: vaga.lado, origem: textoDaOrigem(vaga), motivo: alvo.nota });
        }
        novo[vaga.lado] = alvo.equipe_id;
        resultado.preenchidas += 1;
        mudou = true;
      }

      if (mudou) {
        if (novo[1] !== null && novo[1] === novo[2]) {
          resultado.avisos.push({
            jogo_id: jogoId,
            numero_tabela: jogo.numero_tabela,
            motivo: 'as duas vagas resolveriam para a mesma equipe: o jogo não foi alterado.'
          });
          resultado.preenchidas = Math.max(0, resultado.preenchidas - 1);
          continue;
        }
        await conexao.query('UPDATE jogos SET equipe_1_id = ?, equipe_2_id = ? WHERE id = ?', [novo[1], novo[2], jogoId]);
      }
    }

    await conexao.commit();
    return resultado;
  } catch (erro) {
    await conexao.rollback();
    throw erro;
  } finally {
    conexao.release();
  }
};

// Todas as competições que têm vagas cadastradas
const resolverVagasDeTodas = async () => {
  const [competicoes] = await db.query(
    `SELECT DISTINCT j.competicao_id FROM jogo_vagas v INNER JOIN jogos j ON j.id = v.jogo_id ORDER BY j.competicao_id`
  );
  const resultados = [];
  for (const { competicao_id } of competicoes) {
    resultados.push(await resolverVagas(competicao_id));
  }
  return resultados;
};

// Depois de uma súmula ou de um W.O.: nunca derruba a operação que já deu certo
const resolverVagasSemFalhar = async (competicaoId) => {
  try {
    return await resolverVagas(competicaoId);
  } catch (erro) {
    console.error('Erro ao preencher as vagas do mata-mata:', erro && erro.code ? erro.code : erro);
    return null;
  }
};

// ---------------------------------------------------------------------------
// definirVaga — o ADMIN escolhe a equipe de uma vaga à mão (ou volta ao automático)
// ---------------------------------------------------------------------------
//   { jogoId, lado, equipeId }              -> escolhe a equipe (a vaga fica `manual`)
//   { jogoId, lado, automatico: true }       -> solta a vaga e recalcula
// Jogo iniciado ou encerrado só muda com `confirmar: true`.
const definirVaga = async ({ jogoId, lado, equipeId = null, automatico = false, confirmar = false }) => {
  const conexao = await db.getConnection();
  let competicaoId;
  try {
    await conexao.beginTransaction();

    const [[jogo]] = await conexao.query(
      'SELECT id, competicao_id, fase, status, equipe_1_id, equipe_2_id FROM jogos WHERE id = ? FOR UPDATE',
      [jogoId]
    );
    if (!jogo) throw new ErroDeVaga(404, 'Jogo não encontrado.');
    competicaoId = jogo.competicao_id;

    if (jogo.fase === 'GRUPOS') {
      throw new ErroDeVaga(400, 'As equipes de um jogo da fase de grupos não se trocam por aqui.');
    }
    if (![1, 2].includes(lado)) throw new ErroDeVaga(400, 'O lado da vaga é 1 ou 2.');

    const [[vaga]] = await conexao.query('SELECT id, rotulo FROM jogo_vagas WHERE jogo_id = ? AND lado = ?', [jogoId, lado]);

    if (jogo.status !== 'AGENDADO' && !confirmar) {
      throw new ErroDeVaga(409, `Este jogo já está ${jogo.status === 'EM_ANDAMENTO' ? 'em andamento' : 'encerrado'}. `
        + 'Trocar a equipe agora muda o jogo no meio: confirme para continuar.');
    }

    if (automatico) {
      if (!vaga) throw new ErroDeVaga(400, 'Esta vaga não tem origem cadastrada: não há o que recalcular.');
      await conexao.query('UPDATE jogo_vagas SET manual = 0 WHERE id = ?', [vaga.id]);
    } else {
      if (equipeId !== null) {
        const [[equipe]] = await conexao.query('SELECT id, competicao_id FROM equipes WHERE id = ?', [equipeId]);
        if (!equipe || equipe.competicao_id !== jogo.competicao_id) {
          throw new ErroDeVaga(400, 'A equipe precisa ser desta competição.');
        }
        const outro = lado === 1 ? jogo.equipe_2_id : jogo.equipe_1_id;
        if (outro !== null && outro === equipeId) {
          throw new ErroDeVaga(400, 'Uma equipe não pode jogar contra si mesma.');
        }
      }
      const coluna = lado === 1 ? 'equipe_1_id' : 'equipe_2_id';
      await conexao.query(`UPDATE jogos SET ${coluna} = ? WHERE id = ?`, [equipeId, jogoId]);
      // Escolha à mão trava a vaga; deixar vazia à mão também (o ADMIN decidiu)
      if (vaga) await conexao.query('UPDATE jogo_vagas SET manual = 1 WHERE id = ?', [vaga.id]);
    }

    await conexao.commit();
  } catch (erro) {
    await conexao.rollback();
    throw erro;
  } finally {
    conexao.release();
  }

  // Voltar ao automático recalcula já; a escolha à mão não precisa
  const resolucao = automatico ? await resolverVagas(competicaoId, { forcarJogoId: jogoId }) : null;
  return { competicao_id: competicaoId, resolucao };
};

module.exports = {
  ErroDeVaga,
  resolverVagas,
  resolverVagasDeTodas,
  resolverVagasSemFalhar,
  definirVaga
};
