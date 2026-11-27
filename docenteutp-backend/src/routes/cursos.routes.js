import { Router } from 'express';
import { asyncHandler } from '../utils/errors.js';
import * as cursoService from '../services/cursoService.js';

const router = Router();

router.get(
  '/',
  asyncHandler(async (req, res) => {
    const result = await cursoService.listar(req.query.q);
    res.json(result);
  })
);

router.get(
  '/:id/docentes',
  asyncHandler(async (req, res) => {
    const result = await cursoService.docentesDelCurso(req.params.id);
    res.json(result);
  })
);

export default router;
