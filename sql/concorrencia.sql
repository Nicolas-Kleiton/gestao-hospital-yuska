-- Sistema de Gestao Hospitalar Dra. Yuska Maritan Brito
-- Etapa 2 - Item 6: Concorrencia e Transacoes (PostgreSQL)
--
-- Pre-requisito: create_tables.sql, insert_dados.sql
-- Execucao: psql -f sql/concorrencia.sql

-- Coluna de controle de versao usada pelo lock otimista do SQLAlchemy
-- (version_id_col em Escala, app/models.py). Cada UPDATE bem-sucedido
-- incrementa version_id; se duas transacoes lerem a mesma versao e so uma
-- conseguir comitar primeiro, a ORM detecta a divergencia e rejeita a outra
-- com StaleDataError, sem travar ninguem.
ALTER TABLE escala
    ADD COLUMN IF NOT EXISTS version_id INT NOT NULL DEFAULT 1;
