# Sistema de Gestão Hospitalar — Dra. Yuska Maritan Brito

Sistema para gerenciar os atendimentos de um hospital universitário: pacientes,
profissionais, procedimentos e as escalas de plantão, onde os residentes atendem
sob supervisão dos preceptores.

Este repositório contém a **Etapa 1 e Etapa 2** do projeto, englobando desde a 
modelagem relacional, CRUD e consultas básicas (SQL puro), até funcionalidades
avançadas usando Stored Procedures, Triggers, Views, controle de concorrência e 
uma aplicação Web com ORM.

---

## Tecnologias

- **Banco de Dados:** PostgreSQL
- **Aplicação Web:** Python (Streamlit)
- **ORM:** SQLAlchemy
- **Linguagem:** SQL e Python

---

## Estrutura do repositório

```text
gestao-hospital-yuska/
├── app/
│   ├── app.py                    # interface gráfica em Streamlit com as consultas ORM
│   ├── db.py                     # conexão e execução de queries usando SQLAlchemy
│   ├── models.py                 # mapeamento objeto-relacional (Entidades)
│   └── requirements.txt          # dependências do Python
├── sql/
│   ├── create_tables.sql         # cria as tabelas (Etapa 1 + adaptações Etapa 2)
│   ├── insert_dados.sql          # popula com dados de teste
│   ├── crud_consultas.sql        # CRUD e consultas básicas (Etapa 1)
│   ├── consultas_analiticas.sql  # consultas analíticas (Etapa 1)
│   ├── stored_procedures.sql     # Stored Procedures (Etapa 2)
│   ├── triggers.sql              # Triggers e tabelas de auditoria (Etapa 2)
│   ├── views.sql                 # Views de relatórios (Etapa 2)
│   ├── concorrencia.sql          # Setup para simulação de concorrência/lock (Etapa 2)
│   └── testes_stored_procedures.sql
├── docs/
│   ├── Modelagem_ProjetoBD.pdf   # DER, modelo relacional e normalização
│   └── diagramas/                # DER editável (.drawio)
├── docker-compose.yml            # sobe o PostgreSQL via Docker
└── README.md
```

---

## Pré-requisitos

- **PostgreSQL** instalado — ou **Docker**, se preferir subir o banco via container.
- **Python 3** instalado (para rodar a interface web).

---

## Como executar o Banco de Dados

Os scripts devem ser executados **nesta ordem** para garantir as dependências estruturais e lógicas:

```
create_tables.sql  →  insert_dados.sql  →  [crud_consultas, consultas_analiticas] 
→ stored_procedures.sql → triggers.sql → views.sql → concorrencia.sql
```

### Opção A — PostgreSQL local

```bash
# cria o banco
createdb hospital_yuska

# roda os scripts na ordem
psql -d hospital_yuska -f sql/create_tables.sql
psql -d hospital_yuska -f sql/insert_dados.sql
psql -d hospital_yuska -f sql/crud_consultas.sql
psql -d hospital_yuska -f sql/consultas_analiticas.sql
psql -d hospital_yuska -f sql/stored_procedures.sql
psql -d hospital_yuska -f sql/triggers.sql
psql -d hospital_yuska -f sql/views.sql
psql -d hospital_yuska -f sql/concorrencia.sql
```

### Opção B — Docker (usando o `docker-compose.yml`)

```bash
# sobe o PostgreSQL em segundo plano
docker compose up -d

# roda os scripts na ordem
docker compose exec -T db psql -U postgres -d hospital_yuska < sql/create_tables.sql
docker compose exec -T db psql -U postgres -d hospital_yuska < sql/insert_dados.sql
docker compose exec -T db psql -U postgres -d hospital_yuska < sql/crud_consultas.sql
docker compose exec -T db psql -U postgres -d hospital_yuska < sql/consultas_analiticas.sql
docker compose exec -T db psql -U postgres -d hospital_yuska < sql/stored_procedures.sql
docker compose exec -T db psql -U postgres -d hospital_yuska < sql/triggers.sql
docker compose exec -T db psql -U postgres -d hospital_yuska < sql/views.sql
docker compose exec -T db psql -U postgres -d hospital_yuska < sql/concorrencia.sql

# quando terminar
docker compose down        # para o container, mas mantém os dados salvos
```

---

## Executando a Interface Web (Streamlit)

O projeto possui uma interface visual robusta construída em **Streamlit** que implementa todas as rotinas usando **SQLAlchemy (ORM)**. 

Certifique-se de que o banco de dados esteja rodando e com todos os scripts acima executados antes de iniciar a aplicação.

```bash
# entre na pasta da aplicação
cd app

# instale as dependências
pip install -r requirements.txt

# inicie o servidor do Streamlit
streamlit run app.py
```
A aplicação abrirá automaticamente no seu navegador. Lá você encontrará as operações de CRUD, relatórios analíticos, chamadas para as Stored Procedures e simulação de concorrência.

---

## O que cada script SQL faz

### Etapa 1
- **`create_tables.sql`**: cria as tabelas do modelo e constraints.
- **`insert_dados.sql`**: popula o banco com dados de teste iniciais.
- **`crud_consultas.sql`**: operações de CRUD (inserir, listar, atualizar e deletar).
- **`consultas_analiticas.sql`**: consultas puras (ranking, preceptores mais ativos, etc).

### Etapa 2
- **`stored_procedures.sql`**:
  - `sp_registrar_atendimento_completo`: Registro de atendimento usando transação de múltiplos procedimentos.
  - `sp_calcular_tempo_medio_espera`: Calcula média de tempo de espera.
  - `sp_reajustar_escala`: Move escalas evitando colisões.
- **`triggers.sql`**: 
  - `trg_check_sobreposicao_escala`: Restrição avançada de sobreposição.
  - `trg_audita_atendimento`: Auditoria DML gerando snapshots de JSONB.
  - `trg_atualiza_media_procedimentos`: Atualização incremental de média estatística.
- **`views.sql`**: Cria views para facilitar os relatórios, como pacientes internados, residentes sem supervisão e estatísticas mensais.
- **`concorrencia.sql`**: Adiciona os identificadores de versionamento para lock otimista usado pela ORM.

---

## Autores

- Gerson Gonçalves de Freitas
- Nicolas Kleiton da Silva Melo
- Rodrigo Monteiro Fortes de Oliveira
- Tiago Varelo da Silva
