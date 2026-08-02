from contextlib import contextmanager

from sqlalchemy import func, extract, text, case
from sqlalchemy.orm import joinedload, contains_eager, aliased
from sqlalchemy.orm.exc import StaleDataError
from sqlalchemy.orm.attributes import flag_modified
import json

from models import (
    SessionLocal,
    Pessoa, Paciente, Profissional, Preceptor, Residente,
    Unidade, Procedimento, Atendimento, ProcedimentoRealizado, Escala,
    VwPacientesInternados, VwResidentesSemSupervisor, VwEstatisticasAtendimentosMensal
)


@contextmanager
def get_session():
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()


# pacientes

def listar_pacientes(busca=""):
    with get_session() as s:
        rows = (
            s.query(Paciente)
            .join(Paciente.pessoa)
            .options(contains_eager(Paciente.pessoa))  # reaproveita o JOIN
            .filter(Pessoa.nome.ilike(f"%{busca}%"))
            .order_by(Pessoa.nome)
            .all()
        )
        return [
            {
                "id_pessoa": p.id_pessoa,
                "nome": p.pessoa.nome,
                "cpf": p.pessoa.cpf,
                "telefone": p.pessoa.telefone,
                "num_convenio": p.num_convenio,
                "grupo_sanguineo": p.grupo_sanguineo,
                "alergias": p.alergias,
            }
            for p in rows
        ]


def atualizar_paciente(id_pessoa, num_convenio, telefone):
    with get_session() as s:
        pac = s.get(Paciente, id_pessoa)
        if not pac:
            return
        pac.num_convenio = num_convenio
        # navega o relationship para atualizar a tabela pessoa
        pac.pessoa.telefone = telefone
        s.commit()





# atendimentos

def listar_atendimentos_paciente(id_paciente):
    with get_session() as s:
        # eager loading: joinedload carrega toda a cadeia residente->profissional->pessoa
        # em uma unica query, evitando N+1 selects
        rows = (
            s.query(Atendimento)
            .options(
                joinedload(Atendimento.residente)
                    .joinedload(Residente.profissional)
                    .joinedload(Profissional.pessoa),
                joinedload(Atendimento.preceptor)
                    .joinedload(Preceptor.profissional)
                    .joinedload(Profissional.pessoa),
            )
            .filter(Atendimento.id_paciente == id_paciente)
            .order_by(Atendimento.data_hora.desc())
            .all()
        )
        return [
            {
                "id_atendimento": a.id_atendimento,
                "data_hora": a.data_hora,
                "duracao_minutos": a.duracao_minutos,
                "residente": a.residente.profissional.pessoa.nome,
                "preceptor": a.preceptor.profissional.pessoa.nome,
            }
            for a in rows
        ]


def listar_procedimentos_atendimento(id_atendimento):
    with get_session() as s:
        rows = (
            s.query(
                ProcedimentoRealizado.id_procedimento,
                Procedimento.nome.label("procedimento"),
                ProcedimentoRealizado.quantidade,
                ProcedimentoRealizado.tempo_real_minutos,
                ProcedimentoRealizado.observacao,
                ProcedimentoRealizado.tem_faturamento,
            )
            .join(Procedimento)
            .filter(ProcedimentoRealizado.id_atendimento == id_atendimento)
            .order_by(Procedimento.nome)
            .all()
        )
        return [r._asdict() for r in rows]


def listar_residentes():
    with get_session() as s:
        rows = (
            s.query(
                Residente.id_profissional,
                Pessoa.nome,
            )
            .join(Pessoa, Residente.id_profissional == Pessoa.id_pessoa)
            .order_by(Pessoa.nome)
            .all()
        )
        return [r._asdict() for r in rows]


def listar_preceptores():
    with get_session() as s:
        rows = (
            s.query(
                Preceptor.id_profissional,
                Pessoa.nome,
            )
            .join(Pessoa, Preceptor.id_profissional == Pessoa.id_pessoa)
            .order_by(Pessoa.nome)
            .all()
        )
        return [r._asdict() for r in rows]


