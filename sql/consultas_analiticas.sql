-- Sistema de Gestao Hospitalar Dra. Yuska Maritan Brito
-- Etapa 1 - Item 4: Consultas Analíticas

-- ==============================================================================
-- 1. Ranking dos residentes por número de atendimentos realizados
-- ==============================================================================
-- Utiliza LEFT JOIN a partir de residente (e suas tabelas base profissional/pessoa)
-- para garantir que residentes com 0 atendimentos apareçam na lista.
SELECT 
    p.nome AS nome_residente, 
    COUNT(a.id_atendimento) AS total_atendimentos
FROM residente r
JOIN profissional prof ON r.id_profissional = prof.id_pessoa
JOIN pessoa p ON prof.id_pessoa = p.id_pessoa
LEFT JOIN atendimento a ON r.id_profissional = a.id_residente
GROUP BY r.id_profissional, p.nome
ORDER BY total_atendimentos DESC, p.nome;


-- ==============================================================================
-- 2. Preceptores que supervisionaram mais de 5 atendimentos em um determinado mês
-- ==============================================================================
-- Utilizamos uma CTE (parametros) no topo para isolar e parametrizar o mês e o ano.
-- Filtramos usando HAVING COUNT(a.id_atendimento) > 5.
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


-- ==============================================================================
-- 3. Para cada unidade, quantidade de plantões escalados por residente no mês corrente
-- ==============================================================================
/*
 * ABORDAGEM ESCOLHIDA: Opção (a)
 * Justificativa: A tabela ESCALA modela a grade padrão semanal da unidade.
 * Como não há datas específicas, interpretar "no mês corrente" como "a escala 
 * vigente estrutural" permite contar a carga horária/plantões fixos do residente,
 * mantendo a complexidade adequada para a Etapa 1 sem necessitar de novas tabelas.
 */
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


-- ==============================================================================
-- 4. Pacientes que nunca realizaram nenhum procedimento de nível de risco 'ALTO'
-- ==============================================================================
/* 
 * EXTENSÃO PONTUAL DO SCHEMA PARA A QUERY 4 
 * Obs: O comando ALTER TABLE ... ADD COLUMN IF NOT EXISTS atua como uma 
 * salvaguarda idempotente para adicionar a coluna 'nivel_risco'. Caso ela 
 * já exista no banco, o comando é ignorado sem causar erros, garantindo 
 * que a query e o posterior UPDATE sejam executados com segurança.
 */
ALTER TABLE procedimento ADD COLUMN IF NOT EXISTS nivel_risco VARCHAR(10);

-- UPDATE de exemplo para classificar os procedimentos já existentes de forma coerente.
UPDATE procedimento
SET nivel_risco = CASE 
    WHEN nome ILIKE '%Sutura%' THEN 'ALTO'
    WHEN nome ILIKE '%Intubacao%' THEN 'ALTO'
    WHEN nome ILIKE '%Puncao%' THEN 'ALTO'
    WHEN nome ILIKE '%Reanimacao%' THEN 'ALTO'
    WHEN nome ILIKE '%Drenagem%' THEN 'MEDIO'
    ELSE 'BAIXO'
END;

-- Consulta em si (utilizando NOT EXISTS)
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
