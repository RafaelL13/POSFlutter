# Checklist de producción y rollback

## Gate técnico

- [ ] Git limpio, `main == origin/main`, tag apunta a HEAD.
- [ ] Versión, commit, package, min/target SDK registrados.
- [ ] Flutter analyze/test y Android release desde limpio.
- [ ] Firma y SHA-256 del APK verificados.
- [ ] .NET build/test/publish y startup `/health` verificados.
- [ ] SQL Server de destino con backup y secretos externos.
- [ ] HTTPS válido; sin bypass TLS ni endpoints locales.
- [ ] SQLite fresh/upgrade/integrity y restore verificados.
- [ ] Offline, FIFO, caja, sync, idempotencia y tenant isolation verificados.
- [ ] Enrollment, roles, AdminReadOnly y autorización especial verificados.
- [ ] Bundle/clone/recovery build reproducibles.
- [ ] UAT registrada por separado.

## Rollback APK

No desinstale inmediatamente si existen datos no sincronizados. Detenga nuevas operaciones, revise `SyncQueue`, cree respaldo local y sincronice si es posible. Sólo instale una APK anterior con la misma firma y schema compatible. Después compruebe DB, caja, inventario y ventas. Si no es compatible, restaure mediante el procedimiento formal; nunca borre la base para “hacer funcionar” el downgrade.

## Pruebas manuales

Marque cada una `MANUAL_PASS` o `NOT_RUN`: launch, login/logout, apertura/cierre de caja, venta, descuento, cancelación, compra, gasto, ajuste, venta offline, reconnect, backup, restore y AdminReadOnly.
