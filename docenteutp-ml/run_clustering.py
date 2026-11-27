#!/usr/bin/env python3
"""
DocenteUTP - Pipeline Unificado de Clustering No Supervisado
=============================================================
Ejecuta K-Means (docentes y estudiantes), Mean Shift (modos docentes) y
DBSCAN (detección de anomalías en docentes y reseñas) sobre las vistas ML
de PostgreSQL y persiste los resultados en ml_experimentos, ml_clusters y
ml_asignaciones.
"""

from __future__ import annotations

import json
import os
import sys
import warnings
from typing import Any

import numpy as np
import pandas as pd
import psycopg2
from psycopg2.extras import execute_values
from sklearn.cluster import DBSCAN, KMeans, MeanShift, estimate_bandwidth
from sklearn.decomposition import PCA
from sklearn.metrics import (
    calinski_harabasz_score,
    davies_bouldin_score,
    silhouette_score,
)
from sklearn.preprocessing import StandardScaler

warnings.filterwarnings("ignore")

DEFAULT_DB_URL = "postgresql://dev:dev@localhost:5432/docenteutp"


def safe_metrics(X: np.ndarray, labels: np.ndarray) -> tuple[float | None, float | None, float | None]:
    """Calcula métricas internas excluyendo ruido (-1) si hay >= 2 clústeres válidos."""
    mask = labels != -1
    valid_labels = labels[mask]
    unique_labels = np.unique(valid_labels)
    if len(unique_labels) < 2 or len(valid_labels) <= len(unique_labels):
        return None, None, None
    X_valid = X[mask]
    return (
        float(round(silhouette_score(X_valid, valid_labels), 4)),
        float(round(davies_bouldin_score(X_valid, valid_labels), 4)),
        float(round(calinski_harabasz_score(X_valid, valid_labels), 4)),
    )


def describe_docente_cluster(centroid: dict[str, float], is_outlier: bool = False, size: int = 0) -> tuple[str, str]:
    """Genera etiqueta de negocio y descripción legible a partir del centroide en escala original."""
    if is_outlier:
        return (
            "Perfil Docente Atípico",
            "Casos con polarización extrema en calificaciones, carga de estudio desproporcionada o tasa inusual de rechazos en moderación.",
        )

    dom = centroid.get("avg_dominio", 0.0)
    cla = centroid.get("avg_claridad", 0.0)
    emp = centroid.get("avg_empatia", 0.0)
    dif = centroid.get("dificultad_score", 2.0)
    hrs = centroid.get("avg_horas_estudio", 5.0)
    rec = centroid.get("tasa_recomendacion", 0.5)
    avg_score = (dom + cla + emp) / 3.0

    if hrs >= 18.0:
        return (
            "Carga Extrema / Alto Rigor",
            f"Exigencia muy elevada ({hrs:.1f} h/sem) con dominio técnico sobresaliente ({dom:.1f}/5), pero baja empatía ({emp:.1f}/5).",
        )
    if rec >= 0.85 and avg_score >= 4.4 and hrs >= 4.0:
        return (
            "Excelencia Integral",
            f"Docentes mejor valorados en dominio ({dom:.1f}/5), claridad ({cla:.1f}/5) y empatía ({emp:.1f}/5), con {rec*100:.0f}% de recomendación.",
        )
    if rec >= 0.85 and dif <= 1.5 and hrs < 4.0:
        return (
            "Accesibles y Dinámicos",
            f"Clases dinámicas y cercanas (empatía {emp:.1f}/5, claridad {cla:.1f}/5) con carga manejable (~{hrs:.1f} h/sem).",
        )
    if dif >= 2.5 and dom >= 4.4:
        return (
            "Exigentes / Alto Rigor",
            f"Gran dominio del tema ({dom:.1f}/5) pero ritmo exigente (~{hrs:.1f} h/sem de estudio). Ideal si buscas profundidad técnica.",
        )
    if avg_score < 2.6 or rec < 0.25:
        return (
            "En Riesgo / Baja Claridad",
            f"Reportan baja claridad ({cla:.1f}/5) y solo {rec*100:.0f}% de recomendación estudiantil; requieren acompañamiento pedagógico.",
        )
    if size <= 3 and abs(avg_score - 3.0) <= 0.35:
        return (
            "Opiniones Divididas / Polarizado",
            "Calificación promedio intermedia causada por opiniones muy opuestas entre estudiantes.",
        )
    return (
        "Desempeño Equilibrado",
        f"Balance estable entre claridad ({cla:.1f}/5), empatía ({emp:.1f}/5) y carga semanal (~{hrs:.1f} h/sem).",
    )


