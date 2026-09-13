# POSFlutter Commercial Readiness Audit

Fecha de auditoría: 2026-09-12

Fuente de verdad: working copy local `C:\POSFlutter`

Rama observada: `feature/ux-professionalization`

HEAD base observado: `37ff382` (`feat: professionalize operational UX`)

Referencia publicada: `origin/main` en `750a550`

> Dictamen: **NO COMERCIALMENTE LISTO**. La base transaccional, offline, FIFO, autorización y sincronización es considerablemente más sólida que la de un prototipo. FASE A cerró la deuda de formato/analyze y completó logout, pero el checkout sólo admite efectivo, caja carece de operación diaria completa y faltan validación Android/UAT y soporte operable. No debe venderse todavía como producto generalista.

## 1. Resumen ejecutivo

| Área | Nota /100 | Evaluación |
|---|---:|---|
| Arquitectura | 84 | Separación Flutter/SQLite/API/SQL Server correcta; repositories y transacciones críticas bien orientados. |
| Funcionalidad | 68 | Núcleo de venta, compras, inventario, caja, gastos, usuarios y reportes presente; faltan pagos no efectivo y movimientos manuales de caja. |
| Integridad | 88 | Cantidades y dinero enteros, FK, constraints, FIFO y operaciones críticas transaccionales. Faltan pruebas de recuperación y carga sobre la versión actual. |
| Offline | 86 | Venta y escritura local no dependen de Internet; SyncQueue durable. La comunicación de estado puede mejorar. |
| UX | 66 | POS tablet y pantallas principales han mejorado, pero varios flujos siguen siendo formularios genéricos y caja es demasiado básica. |
| UI | 73 | Material 3 y componentes compartidos; persisten inconsistencias, textos técnicos y riesgo no cerrado con teclado/orientaciones. |
| Facilidad de uso | 61 | Un cajero puede aprender efectivo, pero no se cubre el flujo comercial normal de tarjeta/transferencia y onboarding no guía hasta la primera venta. |
| Seguridad | 83 | Capabilities, guards, tenant isolation, DeviceMode y autorizaciones especiales están implementados y probados. Logout local quedó cerrado y conserva los datos operativos. |
| Pruebas | 82 | 301 pruebas Flutter y 60 backend pasan. Cobertura crítica buena, pero faltan pagos, caja completa, carga, recuperación y UAT Android actual. |
| Rendimiento | 62 | No hay evidencia de benchmark con 10.000 productos/100.000 ventas; búsquedas y varios listados cargan colecciones completas. |
| Soporte | 42 | No existe centro de diagnóstico/ayuda/configuración ni paquete de diagnóstico seguro. |
| Preparación comercial | 55 | Buena plataforma técnica, todavía no un producto que deba cobrarse a comercios sin completar P0 y UAT. |

### Evidencia ejecutada en esta auditoría

| Gate | Resultado real |
|---|---|
| Estado Git/diff/log | Ejecutado; rama distinta de `main`, cambios locales sin commit y archivos sin seguimiento. |
| `flutter pub get` | PASS. |
| `dart format --output=none --set-exit-if-changed .` | PASS final: 132 archivos, 0 cambios pendientes. La deuda histórica de 31 archivos se normalizó por separado. |
| `flutter analyze` | PASS final: 0 issues. Causa inicial: `if` heredado sin llaves en `auth_repository.dart:31`; el formatter global hizo visibles 18 casos históricos equivalentes, corregidos mecánicamente. |
| `flutter test` | PASS final: 301/301, 0 fallidos, 0 omitidos. |
| `flutter build apk --debug` | `BLOCKED_BY_ENVIRONMENT`: Gradle `java.io.IOException: Unable to establish loopback connection`. |
| APK release | NO EJECUTADO en esta auditoría; no se solicitaron ni expusieron secretos. |
| `dotnet restore Pos.Server.sln` | PASS tras autorización para leer NuGet.Config. |
| `dotnet build --no-restore` | PASS, 0 errores, 12 advertencias xUnit1051. |
| `dotnet test --no-build` | PASS: 60/60. |
| `tools/structural_gate.py` | PASS; 0 secretos de alta confianza. |
| `tools/sqlite_validation.py` | PASS; integrity/FK/rollback/conflictos/enteros/FIFO verificados. |
| Android install/UAT/logcat | NO EJECUTADO en esta auditoría. |

### Estado Git y alcance

