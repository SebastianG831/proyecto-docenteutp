import { Router } from 'express';
import { asyncHandler } from '../utils/errors.js';
import * as guardadoService from '../services/guardadoService.js';

const router = Router();

router.get(
  '/usuario/:usuarioId',
  asyncHandler(async (req, res) => {
    const result = await guardadoService.listar(req.params.usuarioId);
    res.json(result);
  })
);

router.post(
  '/usuario/:usuarioId/docente/:docenteId',
  asyncHandler(async (req, res) => {
    await guardadoService.guardar(req.params.usuarioId, req.params.docenteId);
    res.json({ mensaje: 'Docente guardado' });
  })
);

router.delete(
  '/usuario/:usuarioId/docente/:docenteId',
  asyncHandler(async (req, res) => {
    await guardadoService.quitar(req.params.usuarioId, req.params.docenteId);
    res.json({ mensaje: 'Docente quitado de guardados' });
  })
);

export default router;
