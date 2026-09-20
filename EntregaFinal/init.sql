-- init.sql: se ejecuta automáticamente la PRIMERA vez que se crea el volumen de postgres_data

CREATE TABLE IF NOT EXISTS tecnicos (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    especialidad VARCHAR(50) NOT NULL,   -- 'bug' | 'duda de uso' | 'reclamo' | 'reembolso'
    disponible BOOLEAN NOT NULL DEFAULT TRUE,
    asignado_a_session VARCHAR(100),     -- session_id del caso que está atendiendo (NULL si libre)
    creado_en TIMESTAMP DEFAULT NOW()
);

INSERT INTO tecnicos (nombre, especialidad, disponible) VALUES
    ('Martina Gómez',   'bug',           TRUE),
    ('Facundo Rivas',   'bug',           TRUE),
    ('Sofía Herrera',   'duda de uso',   TRUE),
    ('Nicolás Pereyra', 'reclamo',       TRUE),
    ('Camila Duarte',   'reembolso',     TRUE),
    ('Tomás Aguirre',   'bug',           FALSE); -- ejemplo de técnico ya ocupado