La auditoría encontró trabajo no confirmado en logout, diseño responsive, categorías/productos y tests. No se descartó ni sobrescribió. `git diff --cached` estaba vacío. Los cambios locales auditados incluyen `auth_repository.dart`, `app_navigation_drawer.dart`, `app_components.dart`, catálogo/productos y sus tests. La rama local no es la rama principal declarada: está dos contextos por delante de `origin/main` mediante el commit de profesionalización y cambios adicionales sin commit.

### Mapa funcional real

| Módulo | Estado | Evidencia/limitación principal |
|---|---|---|
| Login | IMPLEMENTADO / REQUIERE MEJORA UX | Local offline y cloud AdminReadOnly; falta política clara de case/backoff/diagnóstico. |
| Logout | IMPLEMENTADO | Sesión local, tokens cloud, providers y navegación quedaron cerrados; falta únicamente smoke Android actual. |
| Sesión persistente | IMPLEMENTADO | `app_settings` y contexto local; guards redirigen según sesión/capabilities. |
| Primer inicio | IMPLEMENTADO / REQUIERE MEJORA UX | Crear negocio o enrolar; no guía hasta primera venta. |
| Crear negocio | IMPLEMENTADO | Negocio, principal, dispositivo y admin en transacción; encola Business. |
| Registrar sucursal | PARCIAL | Principal automática y enrolamiento remoto; no hay administración local completa de sucursales. |
| Registrar dispositivo/enrolamiento | IMPLEMENTADO | Token one-time, identidad estable y modo; cobertura cliente/backend. |
| Dashboard | IMPLEMENTADO / REQUIERE MEJORA UX | KPIs/actions/sync; faltan alertas de agotado/bajo stock y caja más rica. |
| Nueva venta/carrito | IMPLEMENTADO / DEFECTUOSO COMERCIALMENTE | Flujo tablet, enteros, stock, descuento y FIFO; sólo efectivo. |
| Productos | IMPLEMENTADO / CAMBIOS SIN COMMIT | Crear/editar/desactivar, categoría, SKU, barcode, precio, mínimo y stock. |
| Categorías | IMPLEMENTADO | CRUD básico y creación contextual; UX todavía genérica. |
| Proveedores | IMPLEMENTADO / REQUIERE MEJORA UX | Registro/listado; poca ficha e historial visible. |
| Compras | IMPLEMENTADO / REQUIERE MEJORA UX | Proveedor, líneas, costos, lotes y SyncQueue; corrección/cancelación no expuesta. |
| Lotes/FIFO | IMPLEMENTADO | Asignación, costo histórico y validación auxiliar reales. |
| Inventario/Kardex | IMPLEMENTADO / REQUIERE MEJORA UX | Existencia, valor, lotes, movimientos y ajustes; simplificar lenguaje/filtrado. |
| Ventas/detalle | IMPLEMENTADO | Historial, detalle y costos según permisos. |
| Cancelaciones | IMPLEMENTADO | Autorización, razón, restauración exacta de lotes y auditoría. |
| Caja/apertura/cierre | PARCIAL | Apertura/cierre e integridad; no hay UI para entradas/salidas ni resumen profesional. |
| Entradas/salidas de caja | IMPLEMENTADO INTERNAMENTE EN MODELO / NO EXPUESTO | `cash_movements` existe; no se encontró flujo UI dedicado. |
| Gastos | IMPLEMENTADO / REQUIERE MEJORA UX | Local/sync y caja para efectivo; formulario/lista genéricos. |
| Usuarios/roles/permisos | IMPLEMENTADO | Roles cerrados, UI profesional, guards y aislamiento; cambios previos locales. |
| Autorizaciones especiales | IMPLEMENTADO | Segundo usuario/reauth, bind, consumo único, auditoría y anti-replay. |
| Reportes locales | IMPLEMENTADO | KPIs/reportes/CSV capability-driven. |
| Respaldos/restauración | IMPLEMENTADO / FALTA UAT ACTUAL | Integridad, preventivo y autorización; no validado ahora en Android. |
| Sincronización | IMPLEMENTADO | Push/pull, cursor, backoff, errores terminales y conflictos. |
| Estado offline/online | PARCIAL / REQUIERE MEJORA UX | Panel de sync y mensajes; falta separación universal operación local/sync. |
| Conflictos | IMPLEMENTADO INTERNAMENTE / PARCIALMENTE EXPUESTO | Persistencia y clasificación; resolución comercial para admin insuficiente. |
| Administración nube | IMPLEMENTADO | Lecturas/reportes GET tenant-safe en AdminReadOnly. |
| Clientes | AUSENTE | No existe entidad, feature, ruta ni contrato. |
| Configuración | AUSENTE | No existe ruta/pantalla central. |
| Ayuda/soporte/diagnóstico | AUSENTE | No existe centro visible ni exportación diagnóstica segura. |
| Información negocio/usuario | PARCIAL | Dashboard muestra usuario/sucursal/rol; no hay ficha central. |
| Versión de aplicación/Acerca de | AUSENTE EN UI | Versionado existe en build, pero no se expone al usuario. |

