# P019 — Release readiness

## Resultado

**NO-GO para UAT mutante en la S12-A actual.**

No existe un defecto confirmado de compra con costo cero, FIFO, persistencia,
idempotencia local, ni integración central en las suites aisladas. El único
bloqueo es correcto y deliberado: la S12-A puede comunicarse con una API
productiva o potencialmente productiva.

## Avance

- Avance técnico verificable: **82%**.
- Pendiente: **18%**.

El porcentaje pendiente corresponde a UAT física mutante aislada, no a trabajo
de código conocido.

## PASS

- Compra offline con costo de adquisición `$0.00`.
- Rechazo de costo negativo y cantidades no válidas por las capas aplicables.
- Lote FIFO, movimiento, SyncQueue y lectura de compra local.
- E2E de importación, venta, FIFO, utilidad y reapertura SQLite.
- Idempotencia y rollback de inventario inicial.
- Pull y aplicación idempotente de transferencias centrales.
- Integración backend de `InitialInventory` y transferencias centrales.
- Formato, análisis, 439 pruebas Flutter, 114 pruebas backend, gate estructural,
  validación SQLite y escaneo de secretos.
- APK release `1.1.2+7` firmada y compatible con S12-A.

## NOT_VERIFIED

- Captura física de una compra de `$0.00` en una SQLite de prueba.
- Venta offline física posterior y persistencia tras reinicio físico.
- Reintento físico de sincronización hacia API/SQL Server de prueba.
- Verificación de que esos eventos no aparecen duplicados en una base central
  de prueba.

## Condiciones para el GO

1. Crear o identificar API y SQL Server exclusivamente de pruebas.
2. Confirmar que la URL de prueba no resuelve a infraestructura productiva.
3. Usar emulador o tablet de pruebas con SQLite independiente.
4. Ejecutar el flujo físico: recepción de transferencia/costo cero, venta
   offline, reinicio, reintento de sync y comprobación central de no duplicado.
5. Conservar evidencia de IDs de prueba y limpiar únicamente el entorno de
   pruebas autorizado.

Hasta entonces no se debe desinstalar, borrar datos, cambiar la configuración
de red, ni generar transacciones de prueba en la S12-A actual.