def describe_usuario_cluster(centroid: dict[str, float]) -> tuple[str, str]:
    """Etiqueta comprensible para segmentos de estudiantes evaluadores."""
    ciclo = centroid.get("ciclo", 5.0)
    rech = centroid.get("tasa_resenas_rechazadas", 0.0)
    rep = centroid.get("total_reportes_recibidos", 0.0)
    rec = centroid.get("tasa_recomendacion_dada", 0.8)
    cal = centroid.get("avg_calificacion_dada", 4.0)
    hrs = centroid.get("avg_horas_reportadas", 5.0)

    if rech >= 0.2 or rep >= 2.0:
        return (
            "Cuentas con Actividad Atípica",
            "Perfiles con múltiples reseñas rechazadas o reportadas por lenguaje extremo y ráfagas en 24h.",
        )
    if ciclo >= 7.5 or (hrs >= 8.0 and rec < 0.7):
        return (
            "Ciclos Avanzados y Exigentes",
            f"Estudiantes de ciclos superiores (ciclo prom. {ciclo:.1f}) que reportan mayor dedicación (~{hrs:.1f} h/sem) y evalúan con mayor rigor ({cal:.1f}/5).",
        )
    if ciclo <= 4.0 and rec >= 0.85:
        return (
            "Ciclos Iniciales Participativos",
            f"Estudiantes de primeros ciclos (ciclo prom. {ciclo:.1f}) que guardan múltiples opciones y recomiendan al {rec*100:.0f}% de sus docentes.",
        )
    return (
        "Evaluadores Regulares Balanceados",
        f"Estudiantes de ciclos intermedios (ciclo prom. {ciclo:.1f}) con criterios equilibrados (promedio {cal:.1f}/5 y ~{hrs:.1f} h/sem).",
    )


def describe_resena_cluster(df_sub: pd.DataFrame, label: int) -> tuple[str, str]:
    """Etiqueta legible para grupos y anomalías de reseñas."""
    if label == -1:
        return (
            "Reseña Anómala / Sospecha de Spam",
            "Desviación extrema respecto al consenso del docente, uso intensivo de mayúsculas, ráfagas en 24h o múltiples reportes.",
        )
    avg_len = float(df_sub["longitud_comentario"].mean())
    avg_cal = float(df_sub["calificacion_promedio"].mean())
    avg_rep = float(df_sub["total_reportes"].mean())
    n_rows = len(df_sub)
    if avg_rep == 0 and avg_len <= 90 and avg_cal >= 4.7 and n_rows <= 20:
        return (
            "Reseñas Promocionales Coordinadas",
            "Micro-grupo compacto de comentarios breves con calificación perfecta atípica (5.0/5) y patrón uniforme.",
        )
    if abs(avg_cal - 3.0) <= 0.25 and n_rows <= 40:
        return (
            "Opiniones Mixtas en Docentes Polarizados",
            "Evaluaciones con alta divergencia interna asociadas a docentes de estilo polarizante.",
        )
    return (
        "Consenso Estudiantil Verificado",
        "Reseñas alineadas con la tendencia histórica del docente y sin señales de spam.",
    )


