-- Sistema de Gestao Hospitalar Dra. Yuska Maritan Brito
-- Etapa 2 - Item 2: Triggers (PostgreSQL / PL-pgSQL)
--
-- Pre-requisito: create_tables.sql, insert_dados.sql e stored_procedures.sql
-- Pre-execucao:
--   psql -f create_tables.sql
--   psql -f insert_dados.sql
--   psql -f stored_procedures.sql
--   psql -f triggers.sql


-- EXTENSOES DE SCHEMA
-- Necessarias para as triggers 2 e 3. IF NOT EXISTS garante idempotencia.

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


-- trg_check_sobreposicao_escala

-- BEFORE INSERT OR UPDATE em ESCALA.
-- Impede que um residente seja escalado no mesmo dia_semana/turno em duas
-- unidades distintas -- caso que a UNIQUE (id_unidade, dia_semana, turno,
-- id_residente) nao cobre, pois ela so bloqueia duplicatas dentro da MESMA
-- unidade.
--
-- No UPDATE, a clausula id_escala <> NEW.id_escala exclui o proprio registro
-- da busca; sem ela, qualquer UPDATE dispararia falso positivo contra si mesmo.

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


-- trg_audita_atendimento

-- AFTER INSERT OR UPDATE OR DELETE em ATENDIMENTO.
-- Grava um registro em AUDITORIA_ATENDIMENTO a cada operacao DML, com
-- snapshot JSONB do estado anterior (dados_antigos) e posterior (dados_novos).
--
-- Campo "usuario": usa CURRENT_USER (usuario de conexao do PostgreSQL) por
-- falta de mecanismo de autenticacao de aplicacao no schema atual. Numa
-- implantacao real, substituir por:
--   current_setting('app.usuario', true)
-- populado via SET LOCAL app.usuario = '...' antes de cada operacao.

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


-- trg_atualiza_media_procedimentos

-- AFTER INSERT em PROCEDIMENTO_REALIZADO.
-- Recalcula AVG(tempo_real_minutos) de todos os registros do procedimento
-- recem-inserido e atualiza procedimento.media_tempo_procedimento.

-- AVG em vez de calculo incremental: evita deriva de arredondamento acumulada
-- ao longo de muitos registros.

-- Escopo limitado a INSERT conforme enunciado. Para cobrir UPDATE/DELETE
-- futuramente: adicionar OR UPDATE OR DELETE ao CREATE TRIGGER e usar
-- COALESCE(NEW.id_procedimento, OLD.id_procedimento) como chave.

-- NULLs em tempo_real_minutos sao ignorados automaticamente pelo AVG.

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

