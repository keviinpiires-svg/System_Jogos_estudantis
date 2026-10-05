const db = require('../config/db');
const { REGRAS } = require('../config/regrasProvisorias');

const FASES = ['GRUPOS', 'SEMIFINAL', 'FINAL'];
const STATUS = ['AGENDADO', 'EM_ANDAMENTO', 'FINALIZADO', 'WO'];

// Jogo já encerrado não é reagendado nem apagado sem passar por cima do
// resultado: a súmula some junto (CASCADE).
const ENCERRADOS = ['FINALIZADO', 'WO'];

// Jogo que já começou também não muda de data, hora nem local: a mesa já está
// na quadra. O valor é o trecho da mensagem de recusa.
const SITUACAO_SEM_REAGENDAMENTO = {
  EM_ANDAMENTO: 'já está em andamento',
  FINALIZADO: 'já foi finalizado',
  WO: 'teve W.O. declarado'
};

// Aceita "2026-11-23T14:30" (o que o input datetime-local manda) e
// "2026-11-23 14:30". O DATETIME do MySQL quer o formato com espaço.
const normalizarDataHora = (valor) => {
  const texto = (valor || '').trim();
  if (!texto) return null;
  if (!/^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2})?$/.test(texto)) return undefined;
  const comEspaco = texto.replace('T', ' ');
  return comEspaco.length === 16 ? `${comEspaco}:00` : comEspaco;
};

const textoOuNulo = (valor) => {
  const texto = (valor || '').trim();
  return texto || null;
};

const GENEROS = { MASCULINO: 'Masculino', FEMININO: 'Feminino', MISTO: 'Misto' };

// "2026-11-24 10:30:00" -> "24/11/2026 às 10:30". A data é hora de parede e
// chega como texto (dateStrings), então não passa por Date.
const formatarQuando = (dataHora) => {
  const [data, hora] = dataHora.split(' ');
  const [ano, mes, dia] = data.split('-');
  return `${dia}/${mes}/${ano} às ${hora.slice(0, 5)}`;
};

// Procura um jogo que ocupe o mesmo local perto demais do horário pedido
// (regrasProvisorias.conflitoDeLocal). Precisa rodar dentro da transação que
// vai gravar o jogo: a linha do local é travada primeiro, o que enfileira
// quem agenda no mesmo local mesmo quando ainda não há jogo nenhum nele, e os
// jogos do local também ficam travados até o commit.
//
// As duas leituras são FOR UPDATE de propósito, e não só pela trava: no
// REPEATABLE READ uma leitura comum enxerga a foto tirada no começo da
// transação, e não veria o jogo que outro agendamento acabou de gravar
// enquanto este esperava a vez no local.
// Devolve { localInexistente: true }, { conflito: {...} } ou {}.
const verificarConflitoDeLocal = async (conexao, { local_id, data_hora, ignorarJogoId = null }) => {
  if (!local_id || !data_hora) return {};

  const [[local]] = await conexao.query(
    'SELECT id, nome FROM locais_disputa WHERE id = ? FOR UPDATE',
    [local_id]
  );

  if (!local) return { localInexistente: true };

  const { intervaloMinutos, statusQueOcupam } = REGRAS.conflitoDeLocal;

  const [conflitos] = await conexao.query(
    `SELECT id, competicao_id, numero_jogo, data_hora
       FROM jogos
      WHERE local_id = ?
        AND data_hora IS NOT NULL
        AND status IN (?)
        AND id <> ?
        AND ABS(TIMESTAMPDIFF(SECOND, data_hora, ?)) < ?
      ORDER BY ABS(TIMESTAMPDIFF(SECOND, data_hora, ?)), id
      FOR UPDATE`,
    [local_id, statusQueOcupam, ignorarJogoId || 0, data_hora, intervaloMinutos * 60, data_hora]
  );

  if (conflitos.length === 0) return {};

  const jogo = conflitos[0];

  // Nome da competição só para a mensagem: dado de cadastro, que não muda
  // durante a transação, então dispensa a trava.
  const [[nomes]] = await conexao.query(
    `SELECT m.nome AS modalidade_nome, cat.nome AS categoria_nome, c.genero
       FROM competicoes c
       INNER JOIN modalidades m ON m.id = c.modalidade_id
       INNER JOIN categorias cat ON cat.id = c.categoria_id
      WHERE c.id = ?`,
    [jogo.competicao_id]
  );
  const competicao = `${nomes.modalidade_nome} ${nomes.categoria_nome} ${GENEROS[nomes.genero] || nomes.genero}`;
  jogo.local_nome = local.nome;

  return {
    conflito: {
      ...jogo,
      mensagem:
        `O local ${jogo.local_nome} já tem o jogo nº ${jogo.numero_jogo} de ${competicao} `
        + `em ${formatarQuando(jogo.data_hora)}. Jogos no mesmo local precisam de pelo menos `
        + `${intervaloMinutos} minutos de diferença.`
    }
  };
};

