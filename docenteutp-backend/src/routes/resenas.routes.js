import { Router } from 'express';
import { asyncHandler } from '../utils/errors.js';
import * as resenaService from '../services/resenaService.js';

const router = Router();

router.post(
  '/',
  asyncHandler(async (req, res) => {
    const result = await resenaService.publicar(req.body || {});
    res.status(201).json(result);
  })
);

router.get(
  '/docente/:docenteId',
  asyncHandler(async (req, res) => {
    const result = await resenaService.listarPorDocente(req.params.docenteId);
    res.json(result);
  })
);

router.get(
  '/usuario/:usuarioId',
  asyncHandler(async (req, res) => {
    const result = await resenaService.listarPorUsuario(req.params.usuarioId);
    res.json(result);
  })
);

router.post(
  '/:id/voto',
  asyncHandler(async (req, res) => {
    const { usuarioId, esUtil = true } = req.body || {};
    const result = await resenaService.votarUtil(req.params.id, usuarioId, esUtil);
    res.json(result);
  })
);

router.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    await resenaService.eliminar(req.params.id, req.query.usuarioId);
    res.json({ mensaje: 'Reseña eliminada' });
  })
);

export default router;
