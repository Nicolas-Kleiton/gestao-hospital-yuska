-- Sistema de Gestao Hospitalar Dra. Yuska Maritan Brito
-- Etapa 2 - Item 1: Stored Procedures (PostgreSQL / PL-pgSQL)
-- Requer create_tables.sql e insert_dados.sql (colunas novas marcadas [Etapa 2])


-- ============================================================================
-- 1. sp_registrar_atendimento_completo
-- ============================================================================
-- Registra o atendimento e seus procedimentos em uma unica transacao: se
-- qualquer procedimento falhar, o atendimento tambem nao e gravado.
--
-- p_procedimentos: array JSON, ex. [{"id_procedimento": 2, "quantidade": 1}]
-- so id_procedimento e obrigatorio; quantidade default 1, tem_faturamento default false.
CREATE OR REPLACE PROCEDURE sp_registrar_atendimento_completo(
    IN    p_data_hora        TIMESTAMP,
    IN    p_duracao_minutos  INT,
    IN    p_id_paciente      INT,
    IN    p_id_residente     INT,
    IN    p_id_preceptor     INT,
    IN    p_id_unidade       INT,
    IN    p_procedimentos    JSONB,
    INOUT p_id_atendimento   INT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_total        INT;
    v_inseridos    INT;
    v_nulos        INT;
    v_inexistentes TEXT;
    v_duplicados   TEXT;
    v_antes_chegada INT;
BEGIN
    p_id_atendimento := NULL;

    IF p_data_hora IS NULL THEN
        RAISE EXCEPTION 'data_hora do atendimento e obrigatoria';
    END IF;

    IF p_duracao_minutos IS NOT NULL AND p_duracao_minutos <= 0 THEN
        RAISE EXCEPTION 'duracao_minutos deve ser maior que zero (recebido: %)',
            p_duracao_minutos;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM paciente WHERE id_pessoa = p_id_paciente) THEN
        RAISE EXCEPTION 'Paciente % nao encontrado', p_id_paciente;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM residente WHERE id_profissional = p_id_residente) THEN
        RAISE EXCEPTION 'Residente % nao encontrado', p_id_residente;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM preceptor WHERE id_profissional = p_id_preceptor) THEN
        RAISE EXCEPTION 'Preceptor % nao encontrado', p_id_preceptor;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM unidade WHERE id_unidade = p_id_unidade) THEN
        RAISE EXCEPTION 'Unidade % nao encontrada', p_id_unidade;
    END IF;

    IF p_procedimentos IS NULL OR jsonb_typeof(p_procedimentos) <> 'array' THEN
        RAISE EXCEPTION 'p_procedimentos deve ser um array JSON (recebido: %)',
            COALESCE(jsonb_typeof(p_procedimentos), 'null');
    END IF;

    v_total := jsonb_array_length(p_procedimentos);
    IF v_total = 0 THEN
        RAISE EXCEPTION 'Informe ao menos um procedimento realizado';
    END IF;

    SELECT COUNT(*)
      INTO v_nulos
      FROM jsonb_to_recordset(p_procedimentos) AS j(id_procedimento INT)
     WHERE j.id_procedimento IS NULL;

    IF v_nulos > 0 THEN
        RAISE EXCEPTION '% item(ns) da lista de procedimentos sem "id_procedimento"',
            v_nulos;
    END IF;

    SELECT string_agg(DISTINCT j.id_procedimento::TEXT, ', ')
      INTO v_inexistentes
      FROM jsonb_to_recordset(p_procedimentos) AS j(id_procedimento INT)
     WHERE NOT EXISTS (
               SELECT 1 FROM procedimento p
                WHERE p.id_procedimento = j.id_procedimento
           );

    IF v_inexistentes IS NOT NULL THEN
        RAISE EXCEPTION 'Procedimento(s) inexistente(s) no catalogo: %', v_inexistentes;
    END IF;

    -- repetido violaria a PK composta (id_atendimento, id_procedimento)
    SELECT string_agg(d.id_procedimento::TEXT, ', ')
      INTO v_duplicados
      FROM (
            SELECT j.id_procedimento
              FROM jsonb_to_recordset(p_procedimentos) AS j(id_procedimento INT)
             GROUP BY j.id_procedimento
            HAVING COUNT(*) > 1
           ) d;

    IF v_duplicados IS NOT NULL THEN
        RAISE EXCEPTION 'Procedimento(s) repetido(s) na lista: %. Use o campo "quantidade" no lugar de repetir o item.',
            v_duplicados;
    END IF;

    SELECT COUNT(*)
      INTO v_antes_chegada
      FROM jsonb_to_recordset(p_procedimentos) AS j(data_hora_inicio TIMESTAMP)
     WHERE j.data_hora_inicio IS NOT NULL
       AND j.data_hora_inicio < p_data_hora;

    IF v_antes_chegada > 0 THEN
        RAISE EXCEPTION '% procedimento(s) com data_hora_inicio anterior a chegada do paciente (%)',
            v_antes_chegada, p_data_hora;
    END IF;

    INSERT INTO atendimento (data_hora, duracao_minutos,
                             id_paciente, id_residente, id_preceptor, id_unidade)
    VALUES (p_data_hora, p_duracao_minutos,
            p_id_paciente, p_id_residente, p_id_preceptor, p_id_unidade)
    RETURNING id_atendimento INTO p_id_atendimento;

    INSERT INTO procedimento_realizado (
        id_atendimento, id_procedimento, quantidade,
        tempo_real_minutos, data_hora_inicio, observacao, tem_faturamento
    )
    SELECT
        p_id_atendimento,
        j.id_procedimento,
        COALESCE(j.quantidade, 1),
        j.tempo_real_minutos,
        j.data_hora_inicio,
        j.observacao,
        COALESCE(j.tem_faturamento, FALSE)
    FROM jsonb_to_recordset(p_procedimentos) AS j(
        id_procedimento    INT,
        quantidade         INT,
        tempo_real_minutos INT,
        data_hora_inicio   TIMESTAMP,
        observacao         TEXT,
        tem_faturamento    BOOLEAN
    );

    GET DIAGNOSTICS v_inseridos = ROW_COUNT;

    RAISE NOTICE 'Atendimento % registrado com % procedimento(s).',
        p_id_atendimento, v_inseridos;

