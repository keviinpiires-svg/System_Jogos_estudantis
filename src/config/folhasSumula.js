// ============================================================================
// FOLHAS DE SÚMULA — o desenho do papel de cada modalidade, num lugar só.
//
// Fonte: docs/referencias/sumulas_modelos.md e os PDFs ao lado
// (sumula_futsal_modelo.pdf, sumula_basquete_modelo.pdf, sumula_volei_modelo.pdf).
//
// O backend usa isto para validar o que a mesa lança (quantas faltas cabem,
// se a modalidade tem cartão) e manda a mesma descrição para a tela, que
// decide qual folha desenhar. Assim a regra do papel existe UMA vez: mudar o
// número de linhas ou o teto de faltas é mexer só aqui.
//
// Decisão do usuário (29/09/2026): TODA folha impressa tem 14 linhas por
// equipe, inclusive basquete e vôlei, cujos papéis trazem 12 — o elenco do
// regulamento é 14 e a folha precisa comportá-lo.
// ============================================================================

const { REGRAS } = require('./regrasProvisorias');

const LINHAS = 14;

// Futsal, Futebol Society e Handebol usam exatamente a mesma folha: muda só o
// título, que sai do nome da modalidade.
const folhaDoFutsal = {
  tipo: 'FUTSAL',
  rotuloEstatistica: 'Gols',
  // O papel tem 11 quadradinhos de gol por atleta (contados no PDF)
  caixasEstatistica: 11,
  cartoes: true,
  maxAmarelos: 2,
  faltasIndividuais: 0,
  faltasAcumuladas: 5,
  tempoTecnico: true,
  sets: false,
  linhas: LINHAS
};

const FOLHAS = {
  futsal: folhaDoFutsal,
  'futebol-society': folhaDoFutsal,
  handebol: folhaDoFutsal,

  // Basquete: folha própria. Não tem cartão; tem faltas individuais de 0 a 5
  // por atleta e faltas acumulativas até 7 por tempo. A grade de PONTOS do
  // papel é a pontuação corrida da EQUIPE (2 a 97), não o placar do atleta.
  basquete: {
    tipo: 'BASQUETE',
    rotuloEstatistica: 'Pontos',
    caixasEstatistica: 0,
    cartoes: false,
    maxAmarelos: 0,
    faltasIndividuais: 5,
    faltasAcumuladas: 7,
    tempoTecnico: true,
    sets: false,
    linhas: LINHAS,
    // Grade da pontuação corrida: 8 colunas de 12 números, 2 a 97
    pontuacaoCorrida: { de: 2, colunas: 8, porColuna: 12 }
  },

  // Vôlei: folha de sets. Sem gols, cartões, faltas ou tempo técnico.
  // O placar sai de jogo_sets — fatia 6, parte do vôlei.
  volei: {
    tipo: 'VOLEI',
    rotuloEstatistica: null,
    caixasEstatistica: 0,
    cartoes: false,
    maxAmarelos: 0,
    faltasIndividuais: 0,
    faltasAcumuladas: 0,
    tempoTecnico: false,
    sets: true,
    linhas: LINHAS,
    // Regulamento: melhor de 3, set de 21 pontos. O papel tem a sequência
    // 1 a 20 por set, com o placar escrito ao lado.
    setsParaVencer: 2,
    maxSets: 3,
    pontosPorSet: 21
  },

  // Baleado: não veio folha oficial. Decisão provisória de 30/09/2026 —
  // usa o desenho do futsal com uma coluna de eliminações no lugar dos gols.
  // A regra vive em regrasProvisorias.baleado; aqui só a consumimos.
  baleado: {
    ...folhaDoFutsal,
    rotuloEstatistica: 'Eliminações',
    provisoria: REGRAS.baleado.provisorio,
    decididoEm: REGRAS.baleado.decididoEm
  }
};

// Modalidade sem folha cadastrada cai na do futsal: é a folha genérica do
// evento e nenhuma validação fica mais frouxa por causa disso.
const folhaDaModalidade = (slug) => FOLHAS[slug] || folhaDoFutsal;

module.exports = { FOLHAS, folhaDaModalidade, LINHAS };
