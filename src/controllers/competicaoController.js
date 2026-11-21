const db = require('../config/db');

const GENEROS = ['MASCULINO', 'FEMININO', 'MISTO'];

// Resume a regra de disputa numa frase, para a tela não ter que reimplementar
// a leitura de qtd_grupos + classificados_por_grupo + melhores_segundos.
// É o mesmo texto conferido em docs/CONFERENCIA_COMPETICOES.md.
const descreverRegra = (c) => {
  if (c.turno === 'IDA_E_VOLTA') return 'Melhor de dois jogos';

  const destino = c.proxima_fase === 'SEMIFINAL' ? 'semifinal' : 'final';

  if (c.proxima_fase === 'NENHUMA') return 'Só fase de grupos';

  const porGrupo = c.classificados_por_grupo === 1
    ? 'o 1º de cada grupo'
    : `os ${c.classificados_por_grupo} primeiros de cada grupo`;

  const base = c.qtd_grupos === 1
    ? `os ${c.classificados_por_grupo} primeiros`
    : porGrupo;

  const segundos = c.melhores_segundos > 0
    ? c.melhores_segundos === 1
      ? ' + o melhor segundo'
      : ` + os ${c.melhores_segundos} melhores segundos`
    : '';

  return `${base}${segundos} → ${destino}`;
};

// Lista as competições, opcionalmente filtradas. Alimenta o submenu da
// modalidade e a tela de lista.
const listarCompeticoes = async (req, res) => {
  const { modalidade, genero, categoria_id } = req.query;

  const condicoes = [];
  const valores = [];

  if (modalidade) {
    // Aceita o slug (que é o que vai na URL do menu) ou o id
    const comoId = Number(modalidade);
    if (Number.isInteger(comoId) && comoId > 0) {
      condicoes.push('m.id = ?');
      valores.push(comoId);
    } else {
      condicoes.push('m.slug = ?');
      valores.push(String(modalidade));
    }
  }

  if (genero) {
    const valor = String(genero).toUpperCase();
    if (!GENEROS.includes(valor)) {
      return res.status(400).json({ erro: 'O gênero precisa ser MASCULINO, FEMININO ou MISTO.' });
    }
    condicoes.push('c.genero = ?');
    valores.push(valor);
  }

  if (categoria_id) {
    const valor = Number(categoria_id);
    if (!Number.isInteger(valor) || valor <= 0) {
      return res.status(400).json({ erro: 'Identificador de categoria inválido.' });
    }
    condicoes.push('cat.id = ?');
    valores.push(valor);
  }

  const onde = condicoes.length > 0 ? `WHERE ${condicoes.join(' AND ')}` : '';

  try {
    const [competicoes] = await db.query(
      `SELECT c.id, c.genero, c.status,
              c.qtd_grupos, c.classificados_por_grupo, c.melhores_segundos,
              c.proxima_fase, c.turno,
              c.minutos_por_tempo, c.minutos_por_tempo_final,
              m.id AS modalidade_id, m.nome AS modalidade_nome, m.slug AS modalidade_slug,
              m.tipo AS modalidade_tipo, m.tipo_placar,
              cat.id AS categoria_id, cat.nome AS categoria_nome,
              (SELECT COUNT(*) FROM equipes e WHERE e.competicao_id = c.id) AS total_equipes
         FROM competicoes c
         INNER JOIN modalidades m ON m.id = c.modalidade_id
         INNER JOIN categorias cat ON cat.id = c.categoria_id
         ${onde}
        ORDER BY m.ordem, cat.ordem, c.genero`,
      valores
    );

    res.status(200).json(competicoes.map((c) => ({ ...c, regra: descreverRegra(c) })));
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao buscar as competições.' });
  }
};

// Detalhe de uma competição: a regra de disputa e os grupos com suas equipes.
const buscarCompeticao = async (req, res) => {
  const id = Number(req.params.id);

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ erro: 'Identificador de competição inválido.' });
  }

  try {
    const [[competicao]] = await db.query(
      `SELECT c.id, c.genero, c.status,
              c.qtd_grupos, c.classificados_por_grupo, c.melhores_segundos,
              c.proxima_fase, c.turno,
              c.minutos_por_tempo, c.minutos_por_tempo_final,
              c.pontos_vitoria, c.pontos_empate, c.pontos_derrota,
              m.id AS modalidade_id, m.nome AS modalidade_nome, m.slug AS modalidade_slug,
              m.tipo AS modalidade_tipo, m.tipo_placar, m.min_atletas, m.max_atletas,
              cat.id AS categoria_id, cat.nome AS categoria_nome, cat.idade_maxima
         FROM competicoes c
         INNER JOIN modalidades m ON m.id = c.modalidade_id
         INNER JOIN categorias cat ON cat.id = c.categoria_id
        WHERE c.id = ?`,
      [id]
    );

    if (!competicao) {
      return res.status(404).json({ erro: 'Competição não encontrada.' });
    }

    // Uma consulta só para todas as equipes: o grupo pode ser nulo, então o
    // agrupamento acontece aqui, e não com um JOIN a partir de grupos.
    const [equipes] = await db.query(
      `SELECT e.id AS equipe_id, e.escola_id, e.tecnico_nome,
              esc.nome AS escola_nome,
              g.id AS grupo_id, g.nome AS grupo_nome,
              (SELECT COUNT(*) FROM inscricoes_atletas i WHERE i.equipe_id = e.id) AS total_inscritos
         FROM equipes e
         INNER JOIN escolas esc ON esc.id = e.escola_id
         LEFT JOIN grupos g ON g.id = e.grupo_id
        WHERE e.competicao_id = ?
        ORDER BY g.nome IS NULL, g.nome, esc.nome`,
      [id]
    );

    const grupos = [];
    const porGrupo = new Map();

    for (const equipe of equipes) {
      // Equipe sem grupo cai num balde próprio, para não sumir da tela
      const chave = equipe.grupo_id ?? 'sem-grupo';

      if (!porGrupo.has(chave)) {
        const grupo = {
          id: equipe.grupo_id,
          nome: equipe.grupo_nome || 'Sem grupo',
          equipes: []
        };
        porGrupo.set(chave, grupo);
        grupos.push(grupo);
      }

      porGrupo.get(chave).equipes.push({
        id: equipe.equipe_id,
        escola_id: equipe.escola_id,
        escola_nome: equipe.escola_nome,
        tecnico_nome: equipe.tecnico_nome,
        total_inscritos: equipe.total_inscritos
      });
    }

    res.status(200).json({
      ...competicao,
      regra: descreverRegra(competicao),
      total_equipes: equipes.length,
      grupos
    });
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao buscar a competição.' });
  }
};

module.exports = { listarCompeticoes, buscarCompeticao };
