// A mesa (PLACAR) adiciona atleta à equipe na hora do jogo e retira o que ela
// mesma colocou (db/45). As rotas passam por travarMesaPorLocal: mesa de outro
// local, ou sem local, nem chega aqui. As regras do cadastro normal valem
// inteiras e são conferidas aqui no backend (src/services/inscricaoService.js);
// a mesa NÃO abre exceção — quando uma regra barra, a resposta é 403 "Precisa
// de autorização do administrador." com o motivo curto em `detalhe`.
//
// Privacidade: a mesa nunca recebe RG, CPF nem data de nascimento de atleta
// nenhum. Na busca vêm só o nome e as equipes em que o atleta já está.

const db = require('../config/db');
const {
  normalizarRg, normalizarNome, dataValida, validarAtleta
} = require('../config/elegibilidade');
const {
  lerEquipeTravada, lerCompeticao, lerAtleta, avaliarEntrada, gravarInscricao,
  avisoDeMinimo, proximoCodigoProvisorio
} = require('../services/inscricaoService');

const PRECISA_DO_ADMIN = 'Precisa de autorização do administrador.';
const STATUS_QUE_ACEITAM = ['AGENDADO', 'EM_ANDAMENTO'];
// O ADMIN corrige também a súmula de jogo já finalizado (lança do papel; 17/11/2026)
const STATUS_QUE_ACEITAM_DO_ADMIN = ['AGENDADO', 'EM_ANDAMENTO', 'FINALIZADO'];
const ehAdmin = (req) => req.usuario?.perfil === 'ADMIN';
const sim = (valor) => valor === true || valor === 'true' || valor === 1 || valor === '1';
const MIN_LETRAS_DA_BUSCA = 3;

const idValido = (valor) => {
  const n = Number(valor);
  return Number.isInteger(n) && n > 0 ? n : null;
};

// O jogo e a equipe da rota: o jogo existe, a equipe é uma das duas dele e o
// jogo ainda aceita mudança no elenco (agendado ou em andamento). `travar`
// bloqueia a linha do jogo (usado dentro da transação de escrita).
const conferirJogoEEquipe = async (conexao, jogo_id, equipe_id, { travar = false, admin = false } = {}) => {
  const [[jogo]] = await conexao.query(
    `SELECT id, status, equipe_1_id, equipe_2_id FROM jogos WHERE id = ?${travar ? ' FOR UPDATE' : ''}`,
    [jogo_id]
  );
  if (!jogo) return { status: 404, erro: 'Jogo não encontrado.' };
  if (equipe_id !== null && equipe_id !== jogo.equipe_1_id && equipe_id !== jogo.equipe_2_id) {
    return { status: 400, erro: 'Esta equipe não joga este jogo.' };
  }
  if (!(admin ? STATUS_QUE_ACEITAM_DO_ADMIN : STATUS_QUE_ACEITAM).includes(jogo.status)) {
    return {
      status: 409,
      erro: jogo.status === 'WO'
        ? 'Jogo decidido por W.O.: não há elenco para mudar.'
        : 'Este jogo já terminou: não dá mais para mudar o elenco por aqui.'
    };
  }
  return { jogo };
};