def listar_unidades():
    with get_session() as s:
        rows = s.query(Unidade).order_by(Unidade.nome).all()
        return [{"id_unidade": u.id_unidade, "nome": u.nome} for u in rows]


def listar_procedimentos():
    with get_session() as s:
        rows = s.query(Procedimento).order_by(Procedimento.nome).all()
        return [{"id_procedimento": p.id_procedimento, "nome": p.nome, "codigo": p.codigo, "risco": p.nivel_risco} for p in rows]


def inserir_atendimento_completo(data_hora, duracao_minutos, id_paciente, id_residente, id_preceptor, id_unidade, procedimentos):
    with get_session() as s:
        try:
            proc_json = json.dumps(procedimentos)
            result = s.execute(
                text("""
                CALL sp_registrar_atendimento_completo(
                    :dh, :dur, :pac, :res, :pre, :uni, :procs::jsonb, NULL
                )
                """),
                {
                    "dh": data_hora, "dur": duracao_minutos, "pac": id_paciente,
                    "res": id_residente, "pre": id_preceptor, "uni": id_unidade,
                    "procs": proc_json
                }
            )
            row = result.fetchone()
            s.commit()
            return row[0] if row else None
        except Exception as e:
            s.rollback()
            print("Erro ao registrar atendimento completo:", e)
            return None


def remover_procedimento_realizado(id_atendimento, id_procedimento):
    with get_session() as s:
        pr = s.get(ProcedimentoRealizado, (id_atendimento, id_procedimento))
        if pr and not pr.tem_faturamento:
            s.delete(pr)
            s.commit()
            return 1
        return 0


def tempo_medio_por_residente():
    with get_session() as s:
        media = func.round(func.avg(Atendimento.duracao_minutos), 1)
        rows = (
            s.query(
                Residente.id_profissional.label("id_residente"),
                Pessoa.nome.label("residente"),
                func.count(Atendimento.id_atendimento).label("total_atendimentos"),
                media.label("media_duracao_min"),
            )
            .join(Pessoa, Residente.id_profissional == Pessoa.id_pessoa)
            .outerjoin(Atendimento, Atendimento.id_residente == Residente.id_profissional)
            .group_by(Residente.id_profissional, Pessoa.nome)
            .order_by(media.desc().nulls_last())
            .all()
        )
        return [r._asdict() for r in rows]


# relatorios

def ranking_residentes():
    with get_session() as s:
        total = func.count(Atendimento.id_atendimento).label("total_atendimentos")
        rows = (
            s.query(Pessoa.nome.label("nome_residente"), total)
            .select_from(Residente)
            .join(Pessoa, Residente.id_profissional == Pessoa.id_pessoa)
            .outerjoin(Atendimento, Residente.id_profissional == Atendimento.id_residente)
            .group_by(Residente.id_profissional, Pessoa.nome)
            .order_by(total.desc(), Pessoa.nome)
            .all()
        )
        return [r._asdict() for r in rows]


def preceptores_mais_de_n_atendimentos(mes, ano, minimo=5):
    with get_session() as s:
        total = func.count(Atendimento.id_atendimento).label("total_atendimentos")
        rows = (
            s.query(Pessoa.nome.label("nome_preceptor"), total)
            .select_from(Preceptor)
            .join(Pessoa, Preceptor.id_profissional == Pessoa.id_pessoa)
            .join(Atendimento, Preceptor.id_profissional == Atendimento.id_preceptor)
            .filter(
                extract("month", Atendimento.data_hora) == mes,
                extract("year", Atendimento.data_hora) == ano,
            )
            .group_by(Preceptor.id_profissional, Pessoa.nome)
            .having(total > minimo)
            .all()
        )
        return [r._asdict() for r in rows]


def plantoes_por_residente_unidade():
    with get_session() as s:
        rows = (
            s.query(
                Unidade.nome.label("nome_unidade"),
                Pessoa.nome.label("nome_residente"),
                func.count(Escala.id_escala).label("quantidade_plantoes"),
            )
            .select_from(Unidade)
            .join(Escala, Unidade.id_unidade == Escala.id_unidade)
            .join(Residente, Escala.id_residente == Residente.id_profissional)
            .join(Pessoa, Residente.id_profissional == Pessoa.id_pessoa)
            .group_by(Unidade.id_unidade, Unidade.nome, Residente.id_profissional, Pessoa.nome)
            .order_by(Unidade.nome, Pessoa.nome)
            .all()
        )
        return [r._asdict() for r in rows]


