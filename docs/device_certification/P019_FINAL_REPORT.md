# P019 — Certificación integral de costo cero, FIFO y sincronización

Fecha: 2026-10-15

Rama auditada: `feature/p019-seller-authorizations`
HEAD inicial: `89fb4b021bf2a24bbcde25a45ea072cc9dbed552`

## Alcance certificado

La certificación confirma por pruebas aisladas que una compra local con costo
unitario de adquisición igual a cero es válida, crea un lote FIFO a costo cero,
incrementa existencias una sola vez, registra movimiento y encola la operación
para sincronización. Los costos negativos, cantidades no positivas y cantidades
fraccionarias se rechazan por las capas correspondientes.

El costo cero es un costo de adquisición local válido; no representa ni altera
el costo económico de producción de la organización.

## Controles ejecutados

| Control | Resultado | Evidencia |
|---|---:|---|
| Formato Dart | PASS | 174 archivos revisados, 0 cambios |
| Flutter analyze | PASS | 0 issues |
| Flutter, regresión dirigida | PASS | 28 pruebas: compras, FIFO, importación, persistencia y transferencias |
| Flutter, suite completa | PASS | 439/439 |
| Backend, integración dirigida | PASS | 20 pruebas: `InitialInventory` y `CentralInventoryTransfer` |
| Backend, compilación | PASS | 0 advertencias, 0 errores |
| Backend, suite completa | PASS | 114/114 |
| `git diff --check` | PASS | Ejecutado antes de la documentación P019 |
| Structural gate | PASS | Incluye escaneo de secretos: 0 hallazgos de alta confianza |
| SQLite validation | PASS | Integridad, FKs, rollback, FIFO, cursor y pagos verificados |
| APK release existente | PASS | Paquete, versión, hash, firma e iconos verificados |
| S12-A, estado no mutante | PASS | ADB conectado; APK instalada y `MainActivity` en primer plano |

## Flujo funcional comprobado en SQLite aislado

1. Compra offline de cuatro unidades con costo unitario `0`.
2. Compra confirmada con total `0`.
3. Lote FIFO con cantidad inicial y disponible `4`, costo unitario `0`.
4. Movimiento de inventario y una entrada `Purchase` en `SyncQueue`.
5. Lectura local de la compra persistida.
6. Reintento de importación inicial por el mismo fingerprint sin duplicar
   catálogo, lote, movimiento, stock ni cola.
7. E2E de catálogo: entrada de 10 unidades a `$100.00`, venta de 3 a `$140.00`,
   existencia final `7`, costo FIFO histórico `$300.00` y utilidad bruta `$120.00`.
8. Cierre y reapertura de SQLite preservando venta, asignación FIFO, costo y
   existencia.
9. Pull de transferencia central: creación idempotente de lote y movimiento;
   rechazo atómico de cantidades fraccionarias y payload inválido.
10. Backend: persistencia e idempotencia de `InitialInventory` y transferencias
    centrales dentro de su base de pruebas.

## APK y dispositivo

- APK: `client/pos_app/build/app/outputs/flutter-apk/app-release.apk`
- SHA-256: `C6BA6B104C1CBD8938279FDA487E8EEC34E253D9422DD1EFA9EF0A37DED30175`
- Package: `com.posflutter.pos_app`
- Versión: `1.1.2+7`
- Firma: APK Signature Scheme v2 válida.
- Certificado SHA-256: `1190414E227223377C1DAB5C199A0C3ECA70B57F193B27F82BE082C97843EFC4`
- S12-A: Android 10 / API 29, ADB `MTK0002606301100350`, app en primer plano.

## Corrección del gate estructural

Se actualizó `tools/structural_gate.py` para representar el diseño vigente sin
relajar controles de producción:

- acepta BOM UTF-8 en evidencia JSON generada por PowerShell;
- no trata un `UnimplementedError` intencional de un doble de prueba como
  defecto de fuente productiva;
- reconoce el endpoint protegido de invitación de recuperación de dispositivo;
- valida los índices EF ignorando espacios de formato;
- valida el contrato actual de código de enrolamiento generado con CSPRNG,
  hash SHA-256, caducidad, revocación, transacción serializable, modo de
  dispositivo, unicidad e IP rate limit.

No se modificó código de negocio, API, SQL Server, IIS, configuraciones de
producción, ni datos de la tablet durante esta certificación.

## Controles no verificados físicamente

La S12-A puede sincronizar con producción. Por seguridad no se realizaron
compras, ventas, cancelaciones, ajustes, ni reintentos de sincronización de
prueba en ese dispositivo. Por tanto, la captura física de costo cero, la
venta offline física y la persistencia física tras reinicio quedan
`NOT_VERIFIED` hasta disponer de API/SQL Server de prueba aislados y una SQLite
de prueba independiente (emulador o tablet de pruebas).

## Riesgo residual y decisión

No hay fallo reproducido en las pruebas aisladas. El bloqueo es exclusivamente
de aislamiento operativo: no es seguro generar datos de negocio de prueba en
una tablet que puede sincronizar con producción.

Estado P019: **PARTIAL — NO-GO para UAT mutante sobre S12-A productiva**.
La entrega de código queda lista para una UAT aislada, no para inyectar datos de
prueba en producción.
