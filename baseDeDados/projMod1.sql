-- criando o banco de dados
CREATE DATABASE projMod1

-- criando tabela principal
CREATE TABLE IF NOT EXISTS dados_desenrola (
	id SERIAL PRIMARY KEY,
	data_base INTEGER,
	tipo_desenrola INTEGER,
	unidade_federacao VARCHAR,
	cod_conglomerado_financeiro INTEGER,
	nome_conglomerado_financeiro VARCHAR,
	numero_operacoes INTEGER,
	volume_operacoes NUMERIC(18,2)
)

-- visualizando tabela
SELECT
	tipo_desenrola,
	unidade_federacao,
	data_base,
	nome_conglomerado_financeiro,
	numero_operacoes,
	volume_operacoes
FROM public.dados_desenrola
WHERE data_base = '202501' AND unidade_federacao = 'AC'
ORDER BY volume_operacoes DESC

-- criando schema data warehouse
CREATE SCHEMA data_warehouse

-- criando dimensão estado
CREATE TABLE data_warehouse.dim_estado (
	id_estado SERIAL PRIMARY KEY,
	uf VARCHAR NOT NULL
)

-- adicionando dados na dimensão estado
SELECT * FROM data_warehouse.dim_estado 

INSERT INTO data_warehouse.dim_estado(uf)
SELECT DISTINCT unidade_federacao FROM public.dados_desenrola
ORDER BY unidade_federacao

-- criando dimensão tipo desenrola
CREATE TABLE data_warehouse.dim_tipo_desenrola (
	id_tipo_desenrola SERIAL PRIMARY KEY,
	tipo VARCHAR NOT NULL,
	descricao VARCHAR
)

-- adicionando dados na dimensão tipo desenrola
SELECT * FROM data_warehouse.dim_tipo_desenrola

INSERT INTO data_warehouse.dim_tipo_desenrola(tipo)
SELECT DISTINCT tipo_desenrola FROM public.dados_desenrola
ORDER BY tipo_desenrola

-- criando dimensão conglomerado
CREATE TABLE data_warehouse.dim_conglomerado (
	id_conglomerado SERIAL PRIMARY KEY,
	codigo INTEGER,
	nome VARCHAR
)

-- adicionando dados na dimensão conglomerado
SELECT * FROM data_warehouse.dim_conglomerado
ORDER BY nome

INSERT INTO data_warehouse.dim_conglomerado(codigo, nome)
SELECT DISTINCT cod_conglomerado_financeiro, nome_conglomerado_financeiro FROM public.dados_desenrola

-- criando a tabela fato
CREATE TABLE data_warehouse.fato_operacoes (
	id_operacao SERIAL PRIMARY KEY,
	id_estado INTEGER NOT NULL,
	id_tipo_desenrola INTEGER NOT NULL,
	id_conglomerado INTEGER NOT NULL,
	data_base INTEGER,
	numero_operacoes INTEGER,
	volume_operacoes NUMERIC(18,2),

	CONSTRAINT fk_estado FOREIGN KEY (id_estado) REFERENCES data_warehouse.dim_estado(id_estado),
	CONSTRAINT fk_tipo_desenrola FOREIGN KEY (id_tipo_desenrola) REFERENCES data_warehouse.dim_tipo_desenrola(id_tipo_desenrola),
	CONSTRAINT fk_conglomerado FOREIGN KEY (id_conglomerado) REFERENCES data_warehouse.dim_conglomerado(id_conglomerado)
)

-- inserindo dados na tabela fato
INSERT INTO data_warehouse.fato_operacoes(id_estado, id_tipo_desenrola, id_conglomerado, data_base, numero_operacoes, volume_operacoes)
SELECT
	de.id_estado,
	td.id_tipo_desenrola,
	cg.id_conglomerado,
	data_base,
	numero_operacoes,
	volume_operacoes
FROM public.dados_desenrola dd
INNER JOIN data_warehouse.dim_estado de
	ON de.uf = dd.unidade_federacao
INNER JOIN data_warehouse.dim_tipo_desenrola td
	ON td.id_tipo_desenrola = dd.tipo_desenrola
INNER JOIN data_warehouse.dim_conglomerado cg
	ON cg.nome = dd.nome_conglomerado_financeiro

-- verificando tabela fato
SELECT * 
FROM data_warehouse.fato_operacoes
WHERE data_base = '202501' AND id_estado = 1
ORDER BY volume_operacoes

