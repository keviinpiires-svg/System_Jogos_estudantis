# Importação de atletas por CSV

Tela **`/importar-atletas`** (só ADMIN, link "Importar Atletas" no menu). No molde da importação de
jogos: primeiro a **prévia**, que não grava nada; depois o **confirmar**, que o servidor refaz do zero
numa **transação única** e grava só as linhas OK — tudo ou nada.

## Arquivo

CSV separado por `;` (o do Excel em português), UTF-8 com ou sem BOM (a tela também aceita o
Windows-1252 do Excel). Cabeçalho na primeira linha, colunas em qualquer ordem, sem diferença de acento
ou maiúscula:

| Coluna | Obrigatória | Aceita |
|---|---|---|
| Escola | não | nome oficial ou apelido (`escola_apelidos`). **Sem a coluna**, a tela exige escolher a escola antes de enviar (planilha de uma escola só) |
| Nome | sim | também "Nome do atleta", "Atleta", "Aluno" |
| RG | sim | normalizado como no cadastro: só letras e números, em maiúsculas (`12.345.678-9` = `123456789`) |
| Nascimento | sim | `DD/MM/AAAA` (também com `-` ou `.`) ou `AAAA-MM-DD`; ano com 4 dígitos. Também "Data de nascimento" |
| Gênero | sim | `M`/`F`, `Masculino`/`Feminino`. Também "Sexo" |
| Modalidade | sim | nome ou apelido (Futsal, Society, Vôlei/Voleibol, Basquete/Basquetebol...) |
| Categoria | não | `Sub 11`, `SUB-11`, `Aberto`... **Em branco, vale a categoria do atleta pela idade** (a menor em que ele cabe); para jogar acima, preencha |

Cada linha é **um aluno numa modalidade**: o mesmo aluno aparece em várias linhas, uma por modalidade
(com os mesmos nome, nascimento, gênero e escola). Modelo vazio: botão "Baixar modelo CSV vazio" na tela.
Exemplo fictício com todos os casos: `docs/importacao/exemplo_atletas_ficticio.csv`.

## O que cada linha vira

- **OK** — cria o atleta (na primeira linha do RG) e a inscrição na equipe da escola na competição
  (modalidade × categoria × gênero; o vôlei misto aceita os dois sexos). Camisa fica em branco.
- **AVISO (pulada)** — **RG já cadastrado**: a linha não grava nada e o atleta existente **não é
  alterado** nem ganha inscrição; ou a linha repete o mesmo aluno na mesma competição (entra uma vez).
- **ERRO (não entra)** — escola não encontrada ou ambígua, modalidade não encontrada, categoria
  inexistente, gênero inválido, nascimento inválido, no futuro ou fora das categorias da modalidade,
  RG vazio, categoria incompatível com a idade, escola sem equipe na competição, elenco cheio
  (`modalidades.max_atletas`: 14, ou 12 no handebol e no baleado), terceira competição coletiva, ou o
  mesmo RG com nome, nascimento, gênero ou escola diferentes de uma linha anterior.

As regras de elegibilidade são **as mesmas da inscrição pela tela** (`src/config/elegibilidade.js`):
o importador e o `inscricaoController` usam as mesmas funções. Os limites contam o que já está gravado
**mais** as linhas OK anteriores do próprio arquivo.

## Confirmar

- Sem erro: grava as linhas OK.
- Com linha em erro: o servidor recusa (**422**) a não ser que a tela peça explicitamente
  "importar só as linhas OK" (`apenas_ok=true`).
- Tudo numa transação: as equipes envolvidas e os RGs são travados, a análise é refeita, e qualquer
  falha no banco desfaz tudo ("Nada foi gravado").
- Resumo final: atletas criados, inscrições, linhas puladas e linhas com erro. Reimportar o mesmo
  arquivo dá 0 criados: tudo vira "RG já cadastrado".

## API (prefixo `/api/importar-atletas`, só ADMIN; corpo `text/csv`)

| Rota | O que faz |
|---|---|
| `POST /previa?escola_id=` | Analisa e devolve `{ resumo, linhas, sem_coluna_escola }`; não grava |
| `POST /confirmar?escola_id=&apenas_ok=true` | Refaz a análise e grava as OK; `201` (ou `200` sem nada novo), `422` com erro sem `apenas_ok`, `400` no arquivo sem cabeçalho certo ou sem escola, `409`/`500` "Nada foi gravado" |

`escola_id` só é lido quando a planilha não tem a coluna Escola.

## Dados pessoais

RG e nascimento são de menores: as duas rotas são só de ADMIN (sem login, 401; mesa, 403), a tela não
mostra RG nem nascimento na tabela, e o log do servidor registra só o código do erro (nunca a mensagem
do banco, que traria o RG, nem o SQL com os parâmetros). Nenhuma rota pública passou a devolver esses
campos (o `npm run fumaca` confere a lista pública da escola depois da importação).

## Teste

`npm run fumaca` (banco próprio de fumaça) roda a seção "importação de atletas por CSV" com a planilha
fictícia (RGs marcados `FUMACA…`): prévia com cada caso, 401/403, escola escolhida na tela, 422 sem
"só as OK", **falha no meio** (um gatilho temporário faz o INSERT do 17º atleta falhar: nada fica
gravado), confirmar, reimportar (0 criados) e RG existente com outros dados (o atleta não muda).
