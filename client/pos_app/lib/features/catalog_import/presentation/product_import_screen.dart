import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/design/app_spacing.dart';
import 'package:pos_app/core/design/components/app_components.dart';
import 'package:pos_app/features/catalog_import/data/catalog_import_csv.dart';
import 'package:pos_app/features/catalog_import/data/catalog_import_xlsx.dart';
import 'package:pos_app/features/catalog_import/data/initial_inventory_repository.dart';

final class ProductImportSelectedFile {
  const ProductImportSelectedFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

typedef ProductImportFilePicker = Future<ProductImportSelectedFile?> Function();

typedef ProductImportExecutor = Future<String> Function({
  required CatalogImportPreview preview,
  required ExistingCatalogPolicy policy,
  String? sourceName,
});

class ProductImportScreen extends StatefulWidget {
  const ProductImportScreen({super.key, this.pickFile, this.executeImport});

  final ProductImportFilePicker? pickFile;
  final ProductImportExecutor? executeImport;

  @override
  State<ProductImportScreen> createState() => _ProductImportScreenState();
}

class _ProductImportScreenState extends State<ProductImportScreen> {
  CatalogImportPreview? _preview;
  ExistingCatalogPolicy _policy = ExistingCatalogPolicy.skip;
  String? _fileName;
  String? _loadError;
  bool _loading = false;
  bool _importing = false;

  int get _totalUnits {
    final preview = _preview;
    if (preview == null) return 0;

    return preview.rows.fold<int>(0, (total, row) => total + row.quantity);
  }

