# Importación de productos e inventario inicial

## Objetivo

POSFlutter permite importar productos desde archivos CSV o XLSX directamente en la tablet.

La lectura, validación y persistencia local funcionan offline. Una caída de Internet no impide realizar la importación local ni continuar vendiendo.

Cuando una fila contiene existencia inicial mayor que cero, POSFlutter registra una operación InitialInventory y crea el lote FIFO correspondiente. No crea una compra ficticia ni modifica silenciosamente una existencia acumulada.

## Acceso

La opción Importar productos se encuentra en la sección Inventario.

Ruta interna:

    /settings/product-import

La autorización utiliza la capacidad:

    initialInventoryImport

Administrator y Manager tienen acceso.

Supervisor y Seller no tienen acceso.

Un dispositivo AdminReadOnly tampoco puede ejecutar esta operación.

## Formatos soportados

Se admiten archivos:

- CSV
- XLSX

Plantillas oficiales:

- docs/templates/plantilla_importacion_productos.csv
- docs/templates/plantilla_importacion_productos.xlsx

## Columnas

El archivo utiliza exactamente estas siete columnas y en este orden:

1. SKU
2. Producto
3. Categoria
4. Proveedor
5. CostoCompra
6. PrecioVenta
7. ExistenciaInicial

Encabezado:

    SKU,Producto,Categoria,Proveedor,CostoCompra,PrecioVenta,ExistenciaInicial

## SKU

El SKU identifica al producto.

No puede estar vacío.

Dentro del mismo archivo no se permiten SKU duplicados. La comparación de duplicados no depende de mayúsculas o minúsculas.

## Producto y categoría

Producto debe contener el nombre del artículo.

Categoria identifica la categoría correspondiente.

El archivo completo se valida antes de comenzar la persistencia.

## Cantidades

ExistenciaInicial debe ser un número entero mayor o igual a cero.

Ejemplos válidos:

    0
    1
    10
    250

Ejemplos inválidos:

    -1
    1.5
    10.25

POSFlutter no vende productos por fracciones.

## Importes monetarios

CostoCompra y PrecioVenta se proporcionan en unidades monetarias.

Ejemplos:

    100
    100.00
    140.50

POSFlutter los convierte internamente a centavos enteros.

Ejemplos:

    100.00 = 10000 centavos
    140.00 = 14000 centavos

La persistencia monetaria utiliza centavos enteros.

## Proveedor

Cuando ExistenciaInicial es mayor que cero, el proveedor es obligatorio.

Cuando ExistenciaInicial es cero, el proveedor puede estar vacío.

Ejemplo permitido:

    P002,Producto sin existencia,Categoria General,,50.00,75.00,0

## Validación previa

Antes de guardar información se valida el archivo completo.

La validación cubre, entre otros casos:

- formato CSV o XLSX;
- columnas requeridas;
- SKU vacío;
- SKU duplicado;
- nombre vacío;
- categoría;
- proveedor requerido para existencia inicial positiva;
- cantidades negativas;
- cantidades fraccionarias;
- costo inválido;
- precio inválido;
- filas mal formadas;
- CSV con comillas incorrectas;
- estructura XLSX inválida.

Si existen errores, la importación no comienza.

La interfaz muestra una vista previa antes de confirmar.

## Política para productos existentes

La pantalla permite seleccionar una política.

### SKIP

Si el SKU ya existe, se conserva el producto existente.

La existencia nunca se sobrescribe silenciosamente.

### UPDATE_CATALOG_DATA

Permite actualizar los datos de catálogo soportados por la implementación para un producto existente.

Esta opción no convierte movimientos históricos en inventario inicial y tampoco debe utilizarse para sobrescribir existencias existentes.

Si el producto ya tiene historial de inventario en la sucursal, no puede reinterpretarse posteriormente como inventario inicial.

## Inventario inicial

Para una fila nueva con ExistenciaInicial mayor que cero, el flujo local registra los elementos correspondientes de catálogo y posteriormente:

1. InitialInventory.
2. Línea de inventario inicial.
3. Lote FIFO.
4. Movimiento de inventario.
5. Auditoría.
6. Operación pendiente en SyncQueue.

InitialInventory es una operación explícita. No es una Purchase ficticia.

## FIFO

El inventario inicial positivo crea un lote FIFO.

Sus valores fundamentales son:

    InitialQuantity = ExistenciaInicial
    AvailableQuantity = ExistenciaInicial
    UnitCostCents = CostoCompra convertido a centavos

Las ventas posteriores consumen los lotes FIFO.

El costo histórico de la venta queda almacenado y no depende de modificaciones posteriores del precio de catálogo.

## Caso P001 validado

Producto:

    SKU = P001
    Existencia inicial = 10
    Costo unitario = $100.00
    Precio de venta = $140.00

Venta:

    Cantidad vendida = 3

Resultado comprobado:

    Existencia restante = 7
    Costo FIFO = $300.00
    Ingreso = $420.00
    Utilidad bruta = $120.00