// GET /api/jogos/:jogoId/equipes/:equipeId/atletas-da-escola?nome=
// Atletas da MESMA escola da equipe, por nome, que ainda não estão nela. Só id
// e nome, mais as equipes em que já estão inscritos (modalidade, categoria e
// gênero) para a mesa distinguir homônimos.
const buscarAtletasDaEscola = async (req, res) => {
  const jogo_id = idValido(req.params.jogoId);
  const equipe_id = idValido(req.params.equipeId);
  if (!jogo_id || !equipe_id) return res.status(400).json({ erro: 'Jogo ou equipe inválidos.' });

  const nome = normalizarNome(req.query.nome);
  if (nome.length < MIN_LETRAS_DA_BUSCA) {
    return res.status(400).json({ erro: `Digite pelo menos ${MIN_LETRAS_DA_BUSCA} letras do nome.` });
  }

  try {
    const conferencia = await conferirJogoEEquipe(db, jogo_id, equipe_id, { admin: ehAdmin(req) });
    if (conferencia.erro) return res.status(conferencia.status).json({ erro: conferencia.erro });

    const [[equipe]] = await db.query('SELECT id, escola_id FROM equipes WHERE id = ?', [equipe_id]);
    if (!equipe) return res.status(404).json({ erro: 'Equipe não encontrada.' });

    const curinga = `%${nome.replace(/[\\%_]/g, (c) => `\\${c}`)}%`;
    const [atletas] = await db.query(
      `SELECT a.id, a.nome
         FROM atletas a
        WHERE a.escola_id = ? AND a.nome LIKE ?
          AND NOT EXISTS (SELECT 1 FROM inscricoes_atletas i WHERE i.atleta_id = a.id AND i.equipe_id = ?)
        ORDER BY a.nome
        LIMIT 20`,
      [equipe.escola_id, curinga, equipe_id]
    );

    let inscricoes = [];
    if (atletas.length > 0) {
      [inscricoes] = await db.query(
        `SELECT i.atleta_id, m.nome AS modalidade, cat.nome AS categoria, c.genero
           FROM inscricoes_atletas i
           INNER JOIN equipes e ON e.id = i.equipe_id
           INNER JOIN competicoes c ON c.id = e.competicao_id
           INNER JOIN modalidades m ON m.id = c.modalidade_id
           INNER JOIN categorias cat ON cat.id = c.categoria_id
          WHERE i.atleta_id IN (?)
          ORDER BY m.nome, cat.ordem, c.genero`,
        [atletas.map((a) => a.id)]
      );
    }

    res.json(atletas.map((a) => ({
      id: a.id,
      nome: a.nome,
      equipes: inscricoes
        .filter((i) => i.atleta_id === a.id)
        .map((i) => ({ modalidade: i.modalidade, categoria: i.categoria, genero: i.genero }))
    })));
  } catch (erro) {
    console.error('Erro ao buscar atletas da escola para a mesa:', erro);
    res.status(500).json({ erro: 'Erro ao buscar atletas.' });
  }
};

