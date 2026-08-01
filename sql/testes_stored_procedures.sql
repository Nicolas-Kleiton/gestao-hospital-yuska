-- Sistema de Gestao Hospitalar Dra. Yuska Maritan Brito
-- Etapa 2 - roteiro de teste das stored procedures
--
-- Ordem de execucao do zero:
--   psql -f create_tables.sql
--   psql -f insert_dados.sql
--   psql -f stored_procedures.sql
--   psql -f testes_stored_procedures.sql

-- 1. sp_registrar_atendimento_completo

-- ---- 1.1 CAMINHO FELIZ: atendimento + 3 procedimentos, tudo gravado ----
BEGIN;

CALL sp_registrar_atendimento_completo(
    p_data_hora       => TIMESTAMP '2025-06-02 08:00:00',
    p_duracao_minutos => 50,
    p_id_paciente     => 1,
    p_id_residente    => 11,
    p_id_preceptor    => 6,
    p_id_unidade      => 3,
    p_procedimentos   => '[
        {"id_procedimento": 2, "quantidade": 1, "tempo_real_minutos": 11,
         "data_hora_inicio": "2025-06-02 08:12:00",
         "observacao": "Coleta para hemograma", "tem_faturamento": true},
        {"id_procedimento": 7, "quantidade": 2, "tempo_real_minutos": 16,
         "data_hora_inicio": "2025-06-02 08:30:00",
         "observacao": "Curativo duplo"},
        {"id_procedimento": 3, "quantidade": 1, "tempo_real_minutos": 5,
         "data_hora_inicio": "2025-06-02 08:45:00"}
    ]'::JSONB
);

-- confere o que foi gravado
SELECT a.id_atendimento, a.data_hora, u.nome AS unidade,
       COUNT(pr.id_procedimento) AS qtd_procedimentos
FROM atendimento a
INNER JOIN unidade u                 ON u.id_unidade = a.id_unidade
INNER JOIN procedimento_realizado pr ON pr.id_atendimento = a.id_atendimento
WHERE a.data_hora = TIMESTAMP '2025-06-02 08:00:00'
GROUP BY a.id_atendimento, a.data_hora, u.nome;

ROLLBACK;  -- troque por COMMIT para persistir


-- ---- 1.2 ROLLBACK: o 2o procedimento nao existe no catalogo ----
-- Esperado: erro e NENHUMA linha gravada (nem o atendimento).
BEGIN;

SELECT COUNT(*) AS atendimentos_antes FROM atendimento;

-- Nota: dentro de PL-pgSQL o parametro INOUT precisa receber uma VARIAVEL
-- (nao da para omitir e usar o DEFAULT, como se faz no CALL direto do psql).
DO $$
DECLARE v_id INT;
BEGIN
    CALL sp_registrar_atendimento_completo(
        p_data_hora       => TIMESTAMP '2025-06-03 10:00:00',
        p_duracao_minutos => 30,
        p_id_paciente     => 2,
        p_id_residente    => 12,
        p_id_preceptor    => 7,
        p_id_unidade      => 1,
        p_procedimentos   => '[
            {"id_procedimento": 1, "quantidade": 1},
            {"id_procedimento": 999, "quantidade": 1}
        ]'::JSONB,
        p_id_atendimento  => v_id
    );
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'ERRO ESPERADO -> %', SQLERRM;
END
$$;

-- deve continuar igual ao "antes" e nao existir atendimento em 2025-06-03
SELECT COUNT(*) AS atendimentos_depois FROM atendimento;
SELECT COUNT(*) AS deve_ser_zero
FROM atendimento
WHERE data_hora = TIMESTAMP '2025-06-03 10:00:00';

ROLLBACK;


-- ---- 1.3 ROLLBACK: procedimento repetido na lista ----
DO $$
DECLARE v_id INT;
BEGIN
    CALL sp_registrar_atendimento_completo(
        TIMESTAMP '2025-06-04 09:00:00', 20, 3, 13, 8, 2,
        '[{"id_procedimento": 2}, {"id_procedimento": 2}]'::JSONB, v_id
    );
EXCEPTION
    WHEN OTHERS THEN RAISE NOTICE 'ERRO ESPERADO -> %', SQLERRM;
END
$$;


-- ---- 1.4 ROLLBACK: procedimento comecando antes da chegada do paciente ----
DO $$
DECLARE v_id INT;
BEGIN
    CALL sp_registrar_atendimento_completo(
        TIMESTAMP '2025-06-05 09:00:00', 20, 3, 13, 8, 2,
        '[{"id_procedimento": 2, "data_hora_inicio": "2025-06-05 08:00:00"}]'::JSONB,
        v_id
    );
EXCEPTION
    WHEN OTHERS THEN RAISE NOTICE 'ERRO ESPERADO -> %', SQLERRM;
END
$$;


-- ---- 1.5 ROLLBACK: paciente inexistente ----
DO $$
DECLARE v_id INT;
BEGIN
    CALL sp_registrar_atendimento_completo(
        TIMESTAMP '2025-06-06 09:00:00', 20, 9999, 13, 8, 2,
        '[{"id_procedimento": 2}]'::JSONB, v_id
    );
