from datetime import datetime, date, time as dtime

import pandas as pd
import streamlit as st

import db

st.set_page_config(
    page_title="Gestão Hospitalar - Dra. Yuska", 
    page_icon="🏥", 
    layout="wide",
    initial_sidebar_state="expanded"
)

st.markdown(
    """
    <style>
    /* Estilos gerais */
    .stApp {
        background-color: #F8F9FA;
    }
    
    /* Sidebar styling */
    section[data-testid="stSidebar"] {
        background-color: #1A3636;
        border-right: 1px solid #112525;
    }
    section[data-testid="stSidebar"] * {
        color: #E2E8F0 !important;
    }
    section[data-testid="stSidebar"] .stRadio label {
        padding: 10px 15px;
        margin-bottom: 5px;
        border-radius: 8px;
        transition: background-color 0.2s ease;
    }
    section[data-testid="stSidebar"] .stRadio label:hover {
        background-color: #2C5252;
    }
    
    /* Tipografia customizada */
    .app-title {
        font-size: 1.5rem;
        font-weight: 800;
        letter-spacing: 0.02em;
        margin-bottom: 0;
        color: #FFFFFF !important;
    }
    .app-subtitle {
        font-size: 0.85rem;
        opacity: 0.7;
        margin-top: 5px;
        margin-bottom: 20px;
    }
    
    /* Headers de secoes */
    h1, h2, h3 {
        color: #1A3636 !important;
    }
    
    /* Cards (st.container border=True usa div[data-testid="stVerticalBlockBorderWrapper"]) */
    div[data-testid="stVerticalBlockBorderWrapper"] > div {
        background-color: #FFFFFF;
        border-radius: 12px;
        box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.05);
        padding: 1rem;
        border: 1px solid #E2E8F0;
    }
    
    /* Botoes */
    .stButton button {
        border-radius: 6px;
        font-weight: 600;
    }
    </style>
    """,
    unsafe_allow_html=True,
)

with st.sidebar:
    st.markdown('<p class="app-title">🏥 HU Dra. Yuska</p>', unsafe_allow_html=True)
    st.markdown('<p class="app-subtitle">Sistema de Gestão Integrada</p>', unsafe_allow_html=True)
    st.markdown("---")
    
    # Dicionario de mapeamento para os ícones
    opcoes_nav = {
        "🩺 Atendimentos": "Atendimentos",
        "👥 Pacientes": "Pacientes",
        "📊 Relatórios": "Relatorios"
    }
    
    escolha_nav = st.radio(
        "Navegação Principal",
        list(opcoes_nav.keys()),
        label_visibility="collapsed",
    )
    pagina = opcoes_nav[escolha_nav]


def formata_data(dt):
    return dt.strftime("%d/%m/%Y %H:%M") if dt else "-"


