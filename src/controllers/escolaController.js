const db = require('../config/db');

const cadastrarEscola = async (req, res) => {
  const { etapa_ensino_id } = req.body;

  // Nome normalizado: sem espaços nas pontas, sem espaços duplos e em maiúsculas.
  // Assim "cebn", " CEBN " e "CEBN" viram o mesmo registro.
  const nome = (req.body.nome || '').trim().replace(/\s+/g, ' ').toUpperCase();

  // O índice UNIQUE recusa um segundo cnpj vazio, mas aceita vários NULL
  const cnpj = (req.body.cnpj || '').trim() || null;

  if (!nome) {
    return res.status(400).json({ erro: 'Informe o nome da escola.' });
  }

  try {
    // A colação da coluna é case-insensitive, então esta comparação já pega
    // qualquer variação de caixa que tenha sido gravada antes da normalização.
    const [existentes] = await db.query('SELECT id, nome FROM escolas WHERE nome = ?', [nome]);

    if (existentes.length > 0) {
      return res.status(400).json({
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
    // Rede de segurança para o caso de dois cadastros simultâneos passarem
    // pela verificação acima. Só protege de fato com índice UNIQUE no banco.
    if (erro.code === 'ER_DUP_ENTRY') {
      const campo = /cnpj/i.test(erro.sqlMessage || '') ? 'CNPJ' : 'nome';
      return res.status(400).json({ erro: `Já existe uma escola cadastrada com este ${campo}.` });
    }
    console.error(erro);
    res.status(500).json({ erro: 'Erro ao cadastrar a escola. Verifique os dados.' });
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

// Exportando as duas funções para o Router conseguir enxergá-las
module.exports = {
  cadastrarEscola,
  listarEscolas
};