EXCEPTION
    WHEN OTHERS THEN
        -- bloco EXCEPTION = subtransacao: erro aqui desfaz o INSERT do atendimento tambem
        p_id_atendimento := NULL;
        RAISE EXCEPTION 'Falha ao registrar atendimento completo: % (SQLSTATE %). Nada foi gravado.',
            SQLERRM, SQLSTATE;
END;
$$;


-- ============================================================================
-- 2. sp_calcular_tempo_medio_espera
-- ============================================================================
-- Tempo medio, por unidade, entre a chegada do paciente e o inicio do
-- primeiro procedimento do atendimento.
--
-- FUNCTION (nao PROCEDURE) porque so funcao pode RETURNS TABLE / ser usada em SELECT.
CREATE OR REPLACE FUNCTION sp_calcular_tempo_medio_espera()
RETURNS TABLE (
    id_unidade                 INT,
    nome_unidade               VARCHAR(100),
    atendimentos_considerados  BIGINT,
    tempo_medio_espera_minutos NUMERIC
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH espera_por_atendimento AS (
        SELECT
            a.id_atendimento,
            a.id_unidade,
            (EXTRACT(EPOCH FROM (MIN(pr.data_hora_inicio) - a.data_hora)) / 60.0)::NUMERIC
                AS espera_minutos
        FROM atendimento a
        INNER JOIN procedimento_realizado pr ON pr.id_atendimento = a.id_atendimento
        WHERE pr.data_hora_inicio IS NOT NULL
        GROUP BY a.id_atendimento, a.id_unidade, a.data_hora
        HAVING MIN(pr.data_hora_inicio) >= a.data_hora  -- descarta inicio antes da chegada
    )
    SELECT
        u.id_unidade,
        u.nome,
        COUNT(e.id_atendimento),
        ROUND(AVG(e.espera_minutos), 1)
    FROM unidade u
    LEFT OUTER JOIN espera_por_atendimento e ON e.id_unidade = u.id_unidade  -- unidade sem atendimento nao some
    GROUP BY u.id_unidade, u.nome
    ORDER BY AVG(e.espera_minutos) DESC NULLS LAST, u.nome;
END;
$$;


-- ============================================================================
-- 3. sp_reajustar_escala
-- ============================================================================
-- Move todas as escalas de um residente de um dia/turno para outro.
-- So executa se nada colidir com a UNIQUE (id_unidade, dia_semana, turno, id_residente);
-- havendo qualquer conflito, nenhuma escala e movida.
CREATE OR REPLACE PROCEDURE sp_reajustar_escala(
    IN    p_id_residente    INT,
    IN    p_dia_origem      VARCHAR,
    IN    p_turno_origem    VARCHAR,
    IN    p_dia_destino     VARCHAR,
    IN    p_turno_destino   VARCHAR,
    INOUT p_escalas_movidas INT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    c_dias   CONSTANT TEXT[] := ARRAY['Segunda','Terca','Quarta','Quinta',
                                      'Sexta','Sabado','Domingo'];
    c_turnos CONSTANT TEXT[] := ARRAY['Manha','Tarde','Noite'];
    v_conflitos TEXT;
BEGIN
    p_escalas_movidas := 0;

    IF NOT EXISTS (SELECT 1 FROM residente WHERE id_profissional = p_id_residente) THEN
        RAISE EXCEPTION 'Residente % nao encontrado', p_id_residente;
    END IF;

    IF p_dia_origem IS NULL OR NOT (p_dia_origem = ANY (c_dias)) THEN
        RAISE EXCEPTION 'Dia de origem invalido: %. Valores aceitos: %',
            COALESCE(p_dia_origem, 'NULL'), array_to_string(c_dias, ', ');
    END IF;

    IF p_dia_destino IS NULL OR NOT (p_dia_destino = ANY (c_dias)) THEN
        RAISE EXCEPTION 'Dia de destino invalido: %. Valores aceitos: %',
            COALESCE(p_dia_destino, 'NULL'), array_to_string(c_dias, ', ');
    END IF;

    IF p_turno_origem IS NULL OR NOT (p_turno_origem = ANY (c_turnos)) THEN
        RAISE EXCEPTION 'Turno de origem invalido: %. Valores aceitos: %',
            COALESCE(p_turno_origem, 'NULL'), array_to_string(c_turnos, ', ');
    END IF;

    IF p_turno_destino IS NULL OR NOT (p_turno_destino = ANY (c_turnos)) THEN
        RAISE EXCEPTION 'Turno de destino invalido: %. Valores aceitos: %',
            COALESCE(p_turno_destino, 'NULL'), array_to_string(c_turnos, ', ');
    END IF;

    IF p_dia_origem = p_dia_destino AND p_turno_origem = p_turno_destino THEN
        RAISE EXCEPTION 'Origem e destino sao o mesmo dia/turno (%/%); nada a reajustar',
            p_dia_origem, p_turno_origem;
    END IF;

    -- verifica conflito antes do UPDATE; dest.id_escala <> orig.id_escala evita
    -- que a propria escala sendo movida conte como conflito com ela mesma
    SELECT string_agg(DISTINCT u.nome, ', ' ORDER BY u.nome)
      INTO v_conflitos
      FROM escala orig
      INNER JOIN unidade u ON u.id_unidade = orig.id_unidade
     WHERE orig.id_residente = p_id_residente
       AND orig.dia_semana   = p_dia_origem
       AND orig.turno        = p_turno_origem
       AND EXISTS (
               SELECT 1
                 FROM escala dest
                WHERE dest.id_residente = p_id_residente
                  AND dest.id_unidade   = orig.id_unidade
                  AND dest.dia_semana   = p_dia_destino
                  AND dest.turno        = p_turno_destino
                  AND dest.id_escala   <> orig.id_escala
           );

    IF v_conflitos IS NOT NULL THEN
        RAISE EXCEPTION 'Conflito de escala: o residente % ja esta escalado em %/% na(s) unidade(s): %. Nenhuma escala foi alterada.',
            p_id_residente, p_dia_destino, p_turno_destino, v_conflitos;
    END IF;

    UPDATE escala
       SET dia_semana = p_dia_destino,
           turno      = p_turno_destino
     WHERE id_residente = p_id_residente
       AND dia_semana   = p_dia_origem
       AND turno        = p_turno_origem;

    GET DIAGNOSTICS p_escalas_movidas = ROW_COUNT;

    IF p_escalas_movidas = 0 THEN
        RAISE EXCEPTION 'Residente % nao possui escalas em %/%. Nada foi alterado.',
            p_id_residente, p_dia_origem, p_turno_origem;
    END IF;

    RAISE NOTICE '% escala(s) do residente % movida(s) de %/% para %/%.',
        p_escalas_movidas, p_id_residente,
        p_dia_origem, p_turno_origem, p_dia_destino, p_turno_destino;
END;
$$;
