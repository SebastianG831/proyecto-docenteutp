import { query } from '../db/pool.js';
import { estadisticas, redondear } from './docenteService.js';

export async function reportePorDocente() {
  const docentesRes = await query('SELECT id, nombre, facultad FROM docentes ORDER BY id ASC');
  const items = await Promise.all(
    docentesRes.rows.map(async (d) => {
      const est = await estadisticas(d.id);
      const pendRes = await query(
        `SELECT COUNT(id)::int AS total
         FROM resenas
         WHERE docente_id = $1 AND estado = 'PENDIENTE'`,
        [d.id]
      );
      return {
        docenteId: Number(d.id),
        docenteNombre: d.nombre,
        facultad: d.facultad,
        promedioGeneral: est.general,
        promedioDominio: redondear(est.dominio),
        promedioClaridad: redondear(est.claridad),
        promedioEmpatia: redondear(est.empatia),
        totalResenas: est.total,
        resenasPendientes: Number(pendRes.rows[0]?.total || 0),
      };
    })
  );

  items.sort((a, b) => b.promedioGeneral - a.promedioGeneral);
  return items;
}
