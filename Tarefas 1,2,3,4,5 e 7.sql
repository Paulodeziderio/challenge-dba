-- Tarefas 1 e 2: Códigos SQL

-- -----------------------------------------------------
-- Schema tenants
-- -----------------------------------------------------
CREATE DATABASE tenants TEMPLATE template1

/c tenant

-- -----------------------------------------------------
-- Table `tenants`.`tenant`
-- -----------------------------------------------------
CREATE TABLE `tenants`.`tenant` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(100) NOT NULL,
  `description` VARCHAR(255) NULL,
  
  PRIMARY KEY (`id`)
  );


-- -----------------------------------------------------
-- Table `tenants`.`person`
-- -----------------------------------------------------
CREATE TABLE `tenants`.`person` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(100) NOT NULL,
  `birth_date` DATE NOT NULL,
  `metadata` JSONB NOT NULL,
  
  PRIMARY KEY (`id`)
  );


-- -----------------------------------------------------
-- Table `tenants`.`institution`
-- -----------------------------------------------------
CREATE TABLE `tenants`.`institution` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `tenant_id` INT NOT NULL,
  `name` VARCHAR(100) NOT NULL,
  `location` VARCHAR(100) NOT NULL,
  `details` JSONB NOT NULL,
  
  PRIMARY KEY (`id`),
  
  INDEX `fk_institution_1_idx` (`tenant_id` ASC),
  CONSTRAINT `fk_institution_1` FOREIGN KEY (`tenant_id`) REFERENCES `tenants`.`tenant` (`id`)
    );


-- -----------------------------------------------------
-- Table `tenants`.`course`
-- -----------------------------------------------------
CREATE TABLE `tenants`.`course` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `tenant_id` INT NOT NULL,
  `institution_id` INT NOT NULL,
  `name` VARCHAR(100) NOT NULL,
  `duration` INT NOT NULL,
  `details` JSONB NOT NULL,
  
  PRIMARY KEY (`id`),
  
  INDEX `fk_course_1_idx` (`tenant_id` ASC),
  INDEX `fk_course_2_idx` (`institution_id` ASC),
  
  CONSTRAINT `fk_course_1` FOREIGN KEY (`tenant_id`) REFERENCES `tenants`.`tenant` (`id`),
  CONSTRAINT `fk_course_2` FOREIGN KEY (`institution_id`) REFERENCES `tenants`.`institution` (`id`)
    );


-- -----------------------------------------------------
-- Table `tenants`.`enrollment`
-- -----------------------------------------------------
CREATE TABLE `tenants`.`enrollment` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `tenant_id` INT NOT NULL,
  `institution_id` INT,
  `person_id` INT NOT NULL,
  `enrollment_date` DATE NOT NULL,
  `status` VARCHAR(20) NOT NULL,
  
  PRIMARY KEY (`id`),
  
  INDEX `fk_enrollment_1_idx` (`tenant_id` ASC),
  INDEX `fk_enrollment_2_idx` (`institution_id` ASC),
  INDEX `fk_enrollment_3_idx` (`person_id` ASC),
  
  CONSTRAINT `fk_enrollment_1` FOREIGN KEY (`tenant_id`) REFERENCES `tenants`.`tenant` (`id`),
  CONSTRAINT `fk_enrollment_2` FOREIGN KEY (`institution_id`) REFERENCES `tenants`.`institution` (`id`),
  CONSTRAINT `fk_enrollment_3` FOREIGN KEY (`person_id`) REFERENCES `tenants`.`person` (`id`)
    );




-- Tarefa 3 Criação de índice exclusivo, pois a retrição UNIQUE não funciona com valor null no Postgre

-- Garante a exclusividade(unique)
CREATE UNIQUE INDEX unique_enrollment
ON enrollment (tenant_id, institution_id, person_id)
WHERE institution_id IS NOT NULL;

-- Garante a exclusividade(unique) onde o institution_id é null
CREATE UNIQUE INDEX unique_enrollment_null_institution
ON enrollment (tenant_id, person_id)
WHERE institution_id IS NULL;



-- Tarefa 4 Exclusão lógica, a forma mais eficiente de realizar a exclusão lógica e garantir a auditoria da tabela é a criação de um outro campo, conforme abaixo.

ALTER TABLE enrollment
ADD COLUMN deleted BOOLEAN DEFAULT FALSE;

/* Esta coluna será do tipo booleano e indicará se o registro foi "excluído" (TRUE) ou se está ativo (FALSE). 
Logo para excluir um registro basta realizar um update no campo deleted, garantindo a a auditoria e facil manutenção do histórico. */

-- Obs: Essa ação vai gerar alteração nos indexes criados para garantir a unicidade da tarefa 3, segue novos indexes abaixo:

CREATE UNIQUE INDEX unique_enrollment_non_null_institution ON enrollment (tenant_id, institution_id, person_id)
WHERE institution_id IS NOT NULL AND is_deleted = FALSE;