// POST /api/jogos/:jogoId/equipes/:equipeId/atletas
// { atleta_id }  OU  { nome, data_nascimento (AAAA-MM-DD), sexo (M|F), documento? }
const adicionarAtleta = async (req, res) => {
  const jogo_id = idValido(req.params.jogoId);
  const equipe_id = idValido(req.params.equipeId);
  if (!jogo_id || !equipe_id) return res.status(400).json({ erro: 'Jogo ou equipe inválidos.' });

  const usuario_id = req.usuario.id;
  const admin = ehAdmin(req);
  // Exceção autorizada: só o ADMIN (se a mesa mandar o campo, é ignorado)
  const excecao = admin && sim(req.body.excecao);
  const existente = req.body.atleta_id !== undefined && req.body.atleta_id !== null && req.body.atleta_id !== '';
  const atleta_id = existente ? idValido(req.body.atleta_id) : null;
  if (existente && !atleta_id) return res.status(400).json({ erro: 'Atleta inválido.' });

  // Atleta novo: valida o que a mesa digitou antes de abrir a transação
  let novo = null;
  if (!existente) {
    const nome = normalizarNome(req.body.nome);
    const documentoInformado = normalizarRg(req.body.documento);
    novo = {
      nome,
      data_nascimento: typeof req.body.data_nascimento === 'string' ? req.body.data_nascimento.trim() : '',
      sexo: typeof req.body.sexo === 'string' ? req.body.sexo.trim().toUpperCase() : '',
      documento: documentoInformado
    };
    if (!nome) return res.status(400).json({ erro: 'Informe o nome do atleta.' });
    if (!dataValida(novo.data_nascimento)) {
      return res.status(400).json({ erro: 'Informe a data de nascimento do atleta.' });
    }
    if (!['M', 'F'].includes(novo.sexo)) return res.status(400).json({ erro: 'Informe o sexo do atleta (M ou F).' });
  }

  let conexao;
  try {
    conexao = await db.getConnection();
    await conexao.beginTransaction();

    const conferencia = await conferirJogoEEquipe(conexao, jogo_id, equipe_id, { travar: true, admin });
    if (conferencia.erro) {
      await conexao.rollback();
      return res.status(conferencia.status).json({ erro: conferencia.erro });
    }

    const equipe = await lerEquipeTravada(conexao, equipe_id);
    if (!equipe) {
      await conexao.rollback();
      return res.status(404).json({ erro: 'Equipe não encontrada.' });
    }
    const competicao = await lerCompeticao(conexao, equipe.competicao_id);

    let atleta;
    if (existente) {
      atleta = await lerAtleta(conexao, atleta_id);
      // Atleta de outra escola é tratado como inexistente: a mesa não precisa saber dele
      if (!atleta || atleta.escola_id !== equipe.escola_id) {
        await conexao.rollback();
        return res.status(404).json({ erro: 'Atleta não encontrado nesta escola.' });
      }
    } else {
      // Mesmo nome e mesmo nascimento na escola: é o atleta já cadastrado, que se acha pela busca
      const [[repetido]] = await conexao.query(
        'SELECT id FROM atletas WHERE escola_id = ? AND nome = ? AND data_nascimento = ? LIMIT 1',
        [equipe.escola_id, novo.nome, novo.data_nascimento]
      );
      if (repetido) {
        await conexao.rollback();
        return res.status(409).json({ erro: 'Este atleta já está cadastrado na escola: procure pelo nome e use "Inscrever".' });
      }
      atleta = {
        id: null, nome: novo.nome, escola_id: equipe.escola_id, sexo: novo.sexo,
        ano_nascimento: Number(novo.data_nascimento.slice(0, 4))
      };
    }

    // As mesmas regras do cadastro normal (sexo x gênero, idade, 2 coletivas, 14). A mesa nunca abre
    // exceção; o ADMIN pode marcar "Exceção autorizada" (só idade e 2 coletivas, como na importação)
    const { recusa, inscritos, dispensadas, pode_excecao } = await avaliarEntrada(conexao, { equipe, competicao, atleta, excecao });
    if (recusa) {
      await conexao.rollback();
      if (admin) return res.status(recusa.status).json({ erro: recusa.erro, pode_excecao });
      return res.status(403).json({ erro: PRECISA_DO_ADMIN, detalhe: recusa.erro });
    }

    let semDocumento = false;
    if (!existente) {
      let rg = novo.documento;
      if (rg) {
        const [[ocupado]] = await conexao.query('SELECT id FROM atletas WHERE rg = ?', [rg]);
        if (ocupado) {
          await conexao.rollback();
          // Sem dizer de quem é: a mesa não vê dado de atleta que já existe
          return res.status(409).json({ erro: 'Este documento já está cadastrado. Fale com o administrador.' });
        }
      } else {
        rg = await proximoCodigoProvisorio(conexao, equipe.escola_id);
        if (!rg) {
          await conexao.rollback();
          return res.status(500).json({ erro: 'A escola não tem sigla cadastrada. Fale com o administrador.' });
        }
        semDocumento = true;
      }

      const invalido = validarAtleta({
        nome: novo.nome, rg, data_nascimento: novo.data_nascimento, sexo: novo.sexo, escola_id: equipe.escola_id
      });
      if (invalido) {
        await conexao.rollback();
        return res.status(400).json({ erro: invalido });
      }

      const [criado] = await conexao.query(
        'INSERT INTO atletas (escola_id, nome, rg, data_nascimento, sexo, criado_por) VALUES (?, ?, ?, ?, ?, ?)',
        [equipe.escola_id, novo.nome, rg, novo.data_nascimento, novo.sexo, usuario_id]
      );
      atleta.id = criado.insertId;
    }

    const inscricao_id = await gravarInscricao(conexao, {
      equipe_id, atleta_id: atleta.id, escola_id: equipe.escola_id, criado_por: usuario_id
    });

    await conexao.commit();

    const total = inscritos + 1;
    // Sem log com nome nem documento: só ids
    console.warn(`[${admin ? 'ADMIN' : 'MESA'} ADICIONOU ATLETA] usuário ${usuario_id}: jogo ${jogo_id}, equipe ${equipe_id}, inscrição ${inscricao_id}${existente ? '' : ' (atleta novo)'}`);
    if (dispensadas.length > 0) {
      console.warn(`[EXCEÇÃO AUTORIZADA] súmula, usuário ${usuario_id}: jogo ${jogo_id}, inscrição ${inscricao_id} (atleta ${atleta.id}, equipe ${equipe_id}) dispensou ${dispensadas.join(' e ')}`);
    }

    res.status(201).json({
      mensagem: 'Atleta adicionado à equipe.',
      inscricao_id,
      atleta: { id: atleta.id, nome: atleta.nome },
      adicionado_pela_mesa: !admin,
      excecao_dispensou: dispensadas,
      atleta_novo: !existente,
      sem_documento: semDocumento,
      total_inscritos: total,
      max_atletas: competicao.max_atletas,
      aviso: avisoDeMinimo(competicao, total)
    });
  } catch (erro) {
    if (conexao) await conexao.rollback();

    if (erro.code === 'ER_DUP_ENTRY') {
      const doRg = /uq_atletas_rg/i.test(erro.sqlMessage || '');
      return res.status(409).json({
        erro: doRg
          ? 'Este documento já está cadastrado. Fale com o administrador.'
          : (/camisa/i.test(erro.sqlMessage || '') ? 'Esse número de camisa já está em uso nesta equipe.' : 'Este atleta já está inscrito nesta equipe.')
      });
    }

    console.error('Erro ao adicionar atleta pela mesa:', erro);
    res.status(500).json({ erro: 'Erro ao adicionar o atleta.' });
  } finally {
    if (conexao) conexao.release();
  }
};

