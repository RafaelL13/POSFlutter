# POSFlutter Web — estado de entrega PS18 (2026-10-22)

## Misión catálogo y cotización (2026-10-23)

- Corregido y cubierto por regresión el contrato de `GET /data/products`: `TenantReadService.ProductsAsync` ahora emite `availableQuantity` como la suma real de lotes FIFO **activos, positivos, del tenant y de la sucursal de la sesión**. El serializador web entrega el campo como `availableQuantity`, consumido por `pos-tablet-parity.js`; no se fabrica stock en JavaScript.
- La regresión xUnit v3 `Product_catalog_exposes_only_tenant_branch_stock_and_category` pasó con un lote propio válido de 7 y lotes excluidos inactivo (50), agotado y de otra sucursal (40), además de producto/lote extranjero. Confirma `"availableQuantity":7` en el JSON serializado y que no se filtra stock extranjero.
- Verificaciones realizadas: `node --check` de `site.js` y `pos-tablet-parity.js` PASS; build aislado de `Infrastructure.Tests` PASS (0 errores; advertencias xUnit1051 preexistentes); ejecutor xUnit v3 real `dotnet Infrastructure.Tests.dll -method ...Product_catalog_exposes_only_tenant_branch_stock_and_category` PASS (1/1).
- `dotnet publish` aislado de `PosFlutter.Web` compiló Domain, Application, Infrastructure y Web, pero el copiado final falló por espacio insuficiente en `C:` al escribir `C:\tmp\posflutter-catalog-stock-20261023-publish`. No se borraron artefactos ajenos ni se declara publish PASS.
- Paridad visual desktop/tablet frente al Flutter original: **NO CERTIFICADA**; no hubo evidencia visual comparativa nueva. El flujo de cotización sigue siendo lectura/cálculo servidor y popup de impresión, sin escritura; no se detectó ni corrigió otro defecto comprobable de impresión/ticket en esta misión.
- Instalación, IIS, producción, UAT y aprobación de cualquier ZIP: **NO APROBADOS / NO EJECUTADOS**.
- Respaldos previos por archivo: `.ps18-backups\catalog-stock-20261023`.

## Resultado

- Candidato preparado, **no instalado** y no certificado para producción.
- xUnit v3 real: **PASS 137/137** (0 fallos, 0 errores), ejecutado con `dotnet Infrastructure.Tests.dll`.
- Sintaxis de `pos-tablet-parity.js`: **PASS** (`node --check`).
- Publicación MVC .NET 10 Release aislada: **PASS** con `P042IsolatedBuild=true` en `C:\POSFlutter_Web\artifacts\PS18_CODEX_BUILD_20261022234122\publish`.
- Preflight del instalador: **PASS**, acción `NONE`; no se aplicó IIS, SQL comercial ni producción.

## Correcciones PS18

- Las pruebas de contrato copian `Program.cs` y `CentralInventoryAuthentication.cs` a la salida de test, por lo que el contrato se ejecuta también desde una raíz aislada. La política financiera se conserva explícita en el grupo de reportes.
- El POS conserva la venta confirmada aun si falla `window.print()`: muestra folio y comprobante visible con `Reimprimir ticket`; no vuelve a informar que la venta falló ni permite un cobro duplicado por ese error.
- La disponibilidad del catálogo es informativa; el checkout del servidor mantiene la validación autoritativa de existencias.
- El preflight IIS normaliza separadores de rutas ZIP para validar paquetes generados por Windows.

## Evidencia LAB HTTPS/CDP

- LAB exclusiva creada por la automatización: `POSFlutter_MvcLab_QUOTES12_b28e3d8981d3426fafe42a70f5f94ad9`.
- PASS: conectividad LocalDB, build/publish, seed, login, cotización anónima denegada, HTTPS quote, precio/total servidor, validaciones de carrito, aislamiento tenant y ausencia de escritura SQL por cotización.
- Browser main/tablet/PDF: **NOT_VERIFIED**. La evidencia más reciente es `C:\POSFlutter_Web\artifacts\POSWEB_QUOTES_PS12_20261022_235439`; Chrome 155 no despacha de forma fiable clicks CDP por coordenadas. El diagnóstico confirma POS y catálogo cargados (10 disponibles). No se declara PASS sintético.
- Producción certificada: **NO**.