  int get _rowsWithInitialStock {
    final preview = _preview;
    if (preview == null) return 0;

    return preview.rows.where((row) => row.quantity > 0).length;
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;

    return AppPage(
      title: 'Importar productos',
      subtitle: 'Carga un catálogo CSV o XLSX. La validación y el guardado se realizan completamente sin Internet.',
      body: Column(
        children: [
          AppCard(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Archivo de catálogo',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'Columnas requeridas: SKU, Producto, Categoria, Proveedor, '
                    'CostoCompra, PrecioVenta y ExistenciaInicial.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.icon(
                    key: const Key('product-import-pick-file'),
                    onPressed: _loading || _importing ? null : _pickFile,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: Text(
                      _loading ? 'Leyendo archivo…' : 'Seleccionar CSV o XLSX',
                    ),
                  ),
                  if (_fileName != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Archivo: $_fileName',
                      key: const Key('product-import-file-name'),
                    ),
                  ],
                  if (_loadError != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    _MessageBox(
                      key: const Key('product-import-load-error'),
                      icon: Icons.error_outline,
                      title: 'No se pudo leer el archivo',
                      messages: [_loadError!],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (preview != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _PreviewCard(
              preview: preview,
              totalUnits: _totalUnits,
              rowsWithInitialStock: _rowsWithInitialStock,
            ),
            if (preview.isValid) ...[
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Productos que ya existen',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const Text(
                        'La existencia nunca se sobrescribe silenciosamente. '
                        'Si un producto ya tiene historial de inventario en esta sucursal, '
                        'una existencia inicial mayor que cero será rechazada.',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      RadioGroup<ExistingCatalogPolicy>(
                        groupValue: _policy,
                        onChanged: (value) {
                          if (_importing || value == null) return;
                          setState(() => _policy = value);
                        },
                        child: const Column(
                          children: [
                            RadioListTile<ExistingCatalogPolicy>(
                              key: Key('product-import-policy-skip'),
                              value: ExistingCatalogPolicy.skip,
                              title: Text('Conservar catálogo existente'),
                              subtitle: Text(
                                'No cambia nombre ni precio de productos existentes.',
                              ),
                            ),
                            RadioListTile<ExistingCatalogPolicy>(
                              key: Key('product-import-policy-update'),
                              value: ExistingCatalogPolicy.updateCatalogData,
                              title: Text('Actualizar datos de catálogo'),
                              subtitle: Text(
                                'Actualiza nombre y precio de venta. No reemplaza existencias.',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton.icon(
                        key: const Key('product-import-confirm'),
                        onPressed: _importing ? null : _confirmImport,
                        icon: _importing
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.inventory_2_outlined),
                        label: Text(
                          _importing ? 'Importando…' : 'Confirmar importación',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final injectedPicker = widget.pickFile;
      final ProductImportSelectedFile? selected;

      if (injectedPicker != null) {
        selected = await injectedPicker();
      } else {
        final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: const ['csv', 'xlsx'],
        );

        if (file == null) {
          selected = null;
        } else {
          selected = ProductImportSelectedFile(
            name: file.name,
            bytes: await file.readAsBytes(),
          );
        }
      }

      if (selected == null) {
        return;
      }

      final selectedFile = selected;
      final bytes = selectedFile.bytes;

      if (bytes.isEmpty) {
        throw StateError('El archivo seleccionado está vacío.');
      }

      final extension = _extensionOf(selectedFile.name).toLowerCase();

      final CatalogImportPreview preview;

      switch (extension) {
        case 'csv':
          preview = CatalogImportCsv.parse(bytes);
        case 'xlsx':
          preview = CatalogImportXlsx.parse(bytes);
        default:
          throw StateError('Solo se permiten archivos CSV o XLSX.');
      }

      if (!mounted) return;

      setState(() {
        _fileName = selectedFile.name;
        _preview = preview;
        _loadError = null;
      });
    } on Object catch (error) {
      if (!mounted) return;

      setState(() {
        _preview = null;
        _loadError = _friendlyError(error);
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _confirmImport() async {
    final preview = _preview;
    if (preview == null || !preview.isValid) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar importación'),
        content: Text(
          'Se procesarán ${preview.rows.length} productos. '
          '$_rowsWithInitialStock productos incluyen existencia inicial, '
          'con $_totalUnits unidades en total.\n\n'
          'La operación se guardará de forma atómica: si ocurre un error, '
          'no se aplicará una importación parcial.',
        ),
        actions: [
          TextButton(
            key: const Key('product-import-cancel-dialog'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('product-import-accept-dialog'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Importar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _importing = true);

    try {
      final executor = widget.executeImport;
      final globalId = executor != null
          ? await executor(
              preview: preview,
              policy: _policy,
              sourceName: _fileName,
            )
          : await InitialInventoryRepository(
              appDatabase,
            ).import(preview: preview, policy: _policy, sourceName: _fileName);

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Importación completada'),
          content: Text(
            'El catálogo fue procesado correctamente.\n\n'
            'Productos válidos: ${preview.rows.length}\n'
            'Productos con existencia inicial: $_rowsWithInitialStock\n'
            'Unidades iniciales: $_totalUnits\n\n'
            'Identificador: $globalId\n\n'
            'Los cambios locales ya están disponibles. '
            'La sincronización con el servidor se realizará cuando haya conexión.',
          ),
          actions: [
            FilledButton(
              key: const Key('product-import-success-close'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );

      if (!mounted) return;

      setState(() {
        _preview = null;
        _fileName = null;
        _loadError = null;
      });
    } on Object catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo importar: ${_friendlyError(error)}'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }

  static String _extensionOf(String name) {
    final index = name.lastIndexOf('.');
    if (index < 0 || index == name.length - 1) return '';
    return name.substring(index + 1);
  }

  static String _friendlyError(Object error) {
    if (error is StateError) {
      return error.message;
    }

    if (error is ArgumentError) {
      return error.message?.toString() ?? error.toString();
    }

    return error.toString();
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.preview,
    required this.totalUnits,
    required this.rowsWithInitialStock,
  });

  final CatalogImportPreview preview;
  final int totalUnits;
  final int rowsWithInitialStock;

  @override
  Widget build(BuildContext context) {
    if (!preview.isValid) {
      return _MessageBox(
        key: const Key('product-import-validation-errors'),
        icon: Icons.warning_amber_outlined,
        title: 'El archivo contiene errores',
        messages: preview.errors,
      );
    }

    return AppCard(
      key: const Key('product-import-preview'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vista previa', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.md,
              children: [
                _Metric(
                  label: 'Productos válidos',
                  value: preview.rows.length.toString(),
                ),
                _Metric(
                  label: 'Con existencia inicial',
                  value: rowsWithInitialStock.toString(),
                ),
                _Metric(
                  label: 'Unidades iniciales',
                  value: totalUnits.toString(),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'La existencia inicial crea lotes FIFO reales. '
              'No se registra como una compra ficticia.',
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
        Text(label),
      ],
    ),
  );
}

class _MessageBox extends StatelessWidget {
  const _MessageBox({
    super.key,
    required this.icon,
    required this.title,
    required this.messages,
  });

  final IconData icon;
  final String title;
  final List<String> messages;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final message in messages)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text('• $message'),
            ),
        ],
      ),
    ),
  );
}
