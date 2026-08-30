import 'package:flutter/material.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/design/app_spacing.dart';
import 'package:pos_app/core/design/components/app_components.dart';

class DatabaseListScreen extends StatefulWidget {
  const DatabaseListScreen({
    super.key,
    required this.title,
    this.query,
    this.loadRows,
    this.action,
    this.subtitle,
    this.actionLabel,
    this.showNavigation = true,
  }) : assert((query == null) != (loadRows == null));
  final String title;
  final String? query;
  final Future<List<Map<String, Object?>>> Function()? loadRows;
  final Future<void> Function(BuildContext)? action;
  final String? subtitle;
  final String? actionLabel;
  final bool showNavigation;
  @override
  State<DatabaseListScreen> createState() => _DatabaseListScreenState();
}

class _DatabaseListScreenState extends State<DatabaseListScreen> {
  Future<List<Map<String, Object?>>> _load() async {
    if (widget.loadRows case final loader?) return loader();
    final db = await appDatabase.open();
    return db.rawQuery(widget.query!);
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: widget.title,
    subtitle:
        widget.subtitle ?? 'Consulta y administra la información disponible.',
    showNavigation: widget.showNavigation,
    scrollable: false,
    primaryAction: widget.action == null
        ? null
        : AppPrimaryButton(
            label: widget.actionLabel ?? 'Nuevo registro',
            icon: Icons.add,
            onPressed: () async {
              await widget.action!(context);
              if (mounted) setState(() {});
            },
          ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: _load(),
      builder: (c, s) {
        if (s.hasError) return AppErrorState(onRetry: () => setState(() {}));
        if (!s.hasData) return const AppLoadingState();
        final rows = s.data!;
        if (rows.isEmpty) {
          return AppEmptyState(
            message: 'No hay ${widget.title.toLowerCase()} registrados.',
          );
        }
        return Card(
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) => ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              title: Text(rows[i].values.skip(1).take(2).join(' · ')),
              subtitle: Text(_humanReadable(rows[i])),
            ),
          ),
        );
      },
    ),
  );

  String _humanReadable(Map<String, Object?> row) => row.entries
      .skip(1)
      .map(
        (entry) => '${entry.key.replaceAll('_', ' ')}: ${entry.value ?? '—'}',
      )
      .join(' · ');
}

Future<List<String>?> textForm(
  BuildContext context,
  String title,
  List<String> labels,
) async {
  final controllers = List.generate(
    labels.length,
    (_) => TextEditingController(),
  );
  final result = await showDialog<List<String>>(
    context: context,
    builder: (d) => AppDialog(
      title: title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppTextField(
                label: labels[i],
                controller: controllers[i],
                keyboardType: _numericLabel(labels[i])
                    ? const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      )
                    : null,
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(d),
          child: const Text('Cancelar'),
        ),
        AppPrimaryButton(
          label: 'Guardar',
          onPressed: () =>
              Navigator.pop(d, controllers.map((e) => e.text).toList()),
        ),
      ],
    ),
  );
  for (final c in controllers) {
    c.dispose();
  }
  return result;
}

bool _numericLabel(String label) {
  final value = label.toLowerCase();
  return [
    'cantidad',
    'precio',
    'costo',
    'monto',
    'saldo',
    'efectivo',
    'stock',
    ' id',
  ].any(value.contains);
}
