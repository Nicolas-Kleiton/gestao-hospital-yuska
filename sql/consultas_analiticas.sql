-- Sistema de Gestao Hospitalar Dra. Yuska Maritan Brito
-- Etapa 1 - Item 4: Consultas Analíticas


--  Ranking de atendimentos por residente
-- Inclui residentes sem histórico de atendimento via LEFT JOIN.
SELECT 
    p.nome AS nome_residente, 
    COUNT(a.id_atendimento) AS total_atendimentos
FROM residente r
JOIN profissional prof ON r.id_profissional = prof.id_pessoa
JOIN pessoa p ON prof.id_pessoa = p.id_pessoa
LEFT JOIN atendimento a ON r.id_profissional = a.id_residente
GROUP BY r.id_profissional, p.nome
ORDER BY total_atendimentos DESC, p.nome;


-- Preceptores com volume de supervisão acima da cota mensal (5)
-- Filtros de período isolados em CTE para facilitar a manutenção da query.
WITH parametros AS (
    SELECT 5 AS mes_filtro, 2025 AS ano_filtro
)
SELECT 
    p.nome AS nome_preceptor, 
    COUNT(a.id_atendimento) AS total_atendimentos
FROM preceptor prec
JOIN profissional prof ON prec.id_profissional = prof.id_pessoa
JOIN pessoa p ON prof.id_pessoa = p.id_pessoa
JOIN atendimento a ON prec.id_profissional = a.id_preceptor
CROSS JOIN parametros param
WHERE EXTRACT(MONTH FROM a.data_hora) = param.mes_filtro 
  AND EXTRACT(YEAR FROM a.data_hora) = param.ano_filtro
GROUP BY prec.id_profissional, p.nome
HAVING COUNT(a.id_atendimento) > 5;


-- Carga horária fixa (plantões/mês) por residente agrupada por unidade
-- Baseado na grade semanal padrão vigente (tabela ESCALA).
SELECT 
    u.nome AS nome_unidade,
    p.nome AS nome_residente,
    COUNT(e.id_escala) AS quantidade_plantoes
FROM unidade u
JOIN escala e ON u.id_unidade = e.id_unidade
JOIN residente r ON e.id_residente = r.id_profissional
JOIN pessoa p ON r.id_profissional = p.id_pessoa
GROUP BY u.id_unidade, u.nome, r.id_profissional, p.nome
ORDER BY u.nome, p.nome;

-- Pacientes isentos de procedimentos de alto risco
-- Extensão de schema: Adição idempotente da coluna nivel_risco.
ALTER TABLE procedimento ADD COLUMN IF NOT EXISTS nivel_risco VARCHAR(10);

-- Seed inicial de classificação de risco (TODO: migrar mapeamento para código TUSS/CBHPM)
UPDATE procedimento
SET nivel_risco = CASE 
    WHEN nome ILIKE '%Sutura%' THEN 'ALTO'
    WHEN nome ILIKE '%Intubacao%' THEN 'ALTO'
    WHEN nome ILIKE '%Puncao%' THEN 'ALTO'
    WHEN nome ILIKE '%Reanimacao%' THEN 'ALTO'
    WHEN nome ILIKE '%Drenagem%' THEN 'MEDIO'
    ELSE 'BAIXO'
END;

-- Filtro de exclusão de pacientes via anti-join (NOT EXISTS)
SELECT 
    p.nome AS nome_paciente,
    pac.num_convenio
FROM paciente pac
JOIN pessoa p ON pac.id_pessoa = p.id_pessoa
WHERE NOT EXISTS (
    SELECT 1
    FROM atendimento a
    JOIN procedimento_realizado pr ON a.id_atendimento = pr.id_atendimento
    JOIN procedimento proc ON pr.id_procedimento = proc.id_procedimento
    WHERE a.id_paciente = pac.id_pessoa
      AND proc.nivel_risco = 'ALTO'
)
ORDER BY p.nome;
