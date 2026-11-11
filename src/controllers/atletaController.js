const db = require('../config/db');
const { veDadosPessoais } = require('../middlewares/authMiddleware');
const { normalizarRg, normalizarNome, validarAtleta } = require('../config/elegibilidade');

const lerCorpo = (corpo) => ({
  nome: normalizarNome(corpo.nome),
  rg: normalizarRg(corpo.rg),
  data_nascimento: (corpo.data_nascimento || '').trim(),
  sexo: (corpo.sexo || '').trim().toUpperCase(),
  escola_id: Number(corpo.escola_id)
});

const cadastrarAtleta = async (req, res) => {
  const atleta = lerCorpo(req.body);
  const problema = validarAtleta(atleta);

  if (problema) {
    return res.status(400).json({ erro: problema });
  }

  try {
    const [resultado] = await db.query(
      'INSERT INTO atletas (nome, rg, data_nascimento, sexo, escola_id) VALUES (?, ?, ?, ?, ?)',
      [atleta.nome, atleta.rg, atleta.data_nascimento, atleta.sexo, atleta.escola_id]
    );

    res.status(201).json({
      mensagem: 'Atleta cadastrado com sucesso!',
      id_atleta: resultado.insertId
    });
  } catch (erro) {
    if (erro.code === 'ER_DUP_ENTRY') {
      // Quem já tem esse RG entra na resposta: a tela usa isso para oferecer
      // seguir com o atleta existente, em vez de deixar o usuário travado
      // tentando cadastrar de novo o mesmo aluno.
      const [[existente]] = await db.query(
        `SELECT a.id, a.nome, a.escola_id, esc.nome AS escola_nome
           FROM atletas a
           INNER JOIN escolas esc ON esc.id = a.escola_id
          WHERE a.rg = ?`,
        [atleta.rg]
      );

      return res.status(409).json({
        erro: existente
          ? `${existente.nome} já está cadastrado com este RG (${existente.escola_nome}).`
          : 'Já existe um atleta cadastrado com este RG.',
        atleta: existente || null
      });
    }
    if (erro.code === 'ER_NO_REFERENCED_ROW_2') {
      return res.status(400).json({ erro: 'A escola informada não existe.' });
    }
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao cadastrar o atleta. Verifique os dados.' });
  }
};

// Lista pública: o RG fica de fora de propósito, é dado pessoal e não faz falta
// em tela de consulta. Quem edita busca o atleta por id, numa rota de ADMIN.
const listarAtletasPorEscola = async (req, res) => {
  const escola_id = Number(req.params.escola_id);

  if (!Number.isInteger(escola_id) || escola_id <= 0) {
    return res.status(400).json({ erro: 'Identificador de escola inválido.' });
  }

  try {
    const [atletas] = await db.query(
      `SELECT id, nome, data_nascimento, sexo, escola_id
       FROM atletas WHERE escola_id = ? ORDER BY nome ASC`,
      [escola_id]
    );

    // Sexo e nascimento só para o ADMIN; a mesa (PLACAR) vê id, nome e escola
    res.status(200).json(veDadosPessoais(req)
      ? atletas
      : atletas.map(({ id, nome, escola_id }) => ({ id, nome, escola_id })));
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao buscar os atletas da escola.' });
  }
};

// Busca de atletas pelo NOME em todas as escolas (tela "Listar Atletas", sem escola escolhida).
// GET /api/atletas/busca?nome=... — só para logados (ADMIN ou PLACAR), com as mesmas regras de privacidade da
// lista por escola: a mesa recebe só id, nome e escola; o ADMIN também sexo e nascimento. RG nunca sai daqui.
// Pedaço do nome, sem diferenciar maiúscula nem acento (a collation do banco faz isso: na produção
// utf8mb4_0900_ai_ci). Mínimo de 3 letras e no máximo 50 resultados; consulta parametrizada, com
// % e _ do texto digitado tratados como letras comuns.
const MINIMO_DA_BUSCA = 3;
const LIMITE_DA_BUSCA = 50;

