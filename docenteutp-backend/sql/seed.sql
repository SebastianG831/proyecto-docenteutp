-- Datos iniciales de prueba para DocenteUTP (PostgreSQL)
-- Admin:       admin@utp.edu.pe     / admin1234
-- Estudiantes: alumno1..4@utp.edu.pe / estudiante123

INSERT INTO usuarios (nombre, correo, password, carrera, ciclo, rol) VALUES
  ('Coordinación Académica', 'admin@utp.edu.pe', '$2a$10$n/ROWDM17JXpydYh1mNeuualIcai5ShrOBQvhITi9f/4rkcbwFIp6', 'Administración', 1, 'ADMIN'),
  ('Ana Torres', 'alumno1@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', 'Ingeniería de Software', 5, 'ESTUDIANTE'),
  ('Diego Rojas', 'alumno2@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', 'Ingeniería de Sistemas', 4, 'ESTUDIANTE'),
  ('Camila Flores', 'alumno3@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', 'Ingeniería Industrial', 3, 'ESTUDIANTE'),
  ('Mateo Castro', 'alumno4@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', 'Informática', 7, 'ESTUDIANTE')
ON CONFLICT (correo) DO NOTHING;

INSERT INTO cursos (codigo, nombre) VALUES
  ('SIS-201', 'Algoritmos y Estructuras de Datos'),
  ('MAT-101', 'Cálculo I'),
  ('SIS-301', 'Base de Datos'),
  ('SOF-401', 'Desarrollo Web Integrado')
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO docentes (nombre, facultad, sede, verificado, estilo_ensenanza, estilo_evaluacion, resumen, etiquetas) VALUES
  ('Carlos Ramírez Salazar', 'Facultad de Ingeniería · Ingeniería de Sistemas', 'UTP Lima Centro · Edificio Arequipa', TRUE,
   'Explicación clara', 'Prácticas y exámenes',
   'Explica los conceptos paso a paso y los conecta con ejercicios similares a las evaluaciones. Las clases son participativas; practicar semanalmente ayuda a llegar con confianza a los exámenes.',
   'Metodología clara,Práctica semanal'),
  ('María Fernanda Paredes', 'Facultad de Ingeniería · Ingeniería Industrial', 'UTP Lima Centro · Edificio Arequipa', TRUE,
   'Evaluación continua', 'Controles semanales y proyecto',
   'Evalúa de forma continua con controles cortos, lo que evita acumular contenido. Muy accesible para resolver dudas dentro y fuera de clase.',
   'Evaluación continua,Accesible'),
  ('Jorge Luis Quispe', 'Facultad de Ingeniería · Ingeniería de Sistemas', 'UTP Lima Centro · Edificio Arequipa', TRUE,
   'Alto nivel de exigencia', 'Exámenes y casos complejos',
   'Domina el tema y exige mucho. Sus exámenes incluyen casos complejos, por lo que conviene estudiar con anticipación y no dejar dudas para el final.',
   'Alto nivel de exigencia,Dominio del tema'),
  ('Rosa Elena Mendoza', 'Facultad de Ingeniería · Ingeniería Industrial', 'UTP Lima Centro · Edificio Arequipa', TRUE,
   'Explicación dinámica', 'Prácticas calificadas',
   'Usa ejemplos cotidianos y dinámicas en clase para explicar los temas. Ideal para quienes sienten que Cálculo es difícil de entender.',
   'Explicación dinámica,Ejemplos reales'),
  ('Luis Alberto Torres', 'Facultad de Ingeniería · Ingeniería de Sistemas', 'UTP Lima Centro · Edificio Arequipa', TRUE,
   'Explicación clara', 'Laboratorios y examen final',
   'Combina teoría breve con laboratorios guiados. Pide entregas puntuales y revisa el avance de cada práctica.',
   'Metodología clara,Laboratorios guiados'),
  ('Ana Lucía Vega', 'Facultad de Ingeniería · Ingeniería de Software', 'UTP Lima Centro · Edificio Arequipa', TRUE,
   'Explicación dinámica', 'Proyecto por entregas',
   'El curso se trabaja con un proyecto por entregas. Da retroalimentación frecuente y fomenta el trabajo en equipo.',
   'Aprendizaje por proyecto,Retroalimentación')
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO docente_curso (docente_id, curso_id) VALUES
  ((SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), (SELECT id FROM cursos WHERE codigo = 'SIS-201')),
  ((SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe'), (SELECT id FROM cursos WHERE codigo = 'SIS-201')),
  ((SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), (SELECT id FROM cursos WHERE codigo = 'MAT-101')),
  ((SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), (SELECT id FROM cursos WHERE codigo = 'MAT-101')),
  ((SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), (SELECT id FROM cursos WHERE codigo = 'SIS-301')),
  ((SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'))
ON CONFLICT (docente_id, curso_id) DO NOTHING;

INSERT INTO resenas (usuario_id, docente_id, curso_id, dominio, claridad, empatia, dificultad, comentario, estado, fecha) VALUES
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), 5, 5, 4, 'MODERADO', 'Los ejemplos de clase se parecen bastante a los ejercicios de evaluación. Explica con paciencia y responde las dudas; practicar por cuenta propia es importante.', 'APROBADA', NOW() - INTERVAL '14 days'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno2@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), 5, 5, 5, 'MODERADO', 'Muy claro al explicar estructuras de datos. Las clases son organizadas y la exigencia es justa si practicas cada semana.', 'APROBADA', NOW() - INTERVAL '20 days'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno3@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), 4, 5, 4, 'MODERADO', 'Buen docente, explica paso a paso. Conviene resolver los ejercicios antes de cada práctica calificada.', 'APROBADA', NOW() - INTERVAL '25 days'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno4@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), 4, 4, 4, 'MODERADO', 'Recién terminé el curso. Me pareció ordenado, aunque algunas semanas el ritmo fue rápido para mí.', 'PENDIENTE', NOW() - INTERVAL '1 day'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), 5, 4, 5, 'LIGERO', 'Los controles cortos ayudan a no acumular temas. Siempre disponible para resolver dudas después de clase.', 'APROBADA', NOW() - INTERVAL '10 days'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno2@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), 4, 4, 5, 'MODERADO', 'Muy amable y accesible. Hay que estar al día porque evalúa casi todas las semanas.', 'APROBADA', NOW() - INTERVAL '18 days'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno4@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), 5, 5, 4, 'MODERADO', 'Explica con calma y repite lo que haga falta. El proyecto final requiere tiempo, pero se entiende bien.', 'APROBADA', NOW() - INTERVAL '30 days'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno3@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), 5, 3, 3, 'EXIGENTE', 'Sabe muchísimo, pero explica rápido y sus exámenes son difíciles. Hay que estudiar con bastante anticipación.', 'APROBADA', NOW() - INTERVAL '12 days'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno4@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), 4, 3, 2, 'EXIGENTE', 'Nivel de exigencia muy alto. Si no entiendes algo en clase, toca buscar ayuda por tu cuenta.', 'APROBADA', NOW() - INTERVAL '22 days'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno2@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), 4, 5, 5, 'LIGERO', 'Hace que Cálculo se sienta más fácil con ejemplos de la vida diaria. Las clases son dinámicas.', 'APROBADA', NOW() - INTERVAL '9 days'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno3@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), 4, 4, 5, 'LIGERO', 'Muy empática y paciente. Sus prácticas calificadas son parecidas a lo visto en clase.', 'APROBADA', NOW() - INTERVAL '16 days'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), 5, 4, 4, 'MODERADO', 'Los laboratorios guiados ayudan mucho. Es estricto con las fechas de entrega de cada práctica.', 'APROBADA', NOW() - INTERVAL '11 days'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno4@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), 4, 5, 4, 'MODERADO', 'Teoría breve y mucha práctica. Se aprende bien si asistes a todos los laboratorios.', 'APROBADA', NOW() - INTERVAL '28 days'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno2@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), 5, 5, 5, 'MODERADO', 'Da retroalimentación en cada entrega del proyecto y se nota que le importa que aprendamos.', 'APROBADA', NOW() - INTERVAL '8 days'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno3@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), 5, 4, 5, 'MODERADO', 'El trabajo en equipo es clave en su curso. Explica bien y está pendiente del avance de cada grupo.', 'APROBADA', NOW() - INTERVAL '15 days')
ON CONFLICT (usuario_id, docente_id, curso_id) DO NOTHING;