## Entrega

- Paquete preflight PASS: `C:\POSFlutter_Web\artifacts\POSFlutter_Web_PS18_DEPLOYMENT_CANDIDATE_20261022_2358.zip`.
- Instalador: `deploy\iis\Install-PosFlutterWeb.ps1`; requiere autorización escrita, `-Apply -OwnerAuthorized`, destino LAB nuevo y cadena SQL segura antes de cualquier aplicación.
- Respaldos previos a edición: `.ps18-backups\20261022233929`.

## Pendientes

- Resolver el despacho de gestos CDP/ventana emergente para certificar captura y PDF de navegador.
- Comparación visual autenticada contra Flutter y certificación de despliegue siguen pendientes de evidencia y autorización.

## Certificación P037 adicional (2026-11-04)

- Compra HTTPS certificada sin reutilizar ni limpiar la base histórica P037: la base exclusiva `POSFlutter_MvcLab_P037_Rerun_b260283e051642508323b7bfb16605f7` se creó tras comprobar que no existía y se sembró con `MvcLabSeed` y contraseña efímera de proceso.
- El certificador original aprobado realizó una sola ejecución: login HTTPS, compra 200, replay 200, conflicto 409, validaciones 400 y auditoría SQL PASS. Resultado: una compra, una línea, un lote FIFO adicional, existencias 10→15, un movimiento Purchase y un SyncChange; no hubo ventas.
- El ZIP de distribución se conservó sin regenerar porque no hubo cambio de código publicado: `artifacts\POSFlutter_Web_DISTRIBUCION_VERIFICADA_20261103_224105.zip`, SHA-256 `72C4E93C40A89D25BF85E5E8C2E22BDA2165797AF86D9DFA0277A5D6DC00E395`, 133 entradas.

## Cierre documental independiente de P04 (2026-11-04)

- Scripts de instalación, preflight y verificación IIS: sintaxis Windows PowerShell 5.1 PASS. El instalador exige destino nuevo, backup y autorización explícita para `-Apply`; no se aplicó contra producción.
- La matriz contractual separa 15 vistas `REVIEW_REQUIRED`, Categorías `BLOCKED` y dos vistas no aplicables. La evidencia visual no se sobredeclara como PASS.
- El paquete aprobado permanece íntegro y es el candidato instalable actual. Producción sigue bloqueada por destino, autorización y aceptación visual autenticada.
- Inventario final de capturas: las 15 filas aplicables ya tienen PNG MVC y referencias Flutter; sólo Categorías carece de captura MVC autenticada. Por ello no se deben repetir las otras capturas para cerrar P04.
- La plantilla de configuración no contiene una cadena comercial y el instalador rechaza `-Apply` sin destino nuevo, conexión SQL segura y `-OwnerAuthorized`. No hay destino productivo identificado en la evidencia actual; no se solicitó ni realizó instalación productiva.

## Auditoría visual contractual P04 (2026-11-04)

- Comparación de las 15 parejas de PNG existentes completada sin iniciar navegador, recompilar, modificar IIS ni escribir SQL. Resultado: **0 PASS, 5 FAIL, 10 REVIEW_REQUIRED**; detalle y hashes en `artifacts\P04_VISUAL_AUDIT_20261104\P04_15_COMPARISONS.md`.
- FAIL demostrados: Dashboard, POS catálogo/carrito, Productos, Compras e Inventario. La diferencia es estructural (drawer/tablet, tarjetas/acciones táctiles y jerarquía) frente a la shell administrativa MVC; no fue clasificada como diferencia cosmética.
- Categorías continúa BLOCKED hasta contar con captura MVC autenticada válida. Las diez revisiones requieren capturas del mismo flujo, rol y datos. P04 visual no está certificado y el ZIP vigente se conserva sin modificación.

