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