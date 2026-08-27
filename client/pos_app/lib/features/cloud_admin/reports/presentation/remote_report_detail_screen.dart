import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/network/cloud_api_client.dart';
import 'package:pos_app/core/utils/money.dart';
import 'package:pos_app/features/cloud_admin/reports/data/remote_report_csv_service.dart';
import 'package:pos_app/features/cloud_admin/reports/data/remote_report_models.dart';
import 'package:pos_app/features/cloud_admin/reports/data/remote_report_repository.dart';

class RemoteReportDetailScreen extends StatefulWidget {
  const RemoteReportDetailScreen({required this.kind, super.key});
  final RemoteReportKind kind;

  @override
  State<RemoteReportDetailScreen> createState() => _RemoteReportDetailScreenState();
}

class _RemoteReportDetailScreenState extends State<RemoteReportDetailScreen> {
  late final RemoteReportRepository _repository = RemoteReportRepository(cloudApiClient);
  late final Future<RemoteReportCatalogs> _catalogs = _repository.catalogs();
  final RemoteReportCsvService _csv = RemoteReportCsvService();
  RemoteReportFilter _filter = RemoteReportFilter.forPreset(ReportPreset.thisMonth);
  RemoteReportTable? _lastTable;
  String _groupBy = 'day';
  String _lowMetric = 'revenue';
  String _productSort = 'revenue';
  int _top = 50;
  String? _productGlobalId;
  String? _categoryGlobalId;
  String? _supplierGlobalId;
  String? _userGlobalId;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.kind.title),
          actions: [IconButton(tooltip: 'Exportar CSV', onPressed: _export, icon: const Icon(Icons.download))],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _DetailPeriodSelector(filter: _filter, onChanged: _changeFilter),
            const SizedBox(height: 12),
            _ReportOptions(
              kind: widget.kind,
              groupBy: _effectiveGroupBy,
              lowMetric: _lowMetric,
              productSort: _productSort,
              top: _top,
              onGroupBy: (value) => setState(() { _groupBy = value; _lastTable = null; }),
              onLowMetric: (value) => setState(() { _lowMetric = value; _lastTable = null; }),
              onProductSort: (value) => setState(() { _productSort = value; _lastTable = null; }),
              onTop: (value) => setState(() { _top = value; _lastTable = null; }),
            ),
            const SizedBox(height: 12),
            FutureBuilder<RemoteReportCatalogs>(
              future: _catalogs,
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Text('Los filtros de catálogo no están disponibles; el reporte general sigue disponible.');
                if (!snapshot.hasData) return const SizedBox.shrink();
                return _DimensionFilters(
                  kind: widget.kind,
                  catalogs: snapshot.data!,
                  productGlobalId: _productGlobalId,
                  categoryGlobalId: _categoryGlobalId,
                  supplierGlobalId: _supplierGlobalId,
                  userGlobalId: _userGlobalId,
                  onProduct: (value) => setState(() { _productGlobalId = value; _lastTable = null; }),
                  onCategory: (value) => setState(() { _categoryGlobalId = value; _lastTable = null; }),
                  onSupplier: (value) => setState(() { _supplierGlobalId = value; _lastTable = null; }),
                  onUser: (value) => setState(() { _userGlobalId = value; _lastTable = null; }),
                );
              },
            ),
            const SizedBox(height: 16),
            FutureBuilder<RemoteReportTable>(
              future: _repository.table(
                widget.kind,
                _filter,
                groupBy: _effectiveGroupBy,
                metric: _lowMetric,
                sortBy: _productSort,
                top: _top,
                productGlobalId: _productGlobalId,
                categoryGlobalId: _categoryGlobalId,
                supplierGlobalId: _supplierGlobalId,
                userGlobalId: _userGlobalId,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()));
                if (snapshot.hasError) return _DetailError(error: snapshot.error);
                final table = snapshot.data!;
                _lastTable = table;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (table.note != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(table.note!)),
                    if (_supportsChart(widget.kind) && table.rows.isNotEmpty) ...[
                      _ReportBarChart(kind: widget.kind, rows: table.rows),
                      const SizedBox(height: 18),
                    ],
                    _ReportDataTable(table: table),
                  ],
                );
              },
            ),
          ],
        ),
      );


  String get _effectiveGroupBy => switch (widget.kind) {
        RemoteReportKind.purchases => _groupBy == 'day' || _groupBy == 'month' || _groupBy == 'product' || _groupBy == 'supplier' ? _groupBy : 'supplier',
        RemoteReportKind.expenses => _groupBy == 'day' || _groupBy == 'month' || _groupBy == 'category' ? _groupBy : 'category',
        _ => _groupBy,
      };

  bool _supportsChart(RemoteReportKind kind) => kind == RemoteReportKind.sales || kind == RemoteReportKind.categories || kind == RemoteReportKind.paymentMethods;

  Future<void> _changeFilter(ReportPreset preset) async {
    if (preset != ReportPreset.custom) {
      setState(() {
        _filter = RemoteReportFilter.forPreset(preset);
        _lastTable = null;
      });
      return;
    }
    final now = DateTime.now();
    final range = await showDateRangePicker(context: context, firstDate: DateTime(now.year - 2), lastDate: DateTime(now.year + 1), initialDateRange: DateTimeRange(start: now, end: now));
    if (range != null) {
      setState(() {
        _filter = RemoteReportFilter.custom(range.start, range.end);
        _lastTable = null;
      });
    }
  }

  Future<void> _export() async {
    final table = _lastTable;
    if (table == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Carga el reporte antes de exportar.')));
      return;
    }
    final file = await _csv.export(table);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('CSV: ${file.path}')));
  }
}

