# Operación offline

El POS conserva localmente login autorizado, catálogo disponible, caja, ventas, FIFO, inventario, compras y gastos. Las operaciones se guardan en SQLite y quedan en `SyncQueue` hasta recuperar conexión.

- **Sin conexión:** la nube no responde; la operación local permitida continúa.
- **Pendiente:** todavía no se confirmó en servidor.
- **Requiere atención:** el servidor rechazó terminalmente la operación; los datos locales no se eliminan ni se revierten.

Al volver Internet, inicie sincronización, espere push/pull, revise pendientes y resuelva “Requiere atención” con un responsable. No repita manualmente ventas. Un 403 no autoriza borrar la operación local. Mantenga razonablemente correcta la hora del dispositivo porque los timestamps se crean sin depender de Internet.