## Remediación P04 sin despliegue (2026-11-04)

- Implementadas correcciones visuales mínimas de Dashboard, POS navegación,
  Productos, Compras e Inventario. No se tocaron controladores ni lógica
  comercial. `node --check` y build Release incremental: PASS, 0 advertencias,
  0 errores.
- Publicación aislada: `artifacts\P04_VISUAL_FIX_20261104\publish`.
  Candidato separado: `artifacts\POSFlutter_Web_P04_VISUAL_CANDIDATE_20261104.zip`,
  SHA-256 `D301EFD69FAFEA0D39B12BCCDA385AC167FC26B05DC9349C248DCFC23AB45D12`.
  El ZIP previamente aprobado no fue sobrescrito.
- P04 sigue sin certificar visualmente hasta obtener evidencia autenticada LAB
  de las cinco vistas corregidas; no se declara PASS por compilación.

## Runtime aislado del candidato P04 (2026-11-04)

- `POSFlutter_Web_P04_VISUAL_CANDIDATE_20261104.zip` se verificó por SHA-256 y
  se instaló únicamente en `C:\POSFlutter_Web\LAB_P04_VISUAL_20261104`.
  Kestrel propio respondió `/health` 200 y `/Home/Login` 200 con antiforgery.
- No se alteró IIS ni `LAB_IIS`, no hubo login ni SQL write, y el proceso propio
  se detuvo. Detalle: `artifacts\P04_VISUAL_FIX_20261104\LAB_RUNTIME_VERIFICATION.md`.

## P04 R3.2 — evidencia actual (2026-11-05)

- La certificación aislada completó instalación LAB, SQL, HTTPS, autenticación y
  las seis navegaciones: **PASS 10/10**. Evidencia:
  `artifacts\P04_VISUAL_LOCAL_20261105_071222`.
- P04 visual: **FAIL, 0/6 certificadas**. Las capturas autenticadas demuestran
  que la web funciona, pero aún no iguala la jerarquía/tabletas Flutter.
- Candidato sin instalar: `C:\POSFlutter_Web\artifacts\POSFlutter_Web_COMMERCIAL_CANDIDATE_20261105_R3_2.zip`;
  SHA-256 `2A29B264AC75A83F7701DACAD6A9A97858C72E83AD14383BBEC748E16353AB70`.
  Producción: NO.

## P04 R7 (2026-11-05)

- Candidato verificado: `C:\POSFlutter_Web\artifacts\POSFlutter_Web_COMMERCIAL_CANDIDATE_20261105_R7.zip`;
  SHA-256 `18AEF86F84FA4E73336FF172D2C1BEDC010BA1D1F7AE7AB911D90011B509EC30`.
- Build y certificación aislada: PASS (10/10 técnico). Paridad visual: PARTIAL;
  Dashboard e Inventario REVIEW_REQUIRED, POS/Productos/Compras/Categorías FAIL.
  Producción permanece NO GO.

## P04 R8 (2026-11-05)

- Candidato: `C:\POSFlutter_Web\artifacts\POSFlutter_Web_COMMERCIAL_CANDIDATE_20261105_R8.zip`;
  SHA-256 `2172002AA7AD42A03B3C90BBE8137E390125685F91C49C8378149E3422E2A7AB`.
- Build Release, JavaScript y ejecución LAB técnica: PASS. Alta de Categorías:
  implementada con sincronización compatible, pero NOT_VERIFIED contra escritura
  por el guardia LAB de sólo lectura. Producción: NO GO.

## Entrega EF / firma Android (2026-11-05)

- IMPLEMENTADO/PROBADO: migración EF aditiva de idempotencia R9 y modelo EF
  consistente (`has-pending-model-changes`: PASS).
- EMPAQUETADO: `C:\POSFlutter_Web\artifacts\POSFlutter_Web_COMMERCIAL_CANDIDATE_20261105_EF_MODEL_FIX.zip`
  (`6BF5C6494CA9C43FE0F644C33A566A982077C2965D100C26869EC582C95AA78E`),
  estructura y extracción PASS; no instalado.
