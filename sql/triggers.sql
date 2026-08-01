-- Sistema de Gestao Hospitalar Dra. Yuska Maritan Brito
-- Etapa 2 - Item 2: Triggers (PostgreSQL / PL-pgSQL)
--
-- Pre-requisito: create_tables.sql, insert_dados.sql e stored_procedures.sql
-- Pre-execucao:
--   psql -f create_tables.sql
--   psql -f insert_dados.sql
--   psql -f stored_procedures.sql
--   psql -f triggers.sql


-- ============================================================================
-- EXTENSOES DE SCHEMA
-- Necessarias para as triggers 2 e 3. IF NOT EXISTS garante idempotencia.
-- ============================================================================

-- Tabela de auditoria criada aqui pois nao existia no schema original.
CREATE TABLE IF NOT EXISTS auditoria_atendimento (
    id_auditoria   SERIAL PRIMARY KEY,
    id_atendimento INT,
    operacao       VARCHAR(6) NOT NULL CHECK (operacao IN ('INSERT','UPDATE','DELETE')),
    usuario        TEXT       NOT NULL,
    data_hora      TIMESTAMP  NOT NULL DEFAULT now(),
    dados_antigos  JSONB,  -- NULL em INSERT
    dados_novos    JSONB   -- NULL em DELETE
);

-- Coluna calculada pela trigger 3; ausente no schema original.
ALTER TABLE procedimento
    ADD COLUMN IF NOT EXISTS media_tempo_procedimento NUMERIC;


-- ============================================================================
-- trg_check_sobreposicao_escala
-- ============================================================================
-- BEFORE INSERT OR UPDATE em ESCALA.
-- Impede que um residente seja escalado no mesmo dia_semana/turno em duas
-- unidades distintas -- caso que a UNIQUE (id_unidade, dia_semana, turno,
-- id_residente) nao cobre, pois ela so bloqueia duplicatas dentro da MESMA
-- unidade.
--
-- No UPDATE, a clausula id_escala <> NEW.id_escala exclui o proprio registro
-- da busca; sem ela, qualquer UPDATE dispararia falso positivo contra si mesmo.
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_check_sobreposicao_escala()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_unidade_conflito TEXT;
BEGIN
    SELECT u.nome
      INTO v_unidade_conflito
      FROM escala e
      INNER JOIN unidade u ON u.id_unidade = e.id_unidade
     WHERE e.id_residente = NEW.id_residente
       AND e.dia_semana   = NEW.dia_semana
       AND e.turno        = NEW.turno
       AND e.id_unidade  <> NEW.id_unidade
       AND e.id_escala   <> NEW.id_escala
     LIMIT 1;

    IF v_unidade_conflito IS NOT NULL THEN
        RAISE EXCEPTION
            'Sobreposicao de escala: residente % ja esta em %/% na unidade "%".',
            NEW.id_residente, NEW.dia_semana, NEW.turno, v_unidade_conflito;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_sobreposicao_escala ON escala;

CREATE TRIGGER trg_check_sobreposicao_escala
    BEFORE INSERT OR UPDATE
    ON escala
    FOR EACH ROW
    EXECUTE FUNCTION fn_check_sobreposicao_escala();


-- ============================================================================
-- trg_audita_atendimento
-- ============================================================================
-- AFTER INSERT OR UPDATE OR DELETE em ATENDIMENTO.
-- Grava um registro em AUDITORIA_ATENDIMENTO a cada operacao DML, com
-- snapshot JSONB do estado anterior (dados_antigos) e posterior (dados_novos).
--
-- Campo "usuario": usa CURRENT_USER (usuario de conexao do PostgreSQL) por
-- falta de mecanismo de autenticacao de aplicacao no schema atual. Numa
-- implantacao real, substituir por:
--   current_setting('app.usuario', true)
-- populado via SET LOCAL app.usuario = '...' antes de cada operacao.
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_audita_atendimento()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO auditoria_atendimento
            (id_atendimento, operacao, usuario, dados_antigos, dados_novos)
        VALUES
            (NEW.id_atendimento, 'INSERT', CURRENT_USER,
             NULL, row_to_json(NEW)::JSONB);
        RETURN NEW;

    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO auditoria_atendimento
            (id_atendimento, operacao, usuario, dados_antigos, dados_novos)
        VALUES
            (NEW.id_atendimento, 'UPDATE', CURRENT_USER,
             row_to_json(OLD)::JSONB, row_to_json(NEW)::JSONB);
        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO auditoria_atendimento
            (id_atendimento, operacao, usuario, dados_antigos, dados_novos)
        VALUES
            (OLD.id_atendimento, 'DELETE', CURRENT_USER,
             row_to_json(OLD)::JSONB, NULL);
        RETURN OLD;
    END IF;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_audita_atendimento ON atendimento;

CREATE TRIGGER trg_audita_atendimento
    AFTER INSERT OR UPDATE OR DELETE
    ON atendimento
    FOR EACH ROW
    EXECUTE FUNCTION fn_audita_atendimento();


-- ============================================================================
-- trg_atualiza_media_procedimentos
-- ============================================================================
-- AFTER INSERT em PROCEDIMENTO_REALIZADO.
-- Recalcula AVG(tempo_real_minutos) de todos os registros do procedimento
-- recem-inserido e atualiza procedimento.media_tempo_procedimento.
--
-- AVG em vez de calculo incremental: evita deriva de arredondamento acumulada
-- ao longo de muitos registros.
--
-- Escopo limitado a INSERT conforme enunciado. Para cobrir UPDATE/DELETE
-- futuramente: adicionar OR UPDATE OR DELETE ao CREATE TRIGGER e usar
-- COALESCE(NEW.id_procedimento, OLD.id_procedimento) como chave.
--
-- NULLs em tempo_real_minutos sao ignorados automaticamente pelo AVG.
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_atualiza_media_procedimentos()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_nova_media NUMERIC;
BEGIN
    SELECT AVG(pr.tempo_real_minutos)
      INTO v_nova_media
      FROM procedimento_realizado pr
     WHERE pr.id_procedimento = NEW.id_procedimento;

    UPDATE procedimento
       SET media_tempo_procedimento = v_nova_media
     WHERE id_procedimento = NEW.id_procedimento;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_atualiza_media_procedimentos ON procedimento_realizado;