# ==========================================
# PAGINA: ATENDIMENTOS
# ==========================================
if pagina == "Atendimentos":
    st.title("🩺 Gestão de Atendimentos")
    st.markdown("Selecione um paciente para ver seu histórico clínico ou registrar um novo atendimento.")
    st.write("")

    pacientes = db.listar_pacientes("")
    if not pacientes:
        st.warning("⚠️ Nenhum paciente cadastrado na base de dados.")
        st.stop()

    opcoes = {f"{p['nome']} (Convênio: {p['num_convenio'] or 'Particular'})": p for p in pacientes}
    
    # Barra de busca estilizada
    col_busca, _ = st.columns([1, 1])
    with col_busca:
        escolha = st.selectbox("🔍 Buscar Paciente", list(opcoes.keys()))
    
    paciente_atual = opcoes[escolha]
    id_paciente = paciente_atual["id_pessoa"]

    # --- Resumo do Paciente em Cards ---
    st.markdown("##### 👤 Ficha do Paciente")
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Telefone", paciente_atual["telefone"] or "N/A")
    c2.metric("CPF", f"{paciente_atual['cpf'][:3]}.***.***-{paciente_atual['cpf'][-2:]}")
    c3.metric("Tipo Sang.", paciente_atual["grupo_sanguineo"] or "N/A")
    c4.metric("Alergias", paciente_atual["alergias"] or "Nenhuma")
    
    st.divider()

    col_esq, col_dir = st.columns([1.2, 1], gap="large")

    with col_esq:
        st.subheader("📋 Histórico Clínico")
        atendimentos = db.listar_atendimentos_paciente(id_paciente)
        if atendimentos:
            df = pd.DataFrame(atendimentos)
            df["data_hora"] = df["data_hora"].apply(formata_data)
            df = df.rename(columns={
                "id_atendimento": "ID", "data_hora": "Data/Hora",
                "duracao_minutos": "Duração (min)", "residente": "Residente", "preceptor": "Preceptor",
            })
            st.dataframe(df, hide_index=True, use_container_width=True)

            id_selecionado = st.selectbox(
                "🔎 Selecione um atendimento para ver os procedimentos",
                [a["id_atendimento"] for a in atendimentos],
                format_func=lambda x: f"Atendimento #{x} - {next((a['data_hora'] for a in atendimentos if a['id_atendimento'] == x), '')}"
            )
        else:
            st.info("ℹ️ Este paciente ainda não possui atendimentos registrados.")
            id_selecionado = None

    with col_dir:
        st.subheader("💉 Procedimentos do Atendimento")
        if id_selecionado:
            procedimentos = db.listar_procedimentos_atendimento(id_selecionado)
            if procedimentos:
                for proc in procedimentos:
                    with st.container(border=True):
                        c1, c2 = st.columns([3, 1])
                        c1.markdown(f"**{proc['procedimento']}**")
                        c1.caption(
                            f"📦 Qtd: {proc['quantidade']} &nbsp;|&nbsp; ⏱️ Tempo: {proc['tempo_real_minutos']} min"
                            + (f"<br>📝 Obs: {proc['observacao']}" if proc["observacao"] else "")
                            , unsafe_allow_html=True
                        )
                        if proc["tem_faturamento"]:
                            c2.success("🔒 Faturado", icon="✅")
                        else:
                            if c2.button("🗑️ Remover", key=f"rm-{proc['id_procedimento']}", use_container_width=True):
                                linhas = db.remover_procedimento_realizado(id_selecionado, proc["id_procedimento"])
                                if linhas:
                                    st.toast("Procedimento removido com sucesso!", icon="✅")
                                    st.rerun()
                                else:
                                    st.error("Não foi possível remover (já faturado).")
            else:
                st.info("Nenhum procedimento registrado para este atendimento.")

    st.markdown("---")
    with st.expander("➕ Registrar Novo Atendimento", expanded=False):
        residentes = {r["nome"]: r["id_profissional"] for r in db.listar_residentes()}
        preceptores = {p["nome"]: p["id_profissional"] for p in db.listar_preceptores()}
        unidades = {u["nome"]: u["id_unidade"] for u in db.listar_unidades()}
        procs_disponiveis = {p["nome"]: p["id_procedimento"] for p in db.listar_procedimentos()}

        with st.form("form_novo_atendimento"):
            c1, c2, c3 = st.columns(3)
            f_data = c1.date_input("📅 Data", value=date.today())
            f_hora = c2.time_input("🕒 Hora", value=dtime(9, 0))
            f_duracao = c3.number_input("⏱️ Duração (min)", min_value=1, value=30)

            c4, c5, c6 = st.columns(3)
            f_residente = c4.selectbox("👨‍⚕️ Residente", list(residentes.keys()))
            f_preceptor = c5.selectbox("👨‍🏫 Preceptor", list(preceptores.keys()))
            f_unidade = c6.selectbox("🏥 Unidade", list(unidades.keys()))

            st.markdown("##### Procedimentos Realizados")
            procs_selecionados = st.multiselect("Selecione os procedimentos", list(procs_disponiveis.keys()))

            st.write("")
            enviado = st.form_submit_button("✅ Salvar Atendimento", use_container_width=True)
            if enviado:
                if not procs_selecionados:
                    st.error("Selecione pelo menos um procedimento!")
                else:
                    lista_json = [{"id_procedimento": procs_disponiveis[p]} for p in procs_selecionados]
                    novo_id = db.inserir_atendimento_completo(
                        datetime.combine(f_data, f_hora),
                        int(f_duracao),
                        id_paciente,
                        residentes[f_residente],
                        preceptores[f_preceptor],
                        unidades[f_unidade],
                        lista_json
                    )
                    if novo_id:
                        st.toast(f"Atendimento #{novo_id} registrado com sucesso!", icon="🎉")
                        st.rerun()
                    else:
                        st.error("Falha ao registrar: verifique dependências ou regras de negócio.")