- BLOQUEADO: APK release actualizado requiere las cuatro credenciales
  originales de firma. El keystore se conserva íntegro; no se creó ni sustituyó
  ningún certificado. Producción: NO GO.

## IIS LAB hostname (2026-11-06)

- IMPLEMENTADO: reparador reversible y acotado al binding LAB 8443, con TLS
  normal, health check y rollback automático.
- PROBADO: sintaxis PowerShell 5.1 y rechazo seguro sin elevación PASS.
- BLOQUEADO: aplicar el cambio requiere un proceso administrativo IIS; la
  sesión actual no puede acceder a `WebAdministration` ni modificar bindings.
- EMPAQUETADO: `C:\POSFlutter_Web\artifacts\POSFlutter_Web_COMMERCIAL_CANDIDATE_20261106_IIS_HOSTNAME_FIX.zip`
  (`8E4B772CE2D1DAD03E6B0242F2ECA690D3B0A55A47A2C0C7279F1D80BA819FEF`).

## P04 visual — corrección mínima pendiente de aceptación (2026-11-06)

- IMPLEMENTADO: app bar/drawer, iconografía de métricas y estados vacíos, y
  supresión de GUID técnico como etiqueta de Inventario.
- PROBADO: sintaxis JavaScript, build MVC Release y revisión de diff PASS.
- CERTIFICACIÓN: REVIEW_REQUIRED. Las seis capturas certifican ruta/sesión,
  no equivalencia visual completa: la comparación requiere mismo viewport,
  rol y datos que las referencias Flutter. Detalle reproducible:
  `artifacts\P04_VISUAL_REAL_FIX_20261106\COMPARISON.md`.
- PRODUCCIÓN: NO GO. No se modifica el paquete previamente validado mientras
  no exista una captura autenticada del binario corregido.

## P04 focalizado — 2026-11-06

- PROBADO: candidato R3 aislado, SQL LAB, HTTPS, autenticación, Dashboard,
  Inventario y Categorías PASS. Las capturas y hashes están en
  `artifacts\P04_VISUAL_REAL_FIX_20261106\COMPARISON.md`.
- CERTIFICACIÓN: P04 permanece PARTIAL/REVIEW_REQUIRED; no hay equivalencia
  visual certificada mientras los escenarios Flutter y MVC difieran en datos,
  rol o viewport. PRODUCCIÓN: NO GO.

## P04 R3 — POS, Productos y Compras (2026-11-06)

- PROBADO: ejecución focalizada autenticada
  `P04_VISUAL_LOCAL_20261106_110552` a 2560x1600. Instalación/SQL LAB/
  identidad/HTTPS/autenticación y las tres rutas PASS; no se repitieron los
  flujos comerciales ya certificados.
- CERTIFICACIÓN VISUAL: POS, Productos y Compras permanecen FAIL. Las
  diferencias verificadas son de jerarquía/shell y composición, no sólo de
  datos. Los pares, hashes y criterio están en
  `artifacts\P04_VISUAL_REAL_FIX_20261106\COMPARISON.md`.
- BLOQUEADOR DE COMPARABILIDAD: el material Flutter no proporciona el seed ni
  los IDs de negocio/sucursal/dispositivo/usuario del escenario original. Se
  requiere un seed LAB desechable y trazable para una recaptura equivalente;
  no se alteró el LAB compartido. PRODUCCIÓN: NO GO.

## P04 R7.1 — candidato de corrección visual (2026-11-06)

- Paquete: `C:\POSFlutter_Web\artifacts\POSFlutter_Web_P04_VISUAL_FIX_R7_1_20261106.zip`.
  SHA-256 `44124282F4BBD89A7EDDACF299CEC8F2113CD2EB680DF936B1B02FF7F3BB4E82`.
  Publicación, manifiesto, layout y extracción: PASS. Instalación: NONE.
