import { Routes } from '@angular/router';
import { HomeComponent } from './features/home/home.component';
import { authGuard } from './core/guards/auth.guard';

export const routes: Routes = [
  { path: '', component: HomeComponent, title: 'Inicio | DocenteUTP' },
  { path: 'buscar', loadComponent: () => import('./features/busqueda/busqueda.component').then(m => m.BusquedaComponent), title: 'Buscar docentes | DocenteUTP' },
  { path: 'docente/:id', loadComponent: () => import('./features/perfil/perfil.component').then(m => m.PerfilComponent), title: 'Perfil del docente | DocenteUTP' },
  { path: 'recomendaciones', loadComponent: () => import('./features/recomendaciones/recomendaciones.component').then(m => m.RecomendacionesComponent), title: 'Recomendaciones | DocenteUTP' },
  { path: 'login', loadComponent: () => import('./features/auth/login/login.component').then(m => m.LoginComponent), title: 'Iniciar sesión | DocenteUTP' },
  { path: 'registro', loadComponent: () => import('./features/auth/registro/registro.component').then(m => m.RegistroComponent), title: 'Registro | DocenteUTP' },
  { path: 'guardados', loadComponent: () => import('./features/guardados/guardados.component').then(m => m.GuardadosComponent), canActivate: [authGuard], title: 'Mis guardados | DocenteUTP' },
  { path: 'mis-resenas', loadComponent: () => import('./features/mis-resenas/mis-resenas.component').then(m => m.MisResenasComponent), canActivate: [authGuard], title: 'Mis reseñas | DocenteUTP' },
  { path: 'admin/reportes', loadComponent: () => import('./features/admin/reportes/reportes.component').then(m => m.ReportesComponent), canActivate: [authGuard], title: 'Reportes admin | DocenteUTP' },
  { path: '**', redirectTo: '' }
];