-- Sistema de Gestao Hospitalar Dra. Yuska Maritan Brito
-- Etapa 1 - CRUD e consultas basicas


-- inserir novo atendimento (so insere se paciente, residente e preceptor existem)
INSERT INTO atendimento (id_atendimento, data_hora, duracao_minutos,
                         id_paciente, id_residente, id_preceptor)
SELECT
    (SELECT COALESCE(MAX(id_atendimento), 0) + 1 FROM atendimento),
    TIMESTAMP '2025-05-28 09:30:00',
    40,
    1,
    11,
    6
WHERE EXISTS (SELECT 1 FROM paciente  WHERE id_pessoa       = 1)
  AND EXISTS (SELECT 1 FROM residente WHERE id_profissional = 11)
  AND EXISTS (SELECT 1 FROM preceptor WHERE id_profissional = 6)
RETURNING id_atendimento;


-- listar os atendimentos de um paciente, ordenados por data
SELECT
    a.id_atendimento,
    a.data_hora,
    a.duracao_minutos,
    pe_res.nome AS residente,
    pe_pre.nome AS preceptor
FROM atendimento a
JOIN residente r      ON r.id_profissional = a.id_residente
JOIN pessoa    pe_res ON pe_res.id_pessoa  = r.id_profissional
JOIN preceptor p      ON p.id_profissional = a.id_preceptor
JOIN pessoa    pe_pre ON pe_pre.id_pessoa  = p.id_profissional
WHERE a.id_paciente = 1
ORDER BY a.data_hora;


-- listar os procedimentos realizados em um atendimento
SELECT
    proc.nome AS procedimento,
    pr.quantidade,
    pr.tempo_real_minutos,
    pr.observacao
FROM procedimento_realizado pr
JOIN procedimento proc ON proc.id_procedimento = pr.id_procedimento
WHERE pr.id_atendimento = 1
ORDER BY proc.nome;


-- atualizar dados do paciente (convenio em paciente, telefone em pessoa)
UPDATE paciente
SET num_convenio = 'UNIMED-9999'
WHERE id_pessoa = 1;

UPDATE pessoa
SET telefone = '83999990001'
WHERE id_pessoa = 1
  AND EXISTS (SELECT 1 FROM paciente WHERE id_pessoa = 1);


-- remover procedimento realizado, so se ainda nao tiver faturamento
DELETE FROM procedimento_realizado
WHERE id_atendimento  = 1
  AND id_procedimento = 7
  AND tem_faturamento = FALSE;


-- tempo medio de duracao dos atendimentos por residente
SELECT
    r.id_profissional AS id_residente,
    pe.nome           AS residente,
    COUNT(a.id_atendimento) AS total_atendimentos,
    ROUND(AVG(a.duracao_minutos), 1) AS media_duracao_min
FROM residente r
JOIN pessoa pe          ON pe.id_pessoa = r.id_profissional
LEFT JOIN atendimento a ON a.id_residente = r.id_profissional
GROUP BY r.id_profissional, pe.nome
ORDER BY media_duracao_min DESC NULLS LAST;
