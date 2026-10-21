// Recria, do zero, o banco próprio do teste de fumaça (padrão: jogos_fumaca_dev)
// com os scripts db/01 a db/17, no mesmo servidor do banco de desenvolvimento.
//
// Por quê: o fumaca procura competições sem jogos para testar. Com a tabela
// oficial de jogos importada no jogos_estudantis_dev (20/10/2026), quase todas
// têm jogos, e o teste deixou de achar onde trabalhar. Num banco recém-criado
// ele roda sempre igual, sem depender (nem mexer) nos dados do dev.
//
// Uso (ver CLAUDE.md, "Comandos"):
//   npm run fumaca:banco                          (recria o jogos_fumaca_dev)
//   PORT=3001 DB_NAME=jogos_fumaca_dev npm start  (API de teste nesse banco)
//   DB_NAME=jogos_fumaca_dev FUMACA_API=http://localhost:3001/api npm run fumaca
//
// Trava: só apaga e recria banco cujo nome tenha "fumaca" E "dev" — nunca o
// jogos_estudantis_dev, nem a produção.
require('dotenv').config({ quiet: true });
const fs = require('fs');
const path = require('path');
const db = require('../src/config/db');

const BANCO = process.argv[2] || 'jogos_fumaca_dev';
const SCRIPTS = [
  '01_schema', '02_carga_base', '03_importar_grupos', '04_locais', '05_faltas_basquete',
  '06_ajustes_regras_provisorios', '07_baleados_por_equipe', '08_baleado_acrescimo_final',
  '09_elenco_handebol_baleado', '10_locais_cebc_ceja', '11_pontos_lancados',
  '12_locais_adelieta_ceti', '13_escola_conveniada', '14_tabela_do_chefe_equipes',
  '15_numero_tabela', '16_pontos_lancados_por_prova', '17_pontos_lancados_historico'
];

// Os scripts não têm ";" dentro de texto nem procedures: dá para separar os
// comandos pelo ";" depois de tirar os comentários de linha
const comandos = (texto) => texto.replace(/--.*$/gm, '').split(';').map((c) => c.trim()).filter(Boolean);

(async () => {
  if (!/^[a-z0-9_]+$/i.test(BANCO) || !/fumaca/i.test(BANCO) || !/dev/i.test(BANCO)) {
    console.error(`Recusado: "${BANCO}" precisa ter "fumaca" e "dev" no nome (ex.: jogos_fumaca_dev).`);
    process.exit(1);
  }

  // Uma conexão só: o db/14 usa tabela temporária, que vive na conexão
  const conexao = await db.getConnection();
  try {
    await conexao.query(`DROP DATABASE IF EXISTS \`${BANCO}\``);
    await conexao.query(`CREATE DATABASE \`${BANCO}\` CHARACTER SET utf8mb4`);
    await conexao.query(`USE \`${BANCO}\``);

    for (const nome of SCRIPTS) {
      const texto = fs.readFileSync(path.join(__dirname, '..', 'db', `${nome}.sql`), 'utf8');
      for (const comando of comandos(texto)) await conexao.query(comando);
    }

    const [[contagem]] = await conexao.query(
      `SELECT (SELECT COUNT(*) FROM competicoes) AS competicoes, (SELECT COUNT(*) FROM equipes) AS equipes,
              (SELECT COUNT(*) FROM locais_disputa) AS locais, (SELECT COUNT(*) FROM jogos) AS jogos`
    );
    console.log(`${BANCO} recriado com db/01 a db/17:`, JSON.stringify(contagem));
  } catch (erro) {
    console.error(`Falha ao montar ${BANCO}:`, erro.code || '', erro.sqlMessage || erro.message);
    process.exitCode = 1;
  } finally {
    // A conexão trocou de banco: não volta para o pool
    conexao.destroy();
    process.exit();
  }
})();
