-- Etapa 2 - Item 3: Views (PostgreSQL)
--
-- Pre-requisito: create_tables.sql, insert_dados.sql
-- Execucao: psql -f views.sql

-- EXTENSOES DE SCHEMA

-- Colunas para controle de internacao no atendimento.
ALTER TABLE atendimento
    ADD COLUMN IF NOT EXISTS data_hora_entrada TIMESTAMP,
    ADD COLUMN IF NOT EXISTS data_hora_saida   TIMESTAMP;

-- Popula internacoes de teste nos atendimentos existentes.
-- Paciente 3 (Daniela) e paciente 4 (Eduardo) ficam internados (saida NULL).
-- Paciente 1 (Ana) ja recebeu alta.
UPDATE atendimento SET data_hora_entrada = '2025-05-02 08:30:00',
                       data_hora_saida   = '2025-05-04 11:00:00'
 WHERE id_atendimento = 1;   -- paciente 1, Enfermaria Central

UPDATE atendimento SET data_hora_entrada = '2025-05-20 13:30:00',
                       data_hora_saida   = NULL
 WHERE id_atendimento = 8;   -- paciente 3, Enfermaria Central (internada)

UPDATE atendimento SET data_hora_entrada = '2025-05-22 15:00:00',
                       data_hora_saida   = NULL
 WHERE id_atendimento = 9;   -- paciente 4, UTI Adulto (internado)


-- 1. vw_pacientes_internados

-- Pacientes cuja internacao mais recente tem data_hora_saida IS NULL.

CREATE OR REPLACE VIEW vw_pacientes_internados AS
SELECT pe.nome            AS nome_paciente,
       pac.num_convenio,
       pac.grupo_sanguineo,
       pac.alergias,
       u.nome             AS unidade,
       a.data_hora_entrada
FROM atendimento a
JOIN paciente pac ON pac.id_pessoa = a.id_paciente
JOIN pessoa   pe  ON pe.id_pessoa  = pac.id_pessoa
JOIN unidade  u   ON u.id_unidade  = a.id_unidade
WHERE a.data_hora_entrada IS NOT NULL
  AND a.data_hora_saida IS NULL
  AND a.data_hora_entrada = (
      SELECT MAX(a2.data_hora_entrada)
        FROM atendimento a2
       WHERE a2.id_paciente = a.id_paciente
         AND a2.data_hora_entrada IS NOT NULL
  );


-- 2. vw_residentes_sem_supervisor

-- Residentes escalados cujo preceptor nao possui titulacao de doutor
-- (ou nao possui supervisao ativa).

CREATE OR REPLACE VIEW vw_residentes_sem_supervisor AS
SELECT DISTINCT
       pe_res.nome        AS nome_residente,
       r.ano_residencia,
       prof.especialidade,
       pe_prec.nome       AS nome_preceptor,
       prec.titulacao
FROM escala e
JOIN residente    r       ON r.id_profissional  = e.id_residente
JOIN pessoa       pe_res  ON pe_res.id_pessoa   = r.id_profissional
JOIN profissional prof    ON prof.id_pessoa      = r.id_profissional
LEFT JOIN preceptor prec  ON prec.id_profissional = e.id_preceptor
LEFT JOIN pessoa  pe_prec ON pe_prec.id_pessoa    = prec.id_profissional
WHERE prec.id_profissional IS NULL
   OR prec.titulacao NOT IN ('Doutor', 'Pos-Doutor');


-- 3. vw_estatisticas_atendimentos_mensal

-- Agregacao por mes e unidade: total de atendimentos, media de duracao
-- e procedimento mais comum.

CREATE OR REPLACE VIEW vw_estatisticas_atendimentos_mensal AS
WITH stats AS (
    SELECT TO_CHAR(a.data_hora, 'YYYY-MM') AS ano_mes,
           u.id_unidade,
           u.nome                           AS nome_unidade,
           COUNT(a.id_atendimento)          AS total_atendimentos,
           ROUND(AVG(a.duracao_minutos), 1) AS media_duracao_minutos
      FROM atendimento a
      JOIN unidade u ON u.id_unidade = a.id_unidade
     GROUP BY TO_CHAR(a.data_hora, 'YYYY-MM'), u.id_unidade, u.nome
),
proc_rank AS (
    SELECT TO_CHAR(a.data_hora, 'YYYY-MM') AS ano_mes,
           a.id_unidade,
           proc.nome                        AS nome_procedimento,
           COUNT(*)                         AS qtd,
           ROW_NUMBER() OVER (
               PARTITION BY TO_CHAR(a.data_hora, 'YYYY-MM'), a.id_unidade
               ORDER BY COUNT(*) DESC, proc.nome
           ) AS rn
      FROM atendimento a
      JOIN procedimento_realizado pr ON pr.id_atendimento = a.id_atendimento
      JOIN procedimento proc        ON proc.id_procedimento = pr.id_procedimento
     GROUP BY TO_CHAR(a.data_hora, 'YYYY-MM'), a.id_unidade, proc.nome
)
SELECT s.ano_mes,
       s.nome_unidade,
       s.total_atendimentos,
       s.media_duracao_minutos,
       pr.nome_procedimento AS procedimento_mais_comum
  FROM stats s
  LEFT JOIN proc_rank pr ON pr.ano_mes    = s.ano_mes
                        AND pr.id_unidade = s.id_unidade
                        AND pr.rn         = 1
 ORDER BY s.ano_mes DESC, s.nome_unidade;

-- TESTES

-- vw_pacientes_internados: deve retornar Daniela (atend. 8) e Eduardo (atend. 9)
SELECT '--- vw_pacientes_internados ---' AS teste;
SELECT * FROM vw_pacientes_internados;

-- vw_residentes_sem_supervisor: residente 13 (Nathalia, preceptor Mestre)
SELECT '--- vw_residentes_sem_supervisor ---' AS teste;
SELECT * FROM vw_residentes_sem_supervisor;

-- vw_estatisticas_atendimentos_mensal: maio/2025 por unidade
SELECT '--- vw_estatisticas_atendimentos_mensal ---' AS teste;
SELECT * FROM vw_estatisticas_atendimentos_mensal;