No se detectaron `TODO`, `FIXME`, `HACK`, `UnimplementedError` ni `NotImplementedException` en fuente funcional mediante búsqueda/gate. No se hallaron rutas registradas sin representación en el modelo de navegación salvo rutas hijas de reportes nube, que se alcanzan desde su módulo. El principal caso “implementado pero no expuesto” es `cash_movements`; la detección exhaustiva de código muerto requiere análisis de cobertura/compilador adicional y no se declara completada sólo por búsqueda textual.

## 2. Lo que ya está bien

- Flutter no se conecta a SQL Server. La nube se consume mediante API y el POS escribe primero en SQLite.
- Venta, detalle, asignaciones FIFO, disminución de lotes, kardex, movimiento de caja y SyncQueue se realizan en una transacción crítica.
- SQLite usa cantidades y centavos enteros con `CHECK`, claves foráneas, IDs globales y restricciones de unicidad relevantes.
- FIFO conserva costo histórico por `sale_detail_lots`; la cancelación restaura las asignaciones originales y deja auditoría.
- La sincronización tiene cola durable, retry/backoff, clasificación de rechazos, cursor monotónico, pull atómico y conflictos persistidos.
- Aislamiento por negocio/sucursal/dispositivo y autorización por capabilities están aplicados también en repositories, no sólo en UI.
- `AdminReadOnly` es modo de dispositivo y no rol. Las escrituras críticas fallan cerradas.
- El dashboard es funcional: ventas, operaciones, caja, inventario, utilidad/margen según permisos, accesos rápidos y estado de sync.
- Búsqueda POS por nombre, código/SKU y código de barras ya existe. Las cantidades permanecen enteras.
- Productos soportan categoría, código, barcode, precio, stock mínimo, estado y edición sin tocar existencias ni historia FIFO.
- Gestión de usuarios evita IDs visibles, usa roles tipados y transacción local + SyncQueue.
- Backup/restore dispone de validación de integridad, copia preventiva y autorización sensible.
- Backend compila y sus 60 pruebas cubren aislamiento, sync, enrollment, autorización y reportes.
- Material 3, design tokens, estados comunes y diseño adaptativo dan una base visual coherente.

## 3. Bloqueadores P0

| ID | Problema | Impacto | Evidencia | Solución recomendada | Archivos afectados | Riesgo |
|---|---|---|---|---|---|---|
| P0-01 CLOSED | Working copy no superaba analyze/formato | Impedía una base reproducible | FASE A: format 132/0, analyze 0, tests 301/301 y diff-check PASS | Cerrado. Mantener formatter/analyze como gates directos por exit code | Auth y 31 archivos históricos de formato inventariados | Bajo |
| P0-02 MODEL CLOSED / UI OPEN | El modelo interno ya soporta Cash/Card/Transfer y desglose mixto; el checkout visible aún fuerza efectivo | La integridad, caja, sync y reportes ya distinguen componentes; el usuario todavía no puede elegirlos hasta FASE C | FASE B: `sale_payments` SQLite/EF, payload Sale v2 compatible con v1, backfills legacy, suma exacta, cash parcial, cancelación trazable y reportes por componente; 311 Flutter y 65 backend PASS | Completar exclusivamente la UX operacional del checkout en FASE C sin reabrir el modelo | POS controller/screen y tests UAT de cobro | Medio |
| P0-03 | No hay APK/UAT Android actual verificable | No se conoce comportamiento real de teclado, orientación, reinicio, logout y offline en esta working copy | Build debug falló por loopback; install/launch/logcat no ejecutados | Ejecutar build en host funcional, instalar en tablet/emulador limpio y completar guion E2E offline/reinicio/logcat | Android, procedimientos QA | Medio |
| P0-04 | Caja no cubre operación comercial diaria | El saldo esperado puede ser incompleto y el cajero no tiene arqueo explicable | UI sólo ofrece abrir/cerrar; no expone entrada/salida ni resumen previo. Reporte remoto reconoce que no sincroniza movimientos manuales | Implementar entradas/salidas tipadas, resumen por método, esperado/contado/diferencia, confirmación fuerte y sync | cash UI/repository/schema/contracts/backend/reportes/tests | Alto |
| P0-05 CLOSED | Logout no estaba terminado como entrega | Riesgo de sesión confusa y regresión de acceso en dispositivo compartido | FASE A: 4/4 tests específicos y 56/56 matriz auth/router/navigation; sesión y tokens limpios, datos preservados, cancelación segura, doble ejecución bloqueada, `/login`, Back bloqueado y relogin | Cerrado. Logout permanece distinto de desenrolar/borrar/cambiar negocio | auth repository, drawer y tests | Medio |

