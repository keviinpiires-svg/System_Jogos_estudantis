# Modelos de súmula por modalidade (papel oficial)

Fonte: PDFs `sumula_*_modelo.pdf` nesta pasta (A4 retrato, logos do evento e da prefeitura no topo).
A folha impressa do sistema deve seguir estes modelos.

> **Decisões do usuário (29/09/2026) — valem sobre o papel:**
> 1. **Toda súmula impressa tem 14 linhas por equipe**, inclusive basquete e vôlei, cujos modelos em papel trazem 12.
>    O limite de elenco do regulamento é 14, e a folha precisa comportar o elenco inteiro.
> 2. **O handebol usa exatamente a folha do futsal** (mesmas colunas e o mesmo rodapé, inclusive "faltas acumuladas 1 a 5").
>    Não é um layout à parte: só muda o título da folha. Cabeçalho comum: Campeonato (JOGOS ESTUDANTIS 2026), Local, Nº do jogo, Cidade, Categoria, Data, Árbitro 1, Árbitro 2, Anotador, Equipe A x Equipe B com caixa de placar.

## Futsal (também Futebol Society) e Handebol — mesma folha, só muda o título
- Um bloco por equipe, com **14 linhas** de atleta.
- Colunas por linha: **Cartões** (A, A, V = 2 amarelos + vermelho), **Nº**, **Atleta**, **Gols** (11 quadradinhos — contados no PDF), **Capitão** (marca vertical ao lado).
- Rodapé da equipe: **Faltas acumuladas** 1º tempo (1 a 5) e 2º tempo (1 a 5); **Tempo técnico** 1º T e 2º T; **Técnico** (nome).
- O handebol usa exatamente a mesma folha do futsal (inclusive "faltas acumuladas 1 a 5").

## Basquete — ✅ feito (30/09/2026, fatia 6)
- Um bloco por equipe. O papel traz **12 linhas**; o sistema imprime **14**.
- Colunas: **Faltas individuais** (1 a 5, marca-se cada falta), **Nº**, **Atleta**, **Pontos** (grade numérica 2 a 97), **Capitão** (faixa vertical à direita).
- Rodapé: **Faltas acumulativas** 1º T (1 a 7) e 2º T (1 a 7); **Tempo técnico** 1º e 2º; **Técnico**.
- Não há coluna de cartões — e o sistema **recusa** cartão lançado em basquete.
- A grade de PONTOS é a **pontuação corrida da equipe** (2 a 97, em 8 colunas de 12), não o placar de
  cada atleta: o anotador risca o número conforme a equipe pontua. Como as linhas de atleta passaram de
  12 para 14, a grade fica num bloco só ao lado delas, mantendo os seus 12 degraus e os números do papel.
- **Acréscimo do sistema:** uma coluna estreita **"Pts"** com os pontos de cada atleta, que o papel não tem.
  O sistema guarda essa informação (é o que alimenta o cestinha) e a folha preenchida a mostra.
- O papel oficial escreve "SÚMULA DE BASQUETEBOL", e é esse o título impresso: **ele sai de `folhasSumula.js`**,
  não do nome da modalidade cadastrada (Basquete). Decisão do usuário de 30/09/2026.

## Vôlei — ✅ feito (30/09/2026, fatia 6)
- Folha à parte, não uma variação da do futsal: o cabeçalho **não tem caixa de placar** (o resultado fica no rodapé).
- Um bloco com as duas equipes **lado a lado**. O papel traz **12 linhas** por equipe (Nº e Atleta); o sistema imprime **14**,
  com a linha mais baixa para a folha continuar cabendo em uma página. Nome da equipe e **Assinatura do Capitão**.
- **Controle dos sets**: 1º, 2º e 3º set, cada um com Saque A / Saque B e a sequência de pontos 1 a 20 por equipe,
  mais o **Placar** do set (___ x ___). Na folha preenchida a sequência vem riscada até o ponto que a equipe fez.
- **Resultado final**: sets de cada equipe, Vencedor (marcado em A ou B), Observações, assinaturas dos Árbitros 1 e 2.
- Não há gols, cartões, faltas nem tempo técnico — e o sistema **recusa** ponto por atleta no vôlei.
- **As caixas de Saque A/B saem em branco nas duas versões:** o sistema guarda o placar dos sets, não quem sacou.
  Registrar o saque exigiria uma coluna nova em `jogo_sets` (seria uma migração `db/07`).
- O papel oficial escreve "SÚMULA DE VOLEIBOL"; como no basquete, **o título sai de `folhasSumula.js`**, não do nome
  da modalidade cadastrada (Vôlei).
