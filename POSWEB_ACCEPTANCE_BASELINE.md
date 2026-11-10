# POSFlutter Web — línea base de aceptación

Fecha de establecimiento: 2026-10-20. Esta matriz sustituye porcentajes narrativos.

Regla de cálculo fija: `COMPLETADO_VERIFICADO` y `NO_APLICA_JUSTIFICADO` aportan 100% de su peso; `IMPLEMENTADO_NO_VERIFICADO` 80%; `EN_DESARROLLO` 60%; `PENDIENTE` y `BLOQUEADO` 0%. Un cambio de alcance requiere una fila nueva y una nota de impacto antes de cambiar los pesos.

| ID | Módulo | Requisito | Peso | Estado | Evidencia / validación | Bloqueador o trabajo pendiente |
|---|---|---|---:|---|---|---|
| A01 | Ventas | Checkout SQL, Cash/Card/Transfer/Mixto e idempotencia | 16% | COMPLETADO_VERIFICADO | P042 HTTPS, auditoría SQL, xUnit | — |
| A02 | Compras | Compra, recepción y FIFO compartido | 8% | COMPLETADO_VERIFICADO | P054/P042 SQL, 135 xUnit | — |
| A03 | Caja y gastos | Apertura, cierre, conciliación y gastos | 7% | COMPLETADO_VERIFICADO | P042 CashFix y HTTPS | — |
| A04 | Cancelaciones | Restitución FIFO, pagos, replay y sincronización | 6% | COMPLETADO_VERIFICADO | P038/P042 HTTPS y SQL | — |
| A05 | Reportes | Filtros, rentabilidad histórica, CSV/XLSX/PDF | 7% | COMPLETADO_VERIFICADO | P039 y P042 HTTPS | — |
| A06 | Seguridad | CSRF, roles, revocación, tenant y cero escrituras rechazadas | 7% | COMPLETADO_VERIFICADO | P042 Security5 HTTPS | — |
| A07 | Sincronización | Contratos y aplicación Android de compra/inventario | 6% | COMPLETADO_VERIFICADO | pruebas Flutter SQLite y regresión SQL | — |
| A08 | UX POS | POS web basado en `pos_screen.dart`, pagos y controles táctiles | 8% | COMPLETADO_VERIFICADO | P04 R7.4 y guardia de renderizador: captura HTTPS autenticada POS con catálogo, carrito, cobro inactivo y controles táctiles | — |
| A09 | P040 básico | Monitor central de dispositivos/sucursales/LastSyncAt | 3% | COMPLETADO_VERIFICADO | controlador, UI y xUnit | — |
| A10 | P040 avanzado | Versión, errores y operaciones de tablet | 2% | NO_APLICA_JUSTIFICADO | modelo Android actual no persiste esos datos centrales | requiere contrato Android aditivo aprobado |
| A11 | P041 | SSO externo | 2% | NO_APLICA_JUSTIFICADO | no existe proveedor/contrato externo asignado | definición de integración externa |
| A12 | P043 paquete | Publish MVC, scripts IIS y ZIP de laboratorio | 4% | COMPLETADO_VERIFICADO | ZIP 20261020 validado | — |
| A13 | P043 runtime | Instalación/reinicio/HTTPS bajo IIS de laboratorio | 2% | IMPLEMENTADO_NO_VERIFICADO | scripts y health check listos | servidor IIS de laboratorio autorizado |
| A14 | SQL Server 2022 | Esquema/migraciones y tablas de destino verificadas | 3% | COMPLETADO_VERIFICADO | A14 LAB nueva: 13 migraciones EF, 28 tablas/PK, 10 FK e índice R9 único verificados por SQL | — |
| A15 | Regresión | Suite backend, seguridad, SQL y publicación | 4% | COMPLETADO_VERIFICADO | xUnit 136/136, P042 Security7, publish aislado | — |
| A16 | Visual | Comparación Android/Web en sesión autenticada | 2% | COMPLETADO_VERIFICADO | P04 R7.4: seis vistas autenticadas comparadas y matriz P04 actualizada | — |
| A17 | Recuperación | Backup, restauración y rendimiento controlado | 4% | IMPLEMENTADO_NO_VERIFICADO | backup/restauración staged con manifiesto SHA-256, simulación y guía incluida en candidato 20261107 PASS | ejecutar backup/restauración contra servidor IIS LAB autorizado y validar health posterior |
| A18 | Datos | Migración lógica de datos comerciales a SQL 2022 | 4% | EN_DESARROLLO | destino y esquema P043 verificados | autorización explícita para copia |
| A19 | Aceptación | Operación de producción, despliegue y respaldo | 5% | BLOQUEADO | no se ha autorizado producción | autorización, IIS lab y validación de operación |

**Total de pesos: 100%. Baseline histórico inicial: 89%. Reconciliación 2026-11-07: A08/A16 pasaron de IMPLEMENTADO_NO_VERIFICADO (80% de su peso) a COMPLETADO_VERIFICADO (+2.0 puntos); A17 pasó a IMPLEMENTADO_NO_VERIFICADO tras una simulación íntegra de backup/restauración con manifiesto SHA-256 (+0.8); A14 se verificó sobre A14 LAB nueva (+0.6). Resultado trazable: 92.2% (presentado como 92% redondeado).**

## Estado contractual P04 actualizado — 2026-11-04

La matriz visual original de 18 filas se conserva en
`artifacts\P04_PARITY_COMPLETION_20261102_220000\P04_PARITY_18_VIEWS.csv`.
El inventario verificable es: 15 capturas MVC históricas, 56 PNG Flutter de
referencia, 2 filas no aplicables (Login y Configuración local) y 1 fila
bloqueada (Categorías). Ninguna fila se convierte en `VISUAL_PASS` sólo por
tener PNG.

