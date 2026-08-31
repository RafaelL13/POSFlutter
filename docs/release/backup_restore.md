# Respaldo, restauración y recuperación

## Respaldo

Con caja y operaciones controladas, cree el respaldo desde la app. El archivo se acepta sólo después de `PRAGMA integrity_check`. Cópielo a almacenamiento protegido y registre fecha/dispositivo sin guardar credenciales.

## Restauración

La restauración es destructiva: requiere confirmación explícita, reautenticación/capacidad, archivo compatible con schema V5 e integridad válida. La app crea una copia preventiva y revierte ante fallo. Después valide caja, inventario, ventas y sincronice de forma controlada.

## Disaster recovery

1. Detenga la operación del dispositivo afectado.
2. Localice el último respaldo válido y preserve una copia inmutable.
3. Valide integridad y versión.
4. Reinstale el APK firmado sólo si hace falta; no desinstale antes de proteger datos pendientes.
5. Restaure y repita integrity check.
6. Verifique caja, inventario, ventas, FIFO y `SyncQueue`.
7. Reconecte y supervise push/pull sin duplicar operaciones.

El SQL Server central requiere su propia política de backup completo/diferencial/log; un backup SQLite no sustituye el backup del servidor.
