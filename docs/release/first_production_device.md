# Primera tablet productiva

Estado FASE 19: `PENDING_EXTERNAL`. No ejecute bootstrap productivo en el AVD temporal.

## Preparación

- [ ] Verificar APK `1.0.0+1`, SHA-256 y certificado release oficial.
- [ ] Confirmar Internet, DNS y HTTPS hacia `api.lasaguilasmercadodelmar.com:443`.
- [ ] Confirmar fecha, hora y zona horaria razonablemente correctas.
- [ ] Instalar APK en la tablet física y abrir sin crash.
- [ ] Seleccionar **Configurar nuevo negocio**.
- [ ] Capturar nombres reales de negocio, administrador y dispositivo; el usuario define la contraseña.
- [ ] Confirmar bootstrap HTTPS, login y creación de SQLite V5.

## UAT offline-first

1. Con Internet, sincronice el catálogo inicial y abra caja controlada.
2. Desconecte Wi-Fi/datos y confirme el indicador **Sin conexión**.
3. Realice una venta controlada; verifique folio, total en centavos, FIFO, inventario, caja y `SyncQueue` pendiente.
4. Cierre completamente y vuelva a abrir la app todavía sin Internet.
5. Confirme persistencia de venta, caja, inventario, lotes FIFO y cola.
6. Reconecte Internet y sincronice.
7. Confirme push/pull, cursor avanzado, cola sincronizada y ausencia de duplicados.
8. Verifique en SQL Server la misma venta/GlobalId, asignaciones FIFO, inventario y caja.
9. Repita envío/refresh para demostrar idempotencia `AlreadyProcessed` sin duplicar.
10. Cree y valide un respaldo local antes de operación comercial abierta.

## Evidencia requerida

Registrar tablet/Android, fecha, responsable, versión/commit, IDs no sensibles y resultado de cada paso. No adjuntar contraseñas, JWT ni connection strings.

```text
FIRST_PRODUCTION_DEVICE=PASS
CLIENT_UAT=PASS
OFFLINE_FIRST_UAT=PASS
BOOTSTRAP_HTTPS=PASS
RESTART_PERSISTENCE=PASS
SYNC_RECONNECT=PASS
SYNC_IDEMPOTENCY=PASS
SQLSERVER_DATA_CONFIRMATION=PASS
```
