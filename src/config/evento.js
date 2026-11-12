// Fuso horário do evento.
//
// As datas dos jogos são hora de parede: "24/11 às 10:30" quer dizer 10:30 em
// Barra do Choça, e é assim que ficam gravadas (DATETIME, sem fuso). Para
// comparar uma delas com "agora" é preciso saber que relógio é esse — daí este
// arquivo.
//
// Por que não vive em `configuracao_evento`: o fuso é o que permite INTERPRETAR
// o que está no banco, então guardá-lo lá seria circular. E ele depende de onde
// o servidor roda (o Render roda em UTC), que é configuração de infraestrutura,
// não dado do campeonato. `FUSO_EVENTO` no .env cobre o dia em que o evento
// mudar de lugar.
const FUSO_HORARIO = process.env.FUSO_EVENTO || 'America/Bahia';

// "agora" no relógio do evento, no formato que o MySQL entende: a comparação
// com jogos.data_hora passa a valer em qualquer servidor. O locale sueco é um
// atalho conhecido: é o único que formata exatamente como "2026-11-24 10:30:00".
const relogio = new Intl.DateTimeFormat('sv-SE', {
  timeZone: FUSO_HORARIO,
  year: 'numeric', month: '2-digit', day: '2-digit',
  hour: '2-digit', minute: '2-digit', second: '2-digit',
  hour12: false
});

const agoraNoFusoDoEvento = () => relogio.format(new Date());

module.exports = { FUSO_HORARIO, agoraNoFusoDoEvento };
