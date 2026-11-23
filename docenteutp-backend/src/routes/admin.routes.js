import { Router } from 'express';
import { asyncHandler } from '../utils/errors.js';
import * as resenaService from '../services/resenaService.js';
import * as reporteService from '../services/reporteService.js';
import * as docenteService from '../services/docenteService.js';
import * as authService from '../services/authService.js';

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
    await resenaService.cambiarEstado(req.params.id, true);
    res.json({ mensaje: 'Reseña aprobada' });
  })
);

router.put(
  '/resenas/:id/rechazar',
  asyncHandler(async (req, res) => {
    await resenaService.cambiarEstado(req.params.id, false);
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

export default router;
