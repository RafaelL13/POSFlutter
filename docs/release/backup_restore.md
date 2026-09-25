# Respaldo, restauración y recuperación

## Respaldo

Con caja y operaciones controladas, cree el respaldo desde la app. El archivo se acepta sólo después de `PRAGMA integrity_check`. Cópielo a almacenamiento protegido y registre fecha/dispositivo sin guardar credenciales.

## Restauración

La restauración es destructiva: requiere confirmación explícita, reautenticación/capacidad, archivo SQLite íntegro y una versión de schema compatible (actualmente V8; se rechazan versiones superiores a la soportada por la app). La app crea una copia preventiva y revierte ante fallo. Después valide caja, inventario, ventas y sincronice de forma controlada.

## Disaster recovery

1. Detenga la operación del dispositivo afectado.
2. Localice el último respaldo válido y preserve una copia inmutable.
3. Valide integridad y versión.
4. Reinstale el APK firmado sólo si hace falta; no desinstale antes de proteger datos pendientes.
5. Restaure y repita integrity check.
6. Verifique caja, inventario, ventas, FIFO y `SyncQueue`.
7. Reconecte y supervise push/pull sin duplicar operaciones.

El SQL Server central requiere su propia política de backup completo/diferencial/log; un backup SQLite no sustituye el backup del servidor.

## Android: respaldo portable mediante SAF

En Android, el respaldo SQLite se crea y valida primero dentro del almacenamiento privado de POSFlutter. Después, la aplicación usa Storage Access Framework (SAF) mediante el selector nativo del sistema para que el usuario guarde una copia en una ubicación bajo su control, por ejemplo Descargas. No se requieren permisos amplios de almacenamiento.

Para restaurar, use el selector nativo de Android y elija el archivo `.db` previamente exportado. POSFlutter prepara una copia temporal privada para validar el archivo antes de reemplazar la base activa. La restauración continúa protegida por autorización especial y confirmación destructiva explícita.

Antes de reemplazar la base activa, POSFlutter crea una copia preventiva. Si la restauración falla, el flujo de recuperación conserva o restablece el estado anterior. No elimine el respaldo externo hasta validar que la aplicación inicia correctamente y que los datos esperados están disponibles.

Procedimiento de recuperación Android:

1. Crear el respaldo desde POSFlutter.
2. Guardarlo mediante SAF en almacenamiento controlado por el usuario.
3. Conservar una copia externa del archivo.
4. Para recuperar, seleccionar el `.db` mediante SAF.
5. Verificar la advertencia de reemplazo de datos.
6. Autorizar y confirmar la restauración únicamente cuando corresponda.
7. Después del restore, validar catálogo, inventario, caja, ventas y funcionamiento general antes de reanudar la operación normal.

El respaldo SQLite protege el estado local del dispositivo. No sustituye el backup de SQL Server ni la estrategia central de recuperación.