### Evidencia FASE B — modelo de pagos

- Baseline de implementación: `447e63e5c602e9d487e6140517fbbadc006faf1c`, rama `feature/ux-professionalization`.
- SQLite avanzó de schema 5 a 6 de forma aditiva. `PRAGMA integrity_check`, `foreign_key_check`, backfill Cash, reapertura sin duplicado y preservación de venta/FIFO/caja/SyncQueue pasan.
- El repository acepta pagos tipados y confirma venta, pagos, FIFO, stock, kardex, efectivo, auditoría y SyncQueue en una sola transacción. Cash, Card, Transfer y combinaciones de dos/tres métodos están probados; importes cero, negativos o sumas distintas se rechazan.
- `receivedCents` permanece como metadata de efectivo entregado; el pago Cash representa sólo el importe aplicado y el cambio no se registra como ingreso.
- Sale sync payload v2 incluye pagos dentro del agregado. El servidor conserva compatibilidad con payload v1, valida suma/métodos/IDs y los retries no duplican pagos.
- EF migration `20260913135713_AddSalePayments` fue listada y probada contra SQL Server LocalDB desde la migración inicial con una venta Cash histórica; el segundo migrate no duplica filas.
- Los pagos permanecen asociados a ventas canceladas. La restauración FIFO continúa y sólo el componente Cash genera/revierte efectivo local.
- Reportes por método distribuyen una venta mixta entre sus componentes; caja usa únicamente el componente Cash y conserva aislamiento tenant.
- Gates de cierre: format/analyze Flutter PASS, 311/311 Flutter PASS, build backend PASS y 65/65 backend PASS, structural/SQLite/diff-check PASS. APK debug quedó `BLOCKED_BY_ENVIRONMENT` por `java.io.IOException: Unable to establish loopback connection`.
- Decisión factual: `P0-02_MODEL=CLOSED`; `P0-02_UI=OPEN`. No se expusieron Card/Transfer/Mixed en UI durante FASE B.

## 4. Mejoras P1

| ID | Mejora | Valor / recomendación |
|---|---|---|
| P1-01 | Onboarding operativo | Tras crear/enlazar negocio, checklist no obligatoria: producto, existencia, caja y primera venta. Reduce soporte y errores. |
| P1-02 | Configuración central | Negocio/sucursal visibles, preferencias POS seguras, sincronización, respaldo, versión y soporte. No permitir editar claves relacionales. |
| P1-03 | Diagnóstico seguro | Versión/build, dispositivo, sucursal, SQLite integrity, respaldo, última sync y pendientes; copiar sin tokens/contraseñas/payloads. |
| P1-04 | Caja profesional | Turno, responsable, desglose por método, movimientos, gastos, cancelaciones, total de operaciones y confirmación de cierre. |
| P1-05 | Rendimiento de catálogos | Búsqueda SQL paginada/indexada y debounce. Evitar cargar/filtrar todo en memoria para 10.000 productos. |
| P1-06 | Reporte de sync accionable | Separar “operación local disponible” de “sincronización pendiente”; resolver/reintentar conflictos sin lenguaje técnico. |
| P1-07 | Manejo de errores en dos niveles | Mensaje comercial + evento diagnóstico seguro. Hoy abundan `catch (_)`, mensajes genéricos y pérdida de causalidad. |
| P1-08 | Productos duplicados | Mantener unicidad de código por negocio y agregar política explícita para barcode; traducir SQLite constraint a mensaje comprensible. |
| P1-09 | Compra/corrección | Historial y detalle claros; definir cancelación/reversión sólo si puede preservar lotes consumidos e historia. Nunca editar una compra histórica destructivamente. |
| P1-10 | Backup/recovery UAT | Probar backup, corrupción, restauración preventiva, reinicio y reanudación sync sobre Android real. |

