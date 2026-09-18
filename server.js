const express = require('express');
const cors = require('cors');
const db = require('./src/config/db'); // Puxa a conexão que criamos

const app = express();
const PORT = 3000;

app.use(cors());
app.use(express.json());

// No Express 5, uma requisição sem corpo (ou sem Content-Type: application/json)
// deixa req.body como undefined, e qualquer destructuring quebra com erro 500.
// Garantir um objeto aqui protege todas as rotas de uma vez.
app.use((req, res, next) => {
    if (req.body === undefined) {
        req.body = {};
    }
    next();
});

// Importa as recepcionistas (apenas uma vez cada)
const escolaRoutes = require('./src/routes/escolaRoutes');

const jogoRoutes = require('./src/routes/jogoRoutes');
const alunoRoutes = require('./src/routes/alunoRoutes');
const sumulaRoutes = require('./src/routes/sumulaRoutes');
const mataMataRoutes = require('./src/routes/mataMataRoutes');
const classificacaoRoutes = require('./src/routes/classificacaoRoutes');
const atletaRoutes = require('./src/routes/atletaRoutes');
const artilhariaRoutes = require('./src/routes/artilhariaRoutes');
const dashboardRoutes = require('./src/routes/dashboardRoutes');
const authRoutes = require('./src/routes/authRoutes');
const grupoRoutes = require('./src/routes/grupoRoutes');
const verificarToken = require('./src/middlewares/authMiddleware');

app.use('/api/alunos', alunoRoutes);
app.use('/api/sumulas', sumulaRoutes);
app.use('/api/matamata', mataMataRoutes);
app.use('/api/classificacao', classificacaoRoutes);
app.use('/api/artilharia', artilhariaRoutes);
app.use('/api/dashboard', dashboardRoutes);
app.use('/api/grupos', grupoRoutes);
app.use('/api', authRoutes);

app.use('/api/escolas', escolaRoutes);
app.use('/api/jogos', jogoRoutes); // <-- Linha nova
app.use('/api/atletas', atletaRoutes);

app.get('/', (req, res) => {
    res.json({ mensagem: "API dos Jogos Estudantis rodando com sucesso!" });
});

// Locais de disputa, usados no dropdown de agendamento de jogos
app.get('/api/locais', async (req, res) => {
    try {
        const [linhas] = await db.query('SELECT id, nome, endereco FROM locais_disputa ORDER BY nome');
        res.json(linhas);
    } catch (erro) {
        console.error(erro);
        res.status(500).json({ erro: 'Erro ao buscar os locais de disputa.' });
    }
});

// Nossa nova rota do Banco de Dados
app.get('/api/etapas-ensino', async (req, res) => {
    try {
        const [linhas] = await db.query('SELECT * FROM etapas_ensino');
        res.json(linhas);
    } catch (erro) {
        console.error(erro);
        res.status(500).json({ erro: 'Erro ao buscar dados no banco.' });
    }
});
// Rota para Cadastrar um Diretor vinculado a uma Escola (Item 1)
app.post('/api/diretores', verificarToken, async (req, res) => {
    const { escola_id, nome, cpf, email, senha } = req.body;

    try {
        // Insere o diretor associado à escola informada
        const [resultado] = await db.query(
            'INSERT INTO diretores (escola_id, nome, cpf, email, senha) VALUES (?, ?, ?, ?, ?)',
            [escola_id, nome, cpf, email, senha]
        );
        
        res.status(201).json({ 
            mensagem: 'Diretor cadastrado com sucesso!',
            id_diretor: resultado.insertId 
        });
    } catch (erro) {
        console.error(erro);
        res.status(500).json({ erro: 'Erro ao cadastrar o diretor. Verifique se o CPF ou E-mail já existem.' });
    }
});

