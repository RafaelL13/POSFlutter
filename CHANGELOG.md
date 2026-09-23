# Changelog

## Unreleased - 2026-09-23

- Cerrado UAT fisico offline y Sync E2E tablet -> API ASP.NET Core -> SQL Server.
- Agregada reparacion segura de cola para primer sync de Business/User.
- Sincronizacion multiusuario conserva actor historico y aplica autorizacion por rol/capacidad.
- Endurecida autorizacion de cancelaciones y movimientos de caja sincronizados.
- Compatibilidad backend para asignaciones FIFO historicas y contrato Flutter canonico para nuevas ventas.
- Sync E2E validado con 38/38 operaciones sincronizadas, 13 ventas centrales, 3 cancelaciones y FIFO integro.
- Validacion cliente final: `flutter analyze` PASS, 357/357 tests PASS y Profile APK PASS.
- Validacion backend final: 84/84 tests PASS mediante runner xUnit v3 directo.

## 1.0.0 - 2026-08-30

Primera candidata productiva del roadmap actual.

- POS Android tablet offline-first con SQLite, caja, ventas, compras, gastos e inventario.
- Costeo FIFO con asignaciones histÃ³ricas inmutables y cancelaciÃ³n exacta.
- SincronizaciÃ³n durable e idempotente con ASP.NET Core/SQL Server.
- Roles, capacidades, AdminReadOnly y autorizaciones especiales offline.
- Enrollment de dispositivos, reportes remotos tenant-safe y diseÃ±o responsive.
- Backup/restore con integridad, reautenticaciÃ³n y copia preventiva.
- Firma Android release controlada y documentaciÃ³n operativa de despliegue/recuperaciÃ³n.

UAT humana y configuraciÃ³n del endpoint/infraestructura de cada despliegue se validan por separado.
