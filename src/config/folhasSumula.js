// ============================================================================
// FOLHAS DE SÚMULA — o desenho do papel de cada modalidade, num lugar só.
//
// Fonte: docs/referencias/sumulas_modelos.md e os PDFs ao lado
// (SUMULA_FUTSAL_MODELO.pdf, SUMULA_BASQUETE_MODELO.pdf, SUMULA_VOLEI_MODELO.pdf).
//
// O backend usa isto para validar o que a mesa lança (quantas faltas cabem,
// se a modalidade tem cartão) e manda a mesma descrição para a tela, que
// decide qual folha desenhar. Assim a regra do papel existe UMA vez: mudar o
// número de linhas ou o teto de faltas é mexer só aqui.
//
// Decisão do usuário (29/09/2026): TODA folha impressa tem 14 linhas por
// equipe, inclusive basquete e vôlei, cujos papéis trazem 12 — o elenco do
// regulamento é 14 e a folha precisa comportá-lo.
//
// Exceção de 06/10/2026, nas folhas oficiais do HANDEBOL e do BALEADO: a folha
// em branco tem as 12 linhas do papel, e a preenchida ganha a 13ª e a 14ª só
// quando a equipe tiver mais de 12 inscritos. Fidelidade ao modelo oficial,
// sem perder atleta na impressão. `linhas` é o que a folha em branco desenha;
// `linhasMaximas` é o teto que o backend aceita e a preenchida pode chegar.
// ============================================================================

const LINHAS = 14;
const LINHAS_DO_PAPEL = 12;

// Futsal e Futebol Society usam exatamente a mesma folha: muda só o título,
// que sai do nome da modalidade.
const folhaDoFutsal = {
  tipo: 'FUTSAL',
  // Sem título próprio: cai no nome da modalidade, que é o que o papel do
  // futsal e do society traz.
  titulo: null,
  rotuloEstatistica: 'Gols',
  // O papel tem 11 quadradinhos de gol por atleta (contados no PDF)
  caixasEstatistica: 11,
  cartoes: true,
  maxAmarelos: 2,
  faltasIndividuais: 0,
  faltasAcumuladas: 5,
  tempoTecnico: true,
  sets: false,
  linhas: LINHAS,
  linhasMaximas: LINHAS
};

const FOLHAS = {
  futsal: folhaDoFutsal,
  'futebol-society': folhaDoFutsal,

  // Handebol: folha oficial própria (docs/referencias/SUMULA_HANDEBOL.pdf).
  // Cartões em duas caixas, "A" e "V" — um amarelo e um vermelho por atleta —,
  // 10 caixas de gols (contadas no PDF), capitão escrito numa célula só e, no
  // rodapé, tempo técnico 1º T / 2º T e o técnico. Não tem falta individual
  // nem falta acumulada.
  handebol: {
    tipo: 'HANDEBOL',
    titulo: 'SÚMULA DE HANDEBOL',
    rotuloEstatistica: 'Gols',
    caixasEstatistica: 10,
    cartoes: true,
    maxAmarelos: 1,
    faltasIndividuais: 0,
    faltasAcumuladas: 0,
    tempoTecnico: true,
    sets: false,
    linhas: LINHAS_DO_PAPEL,
    linhasMaximas: LINHAS
  },

  // Basquete: folha própria. Não tem cartão; tem faltas individuais de 0 a 5
  // por atleta e faltas acumulativas até 7 por tempo. A grade de PONTOS do
  // papel é a pontuação corrida da EQUIPE (2 a 97), não o placar do atleta.
  basquete: {
    tipo: 'BASQUETE',
    // O papel escreve BASQUETEBOL, embora a modalidade se chame Basquete
    titulo: 'SÚMULA DE BASQUETEBOL',
    rotuloEstatistica: 'Pontos',
    caixasEstatistica: 0,
    cartoes: false,
    maxAmarelos: 0,
    faltasIndividuais: 5,
    faltasAcumuladas: 7,
    tempoTecnico: true,
    sets: false,
    linhas: LINHAS,
    linhasMaximas: LINHAS,
    // Grade da pontuação corrida: 8 colunas de 12 números, 2 a 97
    pontuacaoCorrida: { de: 2, colunas: 8, porColuna: 12 }
  },

  // Vôlei: folha de sets, com as duas equipes lado a lado. Sem gols, cartões,
  // faltas ou tempo técnico — o placar do jogo são os sets, de jogo_sets.
  volei: {
    tipo: 'VOLEI',
    // O papel escreve VOLEIBOL, embora a modalidade se chame Vôlei
    titulo: 'SÚMULA DE VOLEIBOL',
    rotuloEstatistica: null,
    caixasEstatistica: 0,
    cartoes: false,
    maxAmarelos: 0,
    faltasIndividuais: 0,
    faltasAcumuladas: 0,
    tempoTecnico: false,
    sets: true,
    linhas: LINHAS,
    linhasMaximas: LINHAS,
    // Regulamento: melhor de 3, set de 21 pontos, vencendo por 2 de vantagem.
    setsParaVencer: 2,
    maxSets: 3,
    pontosPorSet: 21,
    // O papel traz a sequência de pontos 1 a 20 por equipe em cada set,
    // em 4 linhas de 5, com o placar escrito embaixo.
    gradeDoSet: { ate: 20, porLinha: 5 }
  },

  // Baleado: folha oficial própria (docs/referencias/SUMULA_BALEADO.pdf), que
  // substitui a provisória de 30/09/2026. Nº | ATLETAS | BALEADOS | CAPITÃO:,
  // e no rodapé só o técnico. Não tem cartões, faltas nem tempo técnico.
  // BALEADOS é um contador DA EQUIPE, não por atleta: as caixas de 1 a 10
  // marcam as atletas daquela equipe que foram baleadas (06/10/2026), e o
  // placar de uma equipe é o número de baleadas da adversária. Fica em
  // sumula_equipes.baleados (db/07_baleados_por_equipe.sql).
  baleado: {
    tipo: 'BALEADO',
    titulo: 'SÚMULA DE BALEADO',
    // Sem lançamento por atleta: o placar sai do contador da equipe
    rotuloEstatistica: null,
    caixasEstatistica: 0,
    baleadosPorEquipe: 10,
    cartoes: false,
    maxAmarelos: 0,
    faltasIndividuais: 0,
    faltasAcumuladas: 0,
    tempoTecnico: false,
    sets: false,
    linhas: LINHAS_DO_PAPEL,
    linhasMaximas: LINHAS
  }
};

// Modalidade sem folha cadastrada cai na do futsal: é a folha genérica do
// evento e nenhuma validação fica mais frouxa por causa disso.
//
// O título sai daqui e não do nome da modalidade: o papel do basquete diz
// "BASQUETEBOL" e o do vôlei diz "VOLEIBOL", embora as modalidades estejam
// cadastradas como Basquete e Vôlei. Quem não tem título próprio usa o nome.
const folhaDaModalidade = (slug, nomeModalidade) => {
  const folha = FOLHAS[slug] || folhaDoFutsal;
  return {
    ...folha,
    titulo: folha.titulo || `SÚMULA DE ${(nomeModalidade || '').toUpperCase()}`
  };
};

module.exports = { FOLHAS, folhaDaModalidade, LINHAS };