EXCEPTION
    WHEN OTHERS THEN RAISE NOTICE 'ERRO ESPERADO -> %', SQLERRM;
END
$$;


-- ---- 1.6 ROLLBACK: lista de procedimentos vazia ----
DO $$
DECLARE v_id INT;
BEGIN
    CALL sp_registrar_atendimento_completo(
        TIMESTAMP '2025-06-07 09:00:00', 20, 3, 13, 8, 2, '[]'::JSONB, v_id
    );
EXCEPTION
    WHEN OTHERS THEN RAISE NOTICE 'ERRO ESPERADO -> %', SQLERRM;
END
$$;


-- 2. sp_calcular_tempo_medio_espera==

SELECT * FROM sp_calcular_tempo_medio_espera();

-- conferencia manual: espera de cada atendimento que entrou na media
SELECT
    u.nome AS unidade,
    a.id_atendimento,
    a.data_hora AS chegada,
    MIN(pr.data_hora_inicio) AS primeiro_procedimento,
    EXTRACT(EPOCH FROM (MIN(pr.data_hora_inicio) - a.data_hora)) / 60 AS espera_min
FROM atendimento a
INNER JOIN unidade u                 ON u.id_unidade = a.id_unidade
INNER JOIN procedimento_realizado pr ON pr.id_atendimento = a.id_atendimento
WHERE pr.data_hora_inicio IS NOT NULL
GROUP BY u.nome, a.id_atendimento, a.data_hora
ORDER BY u.nome, a.id_atendimento;

-- 3. sp_reajustar_escala

-- estado inicial das escalas
SELECT e.id_escala, u.nome AS unidade, e.dia_semana, e.turno, e.id_residente
FROM escala e
INNER JOIN unidade u ON u.id_unidade = e.id_unidade
ORDER BY e.id_escala;


-- ---- 3.1 CAMINHO FELIZ: residente 13 sai de Terca/Noite para Sexta/Manha ----
BEGIN;

CALL sp_reajustar_escala(13, 'Terca', 'Noite', 'Sexta', 'Manha');

SELECT id_escala, dia_semana, turno
FROM escala
WHERE id_residente = 13;

ROLLBACK;


-- ---- 3.2 CONFLITO: residente 12 tem escala em Segunda/Tarde (unidade 1) e
--       tambem em Segunda/Manha (unidade 1, id_escala 6). Mover Tarde -> Manha
--       colidiria. Esperado: erro e nenhuma escala alterada. ----
BEGIN;

DO $$
DECLARE v_qtd INT;
BEGIN
    CALL sp_reajustar_escala(12, 'Segunda', 'Tarde', 'Segunda', 'Manha', v_qtd);
EXCEPTION
    WHEN OTHERS THEN RAISE NOTICE 'ERRO ESPERADO -> %', SQLERRM;
END
$$;

-- a escala 2 deve continuar em Segunda/Tarde
SELECT id_escala, dia_semana, turno
FROM escala
WHERE id_residente = 12
ORDER BY id_escala;

ROLLBACK;


-- ---- 3.3 MULTIPLAS ESCALAS: residente 11 e 12 estao ambos em Segunda/Manha
--       na unidade 1. Mover o residente 12 inteiro para Quarta/Noite move
--       apenas as escalas dele. ----
BEGIN;

CALL sp_reajustar_escala(12, 'Segunda', 'Manha', 'Quarta', 'Noite');

SELECT id_escala, id_residente, dia_semana, turno
FROM escala
WHERE dia_semana IN ('Segunda','Quarta')
ORDER BY id_escala;

ROLLBACK;


-- ---- 3.4 ERROS DE VALIDACAO ----
-- residente inexistente
DO $$
DECLARE v_qtd INT;
BEGIN
    CALL sp_reajustar_escala(9999, 'Segunda', 'Manha', 'Terca', 'Manha', v_qtd);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'ERRO ESPERADO -> %', SQLERRM;
END
$$;

-- dia fora do dominio do CHECK
DO $$
DECLARE v_qtd INT;
BEGIN
    CALL sp_reajustar_escala(11, 'Segunda-feira', 'Manha', 'Terca', 'Manha', v_qtd);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'ERRO ESPERADO -> %', SQLERRM;
END
$$;

-- turno fora do dominio do CHECK
DO $$
DECLARE v_qtd INT;
BEGIN
    CALL sp_reajustar_escala(11, 'Segunda', 'Madrugada', 'Terca', 'Manha', v_qtd);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'ERRO ESPERADO -> %', SQLERRM;
END
$$;

-- origem igual ao destino
DO $$
DECLARE v_qtd INT;
BEGIN
    CALL sp_reajustar_escala(11, 'Segunda', 'Manha', 'Segunda', 'Manha', v_qtd);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'ERRO ESPERADO -> %', SQLERRM;
END
$$;

-- residente sem escala no dia/turno de origem
DO $$
DECLARE v_qtd INT;
BEGIN
    CALL sp_reajustar_escala(11, 'Domingo', 'Noite', 'Sabado', 'Tarde', v_qtd);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'ERRO ESPERADO -> %', SQLERRM;
END
$$;