const SELECT_JOGO = `
  SELECT j.id, j.competicao_id, j.numero_jogo, j.fase, j.rodada,
         j.data_hora, j.status, j.placar_1, j.placar_2,
         j.penaltis_1, j.penaltis_2, j.prorrogacao,
         j.arbitro_1, j.arbitro_2, j.anotador, j.observacoes,
         j.equipe_1_id, j.equipe_2_id, j.vencedor_equipe_id,
         e1.escola_id AS escola_1_id, esc1.nome AS equipe_1_nome,
         e2.escola_id AS escola_2_id, esc2.nome AS equipe_2_nome,
         j.grupo_id, g.nome AS grupo_nome,
         j.local_id, l.nome AS local_nome,
         m.nome AS modalidade_nome, m.slug AS modalidade_slug, m.tipo_placar,
         cat.nome AS categoria_nome, c.genero
    FROM jogos j
    INNER JOIN equipes e1 ON e1.id = j.equipe_1_id
    INNER JOIN escolas esc1 ON esc1.id = e1.escola_id
    INNER JOIN equipes e2 ON e2.id = j.equipe_2_id
    INNER JOIN escolas esc2 ON esc2.id = e2.escola_id
    INNER JOIN competicoes c ON c.id = j.competicao_id
    INNER JOIN modalidades m ON m.id = c.modalidade_id
    INNER JOIN categorias cat ON cat.id = c.categoria_id
    LEFT JOIN grupos g ON g.id = j.grupo_id
    LEFT JOIN locais_disputa l ON l.id = j.local_id`;