## 5. Mejoras P2

- Cliente opcional y “Público general”, sin bloquear venta y sin facturación electrónica.
- Favoritos, frecuentes y recientes calculados localmente para negocios con catálogos medianos/grandes.
- Venta suspendida/recuperada con reserva explícita o sin reserva; requiere política de stock concurrente.
- Importación CSV con vista previa, validación, dry-run y transacción; exportación segura de catálogos/reportes.
- Descuentos porcentuales y por línea sólo con reglas de redondeo en centavos y authorization/audit.
- Dashboard propietario con comparación de periodos y alertas, separado del dashboard del cajero.
- Ayuda contextual y guía breve de primera venta.
- Cámara como lector opcional; lector USB/Bluetooth tipo teclado debe funcionar primero sin dependencia adicional.

## 6. Mejoras P3

- Cotizaciones separadas de ventas e inventario; no deben consumir FIFO hasta convertirlas.
- Promociones con motor de reglas versionado; alto riesgo para totales/sync, no necesarias en la primera edición.
- Devoluciones parciales avanzadas con trazabilidad de venta/lote; diseñarlas después de pagos múltiples.
- Actualización administrada de app con rollback y política por canal.
- Plantillas opcionales de ticket. La impresión nunca debe bloquear confirmar la venta.

## 7. Funciones comerciales ausentes

| Función | Valor y negocios | Riesgo | Offline/FIFO/sync | ¿Primera versión? |
|---|---|---|---|---|
| Efectivo/tarjeta/transferencia | Esencial para casi todos | Medio | Offline; FIFO igual; amplía contrato de pago | Sí, P0 |
| Pago mixto | Muy alto en retail | Alto | Tabla/desglose local y sync; FIFO igual | Sí, P0/P1 |
| Movimientos manuales de caja | Esencial donde hay retiros/fondos | Alto | Afecta esperado y sync, no FIFO | Sí, P0 |
| Clientes opcionales | Conveniencia/retención | Medio | Nueva entidad sync; no FIFO | P2, salvo negocio que lo exija |
| Scanner teclado | Mucho valor en retail | Bajo | Totalmente local | Sí; asegurar foco/submit |
| Cámara scanner | Valor en equipos sin lector | Medio | Local; permisos/cámara | P2 |
| Stock mínimo/alertas | Ya existe dato; falta explotar alerta global | Bajo | Local, no modifica FIFO | Sí, P1 |
| Favoritos/frecuentes/recientes | Acelera venta | Bajo | Local; frecuente puede derivarse | P2 |
| Filtros/búsqueda avanzada | Importante con catálogo grande | Medio | Consultas locales e índices | P1 |
| Notas de venta | Útil en servicios/encargos | Bajo/medio | Nueva columna/contrato | P2 |
| Repetir venta | Acelera, pero debe revalidar precio/stock | Medio | Nueva venta y FIFO actual | P2 |
| Suspender venta | Útil en alto tráfico | Alto | Persistencia local y conflicto de stock | P2 |
| Cotización | Valor sectorial | Medio | No consumir inventario | P3 |
| Devoluciones | Importante en retail | Alto | Reintegro por lote/pago/auditoría/sync | P1 posterior a pagos |
| Promociones | Valor sectorial | Alto | Totales/versionado/conflictos | P3 |
| Importar catálogo | Reduce onboarding masivo | Alto | Validación/atomicidad/sync masivo | P2 |
| Configuración/ayuda/soporte | Reduce instalación y soporte | Bajo/medio | No comprometer integridad | P1 |
| Bitácora visible | Útil a administrador | Medio | Filtrada y tenant-safe | P2 |

No se encontró módulo real de clientes en schema, features, rutas o backend. Debe ser opcional y la venta sin cliente debe seguir siendo el camino principal.

## 8. Problemas UX

- Flujo de venta observado: Inicio → Nueva venta → búsqueda/categoría → producto → cantidad → efectivo recibido → cobrar. Es razonablemente corto para efectivo, pero la selección del método inexistente produce un modelo mental falso.
- El botón de importe exacto y sugerencias de efectivo deben reducir tecleo; los incrementos deben ser montos comerciales configurables, no adornos.
- Scanner teclado puede aprovechar la búsqueda existente, pero hace falta conducta explícita al Enter: coincidencia exacta única agrega y limpia búsqueda; ambigüedad muestra selección.
- Caja usa formularios genéricos y no presenta esperado/contado/diferencia antes de confirmar.
- Varias pantallas basadas en `DatabaseListScreen` se perciben como CRUD genérico, no como flujo comercial especializado.
- Primer inicio configura identidad técnica, pero no acompaña hasta tener stock y caja abierta.
- No existe Configuración, Ayuda, Acerca de ni Diagnóstico en rutas/navegación.
- Los errores genéricos “No se pudo…” evitan filtrar datos técnicos, pero no ofrecen causa o siguiente acción.
- Etiqueta visible “Barcode” debe ser “Código de barras”.

