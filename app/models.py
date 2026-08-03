import os
import psycopg2

from sqlalchemy import (
    Column, Integer, String, Boolean, Date, DateTime, Numeric, Text,
    ForeignKey, Identity, create_engine,
)
from sqlalchemy.orm import DeclarativeBase, relationship, sessionmaker

# mesma config que funcionava no db.py antigo com psycopg2 direto
DB_CONFIG = {
    "host": os.environ.get("DB_HOST", "localhost"),
    "port": os.environ.get("DB_PORT", "5433"),
    "dbname": os.environ.get("DB_NAME", "hospital_yuska"),
    "user": os.environ.get("DB_USER", "postgres"),
    "password": os.environ.get("DB_PASSWORD", "1234"),
    "client_encoding": "utf8",
}

# creator: passa keyword args ao psycopg2 em vez de montar DSN string
# (evita UnicodeDecodeError em locales nao-ASCII)
engine = create_engine(
    "postgresql+psycopg2://",
    creator=lambda: psycopg2.connect(**DB_CONFIG),
    pool_pre_ping=True,
)
SessionLocal = sessionmaker(bind=engine)


class Base(DeclarativeBase):
    pass


# pessoa -> paciente / profissional -> preceptor / residente
# a PK de cada filho e tambem FK para o pai (especializacao)

class Pessoa(Base):
    __tablename__ = "pessoa"

    id_pessoa = Column(Integer, primary_key=True)
    nome = Column(String(150), nullable=False)
    cpf = Column(String(11), nullable=False, unique=True)
    data_nascimento = Column(Date, nullable=False)
    is_flamengo = Column(Boolean, nullable=False)
    telefone = Column(String(15))

    paciente = relationship("Paciente", back_populates="pessoa", uselist=False)
    profissional = relationship("Profissional", back_populates="pessoa", uselist=False)


class Paciente(Base):
    __tablename__ = "paciente"

    id_pessoa = Column(Integer, ForeignKey("pessoa.id_pessoa", ondelete="CASCADE"), primary_key=True)
    num_convenio = Column(String(50))
    alergias = Column(Text)
    grupo_sanguineo = Column(String(3))

    pessoa = relationship("Pessoa", back_populates="paciente")
    atendimentos = relationship("Atendimento", back_populates="paciente")


class Profissional(Base):
    __tablename__ = "profissional"

    id_pessoa = Column(Integer, ForeignKey("pessoa.id_pessoa", ondelete="CASCADE"), primary_key=True)
    crm = Column(String(20), nullable=False, unique=True)
    data_admissao = Column(Date, nullable=False)
    especialidade = Column(String(100))

    pessoa = relationship("Pessoa", back_populates="profissional")
    preceptor = relationship("Preceptor", back_populates="profissional", uselist=False)
    residente = relationship("Residente", back_populates="profissional", uselist=False)


class Preceptor(Base):
    __tablename__ = "preceptor"

    id_profissional = Column(Integer, ForeignKey("profissional.id_pessoa", ondelete="CASCADE"), primary_key=True)
    titulacao = Column(String(50), nullable=False)

    profissional = relationship("Profissional", back_populates="preceptor")
    atendimentos = relationship("Atendimento", back_populates="preceptor")
    escalas = relationship("Escala", back_populates="preceptor")


class Residente(Base):
    __tablename__ = "residente"

    id_profissional = Column(Integer, ForeignKey("profissional.id_pessoa", ondelete="CASCADE"), primary_key=True)
    ano_residencia = Column(String(2), nullable=False)

    profissional = relationship("Profissional", back_populates="residente")
    atendimentos = relationship("Atendimento", back_populates="residente")
    escalas = relationship("Escala", back_populates="residente")


class Unidade(Base):
    __tablename__ = "unidade"

    id_unidade = Column(Integer, primary_key=True)
    nome = Column(String(100), nullable=False)
    tipo = Column(String(50), nullable=False)
    capacidade_leitos = Column(Integer)

    escalas = relationship("Escala", back_populates="unidade")
    atendimentos = relationship("Atendimento", back_populates="unidade")