const agendarJogo = async (req, res) => {
  const competicao_id = Number(req.body.competicao_id);
  const equipe_1_id = Number(req.body.equipe_1_id);
  const equipe_2_id = Number(req.body.equipe_2_id);
  const fase = (req.body.fase || 'GRUPOS').trim().toUpperCase();
  const data_hora = normalizarDataHora(req.body.data_hora);
  const local_id = req.body.local_id ? Number(req.body.local_id) : null;
  const rodada = req.body.rodada ? Number(req.body.rodada) : null;

  if (!Number.isInteger(competicao_id) || competicao_id <= 0) {
    return res.status(400).json({ erro: 'Informe a competição do jogo.' });
  }

  if (!Number.isInteger(equipe_1_id) || !Number.isInteger(equipe_2_id)
    || equipe_1_id <= 0 || equipe_2_id <= 0) {
    return res.status(400).json({ erro: 'Informe as duas equipes do jogo.' });
  }

  if (equipe_1_id === equipe_2_id) {
    return res.status(400).json({ erro: 'Uma equipe não pode jogar contra si mesma.' });
  }

  if (!FASES.includes(fase)) {
    return res.status(400).json({ erro: 'A fase precisa ser GRUPOS, SEMIFINAL ou FINAL.' });
  }

  if (data_hora === undefined) {
    return res.status(400).json({ erro: 'Informe a data e a hora no formato AAAA-MM-DD HH:MM.' });
  }

  if (rodada !== null && (!Number.isInteger(rodada) || rodada <= 0)) {
    return res.status(400).json({ erro: 'A rodada precisa ser um número inteiro positivo.' });
  }

  let conexao;
  try {
    conexao = await db.getConnection();
    await conexao.beginTransaction();

    // Trava a competição: o numero_jogo é único por competição e sai de um
    // MAX + 1. Sem a trava, dois agendamentos simultâneos pegariam o mesmo.
    const [[competicao]] = await conexao.query(
      'SELECT id FROM competicoes WHERE id = ? FOR UPDATE',
      [competicao_id]
    );

    if (!competicao) {
      await conexao.rollback();
      return res.status(404).json({ erro: 'Competição não encontrada.' });
    }

    const [equipes] = await conexao.query(
      `SELECT e.id, e.competicao_id, e.grupo_id, esc.nome AS escola_nome
         FROM equipes e
         INNER JOIN escolas esc ON esc.id = e.escola_id
        WHERE e.id IN (?, ?)`,
      [equipe_1_id, equipe_2_id]
    );

    const equipe1 = equipes.find((e) => e.id === equipe_1_id);
    const equipe2 = equipes.find((e) => e.id === equipe_2_id);

    if (!equipe1 || !equipe2) {
      await conexao.rollback();
      return res.status(404).json({ erro: 'Equipe não encontrada.' });
    }

    for (const equipe of [equipe1, equipe2]) {
      if (equipe.competicao_id !== competicao_id) {
        await conexao.rollback();
        return res.status(400).json({
          erro: `A equipe ${equipe.escola_nome} não participa desta competição.`
        });
      }
    }

    // Jogo de fase de grupos é entre equipes do MESMO grupo, e o grupo do jogo
    // sai daí. No mata-mata não há grupo: as equipes vêm de grupos diferentes.
    let grupo_id = null;

    if (fase === 'GRUPOS') {
      if (!equipe1.grupo_id || !equipe2.grupo_id) {
        await conexao.rollback();
        return res.status(400).json({
          erro: 'Há equipe sem grupo definido. Defina os grupos antes de agendar a fase de grupos.'
        });
      }

      if (equipe1.grupo_id !== equipe2.grupo_id) {
        await conexao.rollback();
        return res.status(400).json({
          erro: `${equipe1.escola_nome} e ${equipe2.escola_nome} estão em grupos diferentes.`
        });
      }

      grupo_id = equipe1.grupo_id;

      const informado = req.body.grupo_id ? Number(req.body.grupo_id) : null;
      if (informado !== null && informado !== grupo_id) {
        await conexao.rollback();
        return res.status(400).json({ erro: 'O grupo informado não é o grupo destas equipes.' });
      }
    }

    const ocupacao = await verificarConflitoDeLocal(conexao, { local_id, data_hora });

    if (ocupacao.localInexistente) {
      await conexao.rollback();
      return res.status(400).json({ erro: 'Local de disputa inválido.' });
    }

    if (ocupacao.conflito) {
      await conexao.rollback();
      return res.status(409).json({ erro: ocupacao.conflito.mensagem });
    }

    const [[{ proximo }]] = await conexao.query(
      'SELECT COALESCE(MAX(numero_jogo), 0) + 1 AS proximo FROM jogos WHERE competicao_id = ?',
      [competicao_id]
    );

    const [resultado] = await conexao.query(
      `INSERT INTO jogos
         (competicao_id, numero_jogo, fase, rodada, grupo_id, local_id, data_hora,
          equipe_1_id, equipe_2_id, arbitro_1, arbitro_2, anotador, observacoes)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        competicao_id, proximo, fase, rodada, grupo_id, local_id, data_hora,
        equipe_1_id, equipe_2_id,
        textoOuNulo(req.body.arbitro_1), textoOuNulo(req.body.arbitro_2),
        textoOuNulo(req.body.anotador), textoOuNulo(req.body.observacoes)
      ]
    );

    await conexao.commit();

    res.status(201).json({
      mensagem: 'Jogo agendado com sucesso!',
      id_jogo: resultado.insertId,
      numero_jogo: proximo,
      confronto: `${equipe1.escola_nome} x ${equipe2.escola_nome}`
    });
  } catch (erro) {
    if (conexao) await conexao.rollback();

    if (erro.code === 'ER_NO_REFERENCED_ROW_2') {
      return res.status(400).json({ erro: 'Local de disputa inválido.' });
    }

    console.error(erro);
    res.status(500).json({ erro: 'Erro ao agendar o jogo.' });
  } finally {
    if (conexao) conexao.release();
  }
};

const listarJogos = async (req, res) => {
  const condicoes = [];
  const valores = [];

  if (req.query.competicao_id) {
    const valor = Number(req.query.competicao_id);
    if (!Number.isInteger(valor) || valor <= 0) {
      return res.status(400).json({ erro: 'Identificador de competição inválido.' });
    }
    condicoes.push('j.competicao_id = ?');
    valores.push(valor);
  }

  if (req.query.fase) {
    const valor = String(req.query.fase).toUpperCase();
    if (!FASES.includes(valor)) {
      return res.status(400).json({ erro: 'A fase precisa ser GRUPOS, SEMIFINAL ou FINAL.' });
    }
    condicoes.push('j.fase = ?');
    valores.push(valor);
  }

  if (req.query.status) {
    const valor = String(req.query.status).toUpperCase();
    if (!STATUS.includes(valor)) {
      return res.status(400).json({ erro: 'Status inválido.' });
    }
    condicoes.push('j.status = ?');
    valores.push(valor);
  }

  const onde = condicoes.length > 0 ? `WHERE ${condicoes.join(' AND ')}` : '';

  try {
    // Sem filtro de competição a ordem por número não diz nada (o número se
    // repete entre competições), então a competição vem primeiro na ordenação.
    const [jogos] = await db.query(
      `${SELECT_JOGO} ${onde} ORDER BY j.competicao_id, j.numero_jogo`,
      valores
    );

    res.status(200).json(jogos);
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao buscar os jogos.' });
  }
};

const buscarPorId = async (req, res) => {
  const id = Number(req.params.id);

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ erro: 'Identificador de jogo inválido.' });
  }

  try {
    const [[jogo]] = await db.query(`${SELECT_JOGO} WHERE j.id = ?`, [id]);

    if (!jogo) {
      return res.status(404).json({ erro: 'Jogo não encontrado.' });
    }

    res.status(200).json(jogo);
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao buscar o jogo.' });
  }
};

// Só os dados de agenda. Trocar as equipes ou a competição seria outro jogo:
// para isso, apague este e agende de novo.
const atualizarJogo = async (req, res) => {
  const id = Number(req.params.id);

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ erro: 'Identificador de jogo inválido.' });
  }

  const campos = [];
  const valores = [];
  const agenda = {};

  if (req.body.data_hora !== undefined) {
    const data_hora = normalizarDataHora(req.body.data_hora);
    if (data_hora === undefined) {
      return res.status(400).json({ erro: 'Informe a data e a hora no formato AAAA-MM-DD HH:MM.' });
    }
    agenda.data_hora = data_hora;
    campos.push('data_hora = ?');
    valores.push(data_hora);
  }

  if (req.body.local_id !== undefined) {
    const local_id = req.body.local_id ? Number(req.body.local_id) : null;
    if (local_id !== null && (!Number.isInteger(local_id) || local_id <= 0)) {
      return res.status(400).json({ erro: 'Local de disputa inválido.' });
    }
    agenda.local_id = local_id;
    campos.push('local_id = ?');
    valores.push(local_id);
  }

  if (req.body.rodada !== undefined) {
    const rodada = req.body.rodada ? Number(req.body.rodada) : null;
    if (rodada !== null && (!Number.isInteger(rodada) || rodada <= 0)) {
      return res.status(400).json({ erro: 'A rodada precisa ser um número inteiro positivo.' });
    }
    campos.push('rodada = ?');
    valores.push(rodada);
  }

  for (const campo of ['arbitro_1', 'arbitro_2', 'anotador', 'observacoes']) {
    if (req.body[campo] !== undefined) {
      campos.push(`${campo} = ?`);
      valores.push(textoOuNulo(req.body[campo]));
    }
  }

  if (campos.length === 0) {
    return res.status(400).json({ erro: 'Informe ao menos um campo para alterar.' });
  }

  valores.push(id);

  let conexao;
  try {
    conexao = await db.getConnection();
    await conexao.beginTransaction();

    const [[jogo]] = await conexao.query(
      'SELECT id, status, local_id, data_hora FROM jogos WHERE id = ? FOR UPDATE',
      [id]
    );

    if (!jogo) {
      await conexao.rollback();
      return res.status(404).json({ erro: 'Jogo não encontrado.' });
    }

    // Reenviar o mesmo valor (a tela costuma mandar o formulário inteiro) não
    // conta como mudança: só o que de fato muda passa pelas travas abaixo.
    const novoLocal = agenda.local_id !== undefined ? agenda.local_id : jogo.local_id;
    const novaDataHora = agenda.data_hora !== undefined ? agenda.data_hora : jogo.data_hora;
    const mudaAgenda = novoLocal !== jogo.local_id || novaDataHora !== jogo.data_hora;

    if (mudaAgenda && SITUACAO_SEM_REAGENDAMENTO[jogo.status]) {
      await conexao.rollback();
      return res.status(409).json({
        erro: `Este jogo ${SITUACAO_SEM_REAGENDAMENTO[jogo.status]}: a data, a hora e o local `
          + 'não podem mais ser alterados. Árbitros, anotador e observações continuam editáveis.'
      });
    }

    if (mudaAgenda) {
      const ocupacao = await verificarConflitoDeLocal(conexao, {
        local_id: novoLocal,
        data_hora: novaDataHora,
        ignorarJogoId: id
      });

      if (ocupacao.localInexistente) {
        await conexao.rollback();
        return res.status(400).json({ erro: 'Local de disputa inválido.' });
      }

      if (ocupacao.conflito) {
        await conexao.rollback();
        return res.status(409).json({ erro: ocupacao.conflito.mensagem });
      }
    }

    await conexao.query(`UPDATE jogos SET ${campos.join(', ')} WHERE id = ?`, valores);

    await conexao.commit();

    res.status(200).json({ mensagem: 'Jogo atualizado com sucesso!', id_jogo: id });
  } catch (erro) {
    if (conexao) await conexao.rollback();

    if (erro.code === 'ER_NO_REFERENCED_ROW_2') {
      return res.status(400).json({ erro: 'Local de disputa inválido.' });
    }
    console.error('atualizarJogo:', erro);
    res.status(500).json({ erro: 'Erro ao atualizar o jogo.' });
  } finally {
    if (conexao) conexao.release();
  }
};

// Apagar deixa um buraco na numeração, e o regulamento pede a lista sem
// buracos. A renumeração acontece na mesma transação; a ordem ascendente
// evita colidir com o índice único (competicao_id, numero_jogo) no caminho.
const excluirJogo = async (req, res) => {
  const id = Number(req.params.id);

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ erro: 'Identificador de jogo inválido.' });
  }

  let conexao;
  try {
    conexao = await db.getConnection();
    await conexao.beginTransaction();

    const [[jogo]] = await conexao.query(
      'SELECT id, competicao_id, numero_jogo, status FROM jogos WHERE id = ? FOR UPDATE',
      [id]
    );

    if (!jogo) {
      await conexao.rollback();
      return res.status(404).json({ erro: 'Jogo não encontrado.' });
    }

    // A súmula é apagada junto pelo CASCADE, então um jogo encerrado levaria o
    // resultado embora sem aviso.
    if (ENCERRADOS.includes(jogo.status)) {
      await conexao.rollback();
      return res.status(409).json({
        erro: 'Este jogo já foi encerrado. Reabra a súmula antes de apagá-lo.'
      });
    }

    await conexao.query('DELETE FROM jogos WHERE id = ?', [id]);

    const [renumerados] = await conexao.query(
      `UPDATE jogos SET numero_jogo = numero_jogo - 1
        WHERE competicao_id = ? AND numero_jogo > ?
        ORDER BY numero_jogo ASC`,
      [jogo.competicao_id, jogo.numero_jogo]
    );

    await conexao.commit();

    res.status(200).json({
      mensagem: 'Jogo excluído com sucesso!',
      numero_removido: jogo.numero_jogo,
      jogos_renumerados: renumerados.affectedRows
    });
  } catch (erro) {
    if (conexao) await conexao.rollback();
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao excluir o jogo.' });
  } finally {
    if (conexao) conexao.release();
  }
};

// Marca o início da partida. É trabalho de mesa, então o perfil PLACAR também
// faz. O placar em si vem da súmula (fatia 5c).
const iniciarJogo = async (req, res) => {
  const id = Number(req.params.id);

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ erro: 'Identificador de jogo inválido.' });
  }

  try {
    const [[jogo]] = await db.query('SELECT id, status FROM jogos WHERE id = ?', [id]);

    if (!jogo) {
      return res.status(404).json({ erro: 'Jogo não encontrado.' });
    }

    if (jogo.status !== 'AGENDADO') {
      return res.status(409).json({ erro: `Este jogo está como ${jogo.status} e não pode ser iniciado.` });
    }

    await db.query("UPDATE jogos SET status = 'EM_ANDAMENTO' WHERE id = ?", [id]);

    res.status(200).json({ mensagem: 'Jogo iniciado!', id_jogo: id });
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao iniciar o jogo.' });
  }
};

// W.O.: só a Comissão Organizadora declara (regulamento), por isso é de ADMIN.
// O placar é informado — a tela sugere 1x0, mas quem decide é quem declara.
// Como não há súmula, estes gols não entram na artilharia, que é somada de
// sumula_atletas. Eles contam na classificação, que lê o placar do jogo.
const declararWO = async (req, res) => {
  const id = Number(req.params.id);
  const vencedor_equipe_id = Number(req.body.vencedor_equipe_id);
  const motivo = (req.body.motivo || '').trim();

  // O placar é opcional: sem ele vale o padrão da regra provisória (1x0), que
  // mora em src/config/regrasProvisorias.js. Qual lado leva o 1 só se sabe
  // depois de carregar o jogo, então o padrão é aplicado lá embaixo.
  const placarInformado = req.body.placar_1 !== undefined && req.body.placar_2 !== undefined;
  const placarPedido = placarInformado
    ? { um: Number(req.body.placar_1), dois: Number(req.body.placar_2) }
    : null;

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ erro: 'Identificador de jogo inválido.' });
  }

  if (!motivo) {
    return res.status(400).json({ erro: 'Informe o motivo do W.O.' });
  }

  if (placarInformado) {
    for (const placar of [placarPedido.um, placarPedido.dois]) {
      if (!Number.isInteger(placar) || placar < 0) {
        return res.status(400).json({ erro: 'Informe os dois placares como inteiros não negativos.' });
      }
    }

    if (placarPedido.um === placarPedido.dois) {
      return res.status(400).json({ erro: 'Um W.O. não termina empatado.' });
    }
  }

  let conexao;
  try {
    conexao = await db.getConnection();
    await conexao.beginTransaction();

    const [[jogo]] = await conexao.query(
      'SELECT id, equipe_1_id, equipe_2_id, status FROM jogos WHERE id = ? FOR UPDATE',
      [id]
    );

    if (!jogo) {
      await conexao.rollback();
      return res.status(404).json({ erro: 'Jogo não encontrado.' });
    }

    if (ENCERRADOS.includes(jogo.status)) {
      await conexao.rollback();
      return res.status(409).json({ erro: `Este jogo já está como ${jogo.status}.` });
    }

    if (![jogo.equipe_1_id, jogo.equipe_2_id].includes(vencedor_equipe_id)) {
      await conexao.rollback();
      return res.status(400).json({ erro: 'O vencedor precisa ser uma das duas equipes do jogo.' });
    }

    // Agora dá para montar o padrão: o vencedor leva o placar de vitória
    const venceuPrimeira = vencedor_equipe_id === jogo.equipe_1_id;
    const placar_1 = placarInformado ? placarPedido.um
      : (venceuPrimeira ? REGRAS.wo.placarVencedor : REGRAS.wo.placarPerdedor);
    const placar_2 = placarInformado ? placarPedido.dois
      : (venceuPrimeira ? REGRAS.wo.placarPerdedor : REGRAS.wo.placarVencedor);

    // O vencedor declarado e o placar informado têm que contar a mesma história
    const vencedorPeloPlacar = placar_1 > placar_2 ? jogo.equipe_1_id : jogo.equipe_2_id;
    if (vencedorPeloPlacar !== vencedor_equipe_id) {
      await conexao.rollback();
      return res.status(400).json({ erro: 'O placar informado não corresponde ao vencedor escolhido.' });
    }

    // Uma súmula lançada contradiz o W.O.: o placar sairia de dois lugares.
    const [[{ lancamentos }]] = await conexao.query(
      'SELECT COUNT(*) AS lancamentos FROM sumula_atletas WHERE jogo_id = ?',
      [id]
    );

    if (lancamentos > 0) {
      await conexao.rollback();
      return res.status(409).json({
        erro: 'Este jogo já tem súmula lançada. Apague a súmula antes de declarar W.O.'
      });
    }

    await conexao.query(
      `UPDATE jogos
          SET status = 'WO', placar_1 = ?, placar_2 = ?,
              vencedor_equipe_id = ?, observacoes = ?
        WHERE id = ?`,
      [placar_1, placar_2, vencedor_equipe_id, motivo, id]
    );

    await conexao.commit();

    res.status(200).json({
      mensagem: 'W.O. declarado.',
      id_jogo: id,
      placar: `${placar_1} x ${placar_2}`,
      vencedor_equipe_id
    });
  } catch (erro) {
    if (conexao) await conexao.rollback();
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao declarar o W.O.' });
  } finally {
    if (conexao) conexao.release();
  }
};

module.exports = {
  agendarJogo,
  declararWO,
  listarJogos,
  buscarPorId,
  atualizarJogo,
  excluirJogo,
  iniciarJogo
};