// Rota para Inscrever o Atleta em uma Modalidade e Categoria
app.post('/api/inscricoes', verificarToken, async (req, res) => {
    const { atleta_id, modalidade_id, categoria_id } = req.body;

    try {
        const [resultado] = await db.query(
            'INSERT INTO inscricoes_atletas (atleta_id, modalidade_id, categoria_id) VALUES (?, ?, ?)',
            [atleta_id, modalidade_id, categoria_id]
        );
        
        res.status(201).json({ 
            mensagem: 'Inscrição realizada com sucesso!',
            id_inscricao: resultado.insertId 
        });
    } catch (erro) {
        console.error(erro);
        
        // Lembra do "UNIQUE" que colocamos no banco de dados? Ele nos protege aqui!
        if (erro.code === 'ER_DUP_ENTRY') {
            return res.status(400).json({ 
                erro: 'Este atleta já está inscrito nesta modalidade e categoria exata.' 
            });
        }
        
        res.status(500).json({ erro: 'Erro ao processar a inscrição do atleta.' });
    }
});
// Rota para listar escolas participantes de uma modalidade/categoria (Início do Item 3)
app.get('/api/sorteio/participantes/:modalidadeId/:categoriaId', async (req, res) => {
    const { modalidadeId, categoriaId } = req.params;

    try {
        // Query utilizando INNER JOIN para garantir que só venham escolas com inscrições válidas
        const query = `
            SELECT DISTINCT e.id AS escola_id, e.nome AS escola_nome
            FROM inscricoes_atletas ia
            INNER JOIN atletas a ON ia.atleta_id = a.id
            INNER JOIN escolas e ON a.escola_id = e.id
            WHERE ia.modalidade_id = ? AND ia.categoria_id = ?
        `;
        
        const [escolas] = await db.query(query, [modalidadeId, categoriaId]);
        
        res.json({
            total_escolas: escolas.length,
            participantes: escolas
        });
    } catch (erro) {
        console.error(erro);
        res.status(500).json({ erro: 'Erro ao buscar participantes para o sorteio.' });
    }
});

// Rota para Gerar o Sorteio e Dividir em Grupos (Item 3)
app.post('/api/sorteio/gerar', verificarToken, async (req, res) => {
    // Recebe qual a modalidade, a categoria, e quantos grupos o torneio vai ter (ex: 2 grupos, A e B)
    const { modalidade_id, categoria_id, quantidade_grupos } = req.body;

    try {
        // 1. Busca as escolas participantes
        const queryBusca = `
            SELECT DISTINCT e.id, e.nome
            FROM inscricoes_atletas ia
            INNER JOIN atletas a ON ia.atleta_id = a.id
            INNER JOIN escolas e ON a.escola_id = e.id
            WHERE ia.modalidade_id = ? AND ia.categoria_id = ?
        `;
        const [escolas] = await db.query(queryBusca, [modalidade_id, categoria_id]);

        if (escolas.length === 0) {
            return res.status(400).json({ erro: 'Nenhuma escola inscrita para este sorteio.' });
        }

        // 2. Embaralha a lista usando o Algoritmo Fisher-Yates (o padrão ouro do JavaScript)
        for (let i = escolas.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [escolas[i], escolas[j]] = [escolas[j], escolas[i]]; // Troca as posições
        }

        // 3. Prepara a estrutura dos Grupos (A, B, C, D...)
        const grupos = {};
        const alfabeto = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];

        for (let i = 0; i < quantidade_grupos; i++) {
            grupos[alfabeto[i]] = []; // Cria os grupos vazios
        }

        // 4. Distribui as escolas como dar cartas em um jogo de baralho (uma para cada grupo)
        escolas.forEach((escola, index) => {
            const grupoAtual = alfabeto[index % quantidade_grupos];
            grupos[grupoAtual].push(escola);
        });

        // Retorna o resultado final do sorteio!
        res.status(200).json({
            mensagem: 'Sorteio realizado com sucesso!',
            total_participantes: escolas.length,
            resultado: grupos
        });

    } catch (erro) {
        console.error(erro);
        res.status(500).json({ erro: 'Erro ao processar o sorteio.' });
    }
});

// Rota para Salvar o Sorteio Aprovado Manualmente (Item 3)
app.post('/api/sorteio/salvar', verificarToken, async (req, res) => {
    const { modalidade_id, categoria_id, resultado } = req.body;

    try {
        for (const nomeGrupo of Object.keys(resultado)) {
            // 1. Cria o Grupo na tabela 'grupos'
            const [insertGrupo] = await db.query(
                'INSERT INTO grupos (nome, modalidade_id, categoria_id) VALUES (?, ?, ?)',
                [nomeGrupo, modalidade_id, categoria_id]
            );
            
            const grupo_id = insertGrupo.insertId;
            const escolasDoGrupo = resultado[nomeGrupo];

            // 2. Pega as escolas que caíram nesse grupo e salva o vínculo na 'grupos_escolas'
            for (const escola of escolasDoGrupo) {
                await db.query(
                    'INSERT INTO grupos_escolas (grupo_id, escola_id) VALUES (?, ?)',
                    [grupo_id, escola.id]
                );
            }
        }

        res.status(201).json({ mensagem: 'Sorteio aprovado e salvo no banco com sucesso!' });

    } catch (erro) {
        console.error(erro);
        res.status(500).json({ erro: 'Erro ao salvar o sorteio no banco de dados.' });
    }
});


app.listen(PORT, () => {
    console.log(`Servidor rodando na porta ${PORT}`);
});
