# POSFlutter Web — estado canónico local

## P04 V9 · 2026-11-04

- Requisito: comparación visual Flutter–MVC de las seis vistas prioritarias.
- Problema: P04 V9 aprobó la automatización LAB, pero dicha prueba no evaluó
  equivalencia visual contractual.
- Evidencia: `artifacts\P04_VISUAL_LOCAL_20261104_234359\RESULTADOS.json`
  (10/10 PASS) y
  `artifacts\P04_VISUAL_LOCAL_20261104_234359\P04_V9_VISUAL_COMPARISON.md`.
- Candidato conservado: `C:\POSFlutter_Web\artifacts\POSFlutter_Web_P04_VISUAL_CANDIDATE_R2_V8_20261104_234344.zip`,
  SHA-256 `0D67CDB924BB422DE9C58EA666F0141AA490DB59869C1F2C8EB4AC523004E42E`.
- Resultado: cinco incumplimientos visuales demostrados (Dashboard, POS,
  Compras, Inventario y Categorías); Productos requiere comparación con un
  escenario equivalente. No se modificó código, SQL, IIS ni producción.
- Próxima acción: aplicar correcciones mínimas a la shell y jerarquía de las
  cinco vistas, publicar sólo un candidato LAB nuevo y obtener capturas
  comparables antes de cambiar P04 a PASS.

## P04 V10 · 2026-11-04

- Corrección: la shell compartida usa ahora app bar blanca con identidad POS
  Flutter, conserva utilidades administrativas y mantiene la navegación
  operativa. Se reforzó la jerarquía táctil de registros, compras e inventario.
- Corrección de Categorías: el estado vacío devuelto por el servidor se muestra
  como estado vacío semántico; no se inventó una acción de alta ni se escribió
  SQL.
- Archivos: `Views\Shared\_Layout.cshtml`, `wwwroot\css\p04-visual-fixes.css`
  y `wwwroot\js\site.js`. Respaldo verificable:
  `.codex-backups\p04-v9-shell-20261104_235259\SHA256.txt`.
- Pruebas: `node --check` PASS; build Release aislado PASS, 0 advertencias y
  0 errores. Candidato independiente:
  `C:\POSFlutter_Web\artifacts\POSFlutter_Web_P04_VISUAL_CANDIDATE_V10_20261104.zip`,
  SHA-256 `B9579844D95B7CA64D159B5054FC4C01C440CB172FCFFEE76EFCFD9E040A29BF`.
- Pendiente: instalar únicamente en LAB autorizado y obtener nuevas capturas
  comparables; P04 permanece FAIL hasta contar con esa evidencia.
- El ejecutor local P04 se ajustó para recibir SHA-256 explícito del candidato;
  validación estática PowerShell 5.1 PASS, SHA del script
  `25AD60FBFFE2CE02B17479F44830EAF2CD761400592045D345CDCB5590395266`.

## P04 V10.1 · 2026-11-05

- Causa confirmada del Dashboard vacío: `DataController` publica la respuesta
  como `{ items: objeto }`; `site.js` sólo desempaquetaba `items` cuando era un
  arreglo y terminaba renderizando el envoltorio, sin propiedades primitivas.
- Corrección: `load` desempaqueta cualquier propiedad `items` antes de decidir
  entre lista y resumen. No cambia el contrato HTTP, autorización ni datos.
- Corrección drawer: la barra lateral cerrada ahora es no visible y no recibe
  eventos; sólo vuelve visible e interactiva con `drawer-open`.
- Pruebas: `node --check` PASS; build Release aislado PASS, 0 errores y 0
  advertencias. Candidato LAB:
  `C:\POSFlutter_Web\artifacts\POSFlutter_Web_P04_V10_1_VISUAL_CANDIDATE_20261105.zip`,
  SHA-256 `CAF1B466FD059A9AABC2E0367B2DDB7F0FFF721915FE73F929D9E9D5527DCF53`.
- Pendiente: capturas autenticadas con este candidato para comprobar
  indicadores Dashboard, drawer cerrado y paridad; no se afirma VISUAL_PASS.

## Empaquetado comercial permanente · 2026-11-05

- Causa del bloqueo V10.1: los ZIP contenían la publicación en la raíz, pero
  el ejecutor y el contrato de despliegue exigen `release/PosFlutter.Web.dll`.
- Corrección permanente: `deploy\Build-PosFlutterWebCandidate.ps1` publica en
  `release/`, incluye scripts IIS, manifiesto SHA-256, valida ZIP y extracción
  temporal antes de aceptar un paquete. Preflight e instalador IIS ahora
  validan esa misma estructura; el instalador maneja un `appsettings.json`
  vacío sin asumir propiedades existentes.
- Verificaciones: parser PowerShell 5.1 PASS (3 scripts); build/publicación,
  layout, extracción y preflight de instalación sin `-Apply`: PASS.
- Candidato comercial R3:
  `C:\POSFlutter_Web\artifacts\POSFlutter_Web_COMMERCIAL_CANDIDATE_20261105_R3.zip`,
  SHA-256 `E16BFB5640BE36FA34127523C6DC7265B9E5C701414E4C640C5D3D0A89E8F6A8`.
- Preflight IIS permaneció de sólo lectura y devolvió `Health=UNREACHABLE` en
  `https://localhost:8443`; no se cambió IIS. La instalación LAB requiere que
  el host autorizado esté disponible.

## Cantidades decimales e IIS LAB · 2026-11-05

- La revisión de entidades, constraints y contratos confirma que cantidades de
  compra, lote, movimiento, venta y asignación FIFO son `int`; cambiar sólo MVC
  truncaría stock y rompería Android. `DecimalQuantity` es una utilidad exacta
  no integrada; la migración decimal existente es intencionalmente vacía.
- Estado `P02_DECIMAL_GATE=BLOCKED` hasta una definición comercial explícita de
  productos fraccionados, escala y redondeo. Impacto y siguiente migración
  compatible: `docs\DECIMAL_QUANTITY_COMPATIBILITY.md`.
- `WebAdministration` no pudo leer IIS LAB sin elevación. No se modificó IIS,
  bases ni cuentas. El siguiente chequeo autorizado requiere una sesión elevada
  que pueda consultar sólo el sitio POSFlutterWeb_LAB.
