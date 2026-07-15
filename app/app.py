from datetime import datetime, date, time as dtime

import pandas as pd
import streamlit as st

import db

st.set_page_config(page_title="Gestao Hospitalar - Dra. Yuska Maritan Brito", layout="wide")

st.markdown(
    """
    <style>
    section[data-testid="stSidebar"] {
        background-color: #16332C;
    }
    section[data-testid="stSidebar"] * {
        color: #EDEBE4 !important;
    }
    section[data-testid="stSidebar"] .stRadio label {
        padding: 0.35rem 0.5rem;
        border-radius: 6px;
    }
    .app-title {
        font-size: 1.3rem;
        font-weight: 700;
        letter-spacing: 0.03em;
        margin-bottom: 0;
    }
    .app-subtitle {
        font-size: 0.8rem;
        opacity: 0.75;
        margin-top: 0;
    }
    </style>
    """,
    unsafe_allow_html=True,
)

with st.sidebar:
    st.markdown('<p class="app-title">HU · Dra. Yuska Maritan Brito</p>', unsafe_allow_html=True)
    st.markdown('<p class="app-subtitle">Sistema de Gestao Hospitalar</p>', unsafe_allow_html=True)
    st.markdown("---")
    pagina = st.radio(
        "Navegacao",
        ["Atendimentos", "Pacientes", "Relatorios"],
        label_visibility="collapsed",
    )


def formata_data(dt):
    return dt.strftime("%d/%m/%Y %H:%M") if dt else "-"


# ============================================================
# PAGINA: ATENDIMENTOS  (item 3.1, 3.2, 3.3, 3.5)
# ============================================================
if pagina == "Atendimentos":
    st.title("Atendimentos")
    st.caption("Selecione um paciente para ver o historico e registrar novos atendimentos.")

    pacientes = db.listar_pacientes("")
    if not pacientes:
        st.warning("Nenhum paciente cadastrado.")
        st.stop()

    opcoes = {f"{p['nome']}  ·  conv. {p['num_convenio'] or '—'}": p["id_pessoa"] for p in pacientes}
    escolha = st.selectbox("Paciente", list(opcoes.keys()))
    id_paciente = opcoes[escolha]

    col_esq, col_dir = st.columns([1.1, 1])

    with col_esq:
        st.subheader("Historico de atendimentos")
        atendimentos = db.listar_atendimentos_paciente(id_paciente)
        if atendimentos:
            df = pd.DataFrame(atendimentos)
            df["data_hora"] = df["data_hora"].apply(formata_data)
            df = df.rename(columns={
                "id_atendimento": "ID", "data_hora": "Data/Hora",
                "duracao_minutos": "Duracao (min)", "residente": "Residente", "preceptor": "Preceptor",
            })
            st.dataframe(df, hide_index=True, use_container_width=True)

            id_selecionado = st.selectbox(
                "Ver procedimentos do atendimento",
                [a["id_atendimento"] for a in atendimentos],
            )
        else:
            st.info("Este paciente ainda nao possui atendimentos.")
            id_selecionado = None

    with col_dir:
        st.subheader("Procedimentos realizados")
        if id_selecionado:
            procedimentos = db.listar_procedimentos_atendimento(id_selecionado)
            if procedimentos:
                for proc in procedimentos:
                    with st.container(border=True):
                        c1, c2 = st.columns([3, 1])
                        c1.markdown(f"**{proc['procedimento']}**")
                        c1.caption(
                            f"Qtd: {proc['quantidade']}  ·  Tempo real: {proc['tempo_real_minutos']} min"
                            + (f"  ·  {proc['observacao']}" if proc["observacao"] else "")
                        )
                        if proc["tem_faturamento"]:
                            c2.markdown("🔒 faturado")
                        else:
                            if c2.button("Remover", key=f"rm-{proc['id_procedimento']}"):
                                linhas = db.remover_procedimento_realizado(id_selecionado, proc["id_procedimento"])
                                if linhas:
                                    st.success("Procedimento removido.")
                                    st.rerun()
                                else:
                                    st.error("Nao foi possivel remover (ja faturado).")
            else:
                st.info("Nenhum procedimento registrado para este atendimento.")

    st.markdown("---")
    with st.expander("+ Novo atendimento"):
        residentes = {r["nome"]: r["id_profissional"] for r in db.listar_residentes()}
        preceptores = {p["nome"]: p["id_profissional"] for p in db.listar_preceptores()}

        with st.form("form_novo_atendimento"):
            c1, c2, c3 = st.columns(3)
            f_data = c1.date_input("Data", value=date.today())
            f_hora = c2.time_input("Hora", value=dtime(9, 0))
            f_duracao = c3.number_input("Duracao (min)", min_value=1, value=30)

            c4, c5 = st.columns(2)
            f_residente = c4.selectbox("Residente", list(residentes.keys()))
            f_preceptor = c5.selectbox("Preceptor", list(preceptores.keys()))

            enviado = st.form_submit_button("Registrar atendimento")
            if enviado:
                novo_id = db.inserir_atendimento(
                    datetime.combine(f_data, f_hora),
                    int(f_duracao),
                    id_paciente,
                    residentes[f_residente],
                    preceptores[f_preceptor],
                )
                if novo_id:
                    st.success(f"Atendimento #{novo_id} registrado com sucesso.")
                    st.rerun()
                else:
                    st.error("Nao foi possivel registrar: paciente, residente ou preceptor nao encontrados.")


