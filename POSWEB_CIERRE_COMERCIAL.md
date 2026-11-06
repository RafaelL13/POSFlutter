# POSFlutter Web — matriz única de cierre comercial

Fecha de actualización: 2026-11-06. Esta matriz clasifica evidencia vigente;
un renderizado o un ZIP no sustituye una certificación comercial.

| # | Requisito contractual | Estado | Evidencia vigente | Condición para cierre |
|---:|---|---|---|---|
| 1 | Login, sesión, CSRF y HTTPS LAB | VERIFICADO | P04 V10, `P04_VISUAL_LOCAL_20261105_001035/RESULTADOS.json` | Ninguna por este bloque. |
| 2 | Catálogo y precios centralizados | VERIFICADO | P02 catálogo/JWT y corrección JSON Productos V8 | Ninguna por este bloque. |
| 3 | Checkout, pagos e idempotencia SQL | VERIFICADO | AV96 7/7, conciliación HTTPS 5/5 | Ninguna por este bloque. |
| 4 | Caja y conciliación | VERIFICADO | P036 y P042 auditados | Ninguna por este bloque. |
| 5 | Compras, proveedores y FIFO | VERIFICADO | P037 HTTPS/SQL PASS | Ninguna por este bloque. |
| 6 | Cancelación y restitución FIFO | VERIFICADO | P038-J10 CLOSED/PASS | Ninguna por este bloque. |
| 7 | Reportes y exportaciones | VERIFICADO | P039 pruebas/exportaciones y P042 HTTPS | Ninguna por este bloque. |
| 8 | Autorización y aislamiento tenant | VERIFICADO | P042 Security7 y regresión 136/136 histórica | Ninguna por este bloque. |
| 9 | Productos y categorías | IMPLEMENTADO SIN VERIFICAR | Productos V8 PASS; Categorías renderiza estado vacío V10 | Evidencia visual V10.1 comparable. |
| 10 | Dashboard con indicadores reales | IMPLEMENTADO SIN VERIFICAR | Corrección V10.1 del desempaquetado de `items` | Captura autenticada V10.1 con datos LAB. |
| 11 | Drawer y navegación táctil | IMPLEMENTADO SIN VERIFICAR | Corrección V10.1 de visibilidad/eventos | Captura y prueba de foco/navegación V10.1. |
| 12 | Paridad visual de seis vistas prioritarias | PENDIENTE | Auditoría P04 V9: 5 FAIL/1 REVIEW_REQUIRED | Comparación Flutter–MVC V10.1. |
| 13 | Sincronización Android extremo a extremo | IMPLEMENTADO SIN VERIFICAR | Pruebas Flutter SQLite previas | Pull autenticado LAB hacia SQLite con dispositivo autorizado. |
| 14 | Compatibilidad de cantidades decimales | BLOQUEADO | `docs/DECIMAL_QUANTITY_COMPATIBILITY.md`; entidades y contratos vigentes usan `int` | Definición comercial de fracciones, escala, redondeo y capacidad Android; después migración SQL/API/Flutter versionada. |
| 15 | Paquete IIS, instalación y rollback | IMPLEMENTADO SIN VERIFICAR | `Build-PosFlutterWebCandidate.ps1`, install/preflight no-apply | IIS LAB autorizado y health posterior. |
| 16 | Despliegue productivo | PENDIENTE | No autorizado | Destino, respaldo y autorización explícita. |
| 17 | Android release firmado | BLOQUEADO | Keystore original preservada; Flutter 3.47.1/Dart 3.13.1, Gradle 9.3.1 y JDK 17.0.12 disponibles localmente | Credenciales originales de firma (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`) por mecanismo autorizado; no se generará ni sustituirá certificado. |

## Totales

- Total: 17 requisitos.
- VERIFICADO: 8.
- IMPLEMENTADO SIN VERIFICAR: 5.
- PENDIENTE: 2.
- BLOQUEADO: 2.
- NO APLICA: 0.

No se calcula un nuevo porcentaje global: los criterios tienen riesgos y pesos
distintos, y la evidencia no permite convertir los conteos en un porcentaje de
aceptación comercial confiable. La referencia histórica de 63% queda separada
de esta matriz.

## Actualización Android release — 2026-11-06

- El bloqueo es exclusivamente de firma: se confirmaron localmente Flutter
  3.47.1/Dart 3.13.1, Gradle 9.3.1 y JDK 17.0.12 compatibles. No existe
  `android/key.properties` ni las cuatro variables de firma en el proceso.
- La keystore original se conserva sin modificación. No se generó certificado,
  no se descargaron herramientas y no se ejecutó una nueva compilación release.

## Paquete comercial candidato

`C:\POSFlutter_Web\artifacts\POSFlutter_Web_COMMERCIAL_CANDIDATE_20261106_HEALTHCHECK_WAIT.zip`

SHA-256: `FD23A995E8C4AD9F1E91B3936F8EB16AB4145A0A98638F7DF81743A4D2B81F4E`.

Contiene `release/`, scripts IIS, manifiesto SHA-256 e instrucciones de
instalación. Se validó su estructura y extracción; no se instaló en IIS.

## Bloqueadores de entorno comprobados

- IIS LAB: la cuenta actual no puede leer configuración IIS (`WebAdministration`
  exige proceso elevado). El preflight anterior fue de sólo lectura y reportó
  `https://localhost:8443/health` como `UNREACHABLE`; no se cambió ningún sitio.
- Paridad visual V10.1: requiere ejecutar el certificador local autorizado con
  las capturas Flutter de referencia; no se califica por navegación.

## P04 R3.2 — evidencia autenticada y clasificación (2026-11-05)

- El certificador HTTPS aislado se ejecutó contra el candidato R3.2 y la base
  LAB autorizada, sin IIS ni escrituras comerciales: instalación, SQL, HTTPS,
  autenticación y las seis navegaciones fueron **PASS (10/10)**. Evidencia:
  `artifacts\P04_VISUAL_LOCAL_20261105_071222`.
- La comparación humana contra las referencias Flutter no es equivalente a esos
  PASS técnicos: Dashboard, POS, Productos, Compras, Inventario y Categorías
  siguen **FAIL de paridad visual** por jerarquía, distribución y componentes.
  Dashboard ya no muestra claves técnicas e Inventario ya no exhibe un GUID
  como nombre de producto.
- Candidato actualizado, validado por publicación, manifiesto y extracción:
  `C:\POSFlutter_Web\artifacts\POSFlutter_Web_COMMERCIAL_CANDIDATE_20261105_R3_2.zip`
  SHA-256 `2A29B264AC75A83F7701DACAD6A9A97858C72E83AD14383BBEC748E16353AB70`.
  No se instaló en IIS ni producción.

## P04 R7 — corrección de seis vistas (2026-11-05)

- Se reutilizaron las fuentes Flutter `home_content.dart`, `pos_screen.dart`,
  `products_screen.dart`, `purchases_screen.dart`, `inventory_screen.dart` y
  `categories_screen.dart` como referencia. La web ahora comparte patrón de
  acción primaria, tarjeta informativa, búsqueda/lista táctil y accesos rápidos
  para las vistas dinámicas, sin modificar servicios comerciales.
- La certificación autenticada R7 mantiene **PASS 10/10** técnico. Evidencia y
  hashes: `artifacts\P04_VISUAL_LOCAL_20261105_084516`.
- Paridad verificable: Dashboard e Inventario tienen composición equivalente
  suficiente para **REVIEW_REQUIRED**; POS, Productos, Compras y Categorías
  continúan **FAIL** por diferencias demostradas de estructura/acción. P04 no
  se cierra ni se incrementa el avance comercial.
- Paquete único vigente de esta corrección:
  `C:\POSFlutter_Web\artifacts\POSFlutter_Web_COMMERCIAL_CANDIDATE_20261105_R7.zip`;
  SHA-256 `18AEF86F84FA4E73336FF172D2C1BEDC010BA1D1F7AE7AB911D90011B509EC30`.

## P04 R8 — cuatro pantallas y alta de Categorías (2026-11-05)

- Productos migró de tabla técnica a tarjetas operativas sin alterar filtro,
  catálogo, edición ni permisos. Compras conserva recepción real y añade la
  guía informativa observada en Flutter. Categorías tiene acción primaria y
  `AdminCategoriesController` con sesión, rol, CSRF, validación de tenant,
  transacción Serializable y `CategoryPullPayload`/`SyncChange` compatibles
  con Android.
- La ejecución autenticada conserva **PASS 10/10** técnico; evidencia y hashes:
  `artifacts\P04_VISUAL_LOCAL_20261105_085214`.
- Paridad: Dashboard, Inventario, Productos, Compras y Categorías pasan a
  **REVIEW_REQUIRED** por composición equivalente pero sin una revisión manual
  final de los pares a las tres resoluciones; POS permanece **FAIL** por su
  disposición catálogo/carrito/cobro distinta de Flutter. El alta real de
  Categorías está **IMPLEMENTADA / NOT_VERIFIED** porque Kestrel 59444 usa el
  guardia de sólo lectura LAB; no se habilitó escritura ni se creó dato alguno.
- Candidato integrado único: `C:\POSFlutter_Web\artifacts\POSFlutter_Web_COMMERCIAL_CANDIDATE_20261105_R8.zip`;
  SHA-256 `2172002AA7AD42A03B3C90BBE8137E390125685F91C49C8378149E3422E2A7AB`.

## Cierre técnico EF y paquete vigente (2026-11-05)

- La migración aditiva `20261106010757_AddInventoryAdjustmentIdempotencyIndex`
  alinea el snapshot EF con el índice de idempotencia de ajustes R9. La
  comprobación `has-pending-model-changes` es PASS; no hay pérdida de datos ni
  migraciones ejecutadas fuera de LAB.
- Paquete candidato actualizado y validado estructuralmente, sin instalación:
  `C:\POSFlutter_Web\artifacts\POSFlutter_Web_COMMERCIAL_CANDIDATE_20261105_EF_MODEL_FIX.zip`;
  SHA-256 `6BF5C6494CA9C43FE0F644C33A566A982077C2965D100C26869EC582C95AA78E`.
- P11 Android sigue BLOCKED: el keystore original coincide con su SHA-256
  aprobado, pero no hay credencial de firma disponible en variables, archivos
  autorizados ni respaldos montados. Las entradas de Credential Manager son
  ajenas a la firma; no se leyeron secretos ni se intentaron contraseñas.

## IIS LAB — corrección de hostname preparada (2026-11-06)

- Causa confirmada de `https://localhost:8443/health` HTTP 400: HTTP.sys,
  antes de IIS/ASP.NET, registró el binding LAB como
  `HTTPS://127.0.0.1:8443:127.0.0.1/`; el certificado vigente es válido para
  `localhost`. La respuesta incluyó `Server: Microsoft-HTTPAPI/2.0` e
  `Invalid Hostname`.
- Se incorporó `deploy\iis\Fix-PosFlutterWebLabHostname.ps1`, que sólo cambia
  ese binding a `127.0.0.1:8443:localhost`, exige elevación, captura evidencia
  previa, valida `/health` por TLS normal y revierte el binding si falla.
  Parser PowerShell 5.1 y guardia no elevada: PASS.
- Candidato actualizado, validado sin instalación:
  `C:\POSFlutter_Web\artifacts\POSFlutter_Web_COMMERCIAL_CANDIDATE_20261106_IIS_HOSTNAME_FIX.zip`;
  SHA-256 `8E4B772CE2D1DAD03E6B0242F2ECA690D3B0A55A47A2C0C7279F1D80BA819FEF`.
  Aplicar el cambio queda bloqueado por privilegios IIS administrativos de la
  sesión actual; no se modificó producción ni otro sitio.