- El candidato contiene únicamente ajustes de jerarquía visual POS y el
  formato de compras semilladas; no certifica una pantalla hasta que la
  recaptura autenticada exista.
- Bloqueo concreto: LocalDB `POSWEB_V44_LAB_20261018` no inició; evidencia
  sanitizada en `artifacts\P04_VISUAL_LOCAL_20261106_174321\runtime`.
  Producción permanece NO GO.

## P04 R7.4 — entrega focalizada (2026-11-07)

- POS, Productos y Compras: PASS visual autenticado con escenario aislado y
  evidencia/hash en `artifacts\P04_VISUAL_REAL_FIX_20261106\COMPARISON.md`.
- Paquete candidato: `C:\POSFlutter_Web\artifacts\POSFlutter_Web_P04_VISUAL_FIX_R7_4_20261107.zip`,
  SHA-256 `F9BADC615ECE1057B8C6E109535DC6ECDE24394127729957FD38340D50EAC084`.
  Instalación productiva: NONE. Dashboard, Inventario y Categorías aún
  requieren cierre visual; producción sigue NO GO.

## P04 R7.4 — paridad visual contractual cerrada (2026-11-07)

- Las seis vistas P04 quedan PASS con evidencia HTTPS aislada y capturas
  autenticadas. La matriz conserva las demás filas pendientes fuera del alcance
  P04. Producción permanece NO GO hasta completar los demás gates comerciales.

## Guardia de certificación P04 (2026-11-07)

- El flujo POS tiene un renderizador canónico comprobado por el certificador;
  el ejecutor selecciona puerto loopback libre y espera LocalDB sin reintentos
  de arranque equivalentes. Evidencia PASS:
  `artifacts\P04_VISUAL_LOCAL_20261107_040200\RESULTADOS.json`.

## Conciliación comercial e instalación LAB (2026-11-07)

- A08/A16 quedan verificados por P04 R7.4; la matriz ponderada se reconcilia a
  90.8% (91% redondeado), desde el baseline histórico 89%.
- Instalador y reversión: validación sintáctica PASS. Modo preflight del
  instalador: PASS sin escritura. Preflight IIS LAB: certificado/binding y
  listener PASS, health `UNREACHABLE`; no se aplicó ningún cambio, por lo que
  A13 no se cierra.

## Entrega LAB con backup/reversión — 2026-11-07

- Paquete comercial vigente: `C:\POSFlutter_Web\artifacts\POSFlutter_Web_COMMERCIAL_CANDIDATE_20261107_A14_GUARD.zip`
  (`28C25C1E0A84169BDC4E3DDA5AE1CBECFDFA29E49C4CA802F42A1AE658910CB1`).
- El paquete incluye scripts de instalación, backup y restauración staged;
  su layout y extracción, el parser PowerShell 5.1 y una simulación íntegra
  de hashes son PASS. Ningún sitio IIS, conexión SQL o dato LAB fue modificado.
- Para instalación final falta: administrador IIS autorizado, destino LAB
  nuevo/identificado, conexión SQL LAB segura y autorización escrita para
  `-Apply -OwnerAuthorized`; producción continúa NO_GO.
- El paquete incluye además el ejecutor A14 de migración sobre una base LAB
  nueva GUID; sus modos plan y rechazo de base protegida pasaron sin escritura.

## A14 SQL Server 2022 LAB — 2026-11-07

- `POSFlutter_MvcLab_A14_b5f458f24d49474bbac8d5eac9659f6a` fue creada como
  base nueva en `.\SERVER2022` bajo la autorización A14. EF Core 10.0.10
  aplicó 13 migraciones; auditoría SQL: 28 tablas/PK, 10 FK, índice único R9 y
  cero filas comerciales. Evidencia:
  `artifacts\A14_MIGRATION_POSFlutter_MvcLab_A14_b5f458f24d49474bbac8d5eac9659f6a`.
- A14 es VERIFICADO. La base se conserva para auditoría y no se eliminó.
