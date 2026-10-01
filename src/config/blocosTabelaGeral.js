// ============================================================================
// BLOCOS DA TABELA GERAL — qual categoria entra em qual bloco.
//
// A tabela geral é dividida em anos iniciais, anos finais e ensino médio
// (escopo, item 7). A divisão é POR CATEGORIA, decisão do usuário de
// 01/10/2026: dividir pela escola não funciona, porque a mesma escola joga do
// Sub 7 ao Sub 17.
//
// ESTE ARQUIVO É A CONFIGURAÇÃO. Para mudar um Sub de bloco, mude o mapa
// abaixo — nenhum controller tem cópia dele. Enquanto `provisorio` for true,
// as telas avisam que a divisão ainda vai ser confirmada pelo chefe.
//
// A coluna `categorias.etapa_ensino_id` do schema continua existindo e vazia:
// se um dia a divisão virar cadastro de tela, ela é o lugar natural. Por ora
// o mapa daqui é a única fonte.
// ============================================================================

const DECIDIDO_EM = '01/10/2026';

// Os nomes são os de `categorias.nome`, como estão no banco
const BLOCOS = {
  provisorio: true,
  decididoEm: DECIDIDO_EM,
  descricao:
    'Divisão por categoria: Sub 7, 8 e 9 nos anos iniciais; Sub 11 e 13 nos anos finais; '
    + 'Sub 15, 17 e Aberto no ensino médio. É um palpite pela idade escolar típica — '
    + 'o chefe ainda vai dizer quais categorias entram em cada bloco.',

  // bloco -> categorias. A ordem é a de `etapas_ensino.ordem`.
  porBloco: [
    { etapa: 'Anos Iniciais', ordem: 1, categorias: ['Sub 7', 'Sub 8', 'Sub 9'] },
    { etapa: 'Anos Finais', ordem: 2, categorias: ['Sub 11', 'Sub 13'] },
    { etapa: 'Ensino Médio', ordem: 3, categorias: ['Sub 15', 'Sub 17', 'Aberto'] }
  ]
};

// categoria -> bloco, montado uma vez a partir do mapa acima
const PORCATEGORIA = new Map();
for (const bloco of BLOCOS.porBloco) {
  for (const categoria of bloco.categorias) {
    PORCATEGORIA.set(categoria, { etapa: bloco.etapa, ordem: bloco.ordem });
  }
}

// Categoria fora do mapa não some da tabela: cai num bloco próprio, visível,
// para ninguém descobrir só no fim que um Sub inteiro não estava somando.
const BLOCO_DESCONHECIDO = { etapa: 'Sem bloco definido', ordem: 99 };

const blocoDaCategoria = (nome) => PORCATEGORIA.get(nome) || BLOCO_DESCONHECIDO;

const blocosNaOrdem = () => [
  ...BLOCOS.porBloco.map((b) => ({ etapa: b.etapa, ordem: b.ordem })),
  BLOCO_DESCONHECIDO
];

module.exports = { BLOCOS, blocoDaCategoria, blocosNaOrdem, DECIDIDO_EM };
