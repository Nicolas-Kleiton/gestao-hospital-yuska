# Sistema de Gestão Hospitalar — Dra. Yuska Maritan Brito

Sistema para gerenciar os atendimentos de um hospital universitário: pacientes,
profissionais, procedimentos e as escalas de plantão, onde os residentes atendem
sob supervisão dos preceptores.

Este repositório contém a **Etapa 1** do projeto — o modelo relacional, o CRUD e
as consultas básicas, tudo em **SQL puro (sem ORM)**.

---

## Tecnologias

- **Banco:** PostgreSQL
- **Linguagem:** SQL puro (o ORM entra só na Etapa 2)

---

## Estrutura do repositório

```
gestao-hospital-yuska/
├── sql/
│   ├── create_tables.sql     # cria as tabelas (com as constraints: PK, FK, CHECK, NOT NULL, UNIQUE)
│   ├── insert_dados.sql       # popula com dados de teste
│   ├── crud_consultas.sql     # CRUD e consultas básicas (Item 3)
│   └── consultas_analiticas.sql  # consultas analíticas (Item 4)
├── docs/
│   ├── Modelagem_ProjetoBD.pdf        # DER, modelo relacional e normalização (Item 1)
│   ├── diagramas/                     # DER editável (.drawio)
│   └── demo_item3_saida.md            # saída real das operações do Item 3
└── README.md
```

---

## Pré-requisitos

- **PostgreSQL** instalado — ou **Docker**, se preferir subir o banco sem instalar nada.
- Opcionalmente, um cliente como **pgAdmin** ou **DBeaver** pra visualizar os dados.

---

## Como executar

Rode os scripts **nesta ordem** — cada um depende do anterior:

```
create_tables.sql  →  insert_dados.sql  →  crud_consultas.sql  →  consultas_analiticas.sql
```

### Opção A — PostgreSQL local

```bash
# cria o banco
createdb hospital

# roda os scripts na ordem
psql -d hospital -f sql/create_tables.sql
psql -d hospital -f sql/insert_dados.sql
psql -d hospital -f sql/crud_consultas.sql
psql -d hospital -f sql/consultas_analiticas.sql
```

### Opção B — Docker (banco descartável)

```bash
# sobe um PostgreSQL
docker run -d --name hospital_yuska -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=hospital postgres:16-alpine

# roda os scripts na ordem
docker exec -i hospital_yuska psql -U postgres -d hospital < sql/create_tables.sql
docker exec -i hospital_yuska psql -U postgres -d hospital < sql/insert_dados.sql
docker exec -i hospital_yuska psql -U postgres -d hospital < sql/crud_consultas.sql
docker exec -i hospital_yuska psql -U postgres -d hospital < sql/consultas_analiticas.sql

# quando terminar, remove o container
docker rm -f hospital_yuska
```

Rodamos essa sequência num PostgreSQL e deu tudo certo — a saída de cada
operação está guardada em [`docs/demo_item3_saida.md`](docs/demo_item3_saida.md),
caso queira conferir sem precisar executar.

---

## O que cada script faz

**`create_tables.sql`** — cria as 10 tabelas do modelo, com as duas
especializações (`pessoa → paciente/profissional` e
`profissional → preceptor/residente`) e a tabela associativa
`procedimento_realizado`. Todas as restrições de integridade já vêm aqui.

**`insert_dados.sql`** — enche o banco com dados de teste: 5 pacientes,
5 preceptores, 5 residentes, 4 unidades, 8 procedimentos, 10 atendimentos,
14 procedimentos realizados e 6 escalas.

**`crud_consultas.sql` (Item 3)** — as operações de CRUD e as consultas básicas:

| # | Operação | O que faz |
|---|----------|-----------|
| 3.1 | **Create** | Insere um atendimento, checando antes se paciente, residente e preceptor existem |
| 3.2 | **Read** | Lista os atendimentos de um paciente, ordenados por data |
| 3.3 | **Read** | Lista os procedimentos de um atendimento (nome, quantidade e tempo real) |
| 3.4 | **Update** | Atualiza os dados de um paciente (convênio e telefone) |
| 3.5 | **Delete** | Remove um procedimento realizado, mas só se ainda não foi faturado |
| 3.6 | **Read/agregação** | Calcula o tempo médio dos atendimentos por residente |

Como é SQL puro, o `crud_consultas.sql` usa IDs de exemplo que existem no
`insert_dados.sql` e mexe nos dados de teste ao rodar — é isso mesmo, é o jeito
de mostrar as operações funcionando.

**`consultas_analiticas.sql` (Item 4)** — as consultas analíticas exigidas:

| # | Consulta |
|---|----------|
| 4.1 | Ranking dos residentes por número de atendimentos realizados |
| 4.2 | Preceptores que supervisionaram mais de 5 atendimentos em um mês |
| 4.3 | Quantidade de plantões escalados por residente, por unidade |
| 4.4 | Pacientes que nunca realizaram procedimento de risco ALTO |

---

## Modelagem

O DER, o modelo relacional e a justificativa de normalização até a 3FN estão em
[`docs/Modelagem_ProjetoBD.pdf`](docs/Modelagem_ProjetoBD.pdf).

---

## Autores

- Gerson Gonçalves de Freitas
- Nicolas Kleiton da Silva Melo
- Rodrigo Monteiro Fortes de Oliveira
- Tiago Varelo da Silva