def pacientes_sem_procedimento_alto():
    with get_session() as s:
        # subquery: pacientes que possuem procedimento de risco ALTO
        pacientes_com_alto = (
            s.query(Atendimento.id_paciente)
            .join(ProcedimentoRealizado)
            .join(Procedimento)
            .filter(Procedimento.nivel_risco == "ALTO")
            .distinct()
            .subquery()
        )
        rows = (
            s.query(Pessoa.nome.label("nome_paciente"), Paciente.num_convenio)
            .select_from(Paciente)
            .join(Pessoa, Paciente.id_pessoa == Pessoa.id_pessoa)
            .filter(Paciente.id_pessoa.notin_(
                s.query(pacientes_com_alto.c.id_paciente)
            ))
            .order_by(Pessoa.nome)
            .all()
        )
        return [r._asdict() for r in rows]

# ==========================================
# ETAPA 2: Views e Stored Procedures
# ==========================================

def listar_pacientes_internados():
    with get_session() as s:
        rows = s.query(VwPacientesInternados).order_by(VwPacientesInternados.nome_paciente).all()
        return [{k: v for k, v in r.__dict__.items() if k != "_sa_instance_state"} for r in rows]

def listar_residentes_sem_supervisor():
    with get_session() as s:
        rows = s.query(VwResidentesSemSupervisor).order_by(VwResidentesSemSupervisor.nome_residente).all()
        return [{k: v for k, v in r.__dict__.items() if k != "_sa_instance_state"} for r in rows]

def listar_estatisticas_mensais():
    with get_session() as s:
        rows = s.query(VwEstatisticasAtendimentosMensal).order_by(
            VwEstatisticasAtendimentosMensal.ano_mes.desc(),
            VwEstatisticasAtendimentosMensal.nome_unidade
        ).all()
        return [{k: v for k, v in r.__dict__.items() if k != "_sa_instance_state"} for r in rows]

def calcular_tempo_medio_espera():
    with get_session() as s:
        result = s.execute(text("SELECT * FROM sp_calcular_tempo_medio_espera()"))
        return [dict(row._mapping) for row in result]

def reajustar_escala(id_residente, dia_orig, turno_orig, dia_dest, turno_dest):
    with get_session() as s:
        try:
            result = s.execute(
                text("CALL sp_reajustar_escala(:res, :do, :to, :dd, :td, NULL)"),
                {"res": id_residente, "do": dia_orig, "to": turno_orig, "dd": dia_dest, "td": turno_dest}
            )
            row = result.fetchone()
            s.commit()
            return row[0] if row else 0
        except Exception as e:
            s.rollback()
            raise e


# ==========================================
# ETAPA 2 - Item 5: Consultas avancadas com ORM
# ==========================================

def preceptores_de_pacientes_flamenguistas():
    with get_session() as s:
        pessoa_paciente = aliased(Pessoa)
        rows = (
            s.query(Pessoa.nome.label("nome_preceptor"))
            .select_from(Preceptor)
            .join(Pessoa, Preceptor.id_profissional == Pessoa.id_pessoa)
            .join(Atendimento, Atendimento.id_preceptor == Preceptor.id_profissional)
            .join(Paciente, Atendimento.id_paciente == Paciente.id_pessoa)
            .join(pessoa_paciente, Paciente.id_pessoa == pessoa_paciente.id_pessoa)
            .filter(pessoa_paciente.is_flamengo.is_(True))
            .distinct()
            .order_by(Pessoa.nome)
            .all()
        )
        return [r._asdict() for r in rows]