## 9. Problemas UI

- Base Material 3 y tokens compartidos: profesional.
- La adaptación por `LayoutBuilder`, `SafeArea`, scroll y panel POS ancho es adecuada, pero no sustituye prueba real con teclado Android.
- Existen anchos máximos de diálogo (por ejemplo 620/820) con constraints; son aceptables si se mantienen scroll y viewport disponible. Deben probarse a 1200×1920 y 1920×1200 además de matrices existentes.
- Estados vacíos han mejorado en módulos recientes; catálogos genéricos deben revisarse uno a uno para CTA útil.
- Chips comunican estado además de color: correcto. Añadir Semantics a KPI, estado sync y acciones iconográficas críticas.
- Evitar tablas demasiado densas en portrait; priorizar detalle progresivo y encabezados persistentes en listas largas.

## 10. Problemas técnicos

- La rama auditada no es `main`; publicar sin integrar ordenadamente haría que GitHub no represente el producto probado.
- Hay cambios y tests sin commit. No existe artefacto reproducible de esta combinación.
- FASE A normalizó 31 archivos históricos mediante una operación exclusiva de formatter; debe mantenerse en un commit `style` separable del fix funcional.
- FASE A dejó `flutter analyze` en 0 issues mediante exit code directo; no se usó el script externo defectuoso como evidencia.
- Búsqueda POS filtra en memoria `bootstrap.products`; no escala con catálogo grande.
- Índices SQLite actuales favorecen FIFO, movimientos y sync, pero faltan índices explícitos para búsquedas por negocio/nombre/barcode y consultas históricas por fecha/sucursal.
- `payment_method` es texto libre en schema; requiere dominio cerrado y compatibilidad/migración.
- No hay modelo de desglose de pagos, imprescindible para mixto y arqueo correcto.
- Algunos `catch (_) {}` silencian bootstrap/contexto y dificultan soporte.
- Build backend conserva 12 warnings xUnit1051; no bloquean, pero deben sanearse.

### Riesgos de pérdida o error operativo

- No se observó una ruta directa evidente de pérdida en la transacción de venta/FIFO; esa parte está bien defendida.
- El mayor riesgo operativo actual es **clasificación monetaria incorrecta**: toda venta se registra como efectivo, alterando caja y reportes si el comercio acepta otros medios.
- Corregir o cancelar compras consumidas puede destruir trazabilidad si se implementa como edición. Debe diseñarse como reversión con validación de lotes.
- Pago mixto mal modelado como un string o campos agregados puede romper arqueo y sync; requiere entidad `sale_payments`/equivalente, suma exacta y transacción única.
- Restauración y concurrencia multi-sucursal necesitan UAT de recuperación actual antes de producción.

## 11. Seguridad

Fortalezas: hashing/salt local, secure token store, JWT/refresh, claims tenant-safe, capabilities, guards de ruta y repository, autorizaciones especiales consumibles, replay bloqueado, DeviceMode fail-closed y restore sensible.

Pendientes:

- Validar en Android real el cierre de sesión ya cubierto por tests: limpieza de access/refresh tokens, invalidación de providers, navegación atrás bloqueada y conservación de la base local.
- Login local normaliza de forma inconsistente: creación reciente normaliza a minúsculas, pero `AuthRepository.login` consulta `username.trim()` literalmente. Revisar usuarios legacy/case sensitivity.
- Agregar límites/rate limiting local razonable o backoff de login sin bloquear recuperación legítima.
- Crear logging diagnóstico con redacción: nunca hashes, salts, tokens, contraseñas ni payloads sensibles.
- Revisar backup exportado: ubicación, cifrado/política de custodia y exposición fuera del sandbox de Android.

## 12. Offline/sync

La arquitectura cumple el principio central: venta local y FIFO no dependen de Internet. Los gates verificaron cola, cursor, rollback, conflictos y errores terminales. La UI debe presentar siempre dos estados separados:

