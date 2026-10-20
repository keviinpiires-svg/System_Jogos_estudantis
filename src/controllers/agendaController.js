const db = require('../config/db');

// ============================================================================
// Agenda de jogos — pública e só de leitura (tela /agenda, 20/10/2026).
//
// Endpoints próprios, e não os de jogos e súmula, para o contrato público ter
// SÓ o que a tela mostra: nada de árbitros, observações ou ids internos de
// escola e, nos atletas, só nome e número da camisa — nunca RG, data de
// nascimento ou sexo (são menores de idade).
//
// - GET /api/agenda: todos os jogos numa consulta só (a tela filtra no
//   navegador: são uns 200 jogos, e o Render free acorda uma vez só).
// - GET /api/agenda/jogos/:id: o jogo e os atletas das duas equipes, buscados
//   só quando o público abre o detalhe.
// ============================================================================

const ENCERRADO = ['FINALIZADO', 'WO'];

const SELECT_AGENDA = `
  SELECT j.id, j.numero_jogo, j.fase, j.status, j.data_hora,
         j.placar_1, j.placar_2, j.penaltis_1, j.penaltis_2, j.prorrogacao,
         j.vencedor_equipe_id, j.baleou_primeiro_equipe_id,
         j.equipe_1_id, esc1.nome AS escola_1_nome,
         j.equipe_2_id, esc2.nome AS escola_2_nome,
         g.nome AS grupo_nome, j.local_id, l.nome AS local_nome,
         j.competicao_id, c.turno, c.proxima_fase,
         m.nome AS modalidade_nome, m.slug AS modalidade_slug,
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

// Linha do banco -> jogo da agenda. Data e hora saem como texto de relógio de
// parede ("2026-11-24" e "10:30"), sem fuso: o DATETIME já viaja como texto.
const jogoDaAgenda = (j) => {
  const encerrado = ENCERRADO.includes(j.status);
  const [data = null, horaCompleta = null] = j.data_hora ? j.data_hora.split(' ') : [];
  const melhorDeDois = j.turno === 'IDA_E_VOLTA' && j.proxima_fase === 'NENHUMA';

  let decisao = null;
  if (encerrado && j.baleou_primeiro_equipe_id) decisao = 'ACRESCIMO';
  else if (encerrado && j.penaltis_1 !== null && j.penaltis_2 !== null) decisao = 'COBRANCAS';

  return {
    id: j.id,
    numero_jogo: j.numero_jogo,
    data,
    hora: horaCompleta ? horaCompleta.slice(0, 5) : null,
    local: j.local_id ? { id: j.local_id, nome: j.local_nome } : null,
    competicao: {
      id: j.competicao_id,
      modalidade: j.modalidade_nome,
      modalidade_slug: j.modalidade_slug,
      categoria: j.categoria_nome,
      genero: j.genero
    },
    // GRUPOS, SEMIFINAL ou FINAL; "melhor de dois jogos" é a competição de 2
    // escolas em ida e volta, sem mata-mata (os jogos dela são de GRUPOS)
    fase: j.fase,
    melhor_de_dois: melhorDeDois,
    grupo: j.fase === 'GRUPOS' && !melhorDeDois ? j.grupo_nome : null,
    status: j.status,
    equipe_1: { id: j.equipe_1_id, escola: j.escola_1_nome },
    equipe_2: { id: j.equipe_2_id, escola: j.escola_2_nome },
    // Placar e resultado só de jogo encerrado (finalizado ou W.O.)
    placar: encerrado ? { equipe_1: j.placar_1, equipe_2: j.placar_2 } : null,
    resultado: encerrado
      ? {
        vencedor: j.vencedor_equipe_id === j.equipe_1_id ? 1 : j.vencedor_equipe_id === j.equipe_2_id ? 2 : null,
        decisao,
        cobrancas: decisao === 'COBRANCAS' ? { equipe_1: j.penaltis_1, equipe_2: j.penaltis_2 } : null,
        prorrogacao: Boolean(j.prorrogacao),
        wo: j.status === 'WO'
      }
      : null
  };
};

// GET /api/agenda — público. Ordem: dia, local, hora; sem data vai por último.
const listarAgenda = async (req, res) => {
  try {
    const [linhas] = await db.query(
      `${SELECT_AGENDA}
       ORDER BY j.data_hora IS NULL, DATE(j.data_hora), l.nome IS NULL, l.nome, j.data_hora,
                m.nome, cat.nome, j.numero_jogo`
    );
    res.json(linhas.map(jogoDaAgenda));
  } catch (erro) {
    console.error('Erro ao montar a agenda de jogos:', erro);
    res.status(500).json({ erro: 'Erro ao buscar a agenda de jogos.' });
  }
};

// GET /api/agenda/jogos/:id — público. O jogo e os atletas inscritos nas duas
// equipes, com SÓ nome e número da camisa.
const detalharJogo = async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ erro: 'Identificador de jogo inválido.' });
  }

  try {
    const [[linha]] = await db.query(`${SELECT_AGENDA} WHERE j.id = ?`, [id]);
    if (!linha) {
      return res.status(404).json({ erro: 'Jogo não encontrado.' });
    }

    const [atletas] = await db.query(
      `SELECT i.equipe_id, a.nome, i.numero_camisa
         FROM inscricoes_atletas i
         INNER JOIN atletas a ON a.id = i.atleta_id
        WHERE i.equipe_id IN (?, ?)
        ORDER BY i.numero_camisa IS NULL, i.numero_camisa, a.nome`,
      [linha.equipe_1_id, linha.equipe_2_id]
    );

    const jogo = jogoDaAgenda(linha);
    const elenco = (equipe_id) => atletas
      .filter((a) => a.equipe_id === equipe_id)
      .map((a) => ({ nome: a.nome, numero_camisa: a.numero_camisa }));

    res.json({
      ...jogo,
      equipe_1: { ...jogo.equipe_1, atletas: elenco(linha.equipe_1_id) },
      equipe_2: { ...jogo.equipe_2, atletas: elenco(linha.equipe_2_id) }
    });
  } catch (erro) {
    console.error('Erro ao buscar o jogo da agenda:', erro);
    res.status(500).json({ erro: 'Erro ao buscar o jogo.' });
  }
};

module.exports = { listarAgenda, detalharJogo };