// DELETE /api/jogos/:jogoId/inscricoes/:inscricaoId
// Só a inscrição que ESTA mesa criou, de jogo do local dela e enquanto o jogo
// não terminou. Se o atleta foi cadastrado por ela e fica sem inscrição, sai
// também. Tudo o mais continua só com o ADMIN.
const removerAtleta = async (req, res) => {
  const jogo_id = idValido(req.params.jogoId);
  const inscricao_id = idValido(req.params.inscricaoId);
  if (!jogo_id || !inscricao_id) return res.status(400).json({ erro: 'Jogo ou inscrição inválidos.' });

  const usuario_id = req.usuario.id;
  const admin = ehAdmin(req);
  let conexao;
  try {
    conexao = await db.getConnection();
    await conexao.beginTransaction();

    const [[inscricao]] = await conexao.query(
      `SELECT i.id, i.equipe_id, i.atleta_id, i.criado_por, a.criado_por AS atleta_criado_por
         FROM inscricoes_atletas i
         INNER JOIN atletas a ON a.id = i.atleta_id
        WHERE i.id = ? FOR UPDATE`,
      [inscricao_id]
    );
    if (!inscricao) {
      await conexao.rollback();
      return res.status(404).json({ erro: 'Inscrição não encontrada.' });
    }

    const conferencia = await conferirJogoEEquipe(conexao, jogo_id, inscricao.equipe_id, { travar: true, admin });
    if (conferencia.erro) {
      await conexao.rollback();
      return res.status(conferencia.status).json({ erro: conferencia.erro });
    }

    // O ADMIN retira qualquer inscrição; quem já está numa súmula gravada continua não saindo (409)
    if (!admin && inscricao.criado_por !== usuario_id) {
      await conexao.rollback();
      return res.status(403).json({ erro: 'A mesa só retira os atletas que ela mesma adicionou. Fale com o administrador.' });
    }

    try {
      await conexao.query('DELETE FROM inscricoes_atletas WHERE id = ?', [inscricao_id]);
    } catch (erro) {
      if (erro.code === 'ER_ROW_IS_REFERENCED_2') {
        await conexao.rollback();
        return res.status(409).json({ erro: 'Este atleta já aparece na súmula de um jogo e não pode ser retirado. Fale com o administrador.' });
      }
      throw erro;
    }

    // Atleta cadastrado por esta mesa e sem nenhuma inscrição: sai também
    let atletaRemovido = false;
    if (inscricao.atleta_criado_por === usuario_id) {
      const [[{ restantes }]] = await conexao.query(
        'SELECT COUNT(*) AS restantes FROM inscricoes_atletas WHERE atleta_id = ?',
        [inscricao.atleta_id]
      );
      if (restantes === 0) {
        await conexao.query('DELETE FROM atletas WHERE id = ?', [inscricao.atleta_id]);
        atletaRemovido = true;
      }
    }

    await conexao.commit();
    console.warn(`[${admin ? 'ADMIN' : 'MESA'} RETIROU ATLETA] usuário ${usuario_id}: jogo ${jogo_id}, inscrição ${inscricao_id}${atletaRemovido ? ' (atleta removido)' : ''}`);
    res.json({ mensagem: 'Atleta retirado da equipe.', atleta_removido: atletaRemovido });
  } catch (erro) {
    if (conexao) await conexao.rollback();
    console.error('Erro ao retirar atleta pela mesa:', erro);
    res.status(500).json({ erro: 'Erro ao retirar o atleta.' });
  } finally {
    if (conexao) conexao.release();
  }
};

