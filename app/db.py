import os
import psycopg2
import psycopg2.extras
import streamlit as st

DB_CONFIG = {
    "host": os.environ.get("DB_HOST", "localhost"),
    "port": os.environ.get("DB_PORT", "5432"),
    "dbname": os.environ.get("DB_NAME", "hospital_yuska"),
    "user": os.environ.get("DB_USER", "postgres"),
    "password": os.environ.get("DB_PASSWORD", "1234"),
}


@st.cache_resource
def get_connection():
    conn = psycopg2.connect(**DB_CONFIG)
    conn.autocommit = True
    return conn


def query(sql, params=None):
    conn = get_connection()
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql, params or ())
        return cur.fetchall()


def execute(sql, params=None):
    conn = get_connection()
    with conn.cursor() as cur:
        cur.execute(sql, params or ())
        return cur.rowcount


# ---- pacientes ----

def listar_pacientes(busca=""):
    return query(
        """
        SELECT pe.id_pessoa, pe.nome, pe.cpf, pe.telefone,
               pac.num_convenio, pac.grupo_sanguineo, pac.alergias
        FROM paciente pac
        JOIN pessoa pe ON pe.id_pessoa = pac.id_pessoa
        WHERE pe.nome ILIKE %s
        ORDER BY pe.nome
        """,
        (f"%{busca}%",),
    )


def atualizar_paciente(id_pessoa, num_convenio, telefone):
    execute("UPDATE paciente SET num_convenio = %s WHERE id_pessoa = %s", (num_convenio, id_pessoa))
    return execute(
        "UPDATE pessoa SET telefone = %s WHERE id_pessoa = %s AND EXISTS (SELECT 1 FROM paciente WHERE id_pessoa = %s)",
        (telefone, id_pessoa, id_pessoa),
    )


# ---- atendimentos (item 3) ----

def listar_atendimentos_paciente(id_paciente):
    return query(
        """
        SELECT a.id_atendimento, a.data_hora, a.duracao_minutos,
               pe_res.nome AS residente, pe_pre.nome AS preceptor
        FROM atendimento a
        JOIN residente r      ON r.id_profissional = a.id_residente
        JOIN pessoa    pe_res ON pe_res.id_pessoa  = r.id_profissional
        JOIN preceptor p      ON p.id_profissional = a.id_preceptor
        JOIN pessoa    pe_pre ON pe_pre.id_pessoa  = p.id_profissional
        WHERE a.id_paciente = %s
        ORDER BY a.data_hora DESC
        """,
        (id_paciente,),
    )


def listar_procedimentos_atendimento(id_atendimento):
    return query(
        """
        SELECT pr.id_procedimento, proc.nome AS procedimento, pr.quantidade,
               pr.tempo_real_minutos, pr.observacao, pr.tem_faturamento
        FROM procedimento_realizado pr
        JOIN procedimento proc ON proc.id_procedimento = pr.id_procedimento
        WHERE pr.id_atendimento = %s
        ORDER BY proc.nome
        """,
        (id_atendimento,),
    )


def listar_residentes():
    return query(
        """
        SELECT r.id_profissional, pe.nome
        FROM residente r JOIN pessoa pe ON pe.id_pessoa = r.id_profissional
        ORDER BY pe.nome
        """
    )


def listar_preceptores():
    return query(
        """
        SELECT p.id_profissional, pe.nome
        FROM preceptor p JOIN pessoa pe ON pe.id_pessoa = p.id_profissional
        ORDER BY pe.nome
        """
    )