| Filas | Clasificación contractual | Evidencia y pendiente |
|---|---|---|
| 01, 17 | NO_APLICA_JUSTIFICADO | Login y funciones locales de dispositivo no tienen par MVC equivalente. |
| 02–07, 09–16, 18 | REVIEW_REQUIRED (15) | Cada una ya tiene captura MVC en `P04_MVC_POWERSHELL_20261103_094817` y referencia Flutter disponible; falta únicamente revisión comparativa autenticada controlada, no una nueva captura. |
| 08 | BLOCKED | Es la única captura MVC faltante. Categorías está implementada y publicada; Flutter aporta `P04F_CATEGORIAS_20261102_111624.png`, pero los automatizadores de navegador devuelven 405 aunque el contrato HTTPS real acepta el POST. |

Por ello A08 y A16 mantienen `IMPLEMENTADO_NO_VERIFICADO`; el cálculo de
aceptación no se incrementa por las capturas existentes.

## Auditoría visual P04 de evidencia existente — 2026-11-04

La comparación controlada de las quince parejas ya disponibles quedó registrada
en `artifacts\P04_VISUAL_AUDIT_20261104\P04_15_COMPARISONS.md` y en la
matriz original de 18 filas. Resultado verificable: **0 PASS, 5 FAIL y 10
REVIEW_REQUIRED**. Los incumplimientos demostrados son Dashboard, POS
catálogo/carrito, Productos, Compras e Inventario: las evidencias muestran una
shell, navegación y jerarquía de controles de escritorio MVC que no corresponde
a la interfaz táctil Flutter. No se aplicó cambio de código sin una corrección
visual aprobada.

Categorías sigue **BLOCKED** por falta de una captura MVC autenticada válida.
Las diez filas REVIEW_REQUIRED requieren la misma sesión, rol, datos y estado
operativo en ambos clientes; las capturas históricas disponibles no permiten
aceptar equivalencia. A08 y A16 conservan `IMPLEMENTADO_NO_VERIFICADO` y el
avance de aceptación no cambia.

## Remediación P04 pendiente de evidencia — 2026-11-04

Se implementó una corrección mínima de la shell/tablet drawer, los registros
de Productos e Inventario y la presentación de Compras. Conserva las rutas y
servicios existentes; la compilación Release incremental y la sintaxis del
cliente pasaron. La trazabilidad está en
`artifacts\P04_VISUAL_FIX_20261104\P04_REMEDIATION.md`.

No se cambian los cinco `FAIL` a `PASS`: no se desplegó este candidato ni se
obtuvo una captura autenticada nueva. La aceptación y el porcentaje se
mantienen sin incremento.

## P04 V9 — evidencia autenticada disponible, 2026-11-04

La ejecución local V9 produjo capturas autenticadas de Dashboard, POS,
Productos, Compras, Inventario y Categorías con instalación, SQL LAB, HTTPS y
navegación aprobadas. La comparación visual de esas seis parejas se conserva
en `artifacts\P04_VISUAL_LOCAL_20261104_234359\P04_V9_VISUAL_COMPARISON.md`.
Resultado: **5 FAIL, 1 REVIEW_REQUIRED, 0 VISUAL_PASS**. La captura de
Categorías elimina el bloqueo de evidencia, pero demuestra un incumplimiento
de paridad; no convierte la fila en PASS. No se incrementa el avance ni se
certifica producción.

## Corrección candidata P04 V10 — 2026-11-04

La shell, Compras, Inventario y el vacío de Categorías fueron corregidos sin
cambiar reglas comerciales. El candidato LAB independiente está en
`C:\POSFlutter_Web\artifacts\POSFlutter_Web_P04_VISUAL_CANDIDATE_V10_20261104.zip`
con SHA-256 `B9579844D95B7CA64D159B5054FC4C01C440CB172FCFFEE76EFCFD9E040A29BF`.
Su build y sintaxis JS pasaron, pero aún no hay evidencia visual nueva; las
clasificaciones P04 no se modifican hasta ejecutar la comparación autenticada.

## P04 V10.1 — correcciones verificadas por build

Dashboard y drawer recibieron una corrección de causa raíz en el cliente. El
candidato pendiente de aceptación visual es
`C:\POSFlutter_Web\artifacts\POSFlutter_Web_P04_V10_1_VISUAL_CANDIDATE_20261105.zip`
con SHA-256 `CAF1B466FD059A9AABC2E0367B2DDB7F0FFF721915FE73F929D9E9D5527DCF53`.
La sintaxis JavaScript y el build Release pasaron; no sustituye nuevas capturas
autenticadas ni cambia los estados contractuales P04.

## P04 R8 — evidencia autenticada posterior (2026-11-05)

El candidato `C:\POSFlutter_Web\artifacts\POSFlutter_Web_COMMERCIAL_CANDIDATE_20261105_R8.zip`
(`2172002AA7AD42A03B3C90BBE8137E390125685F91C49C8378149E3422E2A7AB`) completó
instalación LAB, SQL, HTTPS, autenticación y seis rutas: PASS 10/10 técnico;
evidencia en `artifacts\P04_VISUAL_LOCAL_20261105_085214`.

La clasificación contractual no se convierte en PASS: Dashboard, Inventario,
Productos, Compras y Categorías quedan REVIEW_REQUIRED hasta comparar cada par
en las resoluciones del contrato; POS continúa FAIL por disposición distinta de
catálogo/carrito/cobro. Por tanto: **0/6 VISUAL_PASS**, producción NO GO.
