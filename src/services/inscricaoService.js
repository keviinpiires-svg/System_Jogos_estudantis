// Inscrição de atleta em equipe, num lugar só: a tela de inscrição do ADMIN
// (inscricaoController) e a mesa (mesaAtletasController) passam por aqui, e
// nenhuma das duas guarda cópia da regra. Todas as funções recebem uma
// CONEXÃO já dentro de transação (quem chama faz begin/commit/rollback).
//
// A regra em si (sexo x gênero, idade, 2 coletivas, teto do elenco) mora em
// src/config/elegibilidade.js. A importação de atletas por CSV tem o seu
// próprio fluxo (com a coluna "Exceção") e não usa este arquivo.

const { motivoDeInelegibilidade, normalizarRg, plural } = require('../config/elegibilidade');

// A equipe, travada (FOR UPDATE): sem isso, duas inscrições simultâneas leriam
// o mesmo total de inscritos e o elenco poderia terminar com 15.
const lerEquipeTravada = async (conexao, equipe_id) => {
  const [[equipe]] = await conexao.query(
    'SELECT id, escola_id, competicao_id FROM equipes WHERE id = ? FOR UPDATE',
    [equipe_id]
  );
  return equipe || null;
};

const lerCompeticao = async (conexao, competicao_id) => {
  const [[competicao]] = await conexao.query(
    `SELECT c.id, c.genero,
            cat.nome AS categoria_nome, cat.idade_maxima,
            m.nome AS modalidade_nome, m.tipo AS modalidade_tipo,
            m.min_atletas, m.max_atletas
     FROM competicoes c
     INNER JOIN categorias cat ON cat.id = c.categoria_id
     INNER JOIN modalidades m ON m.id = c.modalidade_id
     WHERE c.id = ?`,
    [competicao_id]
  );
  return competicao;
};

// YEAR() vem do banco de propósito: uma coluna DATE chega ao Node como Date na
// hora local, e converter aqui erraria o ano por um dia.
const lerAtleta = async (conexao, atleta_id) => {
  const [[atleta]] = await conexao.query(
    'SELECT id, nome, escola_id, sexo, YEAR(data_nascimento) AS ano_nascimento FROM atletas WHERE id = ?',
    [atleta_id]
  );
  return atleta || null;
};

// Confere as regras de entrada do atleta nesta equipe. `atleta` traz
// { id (ou null, se ainda não existe), nome, escola_id, sexo, ano_nascimento }.
// Devolve { recusa: { status, erro } | null, inscritos }. Nunca abre exceção.
const avaliarEntrada = async (conexao, { equipe, competicao, atleta }) => {
  // 1. Atleta e equipe precisam ser da mesma escola. O banco também barra
  // pela chave composta, mas com uma mensagem que não ajuda o usuário.
  if (atleta.escola_id !== equipe.escola_id) {
    return { recusa: { status: 400, erro: 'Este atleta é de outra escola e não pode entrar nesta equipe.' }, inscritos: 0 };
  }

  // 2 a 5. Sexo x gênero, idade pela categoria, no máximo 2 competições
  // coletivas e teto do elenco. A competição de destino sai da conta das
  // coletivas: se ele já estiver inscrito nela, quem barra é o índice UNIQUE,
  // com mensagem própria.
  const [[evento]] = await conexao.query('SELECT ano FROM configuracao_evento WHERE id = 1');
  let coletivas = 0;
  if (atleta.id) {
    [[{ coletivas }]] = await conexao.query(
      `SELECT COUNT(DISTINCT c.id) AS coletivas
       FROM inscricoes_atletas i
       INNER JOIN equipes e ON e.id = i.equipe_id
       INNER JOIN competicoes c ON c.id = e.competicao_id
       INNER JOIN modalidades m ON m.id = c.modalidade_id
       WHERE i.atleta_id = ? AND m.tipo = 'COLETIVO' AND c.id <> ?`,
      [atleta.id, competicao.id]
    );
  }
  const [[{ inscritos }]] = await conexao.query(
    'SELECT COUNT(*) AS inscritos FROM inscricoes_atletas WHERE equipe_id = ?',
    [equipe.id]
  );

  const recusa = motivoDeInelegibilidade({
    competicao, atleta, anoDoEvento: evento.ano, coletivas, inscritos
  });
  return { recusa, inscritos };
};

// Grava a inscrição. `criado_por` = usuário da mesa que fez; NULL = ADMIN
// (o comportamento de sempre).
const gravarInscricao = async (conexao, { equipe_id, atleta_id, escola_id, numero_camisa = null, criado_por = null }) => {
  const [resultado] = await conexao.query(
    'INSERT INTO inscricoes_atletas (equipe_id, atleta_id, escola_id, numero_camisa, criado_por) VALUES (?, ?, ?, ?, ?)',
    [equipe_id, atleta_id, escola_id, numero_camisa, criado_por]
  );
  return resultado.insertId;
};

// O mínimo do regulamento é aviso, nunca bloqueio (decisão do usuário)
const avisoDeMinimo = (competicao, total) => (
  competicao.min_atletas !== null && total < competicao.min_atletas
    ? `A equipe tem ${plural(total, 'atleta', 'atletas')} e ${competicao.modalidade_nome} pede pelo menos ${competicao.min_atletas}.`
    : null
);

// Código provisório de quem não tem documento: <SIGLA>SRG<NNN>, guardado
// normalizado (ex.: ACMSRG028). O número é o maior já usado na escola + 1 (não
// preenche buracos). A escola é travada, para duas mesas não pegarem o mesmo
// número; o índice UNIQUE do RG é a segunda rede de segurança.
const proximoCodigoProvisorio = async (conexao, escola_id) => {
  const [[escola]] = await conexao.query('SELECT id, sigla FROM escolas WHERE id = ? FOR UPDATE', [escola_id]);
  if (!escola || !escola.sigla) return null;
  const prefixo = `${normalizarRg(escola.sigla)}SRG`;
  const [[{ maior }]] = await conexao.query(
    `SELECT COALESCE(MAX(CAST(SUBSTRING(rg, ?) AS UNSIGNED)), 0) AS maior
       FROM atletas WHERE escola_id = ? AND rg REGEXP ?`,
    [prefixo.length + 1, escola_id, `^${prefixo}[0-9]+$`]
  );
  return `${prefixo}${String(Number(maior) + 1).padStart(3, '0')}`;
};

module.exports = {
  lerEquipeTravada,
  lerCompeticao,
  lerAtleta,
  avaliarEntrada,
  gravarInscricao,
  avisoDeMinimo,
  proximoCodigoProvisorio
};
