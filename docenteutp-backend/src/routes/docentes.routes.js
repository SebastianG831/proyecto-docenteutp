import { Router } from 'express';
import { asyncHandler } from '../utils/errors.js';
import * as docenteService from '../services/docenteService.js';

const router = Router();

// GET /api/docentes?q=carlos&estilo=Explicación clara&dificultad=MODERADO&sort=relevantes
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const { q, estilo, dificultad, sort } = req.query;
    const result = await docenteService.buscar({ q, estilo, dificultad, sort });
    res.json(result);
  })
);

// GET /api/docentes/:id
router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const result = await docenteService.obtenerDetalle(req.params.id);
    res.json(result);
  })
);

export default router;
