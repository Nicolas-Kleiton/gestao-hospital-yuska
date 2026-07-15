-- Sistema de Gestao Hospitalar Dra. Yuska Maritan Brito
-- Etapa 1 - criacao das tabelas

DROP TABLE IF EXISTS escala CASCADE;
DROP TABLE IF EXISTS procedimento_realizado CASCADE;
DROP TABLE IF EXISTS atendimento CASCADE;
DROP TABLE IF EXISTS procedimento CASCADE;
DROP TABLE IF EXISTS unidade CASCADE;
DROP TABLE IF EXISTS residente CASCADE;
DROP TABLE IF EXISTS preceptor CASCADE;
DROP TABLE IF EXISTS profissional CASCADE;
DROP TABLE IF EXISTS paciente CASCADE;
DROP TABLE IF EXISTS pessoa CASCADE;


CREATE TABLE pessoa (
    id_pessoa INT PRIMARY KEY,
    nome VARCHAR(150) NOT NULL,
    cpf VARCHAR(11) NOT NULL UNIQUE,
    data_nascimento DATE NOT NULL,
    is_flamengo BOOLEAN NOT NULL,
    telefone VARCHAR(15)
);

-- paciente e profissional sao especializacoes de pessoa,
-- por isso herdam o id_pessoa como pk e fk ao mesmo tempo
CREATE TABLE paciente (
    id_pessoa INT PRIMARY KEY REFERENCES pessoa(id_pessoa) ON DELETE CASCADE,
    num_convenio VARCHAR(50),
    alergias TEXT,
    grupo_sanguineo VARCHAR(3) CHECK (grupo_sanguineo IN ('A+','A-','B+','B-','AB+','AB-','O+','O-'))
);

CREATE TABLE profissional (
    id_pessoa INT PRIMARY KEY REFERENCES pessoa(id_pessoa) ON DELETE CASCADE,
    crm VARCHAR(20) NOT NULL UNIQUE,
    data_admissao DATE NOT NULL,
    especialidade VARCHAR(100)
);

CREATE TABLE preceptor (
    id_profissional INT PRIMARY KEY REFERENCES profissional(id_pessoa) ON DELETE CASCADE,
    titulacao VARCHAR(50) NOT NULL
);

CREATE TABLE residente (
    id_profissional INT PRIMARY KEY REFERENCES profissional(id_pessoa) ON DELETE CASCADE,
    ano_residencia VARCHAR(2) NOT NULL CHECK (ano_residencia IN ('R1','R2','R3'))
);

CREATE TABLE unidade (
    id_unidade INT PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    tipo VARCHAR(50) NOT NULL CHECK (tipo IN ('Enfermaria','UTI','Pronto-Socorro','Ambulatorio')),
    capacidade_leitos INT CHECK (capacidade_leitos >= 0)
);

CREATE TABLE procedimento (
    id_procedimento INT PRIMARY KEY,
    codigo VARCHAR(20) NOT NULL UNIQUE,
    nome VARCHAR(100) NOT NULL,
    tempo_medio_minutos INT,
    nivel_risco VARCHAR(10) NOT NULL CHECK (nivel_risco IN ('BAIXO','MEDIO','ALTO'))
);

CREATE TABLE atendimento (
    id_atendimento INT PRIMARY KEY,
    data_hora TIMESTAMP NOT NULL,
    duracao_minutos INT CHECK (duracao_minutos > 0),
    id_paciente INT NOT NULL REFERENCES paciente(id_pessoa),
    id_residente INT NOT NULL REFERENCES residente(id_profissional),
    id_preceptor INT NOT NULL REFERENCES preceptor(id_profissional)
);

-- tabela que liga atendimento e procedimento (N pra N)
CREATE TABLE procedimento_realizado (
    id_atendimento INT NOT NULL REFERENCES atendimento(id_atendimento) ON DELETE CASCADE,
    id_procedimento INT NOT NULL REFERENCES procedimento(id_procedimento),
    quantidade INT NOT NULL CHECK (quantidade > 0),
    tempo_real_minutos INT,
    observacao TEXT,
    tem_faturamento BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (id_atendimento, id_procedimento)
);

CREATE TABLE escala (
    id_escala INT PRIMARY KEY,
    dia_semana VARCHAR(15) NOT NULL CHECK (dia_semana IN ('Segunda','Terca','Quarta','Quinta','Sexta','Sabado','Domingo')),
    turno VARCHAR(10) NOT NULL CHECK (turno IN ('Manha','Tarde','Noite')),
    id_unidade INT NOT NULL REFERENCES unidade(id_unidade),
    id_residente INT NOT NULL REFERENCES residente(id_profissional),
    id_preceptor INT NOT NULL REFERENCES preceptor(id_profissional),
    -- nao pode o mesmo residente no mesmo local/dia/turno com dois preceptores
    UNIQUE (id_unidade, dia_semana, turno, id_residente)
);
