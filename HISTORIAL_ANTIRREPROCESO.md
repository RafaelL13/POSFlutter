# POSFLUTTER WEB — Historial maestro antirreproceso

Fecha de consolidación: 2026-11-08. Fuente canónica Windows: `C:\POSFlutter_Web\POSFlutter_Original`.

## Política de ejecución

1. Antes de intervenir, consultar este historial, evidencias originales, árbol Git y fuente canónica.
2. No reimplementar, recompilar, redesplegar, resembrar ni repetir una prueba aprobada sin cambio relevante, regresión reproducible o evidencia de invalidez.
3. Registrar cada bloqueador con hipótesis, evidencia, acción, criterio de cierre y estado; cerrar lo resuelto y no reabrir sin prueba nueva.
4. Separar `IMPLEMENTADO`, `PROBADO`, `CERTIFICADO`, `INSTALADO` y `PRODUCCIÓN`. Un PASS aislado no equivale a GO productivo.
5. No usar Codex para exploración o pruebas repetidas. Priorizar PowerShell local, automático, reversible, con logs y guardias. No tocar producción ni SQL productivo sin autorización.
6. Antes de una prueba de autenticación, comparar el contrato vigente con P04 aprobado; no inferir defecto de producto de un ejecutor nuevo.
7. No imprimir ni almacenar contraseñas, tokens, cookies o DPAPI desencriptado en logs.

## Registro de evidencia aprobada o histórica

| ID | Alcance | Resultado sustentado | Evidencia / referencia | Estado / restricción |
|---|---|---|---|---|
| P04-HTTPS | Conciliación real HTTPS | 5/5 PASS: venta 200, inexistente 404, otro tenant 404, viewer 403, pendiente 409; 3 sesiones autenticadas PASS | `artifacts\P04_HTTPS_ISOLATED_20261104_134055` | HISTÓRICO VERIFICADO; no repetir sin regresión |
| P04-VISUAL | Flujo visual autenticado | 11/11 PASS según historial | Historial P04 visual | HISTÓRICO VERIFICADO; conservar evidencia original |
| P04-PATCH | Integridad de parche visual, JS y MVC | PATCH_INTEGRITY, JS_SYNTAX, MVC_BUILD PASS; interacción visual NO_EXECUTED en esa evidencia específica | `artifacts\P04_VISUAL_APPLY_20261104_152953` | No confundir build con certificación visual |
| A14 | Base SQL LAB aislada | 13 migraciones, 28 tablas | `POSFlutter_MvcLab_A14_b5f458f24d49474bbac8d5eac9659f6a` | HISTÓRICO VERIFICADO; no recrear |
| A15-SQLITE | Pruebas SQLite compras, caja, venta/inventario | 9/9 PASS (1/1, 7/7, 1/1) | Historial A15 | HISTÓRICO VERIFICADO |
| A15-REG | Regresión automatizada | xUnit 136/136 PASS según historial | Historial A15; confirmar artefacto exacto si se necesita certificación formal | HISTÓRICO; no repetir sin cambio |
| A15-SEED | Identidad LAB | Seed autorizado ejecutado una vez, respaldo y verificación PASS; usuario `web.lab` | `artifacts\A15_AUTHORIZED_SEED_20261108_091446` | CERRADO; PROHIBIDO RESEMBRAR |
| A15-CLIENT | Cliente CURL V11 | Cinco campos, antiforgery, GUID de negocio válido y coincidente con seed, POST 200, sesión no establecida | `artifacts\A15_AUTHORIZED_SEED_20261108_091446\A15_AUTH_CURL_BUSINESS_CHECK_RESULTADO.txt` | Bloqueo DEL EJECUTOR; no atribuir defecto general a P04 |
| A15-MODEL | Instrumentación MVC temporal | `A15_MODELVALID=true`, `A15_BUSINESSEMPTY=true`, `A15_DEVICEEMPTY=false` | `artifacts\A15_LOCK32_RETRY_20261108_120054` | Discrepancia por conciliar con contrato P04; instrumentación retirada |
| A15-RAWFORM | Diagnóstico temporal | Publicación PASS, GET login 400, RAWFORM no observado; restauración inicial falló | `artifacts\A15_MODELSTATE_LAB_20261108_224150` | DIAGNÓSTICO INCONCLUSO; NO REPETIR |
| A15-IIS-RECOVERY | Restauración IIS LAB | `iis_original` 140 archivos, SHA256 PASS; sitio y pool Started, TCP 8443 True, `/health/live` 200 y `/Home/Login` 200 | `artifacts\A15_MODELSTATE_LAB_20261108_224150\iis_original` y salida PowerShell de recuperación | CERRADO PASS; no repetir restauración |

## Pendientes reales y dependencias

| ID | Pendiente | Criterio de cierre | Estado |
|---|---|---|---|
| A15-AUTH-CONCILIATION | Contrastar flujo/contrato P04 aprobado con A15 CURL; distinguir fallo de ejecutor vs regresión real | Diferencia identificada y corregida con una prueba dirigida; sin reimplementar autenticación aprobada | PENDIENTE |
| A17-DELIVERY | Certificación de reversión y evidencias vigentes, sin repetir respaldo aprobado | Criterios contractuales de rollback verificados en entorno aplicable | PENDIENTE DE CONCILIAR EVIDENCIA |
| A18 | Migración comercial | Requisitos y autorización correspondientes | PENDIENTE / SIN AUTORIZACIÓN PRODUCTIVA |
| P11 | Keystore Android y firma final | Material y pruebas contractuales disponibles | PENDIENTE |
| A19 | Despliegue productivo | Aceptación formal, autorización explícita, verificación y reversión | BLOQUEADO POR AUTORIZACIÓN Y ACEPTACIÓN |

## Estado consolidado

- Avance global **92.2% histórico**, no actualizado ni recalculable con estas evidencias parciales.
- Producción **NO_GO**. No se ha autorizado despliegue productivo.
- Fuente canónica y datos aprobados se preservan.
- Próxima acción técnica: **conciliación documental/código P04 vs A15**, sin HTTP, compilación, publicación ni seeding; luego corregir solo una diferencia demostrada.

## Plantilla de nuevas entradas

`FECHA | ID | FUENTE/HASH | REQUISITO | ESTADO | EVIDENCIA | CAMBIO DESDE ÚLTIMO PASS | ACCIÓN | CRITERIO CIERRE | PRODUCCIÓN`

No sobrescribir resultados históricos; agregar una entrada nueva con vínculo a la anterior. Ante contradicción, conservar ambas y documentar alcance/fecha antes de decidir.
