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
- O papel oficial escreve "SÚMULA DE BASQUETEBOL"; a folha impressa usa o nome da modalidade cadastrada, **Basquete**.

## Vôlei
- Um bloco com as duas equipes lado a lado. O papel traz **12 linhas** por equipe (Nº e Atleta); o sistema imprime **14**, Nome da equipe e **Assinatura do Capitão**.
- **Controle dos sets**: 1º, 2º e 3º set, cada um com Saque A / Saque B (marcação de quem saca) e a sequência de pontos 1 a 20 por equipe, mais o **Placar** do set (___ x ___).
- **Resultado final**: sets de cada equipe, Vencedor (marcar A ou B), Observações, assinaturas dos Árbitros 1 e 2.
- Não há gols, cartões, faltas nem tempo técnico.

## O que muda no sistema
| Item | Futsal/Society | Handebol | Basquete | Vôlei |
|---|---|---|---|---|
| Linhas de atleta | 14 | 14 | 14 (papel: 12) | 14 (papel: 12) |
| Estatística do atleta | gols, cartões | gols, cartões | pontos, faltas (0 a 5) | nenhuma |
| Rodapé da equipe | faltas 1T/2T (até 5), tempo técnico, técnico | igual | faltas 1T/2T (até 7), tempo técnico, técnico | — |
| Placar | soma dos gols | soma dos gols | soma dos pontos | sets (`jogo_sets`) |

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
- Vôlei usa `jogo_sets` (até 3 sets, vence quem faz 2) — **ainda sem tratamento no backend**.
- **Baleado não tem folha oficial** entre os modelos recebidos (pendência 12 da seção 12 do contexto).
  Decisão provisória de 30/09/2026: folha do futsal com coluna de eliminações.
