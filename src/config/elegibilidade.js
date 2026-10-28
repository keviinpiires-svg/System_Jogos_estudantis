// Regras de cadastro e de elegibilidade do atleta, num lugar só: o cadastro de
// atleta, a inscrição na equipe e a importação de atletas por CSV usam estas
// funções, e nenhuma delas guarda cópia da regra.

const SEXOS = ['M', 'F'];

// Decisão do usuário (28/09/2026): o limite conta COMPETIÇÕES coletivas, não
// modalidades. Futsal Sub 13 + Futsal Sub 15 são duas, mesmo sendo a mesma
// modalidade. Atletismo é INDIVIDUAL e não entra na conta.
const LIMITE_COMPETICOES_COLETIVAS = 2;

// "competição masculino" soa errado: o adjetivo concorda com competição.
const ADJETIVO_GENERO = { MASCULINO: 'masculina', FEMININO: 'feminina', MISTO: 'mista' };

const plural = (n, um, varios) => `${n} ${n === 1 ? um : varios}`;

// O RG é o que impede o mesmo aluno de entrar duas vezes, e o índice UNIQUE
// compara texto literal: "12.345.678-9" e "123456789" seriam dois atletas
// diferentes. Guardar só letras e números, em maiúsculas, faz as duas grafias
// colidirem como deveriam.
const normalizarRg = (s) => (s || '').replace(/[^0-9A-Za-z]/g, '').toUpperCase();

const normalizarNome = (s) => (s || '').trim().replace(/\s+/g, ' ');

// Só AAAA-MM-DD, e a data precisa existir: o construtor Date transforma
// 2011-02-30 em 2011-03-02 sem reclamar, e o erro passaria despercebido.
const dataValida = (s) => {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s || '')) return false;
  const data = new Date(`${s}T00:00:00Z`);
  return !Number.isNaN(data.getTime()) && data.toISOString().slice(0, 10) === s;
};

// Tamanhos das colunas de atletas (db/01): passar disso o MySQL estrito recusa
const MAX_NOME = 150;
const MAX_RG = 20;

// A idade em si não é conferida aqui: ela só faz sentido contra a categoria da
// competição, e isso acontece na inscrição.
const validarAtleta = ({ nome, rg, data_nascimento, sexo, escola_id }) => {
  if (!nome) return 'Informe o nome do atleta.';
  if (nome.length > MAX_NOME) return `O nome do atleta passa de ${MAX_NOME} caracteres.`;
  if (!rg) return 'O RG é obrigatório para inscrever o atleta.';
  if (rg.length > MAX_RG) return `O RG passa de ${MAX_RG} letras e números.`;
  if (!dataValida(data_nascimento)) return 'Informe a data de nascimento no formato AAAA-MM-DD.';
  if (data_nascimento > new Date().toISOString().slice(0, 10)) {
    return 'A data de nascimento não pode estar no futuro.';
  }
  if (!SEXOS.includes(sexo)) return 'Informe o sexo do atleta (M ou F).';
  if (!Number.isInteger(escola_id) || escola_id <= 0) return 'Informe a escola do atleta.';
  return null;
};

const sexoCombina = (genero, sexo) => {
  if (genero === 'MISTO') return true;
  return genero === 'MASCULINO' ? sexo === 'M' : sexo === 'F';
};

// Sub N aceita quem nasceu em (ano do evento - N) ou depois; Aberto
// (idade_maxima nula) aceita todos
const anoMinimoDaCategoria = (anoDoEvento, idadeMaxima) => (
  idadeMaxima === null || idadeMaxima === undefined ? null : anoDoEvento - idadeMaxima
);

const idadeCabe = (anoDoEvento, idadeMaxima, anoNascimento) => {
  const minimo = anoMinimoDaCategoria(anoDoEvento, idadeMaxima);
  return minimo === null || anoNascimento >= minimo;
};

// Por que este atleta não pode entrar nesta equipe — ou null se pode.
//   competicao: { genero, categoria_nome, idade_maxima, modalidade_nome,
//                 modalidade_tipo, max_atletas }
//   atleta:     { nome, sexo, ano_nascimento }
//   coletivas:  competições coletivas em que ele já está (fora esta)
//   inscritos:  atletas que a equipe já tem
// Devolve { status, erro }: 400 para o que é do atleta (sexo, idade), 409 para
// o que é de limite (competições coletivas, elenco cheio).
const motivoDeInelegibilidade = ({ competicao, atleta, anoDoEvento, coletivas, inscritos }) => {
  if (!sexoCombina(competicao.genero, atleta.sexo)) {
    return {
      status: 400,
      erro: `${competicao.modalidade_nome} ${competicao.categoria_nome} é uma competição ${ADJETIVO_GENERO[competicao.genero]} e não aceita este atleta.`
    };
  }

  if (!idadeCabe(anoDoEvento, competicao.idade_maxima, atleta.ano_nascimento)) {
    const anoMinimo = anoMinimoDaCategoria(anoDoEvento, competicao.idade_maxima);
    return {
      status: 400,
      erro: `${competicao.categoria_nome} aceita nascidos em ${anoMinimo} ou depois. ${atleta.nome} nasceu em ${atleta.ano_nascimento}.`
    };
  }

  if (competicao.modalidade_tipo === 'COLETIVO' && coletivas >= LIMITE_COMPETICOES_COLETIVAS) {
    return {
      status: 409,
      erro: `${atleta.nome} já está em ${plural(coletivas, 'competição coletiva', 'competições coletivas')}, o máximo permitido pelo regulamento.`
    };
  }

  // Teto da modalidade (modalidades.max_atletas: 14, e 12 no handebol e no
  // baleado desde 07/10/2026). Nulo = sem limite (atletismo).
  if (competicao.max_atletas !== null && competicao.max_atletas !== undefined && inscritos >= competicao.max_atletas) {
    return {
      status: 409,
      erro: `Esta equipe já tem ${plural(inscritos, 'atleta', 'atletas')}, o máximo permitido em ${competicao.modalidade_nome}.`
    };
  }

  return null;
};

module.exports = {
  SEXOS,
  LIMITE_COMPETICOES_COLETIVAS,
  ADJETIVO_GENERO,
  plural,
  normalizarRg,
  normalizarNome,
  dataValida,
  validarAtleta,
  sexoCombina,
  anoMinimoDaCategoria,
  idadeCabe,
  motivoDeInelegibilidade
};