class _ReportOptions extends StatelessWidget {
  const _ReportOptions({
    required this.kind,
    required this.groupBy,
    required this.lowMetric,
    required this.productSort,
    required this.top,
    required this.onGroupBy,
    required this.onLowMetric,
    required this.onProductSort,
    required this.onTop,
  });

  final RemoteReportKind kind;
  final String groupBy;
  final String lowMetric;
  final String productSort;
  final int top;
  final ValueChanged<String> onGroupBy;
  final ValueChanged<String> onLowMetric;
  final ValueChanged<String> onProductSort;
  final ValueChanged<int> onTop;

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];
    if (kind == RemoteReportKind.sales) {
      widgets.add(_selector('Agrupar', groupBy, const {'day': 'Día', 'week': 'Semana', 'month': 'Mes'}, onGroupBy));
    } else if (kind == RemoteReportKind.purchases) {
      widgets.add(_selector('Agrupar', groupBy, const {'supplier': 'Proveedor', 'product': 'Producto', 'day': 'Día', 'month': 'Mes'}, onGroupBy));
    } else if (kind == RemoteReportKind.expenses) {
      widgets.add(_selector('Agrupar', groupBy, const {'category': 'Categoría', 'day': 'Día', 'month': 'Mes'}, onGroupBy));
    }
    if (kind == RemoteReportKind.lowPerformance) {
      widgets.add(_selector('Criterio', lowMetric, const {'revenue': 'Menor ingreso', 'units': 'Menos unidades', 'no-sales': 'Sin ventas', 'negative-margin': 'Margen negativo'}, onLowMetric));
    }
    if (kind == RemoteReportKind.products) {
      widgets.add(_selector('Ordenar', productSort, const {'revenue': 'Ingreso', 'units': 'Unidades', 'profit': 'Utilidad', 'margin': 'Margen'}, onProductSort));
    }
    if (kind == RemoteReportKind.products || kind == RemoteReportKind.lowPerformance || kind == RemoteReportKind.trends) {
      widgets.add(_selectorInt('Top', top, const [20, 50, 100], onTop));
    }
    return widgets.isEmpty ? const SizedBox.shrink() : Wrap(spacing: 12, runSpacing: 8, children: widgets);
  }

  Widget _selector(String label, String value, Map<String, String> values, ValueChanged<String> onChanged) => SizedBox(
        width: 210,
        child: DropdownButtonFormField<String>(
          initialValue: values.containsKey(value) ? value : values.keys.first,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          items: values.entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value))).toList(),
          onChanged: (next) { if (next != null) onChanged(next); },
        ),
      );

  Widget _selectorInt(String label, int value, List<int> values, ValueChanged<int> onChanged) => SizedBox(
        width: 140,
        child: DropdownButtonFormField<int>(
          initialValue: value,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          items: values.map((entry) => DropdownMenuItem(value: entry, child: Text('$entry'))).toList(),
          onChanged: (next) { if (next != null) onChanged(next); },
        ),
      );
}

class _DimensionFilters extends StatelessWidget {
  const _DimensionFilters({
    required this.kind,
    required this.catalogs,
    required this.productGlobalId,
    required this.categoryGlobalId,
    required this.supplierGlobalId,
    required this.userGlobalId,
    required this.onProduct,
    required this.onCategory,
    required this.onSupplier,
    required this.onUser,
  });

  final RemoteReportKind kind;
  final RemoteReportCatalogs catalogs;
  final String? productGlobalId;
  final String? categoryGlobalId;
  final String? supplierGlobalId;
  final String? userGlobalId;
  final ValueChanged<String?> onProduct;
  final ValueChanged<String?> onCategory;
  final ValueChanged<String?> onSupplier;
  final ValueChanged<String?> onUser;

