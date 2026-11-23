import { Router } from 'express';
import { asyncHandler } from '../utils/errors.js';
import * as authService from '../services/authService.js';

const router = Router();

router.post(
  '/registro',
  asyncHandler(async (req, res) => {
    const result = await authService.registrar(req.body || {});
    res.status(201).json(result);
  })
);

router.post(
  '/login',
  asyncHandler(async (req, res) => {
    const result = await authService.login(req.body || {});
    res.json(result);
  })
);

export default router;
