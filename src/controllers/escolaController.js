const db = require('../config/db');

// Padroniza o nome para casar com o índice uq_escolas_nome do banco:
// sem espaços nas pontas, sem espaços duplos no meio e em maiúsculas.
// Assim "cebn", " CEBN " e "Ce  Bn" chegam ao banco como um só valor.
const normalizarNome = (s) => (s || '').trim().replace(/\s+/g, ' ').toUpperCase();

// O índice UNIQUE recusa um segundo cnpj vazio, mas aceita vários NULL
const normalizarCnpj = (s) => (s || '').trim() || null;

// Traduz a violação de índice UNIQUE para uma resposta 409 com a mensagem
// certa. A tabela tem dois índices (uq_escolas_nome e cnpj), então olhamos
// a mensagem do MySQL para não acusar o campo errado.
const responderDuplicidade = (erro, res) => {
  const conflitoDeCnpj = /cnpj/i.test(erro.sqlMessage || '');
  return res.status(409).json({
    erro: conflitoDeCnpj
      ? 'Já existe uma escola com esse CNPJ.'
      : 'Já existe uma escola com esse nome.'
  });
};

const cadastrarEscola = async (req, res) => {
  // A coluna aceita nulo, então o cliente não precisa mandar esse id.
  // Sem o ?? null, um campo ausente chegaria como undefined e o mysql2
  // recusaria a query inteira.
  const etapa_ensino_id = req.body.etapa_ensino_id ?? null;
  const nome = normalizarNome(req.body.nome);
  const cnpj = normalizarCnpj(req.body.cnpj);

  if (!nome) {
    return res.status(400).json({ erro: 'Informe o nome da escola.' });
  }

  try {
    // A colação da coluna é case-insensitive, então esta comparação já pega
    // qualquer variação de caixa que tenha sido gravada antes da normalização.
    const [existentes] = await db.query('SELECT id, nome FROM escolas WHERE nome = ?', [nome]);

    if (existentes.length > 0) {
      return res.status(409).json({
        erro: `A escola "${existentes[0].nome}" já está cadastrada.`,
        id_escola: existentes[0].id
      });
    }

    const [resultado] = await db.query(
      'INSERT INTO escolas (nome, cnpj, etapa_ensino_id) VALUES (?, ?, ?)',
      [nome, cnpj, etapa_ensino_id]
    );

    res.status(201).json({
      mensagem: 'Escola cadastrada com sucesso!',
      id_escola: resultado.insertId
    });
  } catch (erro) {
    // Rede de segurança: dois cadastros simultâneos podem passar pela
    // verificação acima. Quem barra de fato é o índice UNIQUE do banco.
    if (erro.code === 'ER_DUP_ENTRY') {
      return responderDuplicidade(erro, res);
    }
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao cadastrar a escola. Verifique os dados.' });
  }
};

const atualizarEscola = async (req, res) => {
  const id = Number(req.params.id);
  const nome = normalizarNome(req.body.nome);
  const cnpj = normalizarCnpj(req.body.cnpj);

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ erro: 'Identificador de escola inválido.' });
  }

  if (!nome) {
    return res.status(400).json({ erro: 'Informe o nome da escola.' });
  }

  // A etapa só entra no UPDATE se o cliente mandar o campo. Sem isso, o
  // formulário (que não tem mais esse campo) apagaria a etapa já gravada.
  const alterarEtapa = req.body.etapa_ensino_id !== undefined;

  try {
    // O "id <> ?" deixa a escola manter o próprio nome ao salvar o formulário
    // sem se acusar de duplicada.
    const [existentes] = await db.query(
      'SELECT id FROM escolas WHERE nome = ? AND id <> ?',
      [nome, id]
    );

    if (existentes.length > 0) {
      return res.status(409).json({ erro: 'Já existe uma escola com esse nome.' });
    }

    const campos = ['nome = ?', 'cnpj = ?'];
    const valores = [nome, cnpj];

    if (alterarEtapa) {
      campos.push('etapa_ensino_id = ?');
      valores.push(req.body.etapa_ensino_id ?? null);
    }

    valores.push(id);

    const [resultado] = await db.query(
      `UPDATE escolas SET ${campos.join(', ')} WHERE id = ?`,
      valores
    );

    if (resultado.affectedRows === 0) {
      return res.status(404).json({ erro: 'Escola não encontrada.' });
    }

    res.status(200).json({ mensagem: 'Escola atualizada com sucesso!', id_escola: id });
  } catch (erro) {
    // Mesma rede de segurança do cadastro: se duas edições simultâneas
    // escolherem o mesmo nome, quem barra é o índice UNIQUE.
    if (erro.code === 'ER_DUP_ENTRY') {
      return responderDuplicidade(erro, res);
    }
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao atualizar a escola. Verifique os dados.' });
  }
};

// Nova função adicionada: Busca todas as escolas no banco
const listarEscolas = async (req, res) => {
  try {
    const [escolas] = await db.query('SELECT * FROM escolas');
    res.status(200).json(escolas); // Envia os dados para o React
  } catch (erro) {
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao buscar as escolas.' });
  }
};

// Exportando as funções para o Router conseguir enxergá-las
module.exports = {
  cadastrarEscola,
  atualizarEscola,
  listarEscolas
};