def persist_experiment(
    cur: Any,
    *,
    nombre: str,
    algoritmo: str,
    entidad_objetivo: str,
    hiperparametros: dict[str, Any],
    features: list[str],
    X_scaled: np.ndarray,
    X_raw: pd.DataFrame,
    labels: np.ndarray,
    entity_ids: list[int],
    cluster_meta: dict[int, tuple[str, str]],
    centers_scaled: dict[int, np.ndarray],
    centers_orig: dict[int, dict[str, float]],
    ejecutado_por: int | None = None,
) -> int:
    """Desactiva experimento previo del mismo par (algoritmo, entidad) e inserta el nuevo."""
    cur.execute(
        """
        UPDATE ml_experimentos
        SET activo = FALSE
        WHERE algoritmo = %s AND entidad_objetivo = %s AND activo = TRUE
        """,
        (algoritmo, entidad_objetivo),
    )

    sil, db_score, ch_score = safe_metrics(X_scaled, labels)
    n_muestras = int(len(labels))
    unique_clusters = sorted(int(c) for c in np.unique(labels))
    n_clusters = len([c for c in unique_clusters if c != -1])
    n_outliers = int(np.sum(labels == -1))

    # Asegurar nombre único si ya existe un histórico igual
    cur.execute("SELECT 1 FROM ml_experimentos WHERE nombre = %s", (nombre,))
    exp_nombre = nombre
    if cur.fetchone() is not None:
        exp_nombre = f"{nombre} ({pd.Timestamp.utcnow().strftime('%Y%m%d%H%M%S')})"

    cur.execute(
        """
        INSERT INTO ml_experimentos (
          nombre, algoritmo, entidad_objetivo, hiperparametros, features_usadas,
          escalador, n_muestras, n_clusters_encontrados, n_outliers,
          silhouette_score, davies_bouldin_score, calinski_harabasz_score,
          activo, ejecutado_por
        ) VALUES (%s, %s, %s, %s::jsonb, %s, 'StandardScaler', %s, %s, %s, %s, %s, %s, TRUE, %s)
        RETURNING id
        """,
        (
            exp_nombre,
            algoritmo,
            entidad_objetivo,
            json.dumps(hiperparametros),
            features,
            n_muestras,
            n_clusters,
            n_outliers,
            sil,
            db_score,
            ch_score,
            ejecutado_por,
        ),
    )
    experimento_id = int(cur.fetchone()[0])

    # Proyección PCA 2D para trazabilidad en BD
    n_comp = min(2, X_scaled.shape[1], X_scaled.shape[0])
    if n_comp == 2:
        pca_coords = PCA(n_components=2, random_state=42).fit_transform(X_scaled)
    else:
        pca_coords = np.zeros((len(labels), 2), dtype=float)

    # Insertar ml_clusters
    cluster_rows = []
    for clabel in unique_clusters:
        mask = labels == clabel
        tamano = int(np.sum(mask))
        etiqueta_neg, desc = cluster_meta[clabel]
        c_scaled = centers_scaled.get(clabel)
        c_orig = centers_orig.get(clabel, {})
        if c_scaled is not None and tamano > 0:
            dists = np.linalg.norm(X_scaled[mask] - c_scaled, axis=1)
            radio = float(round(np.mean(dists), 4))
            c_scaled_list = [float(round(v, 6)) for v in c_scaled]
        else:
            radio = None
            c_scaled_list = None
        cluster_rows.append(
            (
                experimento_id,
                clabel,
                etiqueta_neg,
                desc,
                tamano,
                json.dumps(c_orig),
                c_scaled_list,
                radio,
            )
        )

    execute_values(
        cur,
        """
        INSERT INTO ml_clusters (
          experimento_id, cluster_label, etiqueta_negocio, descripcion,
          tamano, centroide_original, centroide_escalado, radio_dispersion
        ) VALUES %s
        """,
        cluster_rows,
    )

    # Calcular distancias y probabilidades de pertenencia para cada muestra
    valid_centers = [(k, v) for k, v in centers_scaled.items() if k != -1]
    asig_rows = []
    for idx, eid in enumerate(entity_ids):
        clabel = int(labels[idx])
        is_out = clabel == -1
        c_scaled = centers_scaled.get(clabel)
        dist = float(round(np.linalg.norm(X_scaled[idx] - c_scaled), 4)) if c_scaled is not None else None

        prob = None
        if not is_out and len(valid_centers) >= 2:
            dists_all = np.array([np.linalg.norm(X_scaled[idx] - vc) for _, vc in valid_centers])
            inv = 1.0 / (dists_all + 1e-6)
            probs = inv / np.sum(inv)
            center_idx = [k for k, _ in valid_centers].index(clabel)
            prob = float(round(probs[center_idx], 4))
        elif not is_out:
            prob = 1.0

        vec = {f: float(round(float(X_raw.iloc[idx][f]), 4)) for f in features}
        doc_id = eid if entidad_objetivo == "DOCENTE" else None
        res_id = eid if entidad_objetivo == "RESENA" else None
        usr_id = eid if entidad_objetivo == "USUARIO" else None

        asig_rows.append(
            (
                experimento_id,
                clabel,
                doc_id,
                None,
                res_id,
                usr_id,
                is_out,
                dist,
                prob,
                float(round(float(pca_coords[idx, 0]), 4)),
                float(round(float(pca_coords[idx, 1]), 4)),
                json.dumps(vec),
            )
        )

    execute_values(
        cur,
        """
        INSERT INTO ml_asignaciones (
          experimento_id, cluster_label, docente_id, curso_id, resena_id, usuario_id,
          es_outlier, distancia_centroide, probabilidad_pertenencia,
          pca_x, pca_y, vector_features
        ) VALUES %s
        """,
        asig_rows,
    )
    return experimento_id


