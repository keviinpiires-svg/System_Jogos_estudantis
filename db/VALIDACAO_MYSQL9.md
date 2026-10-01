# Validação dos scripts no motor da produção — fatia 10

**01/10/2026.** Até aqui tudo havia sido testado no **MariaDB 10.4** do XAMPP, que não é o motor da
produção. Esta é a conferência no motor certo, antes de escrever o roteiro de migração.

A validação foi feita **duas vezes**: primeiro em MySQL 8.0.46, enquanto a versão da produção ainda
não era conhecida, e depois em **MySQL 9.4.0**, que é a da produção. **O que vale é o 9.4.0**; o
8.0.46 ficou como termo de comparação e rendeu uma conferência a mais (a comparação de schema, abaixo).

## Como foi montado

| Instância | Porta | Papel |
|---|---|---|
| MariaDB 10.4.32 (XAMPP) | 3306 | o banco de desenvolvimento de sempre, intocado |
| MySQL 8.0.46 | 3307 | primeira validação, instalada para esta fatia |
| **MySQL 9.4.0** | **3308** | **o motor da produção — validação que vale** |

Banco `jogos_estudantis_dev9`, criado com `CHARACTER SET utf8mb4` e **sem `COLLATE`**, como manda o
`README.md`. Nada apontou para a produção em momento algum.

A senha do root da 3308 foi usada por um arquivo de opções do MySQL fora dos dois repositórios,
apagado ao fim da validação. **Não está em nenhum arquivo versionado.**

## Resultado: os 7 scripts rodam limpos, na ordem, em banco vazio

`00` → `01` → `02` → `03` → `04` → `05` → `06`, cada um sem erro, no MySQL 9.4.0.

Importa em especial que o **`05_faltas_basquete.sql` aplica sobre o `01`**: ele é um `ALTER TABLE`
que, no desenvolvimento, tinha entrado em 29/09 sobre um banco já existente. Esta foi a primeira vez
que a sequência inteira rodou do zero.

| Conferência | Obtido | Esperado |
|---|---|---|
| Tabelas | 23 | 23 |
| Chaves estrangeiras | 33 | 33 |
| Restrições `CHECK` | 16 | 16 |
| Escolas | 18 | 18 |
| Apelidos de escola | 16 | 16 |
| Competições | 50 | 50 |
| Grupos | 77 | 77 |
| Equipes | 240 | 240 |
| Provas de atletismo | 3 | 3 |
| Usuários criados pela carga | 0 | 0 |
| Ano do evento | 2026 | 2026 |
| Tabelas fora de `utf8mb4_0900_ai_ci` | 0 | 0 |

## O schema é idêntico em 8.0.46 e 9.4.0

Rodados os mesmos scripts nas duas instâncias e comparados os `mysqldump --no-data`
(normalizando só o nome do banco e o `AUTO_INCREMENT`): **403 linhas de cada lado, sem uma diferença**.
Nenhum tipo, padrão, collation ou restrição mudou de uma versão para a outra. Isso também diz que,
se a produção um dia for atualizada dentro dessa faixa, o schema não muda sozinho.

## O que se comportou diferente do desenvolvimento

**Collation — a diferença real, e ela vale para a produção.** A produção usa `utf8mb4_0900_ai_ci`,
que é **insensível a acento**; o MariaDB do XAMPP usa `utf8mb4_general_ci`, que **não é**. Medido nos três:

| | `'JOSE DIAS' = 'JOSÉ DIAS'` |
|---|---|
| MySQL 9.4.0 (`utf8mb4_0900_ai_ci`) | verdadeiro |
| MySQL 8.0.46 (`utf8mb4_0900_ai_ci`) | verdadeiro |
| MariaDB 10.4 (`utf8mb4_general_ci`) | falso |

Consequência em produção: `uq_escolas_nome` e `uq_apelidos_apelido` **recusam como duplicata** um nome
que só difere por acento. Para este sistema isso é bom — a seção 6 do contexto avisa que as escolas
aparecem escritas de muitas formas e que a importação gera duplicatas. Mas é preciso saber:
**não dá para cadastrar "JOSÉ DIAS" como apelido se existe a escola "JOSE DIAS"**.

Conferido que isso **não morde na importação atual**: o `03_importar_grupos.sql` não usa
`INSERT IGNORE` nem `ON DUPLICATE KEY` (uma colisão daria erro, não passaria batido), os 16 apelidos
entraram, e nenhum par escola/apelido difere apenas por acento.

**Autenticação.** O MySQL 9 **removeu o `mysql_native_password`** — na 3308 só existem
`caching_sha2_password` (o do usuário) e `sha256_password`. O driver `mysql2` do projeto autenticou
sem configuração nenhuma, inclusive sem TLS. Em produção a conexão é com TLS (`DB_SSL=true`), que é
o caso mais fácil. **Nada a mudar no código por causa disso.**

## O que foi testado além de "rodou"

Tudo no MySQL 9.4.0:

- **`CHECK` de verdade recusando** (no MySQL 5.7 elas seriam ignoradas em silêncio): placar negativo
  → `ERROR 3819 ... 'jogos_chk_2'`; mesma equipe dos dois lados → `'jogos_chk_1'`; número de jogo zero
  → `'jogos_chk_4'`.
- **Chave estrangeira composta**: pôr num jogo uma equipe de outra competição → `ERROR 1452`,
  recusado por `fk_jogos_equipe_2`. É o banco garantindo a regra, sem depender do código.
- **Renumeração de jogos** sob o índice único `uq_jogos_numero`, que é o ponto onde os motores mais
  divergem: jogos 1–5, apagado o 2, `UPDATE ... ORDER BY numero_jogo ASC` → 1,2,3,4, sem conflito.
- **`npm run fumaca` contra este banco**: 21 ok, 0 falhas, e o banco voltou ao estado anterior
  (nenhum jogo, atleta, inscrição, súmula, ajuste ou usuário deixado para trás).
- **Rota `/saude`** (nova): 200 com o banco de pé, **503** com o MySQL derrubado, 200 de novo ao voltar.
- **Trava de CORS em produção**: `NODE_ENV=production` sem `CORS_ORIGIN` → o servidor **recusa subir**.
  Com a variável preenchida, sobe, e uma origem não listada não recebe `access-control-allow-origin`.

## Uma correção que esta validação provocou

A trava de segurança do `scripts/fumaca.js` conferia o **`DB_NAME`**, mas o `src/config/db.js`
**ignora o `DB_NAME` quando existe `DATABASE_URL`**. Um `.env` com a URL da produção e um
`DB_NAME=..._dev` esquecido ao lado passava na conferência — e o teste de fumaça escreve e apaga.
A trava agora lê o alvo real da conexão, do mesmo jeito que o `db.js`, e diz em que banco e host a
conexão cairia. Testado: com uma `DATABASE_URL` apontando para a Railway, recusa antes de qualquer
consulta.

## Como repetir

As instâncias 3307 e 3308 são locais e descartáveis. Para subir de novo a do MySQL 8 depois de
reiniciar a máquina:

```
C:\Users\Kevin\mysql8-3307\mysql-8.0.46-winx64\bin\mysqld.exe --defaults-file=C:\Users\Kevin\mysql8-3307\my.ini
```

Para apagá-la: encerre o `mysqld` e remova a pasta — nada foi registrado no Windows. A instância do
MySQL 9.4.0 na 3308 foi preparada pelo usuário e não é gerida por este repositório.

## Conclusão

**Os scripts estão prontos para a produção.** Não há ajuste pendente neles. O que falta da fatia 10
é o roteiro de migração, a configuração do Render e da Vercel, e o plano de volta atrás.
