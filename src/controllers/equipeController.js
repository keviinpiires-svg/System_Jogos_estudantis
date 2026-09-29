const db = require('../config/db');

// Equipes filtradas por escola e/ou competição, com o que a tela de inscrição
// precisa para decidir: a competição a que pertencem, o grupo, quantos atletas
// já estão inscritos e qual é o teto da modalidade.
const listarEquipes = async (req, res) => {
  const condicoes = [];
  const valores = [];

  if (req.query.escola_id) {
    const escola_id = Number(req.query.escola_id);
    if (!Number.isInteger(escola_id) || escola_id <= 0) {
      return res.status(400).json({ erro: 'Identificador de escola inválido.' });
    }
    condicoes.push('e.escola_id = ?');
    valores.push(escola_id);
  }

  if (req.query.competicao_id) {
    const competicao_id = Number(req.query.competicao_id);
    if (!Number.isInteger(competicao_id) || competicao_id <= 0) {
      return res.status(400).json({ erro: 'Identificador de competição inválido.' });
    }
    condicoes.push('e.competicao_id = ?');
    valores.push(competicao_id);
  }

  const onde = condicoes.length > 0 ? `WHERE ${condicoes.join(' AND ')}` : '';

  try {
    const [equipes] = await db.query(
      `SELECT e.id, e.escola_id, e.competicao_id, e.tecnico_nome,
              esc.nome AS escola_nome,
              g.id AS grupo_id, g.nome AS grupo_nome,
              m.id AS modalidade_id, m.nome AS modalidade_nome, m.slug AS modalidade_slug,
              m.tipo AS modalidade_tipo, m.min_atletas, m.max_atletas,
              cat.nome AS categoria_nome, cat.idade_maxima, c.genero,
              (SELECT COUNT(*) FROM inscricoes_atletas i WHERE i.equipe_id = e.id) AS total_inscritos
         FROM equipes e
         INNER JOIN escolas esc ON esc.id = e.escola_id
         INNER JOIN competicoes c ON c.id = e.competicao_id
         INNER JOIN modalidades m ON m.id = c.modalidade_id
         INNER JOIN categorias cat ON cat.id = c.categoria_id
         LEFT JOIN grupos g ON g.id = e.grupo_id
         ${onde}
        ORDER BY m.ordem, cat.ordem, c.genero, esc.nome`,
      valores
    );

    res.status(200).json(equipes);
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao buscar as equipes.' });
  }
};

// Atletas da escola que PODEM entrar nesta equipe: mesma escola, sexo
// compatível com o gênero da competição, idade dentro da categoria e ainda não
// inscritos nela. As regras são as mesmas que a inscrição valida — repetidas
// aqui em SQL para a tela oferecer só quem passa, em vez de deixar o usuário
// escolher e levar um erro.
// O limite de 2 competições coletivas NÃO filtra a lista: o atleta vem com a
// contagem, e a tela avisa. Quem barra continua sendo a inscrição.
const listarElegiveis = async (req, res) => {
  const id = Number(req.params.id);

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ erro: 'Identificador de equipe inválido.' });
  }

  try {
    const [[equipe]] = await db.query(
      `SELECT e.id, e.escola_id, e.competicao_id,
              esc.nome AS escola_nome,
              c.genero, cat.nome AS categoria_nome, cat.idade_maxima,
              m.nome AS modalidade_nome, m.tipo AS modalidade_tipo, m.max_atletas,
              (SELECT COUNT(*) FROM inscricoes_atletas i WHERE i.equipe_id = e.id) AS total_inscritos
         FROM equipes e
         INNER JOIN escolas esc ON esc.id = e.escola_id
         INNER JOIN competicoes c ON c.id = e.competicao_id
         INNER JOIN categorias cat ON cat.id = c.categoria_id
         INNER JOIN modalidades m ON m.id = c.modalidade_id
        WHERE e.id = ?`,
      [id]
    );

    if (!equipe) {
      return res.status(404).json({ erro: 'Equipe não encontrada.' });
    }

    const condicoes = [
      'a.escola_id = ?',
      'NOT EXISTS (SELECT 1 FROM inscricoes_atletas i WHERE i.equipe_id = ? AND i.atleta_id = a.id)'
    ];
    const valores = [equipe.escola_id, id];

    // MISTO aceita os dois sexos; os demais exigem o correspondente
    if (equipe.genero !== 'MISTO') {
      condicoes.push('a.sexo = ?');
      valores.push(equipe.genero === 'MASCULINO' ? 'M' : 'F');
    }

    // Aberto tem idade_maxima nula e não limita
    if (equipe.idade_maxima !== null) {
      const [[evento]] = await db.query('SELECT ano FROM configuracao_evento WHERE id = 1');
      condicoes.push('YEAR(a.data_nascimento) >= ?');
      valores.push(evento.ano - equipe.idade_maxima);
    }

    const [elegiveis] = await db.query(
      `SELECT a.id, a.nome, a.sexo, YEAR(a.data_nascimento) AS ano_nascimento,
              (SELECT COUNT(DISTINCT c2.id)
                 FROM inscricoes_atletas i2
                 INNER JOIN equipes e2 ON e2.id = i2.equipe_id
                 INNER JOIN competicoes c2 ON c2.id = e2.competicao_id
                 INNER JOIN modalidades m2 ON m2.id = c2.modalidade_id
                WHERE i2.atleta_id = a.id AND m2.tipo = 'COLETIVO') AS competicoes_coletivas
         FROM atletas a
        WHERE ${condicoes.join(' AND ')}
        ORDER BY a.nome`,
      valores
    );

    res.status(200).json({ equipe, elegiveis });
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao buscar os atletas elegíveis.' });
  }
};

module.exports = { listarEquipes, listarElegiveis };