- **Operación local: disponible/no disponible** (sólo por un problema local real como base corrupta o sesión inválida).
- **Sincronización: al día/pendiente/requiere atención**.

Agregar última sincronización, número de pendientes y reintento manual seguro. Los conflictos no deben pedir al cajero escoger payloads; deben usar lenguaje comercial y escalar al administrador. Probar reinicio con cola grande, tokens vencidos, reloj incorrecto, conectividad intermitente y dos sucursales modificando catálogos.

## 13. Rendimiento

No hay benchmark ejecutado para 1.000/5.000/10.000 productos ni 100.000 ventas. Por ello rendimiento no puede declararse PASS.

Riesgos concretos:

- Bootstrap del POS trae productos/lotes agregados y luego filtra en Dart.
- Listados genéricos y reportes pueden crecer sin paginación local.
- `contains` en strings minúsculos no usa índices SQLite.
- Sin índices por `sales(branch_id,sale_datetime)`, `purchases(branch_id,purchase_date)`, `products(business_id,barcode)` y campos de consulta, históricos grandes degradarán.
- Sync debe procesar lotes acotados y ceder al UI; medir tiempo, memoria, jank y tamaño de cola.

Plan de medición: fixtures deterministas, p50/p95 de arranque/búsqueda/cobro, raster/build times, memoria y base; criterios sugeridos: búsqueda visible <150 ms, agregar <100 ms, confirmación local <500 ms p95 en tablet objetivo.

## 14. Accesibilidad

- Material y botones grandes ayudan; labels de formulario y tooltips existen en varias acciones.
- Faltan auditorías Semantics sistemáticas y tests con TalkBack.
- Probar escalas 1.0, 1.2, 1.5 y 2.0, contraste claro/oscuro y teclado visible.
- No depender sólo de color para stock/error/sync; conservar texto e icono.
- Botón deshabilitado de cobro debe explicar “abre caja”, “agrega productos” o “ingresa efectivo suficiente”.
- Asegurar 48×48 dp en controles de cantidad y acciones de fila.

## 15. Pruebas faltantes

| Área | Estado | Falta |
|---|---|---|
| Login | Parcial/implementado | Case normalization, bloqueo/backoff, reinicio y token vencido. |
| Logout | Implementado y validado en FASE A | Falta únicamente smoke Android cuando el entorno permita construir/instalar. |
| Navegación/permisos | Buena | E2E real por los cuatro roles en Android. |
| Venta/FIFO | Buena para efectivo | Tarjeta, transferencia, mixto, scanner y carrera de doble cobro. |
| Caja | Parcial | Entrada/salida, resumen, cierre confirmado, pagos por método. |
| Cancelación | Buena lógica | UAT UI y pagos múltiples/devolución. |
| Backup/restore | Buena lógica | Corrupción, espacio insuficiente, process death y Android scoped storage. |
| Sync/offline | Buena lógica | Carga, conectividad intermitente, reinicio y multi-dispositivo real. |
| Formularios/overflow | En expansión | 1200×1920, 1920×1200, escala 1.5/2.0, teclado real. |
| Rendimiento | Ausente | Fixtures 10k productos/100k ventas y métricas p95. |
| Accesibilidad | Ausente | Semantics, contraste y TalkBack. |

Los tests actuales no deben reemplazarse; deben ampliarse con comportamiento, invariantes DB y UAT, no sólo búsqueda de textos.

## 16. Documentación desactualizada

- `PROJECT_STATUS.md` conserva cifras históricas como 22/22 o 28/28 y mezcla checkpoints anteriores con estado actual. La ejecución real de FASE A es 301/301 Flutter; format/analyze ya pasan. El backend permaneció sin diff y su última validación de auditoría fue 60/60.
- `CHANGELOG.md` declara “Primera candidata productiva” 1.0.0; esa frase debe matizarse porque faltan gates externos, pagos comerciales y UAT actual.
- `README.md` y documentos de fases son evidencia histórica, no estado vivo. Deben enlazar un único status actual con fecha/commit/gates.
- No actualizar esos archivos hasta cerrar y confirmar las fases correspondientes. Este informe registra discrepancias sin reescribir la historia.

## 17. Plan de implementación

Cada fase termina en `format`, `analyze`, tests dirigidos/completos, build cuando aplique, `git diff --check`, revisión de diff y commit independiente. No avanzar con gate roto.

### FASE A — Cerrar working copy y logout — CERRADA

