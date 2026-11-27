import { Router } from 'express';
import { asyncHandler } from '../utils/errors.js';
import * as estadisticasService from '../services/estadisticasService.js';

const router = Router();

// GET /api/estadisticas
router.get(
  '/',
  asyncHandler(async (_req, res) => {
    const data = await estadisticasService.obtenerEstadisticasCompletas();
    res.json(data);
  })
);

export default router;
