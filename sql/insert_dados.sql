-- Etapa 1 - dados de teste
-- 5 pacientes, 5 preceptores, 5 residentes, 4 unidades,
-- 8 procedimentos, 10 atendimentos, 14 procedimentos realizados, 6 escalas

BEGIN;

-- pessoas 1-5 viram pacientes, 6-10 viram preceptores, 11-15 viram residentes
INSERT INTO pessoa (id_pessoa, nome, cpf, data_nascimento, is_flamengo, telefone) VALUES
    (1, 'Ana Beatriz Souza', '11111111111', '1990-03-12', TRUE, '83991110001'),
    (2, 'Carlos Eduardo Lima', '22222222222', '1985-07-25', FALSE, '83991110002'),
    (3, 'Daniela Ferreira Melo', '33333333333', '2001-11-02', FALSE, '83991110003'),
    (4, 'Eduardo Santos Rocha', '44444444444', '1978-01-30', TRUE, '83991110004'),
    (5, 'Fernanda Alves Pinto', '55555555555', '1995-09-18', FALSE, '83991110005'),
    (6, 'Gabriela Nunes', '66666666666', '1970-05-10', TRUE, '83991110006'),
    (7, 'Henrique Barbosa', '77777777777', '1968-12-22', FALSE, '83991110007'),
    (8, 'Isabela Cunha', '88888888888', '1975-04-03', FALSE, '83991110008'),
    (9, 'Joao Pedro Castro', '99999999999', '1972-08-14', TRUE, '83991110009'),
    (10, 'Karina Lopes', '10101010101', '1969-02-27', FALSE, '83991110010'),
    (11, 'Lucas Martins Vieira', '12121212121', '1998-06-08', TRUE, '83991110011'),
    (12, 'Marina Costa Dias', '13131313131', '1999-10-19', FALSE, '83991110012'),
    (13, 'Nathalia Ramos Teixeira', '14141414141', '2000-03-05', FALSE, '83991110013'),
    (14, 'Otavio Almeida Freitas', '15151515151', '1997-12-11', TRUE, '83991110014'),
    (15, 'Paula Cristina Moraes', '16161616161', '2001-01-23', FALSE, '83991110015');

INSERT INTO paciente (id_pessoa, num_convenio, alergias, grupo_sanguineo) VALUES
    (1, 'UNIMED-0001', 'Dipirona', 'O+'),
    (2, 'BRADESCO-0002', NULL, 'A+'),
    (3, NULL, 'Penicilina, Lactose', 'B-'),
    (4, 'HAPVIDA-0004', 'Frutos do mar', 'AB+'),
    (5, 'UNIMED-0005', NULL, 'O-');

INSERT INTO profissional (id_pessoa, crm, data_admissao, especialidade) VALUES
    (6, 'CRM-PB-1006', '2005-02-01', 'Clinica Medica'),
    (7, 'CRM-PB-1007', '2003-08-15', 'Cirurgia Geral'),
    (8, 'CRM-PB-1008', '2010-05-20', 'Pediatria'),
    (9, 'CRM-PB-1009', '2001-09-10', 'Cardiologia'),
    (10, 'CRM-PB-1010', '2007-11-30', 'Ortopedia'),
    (11, 'CRM-PB-2011', '2024-02-01', 'Clinica Medica'),
    (12, 'CRM-PB-2012', '2024-02-01', 'Cirurgia Geral'),
    (13, 'CRM-PB-2013', '2023-02-01', 'Pediatria'),
    (14, 'CRM-PB-2014', '2022-02-01', 'Cardiologia'),
    (15, 'CRM-PB-2015', '2024-02-01', 'Ortopedia');

INSERT INTO preceptor (id_profissional, titulacao) VALUES
    (6, 'Doutor'),
    (7, 'Mestre'),
    (8, 'Doutor'),
    (9, 'Pos-Doutor'),
    (10, 'Especialista');

INSERT INTO residente (id_profissional, ano_residencia) VALUES
    (11, 'R1'),
    (12, 'R1'),
    (13, 'R2'),
    (14, 'R3'),
    (15, 'R1');

INSERT INTO unidade (id_unidade, nome, tipo, capacidade_leitos) VALUES
    (1, 'Enfermaria Central', 'Enfermaria', 40),
    (2, 'UTI Adulto', 'UTI', 10),
    (3, 'Pronto-Socorro 24h', 'Pronto-Socorro', 25),
    (4, 'Ambulatorio Geral', 'Ambulatorio', 0);