WITH operacoes_concluidas AS (
	SELECT
		id_operacao,
		de.uf AS estado,
		td.tipo AS tipo,
		cg.nome AS instituicao,
		data_base,
		numero_operacoes,
		volume_operacoes
	FROM data_warehouse.fato_operacoes fo
	INNER JOIN data_warehouse.dim_estado de
		ON fo.id_estado = de.id_estado
	INNER JOIN data_warehouse.dim_tipo_desenrola td
		ON fo.id_tipo_desenrola = td.id_tipo_desenrola
	INNER JOIN data_warehouse.dim_conglomerado cg
		ON fo.id_conglomerado = cg.id_conglomerado
)
SELECT *
FROM operacoes_concluidas
WHERE data_base = '202501' AND estado = 'AC'

ORDER BY volume_operacoes DESC

----------------------------------
-- Volume Financeiro Total: Soma de todas as operações
SELECT
	SUM(volume_operacoes)::MONEY AS total_movimentado
FROM data_warehouse.fato_operacoes
-- Número Total de Operações: Contagem de operações realizadas
SELECT
	SUM(numero_operacoes) AS total_operacoes
FROM data_warehouse.fato_operacoes
-- Ticket Médio: Volume total dividido pelo número de operações
WITH tabela_total AS (
	SELECT
		SUM(numero_operacoes) AS total_operacoes,
		SUM(volume_operacoes)::MONEY AS total_movimentado
	FROM data_warehouse.fato_operacoes
)
SELECT
	total_movimentado / total_operacoes AS ticket_medio
FROM tabela_total
-- Crescimento Mensal/Anual: Variação percentual do volume entre períodos
WITH ano_agrupado AS (
  SELECT
    SUBSTRING(data_base::text, 1, 4)::int AS ano,
    SUM(volume_operacoes)::numeric(18,2) AS total_movimentado
  FROM data_warehouse.fato_operacoes
  GROUP BY 1
),
comparacao AS (
  SELECT
    ano,
    total_movimentado,
    LAG(total_movimentado) OVER (ORDER BY ano) AS mov_ant
  FROM ano_agrupado
)
SELECT
  ano,
  total_movimentado,
  CASE
  	WHEN mov_ant IS NULL THEN 0
	ELSE mov_ant
	END AS movimentado_ano_anterior,
  CASE
	WHEN mov_ant <> 0 THEN ROUND(((total_movimentado - mov_ant) / NULLIF(mov_ant, 0)) * 100, 2)
	ELSE 0
	END	AS variacao_percentual
FROM comparacao
ORDER BY ano;

-- Concentração de Mercado: Participação dos top 5 conglomerados no volume total
SELECT
	cgl.nome AS conglomerado,
	SUM(volume_operacoes)::MONEY AS total_operacoes
FROM data_warehouse.fato_operacoes fo
INNER JOIN data_warehouse.dim_conglomerado cgl
	ON fo.id_conglomerado = cgl.id_conglomerado
GROUP BY conglomerado
ORDER BY total_operacoes DESC
LIMIT 5
-- Distribuição Geográfica: volume por região/estado
SELECT
	de.uf AS estado,
	SUM(volume_operacoes)::MONEY AS total_estado
FROM data_warehouse.fato_operacoes fo
INNER JOIN data_warehouse.dim_estado de
	ON fo.id_estado = de.id_estado
GROUP BY estado
ORDER BY total_estado DESC
LIMIT 5
-- Mix de Produtos: Distribuição por tipo de operação
SELECT
	dtd.tipo AS tipo,
	SUM(volume_operacoes)::MONEY AS total_tipo
FROM data_warehouse.fato_operacoes fo
INNER JOIN data_warehouse.dim_tipo_desenrola dtd
	ON fo.id_tipo_desenrola = dtd.id_tipo_desenrola
GROUP BY tipo
ORDER BY total_tipo

-- colocando dados na tabela tipo desenrola descricao
SELECT * FROM data_warehouse.dim_tipo_desenrola
ORDER BY tipo

UPDATE data_warehouse.dim_tipo_desenrola
SET descricao = 'O Desenrola Brasil Faixa 1 destinava-se a pessoas com renda mensal de até dois salários mínimos ou inscritas no CadÚnico, com dívidas de até R$ 5 mil, negativadas entre 2019 e 2022.'
WHERE tipo = '1'

UPDATE data_warehouse.dim_tipo_desenrola
SET descricao = 'Destinado a renegociar dívidas bancárias de pessoas com renda mensal de até R$ 20 mil.'
WHERE tipo = '2'

UPDATE data_warehouse.dim_tipo_desenrola
SET descricao = 'Refere-se à renegociação de dívidas de pessoas físicas e MEIs/ME/EPP com empresas de setores como comércio, telecomunicações, educação e serviços financeiros, e foi lançado com a abertura da plataforma digital em outubro de 2023 para dívidas negativadas entre 2019 e 2022.'
WHERE tipo = '3'