- **Diferença de leitura do papel:** no modelo, a coluna "Nº" vem pré-impressa de 1 a 12, o que é um contador de linha.
  Aqui ela guarda o **número da camisa** do atleta, como em todas as outras folhas do sistema (em branco nas linhas vazias).

### Regra do set, no backend
Um set termina em **21 pontos com 2 de vantagem** (por isso 23 x 21 vale e 21 x 20 não), e o jogo acaba quando uma
equipe vence **2 sets** — decidido em dois, o terceiro não se joga. Enquanto o set está em andamento a mesa **salva
parcial** normalmente; a validação só fecha o cerco ao finalizar. O placar do jogo (`jogos.placar_1/2`) são os
**sets vencidos**, e os pontos de cada set ficam em `jogo_sets`, que a classificação já usa como critério de desempate.

## Baleado — ✅ feito (30/09/2026, fatia 6), folha PROVISÓRIA
**Não existe folha oficial do baleado** entre os modelos recebidos (pendência 12). Decisão provisória de
30/09/2026, registrada em `regrasProvisorias.baleado`: **usa o desenho da folha do futsal**, com a coluna do
atleta contando **eliminações** no lugar dos gols. O placar é a soma da coluna, que é o que `sumula_atletas.gols`
guarda quando `tipo_placar = ELIMINADOS`; a artilharia rotula "eliminados" e a classificação usa a ordem de
desempate do baleado (confronto direto → mais vitórias → menos vermelhos → menos amarelos → sorteio).

Ela sai com **cartões**, porque o regulamento usa vermelhos e amarelos como desempate do baleado. Duas diferenças
em relação ao papel do futsal, decididas com o usuário em 30/09/2026:
- **sem faltas acumuladas no rodapé** — o baleado não as usa, e o rodapé fica só com o tempo técnico e o técnico.
  Voltar o campo é pôr `faltasAcumuladas: 5` na folha do baleado em `folhasSumula.js`;
- a grade tem **14 caixas de eliminação por atleta** (o futsal tem 11), uma por adversário possível, já que o
  elenco do regulamento é 14. As colunas saem mais estreitas e a faixa da grade continua a mesma, então a folha
  segue em **uma página** nas duas versões. A largura da caixa é calculada em `FolhaFutsal.jsx` a partir do
  número de caixas, e não fixada no CSS.

A tela avisa, fora da impressão, que esta folha é provisória e de que data é a decisão.

## O que muda no sistema
| Item | Futsal/Society | Handebol | Basquete | Vôlei | Baleado |
|---|---|---|---|---|---|
| Linhas de atleta | 14 | 14 | 14 (papel: 12) | 14 (papel: 12) | 14 |
| Caixas na grade do atleta | 11 | 11 | — (grade é da equipe) | — | 14 |
| Estatística do atleta | gols, cartões | gols, cartões | pontos, faltas (0 a 5) | nenhuma | eliminações, cartões |
| Rodapé da equipe | faltas 1T/2T (até 5), tempo técnico, técnico | igual | faltas 1T/2T (até 7), tempo técnico, técnico | — | tempo técnico e técnico (sem faltas) |
| Placar | soma dos gols | soma dos gols | soma dos pontos | sets (`jogo_sets`) | soma das eliminações |
| Título impresso | nome da modalidade | nome da modalidade | SÚMULA DE BASQUETEBOL | SÚMULA DE VOLEIBOL | nome da modalidade |

## Onde isto vive no código

O desenho de cada folha (quantas linhas, se tem cartão, quantas faltas cabem, se tem sets) está em
**`System_jogos/src/config/folhasSumula.js`**, num objeto por modalidade. O backend usa esse objeto para
**validar** o que a mesa lança e manda o mesmo objeto para a tela, que escolhe qual folha desenhar
(`web-jogos/src/components/folhas/`). Mudar o teto de faltas ou o número de linhas é mexer num lugar só.

Estado do schema:
- `sumula_atletas.faltas` (0 a 5) — **criada** em `db/05_faltas_basquete.sql`, aplicada no banco de desenvolvimento
  em 29/09/2026 e **lida e gravada desde 30/09/2026**. Falta aplicar na produção.
- Os pontos do basquete usam a coluna `gols` (ali significa "pontos marcados"), como as eliminações do baleado.
- `sumula_equipes` já cobre faltas por tempo e tempo técnico; no basquete os contadores vão até 7.
- Vôlei usa `jogo_sets` (até 3 sets, vence quem faz 2) — **gravado e lido desde 30/09/2026**.
- **Baleado não tem folha oficial** entre os modelos recebidos (pendência 12 da seção 12 do contexto).
  Decisão provisória de 30/09/2026: folha do futsal com coluna de eliminações.