# ==========================================
# PAGINA: PACIENTES
# ==========================================
elif pagina == "Pacientes":
    st.title("👥 Gestão de Pacientes")
    st.markdown("Consulte a base de pacientes ou atualize os dados cadastrais (convênio e telefone).")
    st.write("")



    col_busca, _ = st.columns([1, 2])
    with col_busca:
        busca = st.text_input("🔍 Buscar por nome do paciente", placeholder="Digite o nome...")
    
    pacientes = db.listar_pacientes(busca)

    if pacientes:
        st.write("")
        df = pd.DataFrame(pacientes).rename(columns={
            "nome": "Nome", "cpf": "CPF", "telefone": "Telefone",
            "num_convenio": "Convênio", "grupo_sanguineo": "Tipo Sanguíneo", "alergias": "Alergias",
        })
        st.dataframe(
            df[["Nome", "CPF", "Convênio", "Tipo Sanguíneo", "Telefone", "Alergias"]],
            hide_index=True, use_container_width=True,
        )

        st.divider()
        st.subheader("✏️ Atualizar Dados Cadastrais")
        
        with st.container(border=True):
            opcoes = {p["nome"]: p for p in pacientes}
            col_selecao, _ = st.columns([1, 1])
            with col_selecao:
                escolha = st.selectbox("Selecione o Paciente para Edição", list(opcoes.keys()))
            
            p = opcoes[escolha]

            with st.form("form_atualiza_paciente"):
                c1, c2 = st.columns(2)
                novo_convenio = c1.text_input("💳 Plano de Saúde / Convênio", value=p["num_convenio"] or "")
                novo_telefone = c2.text_input("📱 Telefone de Contato", value=p["telefone"] or "")
                
                st.write("")
                if st.form_submit_button("💾 Salvar Alterações"):
                    db.atualizar_paciente(p["id_pessoa"], novo_convenio, novo_telefone)
                    st.toast(f"Dados de {p['nome']} atualizados com sucesso!", icon="✅")
                    st.rerun()
    else:
        st.info("Nenhum paciente encontrado com esse nome.")