# ============================================================
# PAGINA: PACIENTES  (item 3.4)
# ============================================================
elif pagina == "Pacientes":
    st.title("Pacientes")
    st.caption("Busque um paciente e atualize convenio ou telefone.")

    busca = st.text_input("Buscar por nome")
    pacientes = db.listar_pacientes(busca)

    if pacientes:
        df = pd.DataFrame(pacientes).rename(columns={
            "nome": "Nome", "cpf": "CPF", "telefone": "Telefone",
            "num_convenio": "Convenio", "grupo_sanguineo": "Grupo sanguineo", "alergias": "Alergias",
        })
        st.dataframe(
            df[["Nome", "CPF", "Convenio", "Grupo sanguineo", "Telefone", "Alergias"]],
            hide_index=True, use_container_width=True,
        )

        st.markdown("---")
        st.subheader("Atualizar dados")
        opcoes = {p["nome"]: p for p in pacientes}
        escolha = st.selectbox("Paciente", list(opcoes.keys()))
        p = opcoes[escolha]

        with st.form("form_atualiza_paciente"):
            c1, c2 = st.columns(2)
            novo_convenio = c1.text_input("Convenio", value=p["num_convenio"] or "")
            novo_telefone = c2.text_input("Telefone", value=p["telefone"] or "")
            if st.form_submit_button("Salvar"):
                db.atualizar_paciente(p["id_pessoa"], novo_convenio, novo_telefone)
                st.success("Dados atualizados.")
                st.rerun()
    else:
        st.info("Nenhum paciente encontrado.")


# ============================================================
# PAGINA: RELATORIOS  (item 4)
# ============================================================
elif pagina == "Relatorios":
    st.title("Relatorios")

    aba_residentes, aba_preceptores, aba_plantoes, aba_pacientes = st.tabs(
        ["Residentes", "Preceptores", "Plantoes", "Pacientes"]
    )

    with aba_residentes:
        st.subheader("Ranking por numero de atendimentos")
        st.dataframe(pd.DataFrame(db.ranking_residentes()), hide_index=True, use_container_width=True)

        st.subheader("Tempo medio de duracao por residente")
        st.dataframe(pd.DataFrame(db.tempo_medio_por_residente()), hide_index=True, use_container_width=True)

    with aba_preceptores:
        st.subheader("Preceptores com mais de 5 atendimentos no mes")
        c1, c2 = st.columns(2)
        mes = c1.number_input("Mes", min_value=1, max_value=12, value=5)
        ano = c2.number_input("Ano", min_value=2000, max_value=2100, value=2025)
        resultado = db.preceptores_mais_de_n_atendimentos(int(mes), int(ano))
        if resultado:
            st.dataframe(pd.DataFrame(resultado), hide_index=True, use_container_width=True)
        else:
            st.info("Nenhum preceptor ultrapassou 5 atendimentos nesse periodo.")

    with aba_plantoes:
        st.subheader("Plantoes escalados por residente e unidade")
        st.dataframe(pd.DataFrame(db.plantoes_por_residente_unidade()), hide_index=True, use_container_width=True)

    with aba_pacientes:
        st.subheader("Pacientes sem nenhum procedimento de risco ALTO")
        st.dataframe(pd.DataFrame(db.pacientes_sem_procedimento_alto()), hide_index=True, use_container_width=True)