Completada e integrada en commits separados: normalización mecánica y logout local/cloud/provider/router, con datos preservados, cancelación, anti-doble ejecución, back navigation y relogin. Format/analyze/tests/diff-check/gates internos pasan. APK debug quedó bloqueado por loopback del entorno.

### FASE B — Modelo de pagos offline

Definir enum/versionado y `sale_payments`; migración SQLite/EF, contratos sync idempotentes y compatibilidad con ventas `Cash` existentes. Invariantes: importes enteros, positivos y suma exacta al total.

### FASE C — Checkout tablet

Selector Efectivo/Tarjeta/Transferencia/Mixto; recibido/cambio sólo para efectivo; importe exacto y sugerencias útiles; doble submit bloqueado. Tests widget/repository/FIFO/sync.

### FASE D — Caja comercial

Entradas, salidas, resumen de turno, desglose por método, esperado/contado/diferencia y confirmación. Auditoría y sync completos.

### FASE E — Onboarding hasta primera venta

Checklist opcional y contextual; CTA para categoría/producto, compra/entrada, abrir caja y vender. Sin bloquear usuarios experimentados.

### FASE F — Configuración, ayuda y diagnóstico

Pantallas capability-driven, datos seguros, versión/build, salud local, respaldo y sync. Copiar diagnóstico redactado.

### FASE G — Rendimiento y catálogo grande

Índices/migración, búsqueda paginada/debounced y pruebas 1k/5k/10k/100k. Mantener scanner teclado rápido.

### FASE H — Errores y accesibilidad

Taxonomía de errores usuario/diagnóstico, logging redactado, Semantics, contraste, touch targets y matriz de escala.

### FASE I — Recovery y Android UAT

Build firmado, instalación limpia, flujo E2E, offline, process death/reinicio, backup/restore, sync multi-sucursal, logcat y rendimiento en tablet física.

### FASE J — Piloto comercial controlado

Un negocio piloto, datos ficticios primero, rollback documentado, soporte y métricas. Corregir hallazgos antes de disponibilidad general.

## 18. Criterios para considerar versión comercial

- [ ] Working copy integrada en rama canónica y reproducible.
- [x] `dart format --set-exit-if-changed .` PASS.
- [x] `flutter analyze` PASS sin falsos positivos de scripts.
- [x] Flutter tests PASS (301/301 al cerrar FASE A).
- [x] Backend build y tests PASS (60/60; quedan warnings no bloqueantes).
- [ ] APK debug/release de la revisión exacta PASS y certificado verificado.
- [ ] Login/logout/relogin/back navigation PASS en Android.
- [ ] Efectivo, tarjeta, transferencia y mixto PASS offline.
- [ ] Venta real, FIFO, caja y reportes coherentes por método.
- [ ] Reinicio/process death conserva venta, stock, caja y cola.
- [ ] Operación offline comunica claramente que se puede seguir vendiendo.
- [ ] Sync intermitente y multi-sucursal probado sin duplicar operaciones.
- [ ] Conflictos y rechazos tienen recuperación administrable.
- [ ] Backup y restore probados en Android, incluida copia preventiva.
- [ ] Sin overflow crítico en 800×1280, 1280×800, 1200×1920 y 1920×1200.
- [ ] Teclado Android, rotación, SafeArea y escala 1.5/2.0 probados.
- [ ] Rendimiento aceptable con 10.000 productos y 100.000 ventas.
- [ ] Caja tiene entradas/salidas, arqueo y cierre no accidental.
- [ ] Configuración, diagnóstico, ayuda y soporte están disponibles.
- [ ] No hay secretos/versiones de keystore/configuración sensible en Git.
- [ ] UAT de cajero sin capacitación extensa completado.
- [ ] Piloto comercial y procedimiento de recuperación aprobados.

### Conclusión profesional

POSFlutter ya tiene rasgos de producto profesional: integridad transaccional, FIFO histórico, operación offline, controles de autorización, sync durable, backend tenant-safe y una base UI tablet coherente. Lo que todavía lo hace parecer incompleto no es principalmente el color o el estilo: son la ausencia de pagos comerciales, una caja demasiado limitada, falta de configuración/soporte y ausencia de evidencia Android actual.

P0-01 y P0-05 quedaron cerrados en FASE A. Antes de cobrar a un cliente todavía deben cerrarse P0-02 a P0-04, completar las fases B–D y ejecutar la fase I sobre el commit exacto. Hasta entonces, la clasificación correcta es **piloto técnico avanzado, no versión comercial general**.
