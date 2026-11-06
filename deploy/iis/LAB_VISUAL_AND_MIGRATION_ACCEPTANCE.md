# Aceptación visual y migración lógica de laboratorio

Este documento no autoriza una instalación, copia de datos ni cambio de conexión. Es la lista reproducible para cerrar los requisitos A08, A16, A17 y A18 cuando haya un responsable de laboratorio.

## Comparación Android-Web autenticada

Con el mismo negocio, sucursal y producto de laboratorio, capturar una imagen de la tablet y otra del navegador para cada estado: catálogo sin búsqueda, resultado de búsqueda, carrito con cantidad modificada, cobro Cash/Card/Transfer/Mixto, cancelación y caja. Registrar resolución, escala del navegador y versión Android.

Los criterios de aceptación son: nombres de acciones coinciden, colores y jerarquía respetan `app_theme.dart`, las acciones táctiles tienen un área mínima de 44 px, producto agotado no se puede agregar, total y métodos de pago coinciden y el flujo web conserva la secuencia de `pos_screen.dart`. Adjuntar las capturas a la evidencia de laboratorio; no se declara paridad visual por una revisión de código solamente.

## Migración lógica SQL Server 2022

1. El responsable autoriza por escrito una copia de origen y una base de destino nueva y vacía.
2. Ejecutar primero el inventario de origen en modo lectura: conteos por negocio/sucursal y checksum por tablas comerciales.
3. Restaurar o copiar únicamente a la base destino autorizada; no apuntar nunca a `POSFlutterDB`, LocalDB comercial ni una base certificada.
4. Aplicar las migraciones ya auditadas y comparar conteos, claves globales, integridad referencial, inventario por lote y sumas de pagos.
5. Ejecutar el flujo P042 contra la destino y una prueba de restauración con tiempos registrados.

La autorización debe definir origen, destino, ventana, responsable, retención de respaldo y criterio de rollback antes de cualquier escritura.