def run_all(db_url: str, admin_id: int | None = None) -> dict[str, Any]:
    conn = psycopg2.connect(db_url)
    conn.autocommit = False
    try:
        df_doc = pd.read_sql(
            "SELECT * FROM vw_ml_docentes_features WHERE tiene_suficientes_datos = TRUE ORDER BY docente_id",
            conn,
        )
        df_res = pd.read_sql("SELECT * FROM vw_ml_resenas_features ORDER BY resena_id", conn)
        df_usr = pd.read_sql(
            "SELECT * FROM vw_ml_usuarios_features WHERE tiene_actividad = TRUE ORDER BY usuario_id",
            conn,
        )

        cur = conn.cursor()
        summary: dict[str, Any] = {}

        # ------------------------------------------------------------------
        # 1. K-MEANS EN DOCENTES (k=4 perfiles pedagógicos + curva del codo)
        # ------------------------------------------------------------------
        feat_doc_km = [
            "avg_dominio",
            "avg_claridad",
            "avg_empatia",
            "dificultad_score",
            "avg_horas_estudio",
            "tasa_recomendacion",
        ]
        scaler_km_doc = StandardScaler()
        X_doc_km = scaler_km_doc.fit_transform(df_doc[feat_doc_km])

        elbow_curve = []
        for k in range(2, min(7, len(df_doc))):
            km_tmp = KMeans(n_clusters=k, n_init=20, random_state=42)
            lbl_tmp = km_tmp.fit_predict(X_doc_km)
            elbow_curve.append(
                {
                    "k": k,
                    "inertia": round(float(km_tmp.inertia_), 2),
                    "silhouette": round(float(silhouette_score(X_doc_km, lbl_tmp)), 4),
                }
            )

        k_doc = 4 if len(df_doc) >= 4 else max(2, len(df_doc))
        km_doc = KMeans(n_clusters=k_doc, n_init=25, random_state=42)
        km_doc_labels = km_doc.fit_predict(X_doc_km)
        km_centers_orig_arr = scaler_km_doc.inverse_transform(km_doc.cluster_centers_)

        km_doc_meta: dict[int, tuple[str, str]] = {}
        km_doc_c_scaled: dict[int, np.ndarray] = {}
        km_doc_c_orig: dict[int, dict[str, float]] = {}
        for cid in sorted(int(c) for c in np.unique(km_doc_labels)):
            c_dict = {f: round(float(km_centers_orig_arr[cid, j]), 3) for j, f in enumerate(feat_doc_km)}
            km_doc_c_scaled[cid] = km_doc.cluster_centers_[cid]
            km_doc_c_orig[cid] = c_dict
            size = int(np.sum(km_doc_labels == cid))
            km_doc_meta[cid] = describe_docente_cluster(c_dict, is_outlier=False, size=size)

        exp_km_doc = persist_experiment(
            cur,
            nombre="KMeans_Docentes_Perfiles_Pedagogicos",
            algoritmo="KMEANS",
            entidad_objetivo="DOCENTE",
            hiperparametros={"n_clusters": k_doc, "n_init": 25, "random_state": 42, "elbow": elbow_curve},
            features=feat_doc_km,
            X_scaled=X_doc_km,
            X_raw=df_doc[feat_doc_km],
            labels=km_doc_labels,
            entity_ids=[int(x) for x in df_doc["docente_id"]],
            cluster_meta=km_doc_meta,
            centers_scaled=km_doc_c_scaled,
            centers_orig=km_doc_c_orig,
            ejecutado_por=admin_id,
        )
        summary["kmeans_docentes"] = {"experimento_id": exp_km_doc, "k": k_doc, "n": len(df_doc)}

        # ------------------------------------------------------------------
        # 2. K-MEANS EN ESTUDIANTES (k=3 perfiles de evaluación)
        # ------------------------------------------------------------------
        feat_usr_km = [
            "ciclo",
            "total_resenas",
            "total_guardados",
            "avg_calificacion_dada",
            "avg_dificultad_dada",
            "avg_horas_reportadas",
            "tasa_recomendacion_dada",
            "total_reportes_recibidos",
        ]
        scaler_km_usr = StandardScaler()
        X_usr_km = scaler_km_usr.fit_transform(df_usr[feat_usr_km])

        usr_elbow = []
        for k in range(2, min(6, len(df_usr))):
            km_tmp = KMeans(n_clusters=k, n_init=20, random_state=42)
            lbl_tmp = km_tmp.fit_predict(X_usr_km)
            usr_elbow.append(
                {
                    "k": k,
                    "inertia": round(float(km_tmp.inertia_), 2),
                    "silhouette": round(float(silhouette_score(X_usr_km, lbl_tmp)), 4),
                }
            )

        k_usr = 3 if len(df_usr) >= 3 else max(2, len(df_usr))
        km_usr = KMeans(n_clusters=k_usr, n_init=25, random_state=42)
        km_usr_labels = km_usr.fit_predict(X_usr_km)
        km_usr_orig_arr = scaler_km_usr.inverse_transform(km_usr.cluster_centers_)

        km_usr_meta: dict[int, tuple[str, str]] = {}
        km_usr_c_scaled: dict[int, np.ndarray] = {}
        km_usr_c_orig: dict[int, dict[str, float]] = {}
        for cid in sorted(int(c) for c in np.unique(km_usr_labels)):
            c_dict = {f: round(float(km_usr_orig_arr[cid, j]), 3) for j, f in enumerate(feat_usr_km)}
            km_usr_c_scaled[cid] = km_usr.cluster_centers_[cid]
            km_usr_c_orig[cid] = c_dict
            km_usr_meta[cid] = describe_usuario_cluster(c_dict)

        exp_km_usr = persist_experiment(
            cur,
            nombre="KMeans_Usuarios_Perfiles_Estudiantes",
            algoritmo="KMEANS",
            entidad_objetivo="USUARIO",
            hiperparametros={"n_clusters": k_usr, "n_init": 25, "random_state": 42, "elbow": usr_elbow},
            features=feat_usr_km,
            X_scaled=X_usr_km,
            X_raw=df_usr[feat_usr_km],
            labels=km_usr_labels,
            entity_ids=[int(x) for x in df_usr["usuario_id"]],
            cluster_meta=km_usr_meta,
            centers_scaled=km_usr_c_scaled,
            centers_orig=km_usr_c_orig,
            ejecutado_por=admin_id,
        )
        summary["kmeans_usuarios"] = {"experimento_id": exp_km_usr, "k": k_usr, "n": len(df_usr)}

        # ------------------------------------------------------------------
        # 3. MEAN SHIFT EN DOCENTES (modos naturales automáticos)
        # ------------------------------------------------------------------
        scaler_ms = StandardScaler()
        X_doc_ms = scaler_ms.fit_transform(df_doc[feat_doc_km])
        bw = float(estimate_bandwidth(X_doc_ms, quantile=0.22, random_state=42))
        if bw <= 0:
            bw = 1.0
        ms_doc = MeanShift(bandwidth=bw)
        ms_labels = ms_doc.fit_predict(X_doc_ms)
        ms_orig_arr = scaler_ms.inverse_transform(ms_doc.cluster_centers_)

        ms_meta: dict[int, tuple[str, str]] = {}
        ms_c_scaled: dict[int, np.ndarray] = {}
        ms_c_orig: dict[int, dict[str, float]] = {}
        for cid in sorted(int(c) for c in np.unique(ms_labels)):
            c_dict = {f: round(float(ms_orig_arr[cid, j]), 3) for j, f in enumerate(feat_doc_km)}
            ms_c_scaled[cid] = ms_doc.cluster_centers_[cid]
            ms_c_orig[cid] = c_dict
            size = int(np.sum(ms_labels == cid))
            ms_meta[cid] = describe_docente_cluster(c_dict, is_outlier=False, size=size)

        exp_ms_doc = persist_experiment(
            cur,
            nombre="MeanShift_Docentes_Modos_Automaticos",
            algoritmo="MEAN_SHIFT",
            entidad_objetivo="DOCENTE",
            hiperparametros={"quantile": 0.22, "bandwidth": round(bw, 4)},
            features=feat_doc_km,
            X_scaled=X_doc_ms,
            X_raw=df_doc[feat_doc_km],
            labels=ms_labels,
            entity_ids=[int(x) for x in df_doc["docente_id"]],
            cluster_meta=ms_meta,
            centers_scaled=ms_c_scaled,
            centers_orig=ms_c_orig,
            ejecutado_por=admin_id,
        )
        summary["meanshift_docentes"] = {
            "experimento_id": exp_ms_doc,
            "clusters": len(np.unique(ms_labels)),
            "bandwidth": round(bw, 4),
        }

        # ------------------------------------------------------------------
        # 4. DBSCAN EN DOCENTES (arquetipos densos + outliers atípicos)
        # ------------------------------------------------------------------
        feat_doc_db = feat_doc_km + [
            "indice_polarizacion",
            "tasa_rechazo_bruta",
            "ratio_guardados_resena",
            "avg_nota_obtenida",
        ]
        scaler_db_doc = StandardScaler()
        X_doc_db = scaler_db_doc.fit_transform(df_doc[feat_doc_db])
        db_doc = DBSCAN(eps=1.7, min_samples=3)
        db_doc_labels = db_doc.fit_predict(X_doc_db)

        db_doc_meta: dict[int, tuple[str, str]] = {}
        db_doc_c_scaled: dict[int, np.ndarray] = {}
        db_doc_c_orig: dict[int, dict[str, float]] = {}
        for cid in sorted(int(c) for c in np.unique(db_doc_labels)):
            mask = db_doc_labels == cid
            mean_scaled = np.mean(X_doc_db[mask], axis=0)
            mean_orig = df_doc.loc[mask, feat_doc_db].mean().to_dict()
            c_dict = {f: round(float(mean_orig[f]), 3) for f in feat_doc_db}
            db_doc_c_scaled[cid] = mean_scaled
            db_doc_c_orig[cid] = c_dict
            db_doc_meta[cid] = describe_docente_cluster(c_dict, is_outlier=(cid == -1), size=int(np.sum(mask)))

        exp_db_doc = persist_experiment(
            cur,
            nombre="DBSCAN_Docentes_Deteccion_Outliers",
            algoritmo="DBSCAN",
            entidad_objetivo="DOCENTE",
            hiperparametros={"eps": 1.7, "min_samples": 3},
            features=feat_doc_db,
            X_scaled=X_doc_db,
            X_raw=df_doc[feat_doc_db],
            labels=db_doc_labels,
            entity_ids=[int(x) for x in df_doc["docente_id"]],
            cluster_meta=db_doc_meta,
            centers_scaled=db_doc_c_scaled,
            centers_orig=db_doc_c_orig,
            ejecutado_por=admin_id,
        )
        summary["dbscan_docentes"] = {
            "experimento_id": exp_db_doc,
            "outliers": int(np.sum(db_doc_labels == -1)),
        }

        # ------------------------------------------------------------------
        # 5. DBSCAN EN RESEÑAS (detección de anomalías / spam / brigading)
        # ------------------------------------------------------------------
        feat_res_db = [
            "desviacion_abs_vs_docente",
            "zscore_vs_docente",
            "rango_interno_rubrica",
            "ratio_mayusculas",
            "total_reportes",
            "resenas_usuario_24h",
            "horas_estudio_semanal",
        ]
        scaler_db_res = StandardScaler()
        X_res_db = scaler_db_res.fit_transform(df_res[feat_res_db])
        db_res = DBSCAN(eps=2.0, min_samples=6)
        db_res_labels = db_res.fit_predict(X_res_db)

        db_res_meta: dict[int, tuple[str, str]] = {}
        db_res_c_scaled: dict[int, np.ndarray] = {}
        db_res_c_orig: dict[int, dict[str, float]] = {}
        for cid in sorted(int(c) for c in np.unique(db_res_labels)):
            mask = db_res_labels == cid
            mean_scaled = np.mean(X_res_db[mask], axis=0)
            mean_orig = df_res.loc[mask, feat_res_db].mean().to_dict()
            c_dict = {f: round(float(mean_orig[f]), 3) for f in feat_res_db}
            db_res_c_scaled[cid] = mean_scaled
            db_res_c_orig[cid] = c_dict
            db_res_meta[cid] = describe_resena_cluster(df_res.loc[mask], cid)

        exp_db_res = persist_experiment(
            cur,
            nombre="DBSCAN_Resenas_Anomalias_Spam",
            algoritmo="DBSCAN",
            entidad_objetivo="RESENA",
            hiperparametros={"eps": 2.0, "min_samples": 6},
            features=feat_res_db,
            X_scaled=X_res_db,
            X_raw=df_res[feat_res_db],
            labels=db_res_labels,
            entity_ids=[int(x) for x in df_res["resena_id"]],
            cluster_meta=db_res_meta,
            centers_scaled=db_res_c_scaled,
            centers_orig=db_res_c_orig,
            ejecutado_por=admin_id,
        )

        # Sincronizar bandera es_anomalia_ml en resenas para outliers detectados por DBSCAN
        outlier_res_ids = [int(rid) for rid, lbl in zip(df_res["resena_id"], db_res_labels) if lbl == -1]
        if outlier_res_ids:
            cur.execute(
                "UPDATE resenas SET es_anomalia_ml = TRUE WHERE id = ANY(%s) AND es_anomalia_ml = FALSE",
                (outlier_res_ids,),
            )

        summary["dbscan_resenas"] = {
            "experimento_id": exp_db_res,
            "anomalias": len(outlier_res_ids),
            "n": len(df_res),
        }

        conn.commit()
        return summary
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    database_url = os.environ.get("DATABASE_URL", DEFAULT_DB_URL)
    admin_env = os.environ.get("ADMIN_ID")
    admin_id = int(admin_env) if admin_env and admin_env.isdigit() else None
    result = run_all(database_url, admin_id=admin_id)
    print(json.dumps(result, ensure_ascii=False, indent=2))
