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
  final Future<bool> Function(BuildContext)? action;
  final String? subtitle;
  final String? actionLabel;
  final bool showNavigation;
  @override
  State<DatabaseListScreen> createState() => _DatabaseListScreenState();
}

class _DatabaseListScreenState extends State<DatabaseListScreen> {
  bool _submitting = false;
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
    primaryAction:
        widget.action == null
            ? null
            : AppPrimaryButton(
              label:
                  _submitting
                      ? 'Guardando…'
                      : widget.actionLabel ?? 'Nuevo registro',
              icon: Icons.add,
              onPressed: _submitting ? null : _runAction,
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
            action:
                widget.action == null
                    ? null
                    : AppPrimaryButton(
                      label: widget.actionLabel ?? 'Nuevo registro',
                      icon: Icons.add,
                      onPressed: _submitting ? null : _runAction,
                    ),
          );
        }
        return Card(
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder:
                (_, i) => ListTile(
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

  Future<void> _runAction() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final completed = await widget.action!(context);
      if (!mounted) return;
      if (completed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Operación completada correctamente.')),
        );
      }
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo completar la operación. Revisa los datos.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class TextFormFieldSpec {
  const TextFormFieldSpec(
    this.label, {
    this.required = true,
    this.numeric = false,
    this.allowNegative = false,
    this.allowZero = false,
    this.helperText,
  });

  final String label;
  final bool required;
  final bool numeric;
  final bool allowNegative;
  final bool allowZero;
  final String? helperText;
}

Future<List<String>?> textForm(
  BuildContext context,
  String title,
  List<String> labels,
) => configuredTextForm(
  context,
  title,
  labels
      .map(
        (label) => TextFormFieldSpec(
          label,
          numeric: _numericLabel(label),
          allowNegative: label.contains('(+/-)'),
          allowZero: label.toLowerCase().contains('stock mínimo'),
        ),
      )
      .toList(),
);

Future<List<String>?> configuredTextForm(
  BuildContext context,
  String title,
  List<TextFormFieldSpec> fields,
) async {
  final formKey = GlobalKey<FormState>();
  final controllers = List.generate(
    fields.length,
    (_) => TextEditingController(),
  );
  final result = await showDialog<List<String>>(
    context: context,
    builder:
        (d) => AppDialog(
          title: title,
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < fields.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppTextField(
                        label: fields[i].label,
                        controller: controllers[i],
                        required: fields[i].required,
                        helperText: fields[i].helperText,
                        autofocus: i == 0,
                        textInputAction:
                            i == fields.length - 1
                                ? TextInputAction.done
                                : TextInputAction.next,
                        keyboardType:
                            fields[i].numeric
                                ? TextInputType.numberWithOptions(
                                  decimal: true,
                                  signed: fields[i].allowNegative,
                                )
                                : null,
                        validator: (value) => _validateField(value, fields[i]),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('Cancelar'),
            ),
            AppPrimaryButton(
              label: 'Guardar',
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                Navigator.pop(
                  d,
                  controllers.map((e) => e.text.trim()).toList(),
                );
              },
            ),
          ],
        ),
  );
  // showDialog completes when the route starts closing; wait until its reverse
  // animation no longer references the field controllers before disposing them.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  for (final c in controllers) {
    c.dispose();
  }
  return result;
}

String? _validateField(String? rawValue, TextFormFieldSpec field) {
  final value = rawValue?.trim() ?? '';
  if (field.required && value.isEmpty) return 'Este campo es obligatorio.';
  if (!field.numeric || value.isEmpty) return null;
  final number = num.tryParse(value.replaceAll(',', '.'));
  if (number == null) return 'Ingresa un número válido.';
  if (!field.allowNegative && number < 0) {
    return 'El valor no puede ser negativo.';
  }
  if (!field.allowZero && number == 0) {
    return 'El valor debe ser mayor que cero.';
  }
  return null;
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