const buscarAtletasPorNome = async (req, res) => {
  const termo = String(req.query.nome ?? '').replace(/\s+/g, ' ').trim();

  if (termo.length < MINIMO_DA_BUSCA) {
    return res.status(400).json({ erro: `Digite pelo menos ${MINIMO_DA_BUSCA} letras para buscar.` });
  }
  if (termo.length > 80) {
    return res.status(400).json({ erro: 'O nome buscado é grande demais.' });
  }

  try {
    const padrao = `%${termo.replace(/[\\%_]/g, '\\$&')}%`;
    // Pede 1 a mais que o limite só para saber se a lista foi cortada
    const [linhas] = await db.query(
      `SELECT a.id, a.nome, a.data_nascimento, a.sexo, a.escola_id, s.nome AS escola_nome
         FROM atletas a
         INNER JOIN escolas s ON s.id = a.escola_id
        WHERE a.nome LIKE ?
        ORDER BY a.nome ASC, a.id ASC
        LIMIT ${LIMITE_DA_BUSCA + 1}`,
      [padrao]
    );

    const cortada = linhas.length > LIMITE_DA_BUSCA;
    const atletas = linhas.slice(0, LIMITE_DA_BUSCA);

    res.status(200).json({
      limite: LIMITE_DA_BUSCA,
      mais_resultados: cortada,
      atletas: veDadosPessoais(req)
        ? atletas
        : atletas.map(({ id, nome, escola_id, escola_nome }) => ({ id, nome, escola_id, escola_nome }))
    });
  } catch (erro) {
    console.error('Erro ao buscar atletas pelo nome:', erro);
    res.status(500).json({ erro: 'Erro ao buscar atletas.' });
  }
};

// Competições em que o atleta está inscrito (tela "Listar Atletas"). Só para logados, como a lista de atletas:
// modalidade, categoria, gênero e escola da equipe não são dado pessoal. A marca de EXCEÇÃO (idade acima
// do limite da categoria, revela o nascimento) só vai para o ADMIN. O RG e o nascimento não saem daqui.
const listarInscricoesDoAtleta = async (req, res) => {
  const id = Number(req.params.id);

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ erro: 'Identificador de atleta inválido.' });
  }

  try {
    const [[atleta]] = await db.query(
      `SELECT a.id, a.nome, a.escola_id, s.nome AS escola_nome
         FROM atletas a INNER JOIN escolas s ON s.id = a.escola_id WHERE a.id = ?`,
      [id]
    );

    if (!atleta) {
      return res.status(404).json({ erro: 'Atleta não encontrado.' });
    }

    const [linhas] = await db.query(
      `SELECT i.id AS inscricao_id, i.equipe_id, e.competicao_id, e.escola_id,
              s.nome AS escola_nome, m.nome AS modalidade, m.tipo AS tipo_modalidade,
              k.nome AS categoria, c.genero,
              (k.idade_maxima IS NOT NULL AND YEAR(a.data_nascimento) < ev.ano - k.idade_maxima) AS fora_da_idade
         FROM inscricoes_atletas i
         INNER JOIN atletas a ON a.id = i.atleta_id
         INNER JOIN equipes e ON e.id = i.equipe_id
         INNER JOIN escolas s ON s.id = e.escola_id
         INNER JOIN competicoes c ON c.id = e.competicao_id
         INNER JOIN modalidades m ON m.id = c.modalidade_id
         INNER JOIN categorias k ON k.id = c.categoria_id
         INNER JOIN configuracao_evento ev ON ev.id = 1
        WHERE i.atleta_id = ?
        ORDER BY m.nome, k.idade_maxima IS NULL, k.idade_maxima, c.genero`,
      [id]
    );

    const admin = veDadosPessoais(req);
    const inscricoes = linhas.map((l) => ({
      inscricao_id: l.inscricao_id,
      equipe_id: l.equipe_id,
      competicao_id: l.competicao_id,
      escola_id: l.escola_id,
      escola_nome: l.escola_nome,
      modalidade: l.modalidade,
      coletiva: l.tipo_modalidade === 'COLETIVO',
      categoria: l.categoria,
      genero: l.genero,
      ...(admin ? { excecao: Boolean(l.fora_da_idade) } : {})
    }));

    res.status(200).json({
      atleta: { id: atleta.id, nome: atleta.nome, escola_id: atleta.escola_id, escola_nome: atleta.escola_nome },
      inscricoes,
      total_coletivas: inscricoes.filter((i) => i.coletiva).length
    });
  } catch (erro) {
    console.error('Erro ao buscar as inscrições do atleta:', erro);
    res.status(500).json({ erro: 'Erro ao buscar as inscrições do atleta.' });
  }
};