class Procedimento(Base):
    __tablename__ = "procedimento"

    id_procedimento = Column(Integer, primary_key=True)
    codigo = Column(String(20), nullable=False, unique=True)
    nome = Column(String(100), nullable=False)
    tempo_medio_minutos = Column(Integer)
    nivel_risco = Column(String(10), nullable=False)
    media_tempo_procedimento = Column(Numeric)  # calculada pela trigger

    procedimentos_realizados = relationship("ProcedimentoRealizado", back_populates="procedimento")


class Atendimento(Base):
    __tablename__ = "atendimento"

    id_atendimento = Column(Integer, Identity(), primary_key=True)
    data_hora = Column(DateTime, nullable=False)
    duracao_minutos = Column(Integer)
    id_paciente = Column(Integer, ForeignKey("paciente.id_pessoa"), nullable=False)
    id_residente = Column(Integer, ForeignKey("residente.id_profissional"), nullable=False)
    id_preceptor = Column(Integer, ForeignKey("preceptor.id_profissional"), nullable=False)
    id_unidade = Column(Integer, ForeignKey("unidade.id_unidade"), nullable=False)
    data_hora_entrada = Column(DateTime)
    data_hora_saida = Column(DateTime)

    paciente = relationship("Paciente", back_populates="atendimentos")
    residente = relationship("Residente", back_populates="atendimentos")
    preceptor = relationship("Preceptor", back_populates="atendimentos")
    unidade = relationship("Unidade", back_populates="atendimentos")
    procedimentos_realizados = relationship(
        "ProcedimentoRealizado", back_populates="atendimento", cascade="all, delete-orphan",
    )


class ProcedimentoRealizado(Base):
    __tablename__ = "procedimento_realizado"

    id_atendimento = Column(Integer, ForeignKey("atendimento.id_atendimento", ondelete="CASCADE"), primary_key=True)
    id_procedimento = Column(Integer, ForeignKey("procedimento.id_procedimento"), primary_key=True)
    quantidade = Column(Integer, nullable=False)
    tempo_real_minutos = Column(Integer)
    data_hora_inicio = Column(DateTime)
    observacao = Column(Text)
    tem_faturamento = Column(Boolean, nullable=False, default=False)

    atendimento = relationship("Atendimento", back_populates="procedimentos_realizados")
    procedimento = relationship("Procedimento", back_populates="procedimentos_realizados")


class Escala(Base):
    __tablename__ = "escala"

    id_escala = Column(Integer, primary_key=True)
    dia_semana = Column(String(15), nullable=False)
    turno = Column(String(10), nullable=False)
    id_unidade = Column(Integer, ForeignKey("unidade.id_unidade"), nullable=False)
    id_residente = Column(Integer, ForeignKey("residente.id_profissional"), nullable=False)
    id_preceptor = Column(Integer, ForeignKey("preceptor.id_profissional"), nullable=False)
    # coluna de controle de versao para o lock otimista (Etapa 2 - Item 6)
    version_id = Column(Integer, nullable=False, default=1)

    unidade = relationship("Unidade", back_populates="escalas")
    residente = relationship("Residente", back_populates="escalas")
    preceptor = relationship("Preceptor", back_populates="escalas")

    __mapper_args__ = {"version_id_col": version_id}

# VIEWS (Etapa 2)

class VwPacientesInternados(Base):
    __tablename__ = "vw_pacientes_internados"
    
    # SQLAlchemy requires a primary key, even for views.
    # We use a composite of existing columns that should be unique enough, or just one column
    # Since nome_paciente + data_hora_entrada is practically unique here:
    nome_paciente = Column(String, primary_key=True)
    num_convenio = Column(String)
    grupo_sanguineo = Column(String)
    alergias = Column(String)
    unidade = Column(String)
    data_hora_entrada = Column(DateTime, primary_key=True)

class VwResidentesSemSupervisor(Base):
    __tablename__ = "vw_residentes_sem_supervisor"

    nome_residente = Column(String, primary_key=True)
    ano_residencia = Column(String)
    especialidade = Column(String)
    nome_preceptor = Column(String, primary_key=True)
    titulacao = Column(String)

class VwEstatisticasAtendimentosMensal(Base):
    __tablename__ = "vw_estatisticas_atendimentos_mensal"

    ano_mes = Column(String, primary_key=True)
    nome_unidade = Column(String, primary_key=True)
    total_atendimentos = Column(Integer)
    media_duracao_minutos = Column(Numeric)
    procedimento_mais_comum = Column(String)

