import { Router } from 'express';
import { asyncHandler } from '../utils/errors.js';
import * as resenaService from '../services/resenaService.js';
import * as reporteService from '../services/reporteService.js';
import * as docenteService from '../services/docenteService.js';
import * as authService from '../services/authService.js';
import * as estadisticasService from '../services/estadisticasService.js';

const router = Router();

router.get(
  '/resenas/pendientes',
  asyncHandler(async (_req, res) => {
    const result = await resenaService.listarPendientes();
    res.json(result);
  })
);

router.put(
  '/resenas/:id/aprobar',
  asyncHandler(async (req, res) => {
    const { adminId = null } = req.body || {};
    await resenaService.cambiarEstado(req.params.id, true, { adminId });
    res.json({ mensaje: 'Reseña aprobada' });
  })
);

router.put(
  '/resenas/:id/rechazar',
  asyncHandler(async (req, res) => {
    const { adminId = null, motivo = null } = req.body || {};
    await resenaService.cambiarEstado(req.params.id, false, { adminId, motivo });
    res.json({ mensaje: 'Reseña rechazada' });
  })
);

router.get(
  '/reportes/docentes',
  asyncHandler(async (_req, res) => {
    const result = await reporteService.reportePorDocente();
    res.json(result);
  })
);

router.get(
  '/docentes',
  asyncHandler(async (_req, res) => {
    const result = await docenteService.buscar({});
    res.json(result);
  })
);

router.post(
  '/docentes',
  asyncHandler(async (req, res) => {
    const result = await docenteService.crearDocente(req.body || {});
    res.status(201).json(result);
  })
);

router.get(
  '/usuarios',
  asyncHandler(async (_req, res) => {
    const result = await authService.listarUsuariosAdmin();
    res.json(result);
  })
);

router.get(
  '/moderacion/historial',
  asyncHandler(async (req, res) => {
    const result = await estadisticasService.obtenerHistorialModeracion(req.query.limit);
    res.json(result);
  })
);

router.post(
  '/ml/recalcular',
  asyncHandler(async (req, res) => {
    const { adminId = null } = req.body || {};
    const result = await estadisticasService.recalcularClustering(adminId);
    res.json({ mensaje: 'Modelos K-Means, Mean Shift y DBSCAN actualizados', resumen: result });
  })
);

export default router;
