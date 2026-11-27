import { BrowserRouter, Route, Routes } from 'react-router-dom';
import { AuthProvider } from './context/AuthContext';
import { ToastProvider } from './context/ToastContext';
import { Navbar } from './components/Navbar';
import { Footer } from './components/Footer';
import { HomePage } from './pages/HomePage';
import { TeacherProfilePage } from './pages/TeacherProfilePage';
import { ComparePage } from './pages/ComparePage';
import { StatisticsPage } from './pages/StatisticsPage';
import { MyReviewsPage } from './pages/MyReviewsPage';
import { SavedTeachersPage } from './pages/SavedTeachersPage';
import { HowItWorksPage } from './pages/HowItWorksPage';
import { LoginPage } from './pages/LoginPage';
import { RegisterPage } from './pages/RegisterPage';
import { AdminPage } from './pages/AdminPage';

export function App() {
  return (
    <BrowserRouter>
      <ToastProvider>
        <AuthProvider>
          <div className="app-shell">
            <Navbar />
            <main className="app-main">
              <Routes>
                <Route path="/" element={<HomePage />} />
                <Route path="/docentes/:id" element={<TeacherProfilePage />} />
                <Route path="/comparar" element={<ComparePage />} />
                <Route path="/estadisticas" element={<StatisticsPage />} />
                <Route path="/mis-resenas" element={<MyReviewsPage />} />
                <Route path="/guardados" element={<SavedTeachersPage />} />
                <Route path="/como-funciona" element={<HowItWorksPage />} />
                <Route path="/login" element={<LoginPage />} />
                <Route path="/registro" element={<RegisterPage />} />
                <Route path="/admin" element={<AdminPage />} />
              </Routes>
            </main>
            <Footer />
          </div>
        </AuthProvider>
      </ToastProvider>
    </BrowserRouter>
  );
}

export default App;