CREATE TRIGGER trg_atualiza_media_procedimentos
    AFTER INSERT
    ON procedimento_realizado
    FOR EACH ROW
    EXECUTE FUNCTION fn_atualiza_media_procedimentos();


-- ============================================================================
-- TESTES MINIMOS
-- ============================================================================


-- ----------------------------------------------------------------------------
-- trg_check_sobreposicao_escala
-- Residente 14 ja esta em Quarta/Manha na unidade 2 (id_escala = 4).
-- Inserir na unidade 1 no mesmo horario deve ser bloqueado.
-- ----------------------------------------------------------------------------

-- 1a: deve lancar excecao
DO $$
BEGIN
    INSERT INTO escala (id_escala, dia_semana, turno, id_unidade, id_residente, id_preceptor)
    VALUES (99, 'Quarta', 'Manha', 1, 14, 6);
    RAISE NOTICE 'FALHA: insercao deveria ter sido bloqueada';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'OK [1a] - excecao esperada: %', SQLERRM;
END;
$$;

-- 1b: residente 15 sem escala em Quarta/Manha -- deve passar
BEGIN;
INSERT INTO escala (id_escala, dia_semana, turno, id_unidade, id_residente, id_preceptor)
VALUES (100, 'Quarta', 'Manha', 4, 15, 10);
SELECT id_escala, dia_semana, turno, id_unidade, id_residente FROM escala WHERE id_escala = 100;
ROLLBACK;

-- 1c: UPDATE no proprio registro nao deve gerar falso positivo
DO $$
BEGIN
    UPDATE escala SET id_preceptor = 7 WHERE id_escala = 4;
    UPDATE escala SET id_preceptor = 8 WHERE id_escala = 4;  -- reverte
    RAISE NOTICE 'OK [1c] - UPDATE na propria escala sem falso positivo';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'FALHA [1c] - falso positivo: %', SQLERRM;
END;
$$;


-- ----------------------------------------------------------------------------
-- trg_audita_atendimento
-- INSERT + UPDATE + DELETE em ATENDIMENTO; esperado: 3 linhas em auditoria.
-- ----------------------------------------------------------------------------

DO $$
DECLARE
    v_id  INT;
    v_cnt INT;
BEGIN
    INSERT INTO atendimento (data_hora, duracao_minutos, id_paciente, id_residente, id_preceptor, id_unidade)
    VALUES (TIMESTAMP '2026-01-10 10:00:00', 30, 1, 11, 6, 1)
    RETURNING id_atendimento INTO v_id;

    UPDATE atendimento SET duracao_minutos = 45 WHERE id_atendimento = v_id;
    DELETE FROM atendimento WHERE id_atendimento = v_id;

    SELECT COUNT(*) INTO v_cnt FROM auditoria_atendimento WHERE id_atendimento = v_id;

    IF v_cnt = 3 THEN
        RAISE NOTICE 'OK [2] - 3 registros de auditoria para id_atendimento = %', v_id;
    ELSE
        RAISE NOTICE 'FALHA [2] - esperado 3, encontrado %', v_cnt;
    END IF;
END;
$$;

-- Conferencia visual
SELECT id_auditoria, id_atendimento, operacao, usuario, data_hora,
       dados_antigos IS NOT NULL AS tem_antigos,
       dados_novos   IS NOT NULL AS tem_novos
  FROM auditoria_atendimento
 ORDER BY id_auditoria DESC
 LIMIT 3;

-- Limpeza dos registros de teste
DELETE FROM auditoria_atendimento
 WHERE id_auditoria IN (
     SELECT id_auditoria FROM auditoria_atendimento ORDER BY id_auditoria DESC LIMIT 3
 );


-- ----------------------------------------------------------------------------
-- trg_atualiza_media_procedimentos
-- id_procedimento = 2 (Coleta de sangue) tem tempo_real_minutos 12, 11, 10
-- nos dados iniciais. Inserir tempo = 9 deve resultar em AVG = 10.5.
-- ----------------------------------------------------------------------------

BEGIN;

SELECT id_procedimento, nome, media_tempo_procedimento AS media_antes
  FROM procedimento WHERE id_procedimento = 2;

-- atendimento temporario para satisfazer a FK
INSERT INTO atendimento (data_hora, duracao_minutos, id_paciente, id_residente, id_preceptor, id_unidade)
VALUES (TIMESTAMP '2026-02-01 09:00:00', 20, 2, 12, 7, 4)
RETURNING id_atendimento;

INSERT INTO procedimento_realizado
    (id_atendimento, id_procedimento, quantidade, tempo_real_minutos, tem_faturamento)
SELECT id_atendimento, 2, 1, 9, FALSE
  FROM atendimento
 WHERE data_hora = TIMESTAMP '2026-02-01 09:00:00'
 LIMIT 1;

-- media_depois deve ser 10.5
SELECT id_procedimento, nome, media_tempo_procedimento AS media_depois
  FROM procedimento WHERE id_procedimento = 2;

ROLLBACK;


-- ============================================================================
-- FIM DO ARQUIVO triggers.sql
-- ============================================================================