def ultimo_atendimento_por_paciente():
    with get_session() as s:
        ultimo = (
            s.query(
                Atendimento.id_paciente,
                func.max(Atendimento.data_hora).label("ultima_data"),
            )
            .group_by(Atendimento.id_paciente)
            .subquery()
        )
        rows = (
            s.query(Atendimento)
            .join(
                ultimo,
                (Atendimento.id_paciente == ultimo.c.id_paciente)
                & (Atendimento.data_hora == ultimo.c.ultima_data),
            )
            .options(
                joinedload(Atendimento.paciente).joinedload(Paciente.pessoa),
                joinedload(Atendimento.residente).joinedload(Residente.profissional).joinedload(Profissional.pessoa),
                joinedload(Atendimento.preceptor).joinedload(Preceptor.profissional).joinedload(Profissional.pessoa),
                joinedload(Atendimento.procedimentos_realizados).joinedload(ProcedimentoRealizado.procedimento),
            )
            .all()
        )
        resultado = [
            {
                "paciente": a.paciente.pessoa.nome,
                "data_hora": a.data_hora,
                "residente": a.residente.profissional.pessoa.nome,
                "preceptor": a.preceptor.profissional.pessoa.nome,
                "procedimentos": ", ".join(pr.procedimento.nome for pr in a.procedimentos_realizados) or "-",
            }
            for a in rows
        ]
        resultado.sort(key=lambda r: r["paciente"])
        return resultado


def percentual_alto_risco_por_residente():
    with get_session() as s:
        total = func.count(ProcedimentoRealizado.id_procedimento).label("total")
        total_alto = func.sum(case((Procedimento.nivel_risco == "ALTO", 1), else_=0)).label("total_alto")
        rows = (
            s.query(Pessoa.nome.label("residente"), total, total_alto)
            .select_from(Residente)
            .join(Pessoa, Residente.id_profissional == Pessoa.id_pessoa)
            .join(Atendimento, Atendimento.id_residente == Residente.id_profissional)
            .join(ProcedimentoRealizado, ProcedimentoRealizado.id_atendimento == Atendimento.id_atendimento)
            .join(Procedimento, Procedimento.id_procedimento == ProcedimentoRealizado.id_procedimento)
            .group_by(Residente.id_profissional, Pessoa.nome)
            .order_by(Pessoa.nome)
            .all()
        )
        return [
            {
                "residente": r.residente,
                "total_procedimentos": r.total,
                "percentual_alto_risco": round((r.total_alto / r.total) * 100, 1) if r.total else 0.0,
            }
            for r in rows
        ]


# ==========================================
# ETAPA 2 - Item 6: Concorrencia e transacoes (lock otimista)
# ==========================================

def simular_concorrencia_escala(id_escala, turno_a, turno_b):
    """Abre duas sessoes independentes sobre a MESMA linha de escala, simulando
    duas pessoas editando a escala ao mesmo tempo. A primeira a comitar vence;
    a segunda, que leu a versao antiga, e rejeitada pelo lock otimista."""
    logs = []
    sessao_a = SessionLocal()
    sessao_b = SessionLocal()
    try:
        escala_a = sessao_a.get(Escala, id_escala)
        escala_b = sessao_b.get(Escala, id_escala)
        logs.append(f"Transacao A e B leram a escala #{id_escala} (versao {escala_a.version_id}).")
        print(logs[-1])

        escala_a.turno = turno_a
        # forca o UPDATE mesmo se turno_a repetir o valor atual, senao o
        # SQLAlchemy nao detecta mudanca, pula o UPDATE e a versao nao avanca
        # (o que anularia o conflito que estamos tentando demonstrar)
        flag_modified(escala_a, "turno")
        sessao_a.commit()
        logs.append(f"Transacao A mudou o turno para '{turno_a}' e comitou (nova versao {escala_a.version_id}).")
        print(logs[-1])

        escala_b.turno = turno_b
        flag_modified(escala_b, "turno")
        try:
            sessao_b.commit()
            logs.append(f"Transacao B mudou o turno para '{turno_b}' e comitou (nenhum conflito detectado).")
            print(logs[-1])
        except StaleDataError:
            sessao_b.rollback()
            logs.append(
                "Transacao B tentou comitar com a versao antiga e foi REJEITADA "
                "(StaleDataError - conflito detectado pelo lock otimista)."
            )
            print(logs[-1])
    finally:
        sessao_a.close()
        sessao_b.close()
    return logs