def inserir_atendimento(data_hora, duracao_minutos, id_paciente, id_residente, id_preceptor):
    rows = query(
        """
        INSERT INTO atendimento (id_atendimento, data_hora, duracao_minutos,
                                 id_paciente, id_residente, id_preceptor)
        SELECT (SELECT COALESCE(MAX(id_atendimento), 0) + 1 FROM atendimento),
               %s, %s, %s, %s, %s
        WHERE EXISTS (SELECT 1 FROM paciente  WHERE id_pessoa       = %s)
          AND EXISTS (SELECT 1 FROM residente WHERE id_profissional = %s)
          AND EXISTS (SELECT 1 FROM preceptor WHERE id_profissional = %s)
        RETURNING id_atendimento
        """,
        (data_hora, duracao_minutos, id_paciente, id_residente, id_preceptor,
         id_paciente, id_residente, id_preceptor),
    )
    return rows[0]["id_atendimento"] if rows else None


def remover_procedimento_realizado(id_atendimento, id_procedimento):
    return execute(
        """
        DELETE FROM procedimento_realizado
        WHERE id_atendimento = %s AND id_procedimento = %s AND tem_faturamento = FALSE
        """,
        (id_atendimento, id_procedimento),
    )


def tempo_medio_por_residente():
    return query(
        """
        SELECT r.id_profissional AS id_residente, pe.nome AS residente,
               COUNT(a.id_atendimento) AS total_atendimentos,
               ROUND(AVG(a.duracao_minutos), 1) AS media_duracao_min
        FROM residente r
        JOIN pessoa pe          ON pe.id_pessoa = r.id_profissional
        LEFT JOIN atendimento a ON a.id_residente = r.id_profissional
        GROUP BY r.id_profissional, pe.nome
        ORDER BY media_duracao_min DESC NULLS LAST
        """
    )


# ---- relatorios (item 4) ----

def ranking_residentes():
    return query(
        """
        SELECT pe.nome AS nome_residente, COUNT(a.id_atendimento) AS total_atendimentos
        FROM residente r
        JOIN profissional prof ON r.id_profissional = prof.id_pessoa
        JOIN pessoa pe ON prof.id_pessoa = pe.id_pessoa
        LEFT JOIN atendimento a ON r.id_profissional = a.id_residente
        GROUP BY r.id_profissional, pe.nome
        ORDER BY total_atendimentos DESC, pe.nome
        """
    )


def preceptores_mais_de_n_atendimentos(mes, ano, minimo=5):
    return query(
        """
        SELECT pe.nome AS nome_preceptor, COUNT(a.id_atendimento) AS total_atendimentos
        FROM preceptor prec
        JOIN profissional prof ON prec.id_profissional = prof.id_pessoa
        JOIN pessoa pe ON prof.id_pessoa = pe.id_pessoa
        JOIN atendimento a ON prec.id_profissional = a.id_preceptor
        WHERE EXTRACT(MONTH FROM a.data_hora) = %s
          AND EXTRACT(YEAR FROM a.data_hora) = %s
        GROUP BY prec.id_profissional, pe.nome
        HAVING COUNT(a.id_atendimento) > %s
        """,
        (mes, ano, minimo),
    )


def plantoes_por_residente_unidade():
    return query(
        """
        SELECT u.nome AS nome_unidade, pe.nome AS nome_residente,
               COUNT(e.id_escala) AS quantidade_plantoes
        FROM unidade u
        JOIN escala e ON u.id_unidade = e.id_unidade
        JOIN residente r ON e.id_residente = r.id_profissional
        JOIN pessoa pe ON r.id_profissional = pe.id_pessoa
        GROUP BY u.id_unidade, u.nome, r.id_profissional, pe.nome
        ORDER BY u.nome, pe.nome
        """
    )


def pacientes_sem_procedimento_alto():
    return query(
        """
        SELECT pe.nome AS nome_paciente, pac.num_convenio
        FROM paciente pac
        JOIN pessoa pe ON pac.id_pessoa = pe.id_pessoa
        WHERE NOT EXISTS (
            SELECT 1
            FROM atendimento a
            JOIN procedimento_realizado pr ON a.id_atendimento = pr.id_atendimento
            JOIN procedimento proc ON pr.id_procedimento = proc.id_procedimento
            WHERE a.id_paciente = pac.id_pessoa AND proc.nivel_risco = 'ALTO'
        )
        ORDER BY pe.nome
        """
    )