# ==========================================
# PAGINA: RELATORIOS
# ==========================================
elif pagina == "Relatorios":
    st.title("📊 Relatórios e Painéis")
    st.markdown("Métricas de performance, ranking de profissionais e auditoria clínica.")
    st.write("")

    aba_residentes, aba_preceptores, aba_plantoes, aba_pacientes, aba_internados, aba_aviso_sup, aba_estatisticas, aba_espera, aba_reajuste, aba_avancadas, aba_concorrencia = st.tabs([
        "👨‍⚕️ Residentes",
        "👨‍🏫 Preceptores",
        "🏥 Escalas",
        "⚠️ Risco",
        "🛏️ Internados",
        "⚠️ Sem Sup. Doutor",
        "📈 Estatísticas Mensais",
        "⏱️ Tempo de Espera",
        "🔄 Reajustar Escala",
        "🔬 Consultas Avançadas",
        "🔒 Concorrência",
    ])

    with aba_residentes:
        c1, c2 = st.columns(2, gap="large")
        with c1:
            st.subheader("🏆 Ranking de Atendimentos")
            st.caption("Volume total de atendimentos por residente.")
            df_rank = pd.DataFrame(db.ranking_residentes())
            if not df_rank.empty:
                df_rank = df_rank.rename(columns={"nome_residente": "Residente", "total_atendimentos": "Total de Atendimentos"})
                st.dataframe(df_rank, hide_index=True, use_container_width=True)
            else:
                st.info("Sem dados.")

        with c2:
            st.subheader("⏱️ Tempo Médio (min)")
            st.caption("Média de tempo gasto por atendimento.")
            df_tempo = pd.DataFrame(db.tempo_medio_por_residente())
            if not df_tempo.empty:
                df_tempo = df_tempo.rename(columns={"residente": "Residente", "total_atendimentos": "Atend.", "media_duracao_min": "Média (min)"})
                st.dataframe(df_tempo[["Residente", "Atend.", "Média (min)"]], hide_index=True, use_container_width=True)
            else:
                st.info("Sem dados.")

    with aba_preceptores:
        st.subheader("⭐ Preceptores de Alta Demanda")
        st.markdown("Filtrar preceptores que supervisionaram **mais de 5 atendimentos** no mês/ano.")
        with st.container(border=True):
            c1, c2, c3 = st.columns([1, 1, 2])
            mes = c1.number_input("Mês", min_value=1, max_value=12, value=datetime.today().month)
            ano = c2.number_input("Ano", min_value=2000, max_value=2100, value=datetime.today().year)
            st.write("")
            
            resultado = db.preceptores_mais_de_n_atendimentos(int(mes), int(ano))
            if resultado:
                st.write("")
                df_res = pd.DataFrame(resultado).rename(columns={"nome_preceptor": "Preceptor", "total_atendimentos": "Total de Supervisões"})
                st.dataframe(df_res, hide_index=True, use_container_width=True)
            else:
                st.info(f"Nenhum preceptor ultrapassou 5 atendimentos em {mes}/{ano}.")

    with aba_plantoes:
        st.subheader("📅 Mapa de Plantões")
        st.caption("Quantidade de plantões alocados por unidade e residente na escala.")
        resultado = db.plantoes_por_residente_unidade()
        if resultado:
            df_pl = pd.DataFrame(resultado).rename(columns={"nome_unidade": "Unidade", "nome_residente": "Residente", "quantidade_plantoes": "Qtd Plantões"})
            st.dataframe(df_pl, hide_index=True, use_container_width=True)
        else:
            st.info("Nenhuma escala encontrada.")

    with aba_pacientes:
        st.subheader("🛡️ Auditoria: Pacientes de Baixo/Médio Risco")
        st.caption("Pacientes que **nunca** passaram por procedimentos classificados como de risco ALTO.")
        resultado = db.pacientes_sem_procedimento_alto()
        if resultado:
            df_pac = pd.DataFrame(resultado).rename(columns={"nome_paciente": "Paciente", "num_convenio": "Convênio"})
            st.dataframe(df_pac, hide_index=True, use_container_width=True)
        else:
            st.info("Todos os pacientes já passaram por procedimentos de alto risco.")

    with aba_internados:
        st.subheader("🛏️ Pacientes Atualmente Internados")
        st.caption("Baseado em internamentos sem data de saída (VIEW vw_pacientes_internados)")
        resultado = db.listar_pacientes_internados()
        if resultado:
            st.dataframe(pd.DataFrame(resultado), hide_index=True, use_container_width=True)
        else:
            st.info("Não há pacientes internados no momento.")

    with aba_aviso_sup:
        st.subheader("⚠️ Alerta de Supervisão")
        st.caption("Residentes em plantão cujo preceptor NÃO é Doutor (VIEW vw_residentes_sem_supervisor)")
        resultado = db.listar_residentes_sem_supervisor()
        if resultado:
            st.dataframe(pd.DataFrame(resultado), hide_index=True, use_container_width=True)
        else:
            st.info("Todos os residentes estão com preceptores Doutores/Pós-Doutores.")

    with aba_estatisticas:
        st.subheader("📈 Estatísticas Mensais")
        st.caption("Visão agregada por mês e unidade (VIEW vw_estatisticas_atendimentos_mensal)")
        resultado = db.listar_estatisticas_mensais()
        if resultado:
            st.dataframe(pd.DataFrame(resultado), hide_index=True, use_container_width=True)
        else:
            st.info("Sem estatísticas disponíveis.")

    with aba_espera:
        st.subheader("⏱️ Tempo Médio de Espera (Unidades)")
        st.caption("Tempo entre chegada do paciente e o início do 1º procedimento (STORED FUNCTION sp_calcular_tempo_medio_espera)")
        resultado = db.calcular_tempo_medio_espera()
        if resultado:
            st.dataframe(pd.DataFrame(resultado), hide_index=True, use_container_width=True)
        else:
            st.info("Sem dados suficientes para calcular tempo de espera.")

    with aba_reajuste:
        st.subheader("🔄 Reajuste Rápido de Escala")
        st.caption("Move todas as escalas de um residente para outro dia/turno (STORED PROCEDURE sp_reajustar_escala)")
        dias = ["Segunda", "Terca", "Quarta", "Quinta", "Sexta", "Sabado", "Domingo"]
        turnos = ["Manha", "Tarde", "Noite"]
        residentes_dict = {r["nome"]: r["id_profissional"] for r in db.listar_residentes()}
        
        with st.form("form_reajuste_escala"):
            res_sel = st.selectbox("Selecione o Residente", list(residentes_dict.keys()))
            c1, c2 = st.columns(2)
            dia_o = c1.selectbox("De: Dia", dias)
            turno_o = c2.selectbox("De: Turno", turnos)
            
            c3, c4 = st.columns(2)
            dia_d = c3.selectbox("Para: Dia", dias, index=1)
            turno_d = c4.selectbox("Para: Turno", turnos)
            
            submit_reajuste = st.form_submit_button("Reajustar Escala")
            if submit_reajuste:
                try:
                    movidas = db.reajustar_escala(residentes_dict[res_sel], dia_o, turno_o, dia_d, turno_d)
                    if movidas > 0:
                        st.success(f"{movidas} escala(s) movida(s) com sucesso!")
                    else:
                        st.warning("Nenhuma escala encontrada para reajustar (ou 0 movidas).")
                except Exception as e:
                    # Extracts the friendly part from psycopg2 error if possible
                    err_msg = str(e).split("CONTEXT")[0].strip() if "CONTEXT" in str(e) else str(e)
                    st.error(f"Erro ao reajustar: {err_msg}")

    with aba_avancadas:
        st.subheader("🔬 Consultas Avançadas (ORM)")

        st.markdown("**Preceptores que supervisionaram residentes que atenderam pacientes flamenguistas**")
        resultado = db.preceptores_de_pacientes_flamenguistas()
        if resultado:
            st.dataframe(pd.DataFrame(resultado).rename(columns={"nome_preceptor": "Preceptor"}),
                         hide_index=True, use_container_width=True)
        else:
            st.info("Nenhum preceptor supervisionou atendimento de paciente flamenguista.")

        st.divider()
        st.markdown("**Último atendimento de cada paciente**")
        resultado = db.ultimo_atendimento_por_paciente()
        if resultado:
            df = pd.DataFrame(resultado)
            df["data_hora"] = df["data_hora"].apply(formata_data)
            df = df.rename(columns={
                "paciente": "Paciente", "data_hora": "Data/Hora",
                "residente": "Residente", "preceptor": "Preceptor", "procedimentos": "Procedimentos",
            })
            st.dataframe(df, hide_index=True, use_container_width=True)
        else:
            st.info("Nenhum atendimento registrado.")

        st.divider()
        st.markdown("**Percentual de procedimentos de alto risco por residente**")
        resultado = db.percentual_alto_risco_por_residente()
        if resultado:
            df = pd.DataFrame(resultado).rename(columns={
                "residente": "Residente", "total_procedimentos": "Total de Procedimentos",
                "percentual_alto_risco": "% Alto Risco",
            })
            st.dataframe(df, hide_index=True, use_container_width=True)
        else:
            st.info("Nenhum procedimento registrado.")

    with aba_concorrencia:
        st.subheader("🔒 Simulação de Concorrência (Lock Otimista)")
        st.caption(
            "Duas transações tentam alterar a mesma escala ao mesmo tempo. "
            "A primeira a salvar vence; a segunda é rejeitada por versão desatualizada."
        )
        escalas = db.plantoes_por_residente_unidade()
        with st.form("form_concorrencia"):
            id_escala = st.number_input("ID da escala (banco de testes: 1 a 6)", min_value=1, value=1, step=1)
            c1, c2 = st.columns(2)
            turno_a = c1.selectbox("Transação A tenta mudar o turno para", ["Manha", "Tarde", "Noite"], index=1)
            turno_b = c2.selectbox("Transação B tenta mudar o turno para", ["Manha", "Tarde", "Noite"], index=2)
            simular = st.form_submit_button("▶️ Simular conflito")

        if simular:
            try:
                logs = db.simular_concorrencia_escala(int(id_escala), turno_a, turno_b)
                for linha in logs:
                    if "REJEITADA" in linha:
                        st.error(linha)
                    else:
                        st.success(linha)
            except Exception as e:
                st.error(f"Erro ao simular: {e}")
