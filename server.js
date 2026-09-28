// Carrega o .env antes de qualquer checagem de variável de ambiente.
// Antes isso vinha de carona no require do db.js, que saiu daqui na limpeza.
require('dotenv').config();

const express = require('express');
const cors = require('cors');

const app = express();

// O Render entrega a requisição por trás de um proxy: sem isto, o rate limit do
// login enxergaria o IP do proxy e contaria todo mundo como um visitante só.
app.set('trust proxy', 1);

// A nuvem (Render/Railway) injeta a porta e derruba o serviço se ele não a usar
const PORT = process.env.PORT || 3000;

// Sem o segredo do JWT o login quebra em tempo de execução com erro obscuro,
// então a falha acontece aqui, na subida, com mensagem clara.
if (!process.env.JWT_SECRET) {
    throw new Error('JWT_SECRET não definido. Configure essa variável de ambiente antes de iniciar o servidor.');
}

// Em produção, só o domínio do frontend pode consumir a API.
// Aceita vários domínios separados por vírgula (ex: preview + produção da Vercel).
const origensPermitidas = (process.env.CORS_ORIGIN || '')
    .split(',')
    .map((origem) => origem.trim())
    .filter(Boolean);

app.use(cors({
    origin: origensPermitidas.length > 0 ? origensPermitidas : true
}));
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
const sumulaRoutes = require('./src/routes/sumulaRoutes');
const mataMataRoutes = require('./src/routes/mataMataRoutes');
const classificacaoRoutes = require('./src/routes/classificacaoRoutes');
const atletaRoutes = require('./src/routes/atletaRoutes');
const artilhariaRoutes = require('./src/routes/artilhariaRoutes');
const dashboardRoutes = require('./src/routes/dashboardRoutes');
const authRoutes = require('./src/routes/authRoutes');
const grupoRoutes = require('./src/routes/grupoRoutes');
const campeonatoRoutes = require('./src/routes/campeonatoRoutes');
const usuarioRoutes = require('./src/routes/usuarioRoutes');
const modalidadeRoutes = require('./src/routes/modalidadeRoutes');
const competicaoRoutes = require('./src/routes/competicaoRoutes');
const localRoutes = require('./src/routes/localRoutes');
const etapaEnsinoRoutes = require('./src/routes/etapaEnsinoRoutes');
const inscricaoRoutes = require('./src/routes/inscricaoRoutes');

app.use('/api/sumulas', sumulaRoutes);
app.use('/api/matamata', mataMataRoutes);
app.use('/api/classificacao', classificacaoRoutes);
app.use('/api/artilharia', artilhariaRoutes);
app.use('/api/dashboard', dashboardRoutes);
app.use('/api/grupos', grupoRoutes);
app.use('/api/campeonato', campeonatoRoutes);
app.use('/api', authRoutes);
app.use('/api/usuarios', usuarioRoutes);

app.use('/api/escolas', escolaRoutes);
app.use('/api/jogos', jogoRoutes); // <-- Linha nova
app.use('/api/atletas', atletaRoutes);
app.use('/api/locais', localRoutes);
app.use('/api/etapas-ensino', etapaEnsinoRoutes);
app.use('/api/inscricoes', inscricaoRoutes);
app.use('/api/modalidades', modalidadeRoutes);
app.use('/api/competicoes', competicaoRoutes);

app.get('/', (req, res) => {
    res.json({ mensagem: "API dos Jogos Estudantis rodando com sucesso!" });
});

app.listen(PORT, () => {
    console.log(`Servidor rodando na porta ${PORT}`);
});
