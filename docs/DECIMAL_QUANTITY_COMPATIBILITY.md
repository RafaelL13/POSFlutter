# Cantidades decimales — compatibilidad contractual

## Hechos verificados

El modelo transaccional vigente persiste unidades enteras (`int`) en
`PurchaseLine.Quantity`, `InventoryLot.InitialQuantity`,
`InventoryLot.AvailableQuantity`, `InventoryMovement.QuantityDelta`,
`InitialInventoryLine.Quantity`, `SaleLine.Quantity` y
`SaleLotAllocation.Quantity`. Los mismos enteros son parte de los contratos de
checkout, compra y sincronización Android.

`DecimalQuantity` valida y calcula micro/mili-unidades de forma exacta, pero no
está conectado al modelo de persistencia ni a los eventos sincronizados. La
migración `20261102190000_AddAdminComboDecimalQuantity` es intencionalmente
vacía: el alcance comercial vigente define los componentes de combos e
inventario como piezas; la presentación de empaques no representa fracciones
de inventario.

## Cambio requerido si se aprueban fracciones comerciales

No es seguro cambiar sólo el formulario web. Se requeriría una versión aditiva
de contrato con capacidad de dispositivo, columnas enteras de micro-unidades,
backfill exacto `legacyQuantity * 1_000_000`, restricciones nuevas y rutas de
lectura/escritura que mantengan los campos `int` para clientes Android antiguos.
FIFO, movimientos, compras, ventas, cancelaciones, inventario inicial, reportes
e idempotencia deben usar la misma escala. Los payloads de compra/venta/lote y
sus appliers SQLite necesitan versión compatible y pruebas SQL→pull→SQLite.

## Estado

`P02_DECIMAL_GATE=BLOCKED` por definición comercial pendiente: confirmar si
algún producto se vende o almacena fraccionado y, en tal caso, la escala,
redondeo de precios y la capacidad mínima Android. Hasta entonces se mantiene
la validación entera vigente para no truncar inventario ni romper FIFO.