// GET /api/inscricoes/adicionadas-pela-mesa (ADMIN): para conferir depois do evento.
// O atleta que a mesa cadastrou vem com a marca atleta_novo; o código provisório
// não sai daqui (o ADMIN o vê em Listar Atletas).
const listarAdicionadasPelaMesa = async (req, res) => {
  try {
    const [linhas] = await db.query(
      `SELECT i.id AS inscricao_id, i.criado_em, u.nome AS mesa, u.id AS mesa_id, u.perfil,
              l.nome AS local_da_mesa,
              s.nome AS escola, m.nome AS modalidade, cat.nome AS categoria, c.genero,
              a.id AS atleta_id, a.nome AS atleta,
              (a.criado_por IS NOT NULL) AS atleta_novo
         FROM inscricoes_atletas i
         INNER JOIN usuarios u ON u.id = i.criado_por
         LEFT JOIN locais_disputa l ON l.id = u.local_id
         INNER JOIN atletas a ON a.id = i.atleta_id
         INNER JOIN escolas s ON s.id = i.escola_id
         INNER JOIN equipes e ON e.id = i.equipe_id
         INNER JOIN competicoes c ON c.id = e.competicao_id
         INNER JOIN modalidades m ON m.id = c.modalidade_id
         INNER JOIN categorias cat ON cat.id = c.categoria_id
        ORDER BY i.criado_em DESC, i.id DESC`
    );
    res.json(linhas.map((l) => ({ ...l, atleta_novo: Boolean(l.atleta_novo) })));
  } catch (erro) {
    console.error('Erro ao listar atletas adicionados pelas mesas:', erro);
    res.status(500).json({ erro: 'Erro ao listar os atletas adicionados pelas mesas.' });
  }
};

module.exports = { buscarAtletasDaEscola, adicionarAtleta, removerAtleta, listarAdicionadasPelaMesa };