Este circuito está cubierto por pruebas automatizadas locales y backend.

## Atomicidad local

La importación utiliza una transacción SQLite.

Un error durante la operación no debe dejar parcialmente registrados los datos correspondientes.

Las pruebas cubren rollback ante fallo durante una importación.

## Idempotencia local

El archivo genera una huella SHA-256.

La tabla initial_inventory_imports protege la combinación:

    business_id
    branch_id
    source_fingerprint

El esquema SQLite contiene una restricción UNIQUE sobre esa combinación.

Reimportar el mismo archivo para la misma empresa y sucursal no debe duplicar el inventario inicial.

Esta propiedad también fue validada después de cerrar SQLite y volver a abrir el mismo archivo de base de datos.

## Operación offline

La importación local no depende de la API.

Flujo:

    CSV/XLSX
        -> validación
        -> vista previa
        -> confirmación
        -> transacción SQLite
        -> catálogo
        -> InitialInventory
        -> lote FIFO
        -> movimiento
        -> auditoría
        -> SyncQueue

La tienda puede continuar trabajando aunque no exista conectividad.

## Sincronización

Cuando existe conexión, las operaciones pendientes se sincronizan mediante:

    SQLite
        -> SyncQueue
        -> HTTPS
        -> ASP.NET Core
        -> SQL Server

Flutter nunca se conecta directamente a SQL Server.

## Idempotencia backend

El backend representa InitialInventory explícitamente.

La persistencia central protege la combinación:

    BusinessId
    BranchId
    SourceFingerprint

Los reintentos de operaciones procesadas no deben volver a aplicar inventario.

Las ventas utilizan identificadores globales y claves de idempotencia para impedir duplicados durante reintentos.

## Seguridad multi-tenant

La API valida el contexto autenticado de:

- empresa;
- sucursal;
- dispositivo;
- usuario.

Las referencias utilizadas por una operación deben pertenecer al tenant autenticado.

## Persistencia SQLite validada

La prueba de persistencia cubre:

    crear SQLite temporal en disco
        -> importar P001
        -> crear inventario inicial
        -> vender 3 unidades
        -> cerrar AppDatabase
        -> crear una nueva instancia
        -> reabrir el mismo SQLite
        -> verificar producto
        -> verificar lote
        -> verificar existencia 7
        -> verificar venta
        -> verificar costo FIFO 30000 centavos
        -> verificar ingreso 42000 centavos
        -> verificar utilidad 12000 centavos
        -> verificar SyncQueue
        -> reimportar
        -> verificar idempotencia

## Pruebas relevantes Flutter

Entre las pruebas del módulo se encuentran:

    test/features/catalog_import/catalog_import_csv_test.dart
    test/features/catalog_import/catalog_import_xlsx_test.dart
    test/features/catalog_import/product_import_screen_test.dart
    test/features/catalog_import/product_import_sale_fifo_e2e_test.dart
    test/features/catalog_import/product_import_persistence_e2e_test.dart
    test/features/catalog_import/official_templates_test.dart
    test/initial_inventory_authorization_test.dart
    test/schema_v8_migration_test.dart

## Pruebas relevantes backend

    server/tests/Infrastructure.Tests/InitialInventorySyncTests.cs
    server/tests/Infrastructure.Tests/InitialInventorySaleE2ETests.cs

## Uso operativo

Antes de realizar una importación real:

1. Crear una copia de la plantilla oficial.
2. Capturar y revisar los SKU.
3. Revisar nombres y categorías.
4. Revisar costos y precios.
5. Confirmar las cantidades iniciales.
6. Especificar proveedor cuando exista inventario inicial.
7. Abrir el archivo desde Importar productos.
8. Revisar la vista previa.
9. Corregir cualquier error indicado.
10. Seleccionar la política para productos existentes.
11. Confirmar la importación.
12. Conservar el archivo original utilizado.

InitialInventory debe utilizarse para la carga inicial controlada.

No debe utilizarse como mecanismo habitual para corregir existencias de productos que ya cuentan con movimientos.

## Plantillas oficiales verificadas

Las dos plantillas oficiales son procesadas por los parsers productivos mediante una prueba automatizada:

    docs/templates/plantilla_importacion_productos.csv
    docs/templates/plantilla_importacion_productos.xlsx

La prueba correspondiente es:

    test/features/catalog_import/official_templates_test.dart

## Estado de validación

La funcionalidad cuenta con cobertura automatizada para:

- CSV;
- XLSX;
- validación;
- autorización;
- rollback transaccional;
- migración SQLite V8;
- navegación;
- interfaz de importación;
- inventario inicial;
- lote FIFO;
- venta posterior;
- costo histórico;
- utilidad;
- persistencia después de reapertura;
- idempotencia local;
- idempotencia backend;
- plantillas oficiales.

Las pruebas automatizadas no sustituyen el UAT físico final en tablet.

No debe realizarse una instalación limpia destructiva de producción hasta completar la validación integral del release.