  @override
  Widget build(BuildContext context) {
    final fields = <Widget>[];
    final productKinds = {RemoteReportKind.products, RemoteReportKind.lowPerformance, RemoteReportKind.inventory, RemoteReportKind.trends};
    final categoryKinds = {...productKinds, RemoteReportKind.categories};
    final supplierKinds = {RemoteReportKind.purchases, RemoteReportKind.suppliers};
    final userKinds = {RemoteReportKind.sales, RemoteReportKind.users, RemoteReportKind.expenses, RemoteReportKind.cash, RemoteReportKind.cancellations};
    if (productKinds.contains(kind)) fields.add(_dropdown('Producto', productGlobalId, catalogs.products, onProduct));
    if (categoryKinds.contains(kind)) fields.add(_dropdown('Categoría', categoryGlobalId, catalogs.categories, onCategory));
    if (supplierKinds.contains(kind)) fields.add(_dropdown('Proveedor', supplierGlobalId, catalogs.suppliers, onSupplier));
    if (userKinds.contains(kind)) fields.add(_dropdown('Usuario', userGlobalId, catalogs.users, onUser));
    return fields.isEmpty ? const SizedBox.shrink() : Wrap(spacing: 12, runSpacing: 8, children: fields);
  }

  Widget _dropdown(String label, String? value, List<RemoteReportOption> items, ValueChanged<String?> onChanged) => SizedBox(
        width: 260,
        child: DropdownButtonFormField<String?>(
          initialValue: value,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
            ...items.map((item) => DropdownMenuItem<String?>(value: item.globalId, child: Text(item.label, overflow: TextOverflow.ellipsis))),
          ],
          onChanged: onChanged,
        ),
      );
}

class _ReportDataTable extends StatelessWidget {
  const _ReportDataTable({required this.table});
  final RemoteReportTable table;

  @override
  Widget build(BuildContext context) {
    if (table.rows.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('No hay datos para el periodo seleccionado.')));
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: table.columns.map((column) => DataColumn(label: Text(_title(column)))).toList(),
          rows: table.rows.map((row) => DataRow(cells: table.columns.map((column) => DataCell(Text(_format(column, row[column])))).toList())).toList(),
        ),
      ),
    );
  }

  String _format(String column, Object? value) {
    if (column.endsWith('Cents') && value is num) return formatMoney(value.toInt());
    if (column.toLowerCase().contains('percent') && value is num) return '${value.toStringAsFixed(2)}%';
    return value?.toString() ?? '';
  }

  String _title(String value) {
    final spaced = value.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(1)}').trim();
    return spaced.isEmpty ? value : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
  }
}

class _ReportBarChart extends StatelessWidget {
  const _ReportBarChart({required this.kind, required this.rows});
  final RemoteReportKind kind;
  final List<Map<String, Object?>> rows;

  @override
  Widget build(BuildContext context) {
    final labelKey = switch (kind) {
      RemoteReportKind.sales => 'period',
      RemoteReportKind.categories => 'category',
      RemoteReportKind.paymentMethods => 'paymentMethod',
      _ => 'name',
    };
    final valueKey = kind == RemoteReportKind.paymentMethods ? 'amountCents' : kind == RemoteReportKind.categories ? 'revenueCents' : 'salesCents';
    final visible = rows.take(12).toList();
    final maxValue = visible.fold<num>(0, (maxValue, row) => math.max(maxValue, row[valueKey] is num ? row[valueKey] as num : 0));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Gráfica', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final row in visible)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(width: 130, child: Text(row[labelKey]?.toString() ?? '', overflow: TextOverflow.ellipsis)),
                    Expanded(child: LinearProgressIndicator(value: maxValue == 0 ? 0 : ((row[valueKey] as num?)?.toDouble() ?? 0) / maxValue.toDouble(), minHeight: 14)),
                    const SizedBox(width: 10),
                    SizedBox(width: 110, child: Text(formatMoney((row[valueKey] as num?)?.toInt() ?? 0), textAlign: TextAlign.end)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailPeriodSelector extends StatelessWidget {
  const _DetailPeriodSelector({required this.filter, required this.onChanged});
  final RemoteReportFilter filter;
  final ValueChanged<ReportPreset> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: ReportPreset.values.map((preset) => ChoiceChip(label: Text(RemoteReportFilter.forPreset(preset).label), selected: filter.preset == preset, onSelected: (_) => onChanged(preset))).toList(),
      );
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.error});
  final Object? error;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(error is CloudApiException ? (error as CloudApiException).message : 'No fue posible cargar el reporte remoto.'),
        ),
      );
}
