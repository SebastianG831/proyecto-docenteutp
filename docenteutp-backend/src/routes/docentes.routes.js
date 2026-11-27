import { Router } from 'express';
import { asyncHandler } from '../utils/errors.js';
import * as docenteService from '../services/docenteService.js';

const router = Router();

// GET /api/docentes?q=carlos&estilo=...&dificultad=MODERADO&sede=...&modalidad=...&perfil=...&sort=relevantes
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const { q, estilo, dificultad, sede, modalidad, perfil, sort } = req.query;
    const result = await docenteService.buscar({
      q,
      estilo,
      dificultad,
      sede,
      modalidad,
      perfil,
      sort,
    });
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