CREATE UNIQUE INDEX unique_enrollment_null_institution ON enrollment (tenant_id, person_id)
WHERE institution_id IS NULL AND is_deleted = FALSE;



-- Tarefa 5  Construindo a consulta

SELECT 
    c.id AS course_id,
    c.name AS course_name,
    COUNT(e.id) AS enrollment_count  -- Contagem das matrículas
FROM 
    enrollment e
	
-- Filtros obrigatórios: tenant_id e institution_id

JOIN 
    course c ON e.course_id = c.id
              AND e.tenant_id = c.tenant_id 
              AND e.institution_id = c.institution_id
JOIN 
    person p ON e.person_id = p.id
WHERE 
    e.tenant_id = :tenant_id
    AND e.institution_id = :institution_id
    AND e.is_deleted = FALSE  -- Exibe apenas registros válidos (não excluídos logicamente)
-- busca de texto completo em campos JSONB pode ser feita usando o operador to_tsvector em combinação com to_tsquery
    AND to_tsvector('english', p.metadata::text) @@ to_tsquery('english', :"texto para busca")
-- Agrupando por id da course e name da course
GROUP BY 
    c.id, c.name;

-- Pode-se ainda usar liguagem procedural pl/pgsql para criar uma function conforme abaixo:

CREATE OR REPLACE FUNCTION contagem_mat_curso(
    p_tenant_id INT,
    p_institution_id INT,
    p_search_text TEXT
)
RETURNS TABLE (
    course_id INT,
    course_name VARCHAR,
    enrollment_count INT
) AS teste
BEGIN
    RETURN QUERY
    SELECT 
        c.id AS course_id,
        c.name AS course_name,
        COUNT(e.id) AS enrollment_count
    FROM 
        enrollment e
    JOIN 
        course c ON e.course_id = c.id
                  AND e.tenant_id = c.tenant_id 
                  AND e.institution_id = c.institution_id
    JOIN 
        person p ON e.person_id = p.id
    WHERE 
        e.tenant_id = p_tenant_id
        AND e.institution_id = p_institution_id
        AND e.is_deleted = FALSE  -- Exibe apenas registros válidos (não excluídos logicamente)
        AND to_tsvector('english', p.metadata::text) @@ to_tsquery('english', p_texto_para_busca)
    GROUP BY 
        c.id, c.name;
END;
teste LANGUAGE plpgsql;

-- chamando a function contagem_mat_curso:

SELECT * FROM contagem_mat_curso(tenant_id , institution_id, 'texto para busca');


-- Tarefa 7 Particionamento ta tabela enrollment, campo utilizado foi o enrollment_date, onde a lógica é particionar por intervalo de ano

-- Criação da tabela principal com particionamento por intervalo na coluna enrollment_date
CREATE TABLE enrollment (
    id SERIAL PRIMARY KEY,
    tenant_id INT NOT NULL,
    institution_id INT,
    person_id INT NOT NULL,
    enrollment_date DATE NOT NULL,
    status VARCHAR(50) NOT NULL,
    is_deleted BOOLEAN DEFAULT FALSE, -- Exclusão lógica
    
    -- Chaves estrangeiras
    CONSTRAINT fk_tenant FOREIGN KEY (tenant_id) REFERENCES tenant(id),
    CONSTRAINT fk_institution FOREIGN KEY (institution_id) REFERENCES institution(id),
    CONSTRAINT fk_person FOREIGN KEY (person_id) REFERENCES person(id)
) PARTITION BY RANGE (enrollment_date);

-- Partição para matrículas no ano de 2020
CREATE TABLE enrollment_2023 PARTITION OF enrollment
FOR VALUES FROM ('2020-01-01') TO ('2021-01-01');

-- Partição para matrículas no ano de 2021
CREATE TABLE enrollment_2023 PARTITION OF enrollment
FOR VALUES FROM ('2021-01-01') TO ('2022-01-01');

-- Partição para matrículas no ano de 2022
CREATE TABLE enrollment_2023 PARTITION OF enrollment
FOR VALUES FROM ('2022-01-01') TO ('2023-01-01');

-- Partição para matrículas no ano de 2023
CREATE TABLE enrollment_2023 PARTITION OF enrollment
FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');

-- Partição para matrículas no ano de 2024
CREATE TABLE enrollment_2024 PARTITION OF enrollment
FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

CREATE TABLE enrollment_2025 PARTITION OF enrollment
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');

-- E assim por diante, conforme a necessidade.

-- Partição padrão para matrículas fora dos intervalos especificados
CREATE TABLE enrollment_default PARTITION OF enrollment
DEFAULT;

-- Índice exclusivo para tenant_id, institution_id e person_id, condicionando is_deleted
CREATE UNIQUE INDEX unique_enrollment_non_null_institution ON enrollment (tenant_id, institution_id, person_id)
WHERE institution_id IS NOT NULL AND is_deleted = FALSE;

CREATE UNIQUE INDEX unique_enrollment_null_institution ON enrollment (tenant_id, person_id)
WHERE institution_id IS NULL AND is_deleted = FALSE;