INSERT INTO procedimento (id_procedimento, codigo, nome, tempo_medio_minutos, nivel_risco) VALUES
    (1, 'PROC-001', 'Sutura simples', 20, 'MEDIO'),
    (2, 'PROC-002', 'Coleta de sangue', 10, 'BAIXO'),
    (3, 'PROC-003', 'Aplicacao de medicacao', 5, 'BAIXO'),
    (4, 'PROC-004', 'Intubacao orotraqueal', 30, 'ALTO'),
    (5, 'PROC-005', 'Drenagem de abscesso', 40, 'MEDIO'),
    (6, 'PROC-006', 'Puncao lombar', 35, 'ALTO'),
    (7, 'PROC-007', 'Curativo', 15, 'BAIXO'),
    (8, 'PROC-008', 'Reanimacao cardiopulmonar', 25, 'ALTO');

-- todos os atendimentos em maio/2025. a Gabriela (6) supervisiona 6 deles
-- [Etapa 2] coluna id_unidade, distribuida de forma coerente com a escala
INSERT INTO atendimento (id_atendimento, data_hora, duracao_minutos, id_paciente, id_residente, id_preceptor, id_unidade) VALUES
    (1,  '2025-05-02 08:30:00', 45, 1, 11,  6, 1),
    (2,  '2025-05-03 09:15:00', 30, 2, 12,  6, 1),
    (3,  '2025-05-05 10:00:00', 60, 3, 11,  6, 3),
    (4,  '2025-05-08 14:20:00', 25, 1, 13,  6, 2),
    (5,  '2025-05-12 16:45:00', 50, 4, 14,  6, 2),
    (6,  '2025-05-15 11:10:00', 20, 5, 15,  6, 4),
    (7,  '2025-05-18 08:00:00', 35, 2, 12,  7, 3),
    (8,  '2025-05-20 13:30:00', 40, 3, 13,  8, 1),
    (9,  '2025-05-22 15:00:00', 55, 4, 14,  9, 2),
    (10, '2025-05-25 09:40:00', 30, 1, 11, 10, 4);

-- [Etapa 2] coluna data_hora_inicio: o primeiro procedimento de cada
-- atendimento comeca de 5 a 30 min apos a chegada e, dentro do mesmo
-- atendimento, ha 20 min entre um procedimento e o seguinte
INSERT INTO procedimento_realizado (id_atendimento, id_procedimento, quantidade, tempo_real_minutos, data_hora_inicio, observacao, tem_faturamento) VALUES
    (1,  2, 1, 12, '2025-05-02 08:40:00', 'Sem intercorrencias', TRUE),
    (1,  7, 2, 18, '2025-05-02 09:00:00', 'Troca de curativo dupla', FALSE),
    (2,  1, 1, 22, '2025-05-03 09:30:00', 'Sutura em regiao frontal', TRUE),
    (2,  4, 1, 33, '2025-05-03 09:50:00', 'Intubacao com leve dessaturacao', TRUE),
    (3,  3, 3,  6, '2025-05-05 10:20:00', 'Medicacao endovenosa', FALSE),
    (4,  6, 1, 38, '2025-05-08 15:05:00', 'Puncao lombar diagnostica', TRUE),
    (4,  2, 1, 11, '2025-05-08 14:45:00', 'Coleta para hemograma', FALSE),
    (5,  8, 1, 27, '2025-05-12 17:15:00', 'RCP por 4 ciclos', TRUE),
    (6,  7, 1, 14, '2025-05-15 11:15:00', 'Curativo simples', FALSE),
    (7,  1, 2, 25, '2025-05-18 08:10:00', 'Duas suturas', TRUE),
    (7,  5, 1, 42, '2025-05-18 08:30:00', 'Drenagem com anestesia local', TRUE),
    (8,  2, 1, 10, '2025-05-20 13:45:00', 'Coleta de rotina', FALSE),
    (9,  4, 1, 31, '2025-05-22 15:20:00', 'Intubacao eletiva', TRUE),
    (10, 3, 1,  5, '2025-05-25 10:05:00', 'Analgesico aplicado', FALSE);

INSERT INTO escala (id_escala, dia_semana, turno, id_unidade, id_residente, id_preceptor) VALUES
    (1, 'Segunda', 'Manha', 1, 11, 6),
    (2, 'Segunda', 'Tarde', 1, 12, 6),
    (3, 'Terca', 'Noite', 2, 13, 7),
    (4, 'Quarta', 'Manha', 2, 14, 8),
    (5, 'Quinta', 'Tarde', 3, 15, 9),
    (6, 'Segunda', 'Manha', 1, 12, 6);

-- [Etapa 2] os atendimentos acima foram inseridos com id explicito, o que nao
-- avanca a sequencia da IDENTITY. Sem este setval a sp_registrar_atendimento_completo
-- geraria id 1 e colidiria com as linhas ja existentes.
SELECT setval(pg_get_serial_sequence('atendimento', 'id_atendimento'),
              (SELECT MAX(id_atendimento) FROM atendimento));

COMMIT;