// Só ADMIN: devolve o RG, para preencher a tela de edição.
const buscarAtletaPorId = async (req, res) => {
  const id = Number(req.params.id);

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ erro: 'Identificador de atleta inválido.' });
  }

  try {
    const [[atleta]] = await db.query(
      'SELECT id, nome, rg, data_nascimento, sexo, escola_id FROM atletas WHERE id = ?',
      [id]
    );

    if (!atleta) {
      return res.status(404).json({ erro: 'Atleta não encontrado.' });
    }

    res.status(200).json(atleta);
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao buscar o atleta.' });
  }
};

const excluirAtleta = async (req, res) => {
  const id = Number(req.params.id);

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ erro: 'Identificador de atleta inválido.' });
  }

  try {
    const [resultado] = await db.query('DELETE FROM atletas WHERE id = ?', [id]);

    if (resultado.affectedRows === 0) {
      return res.status(404).json({ erro: 'Atleta não encontrado.' });
    }

    res.status(200).json({ mensagem: 'Atleta excluído com sucesso!' });
  } catch (erro) {
    // inscricoes_atletas e resultados_atletismo apontam para cá com RESTRICT:
    // apagar um atleta inscrito levaria o elenco junto.
    if (erro.code === 'ER_ROW_IS_REFERENCED_2') {
      return res.status(409).json({
        erro: 'Este atleta está inscrito em alguma equipe. Remova as inscrições antes de excluí-lo.'
      });
    }
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao excluir o atleta.' });
  }
};

// Trocar a escola de um atleta já inscrito quebraria a regra de que atleta e
// equipe são da mesma escola, e o banco recusaria pela chave composta. Por isso
// a troca só passa enquanto ele não tiver inscrição.
const atualizarAtleta = async (req, res) => {
  const id = Number(req.params.id);
  const atleta = lerCorpo(req.body);
  const problema = validarAtleta(atleta);

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ erro: 'Identificador de atleta inválido.' });
  }

  if (problema) {
    return res.status(400).json({ erro: problema });
  }

  try {
    const [[atual]] = await db.query('SELECT escola_id FROM atletas WHERE id = ?', [id]);

    if (!atual) {
      return res.status(404).json({ erro: 'Atleta não encontrado.' });
    }

    if (atual.escola_id !== atleta.escola_id) {
      const [[{ inscricoes }]] = await db.query(
        'SELECT COUNT(*) AS inscricoes FROM inscricoes_atletas WHERE atleta_id = ?',
        [id]
      );

      if (inscricoes > 0) {
        return res.status(409).json({
          erro: 'Não dá para mudar a escola de um atleta já inscrito. Remova as inscrições primeiro.'
        });
      }
    }

    await db.query(
      'UPDATE atletas SET nome = ?, rg = ?, data_nascimento = ?, sexo = ?, escola_id = ? WHERE id = ?',
      [atleta.nome, atleta.rg, atleta.data_nascimento, atleta.sexo, atleta.escola_id, id]
    );

    res.status(200).json({ mensagem: 'Atleta atualizado com sucesso!', id_atleta: id });
  } catch (erro) {
    if (erro.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({ erro: 'Já existe um atleta cadastrado com este RG.' });
    }
    if (erro.code === 'ER_NO_REFERENCED_ROW_2') {
      return res.status(400).json({ erro: 'A escola informada não existe.' });
    }
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao atualizar o atleta.' });
  }
};

module.exports = {
  listarInscricoesDoAtleta,
  cadastrarAtleta,
  listarAtletasPorEscola,
  buscarAtletasPorNome,
  buscarAtletaPorId,
  excluirAtleta,
  atualizarAtleta
};
