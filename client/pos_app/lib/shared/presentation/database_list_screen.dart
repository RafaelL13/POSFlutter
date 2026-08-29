import 'package:flutter/material.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/shared/presentation/app_navigation_drawer.dart';

class DatabaseListScreen extends StatefulWidget {
  const DatabaseListScreen({
    super.key,
    required this.title,
    this.query,
    this.loadRows,
    this.action,
    this.showNavigation = true,
  }) : assert((query == null) != (loadRows == null));
  final String title;
  final String? query;
  final Future<List<Map<String, Object?>>> Function()? loadRows;
  final Future<void> Function(BuildContext)? action;
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    drawer: widget.showNavigation ? const AppNavigationDrawer() : null,
    floatingActionButton: widget.action == null
        ? null
        : FloatingActionButton(
            onPressed: () async {
              await widget.action!(context);
              if (mounted) setState(() {});
            },
            child: const Icon(Icons.add),
          ),
    body: FutureBuilder(
      future: _load(),
      builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final rows = s.data!;
        if (rows.isEmpty) return const Center(child: Text('Sin registros'));
        return ListView.builder(
          itemCount: rows.length,
          itemBuilder: (_, i) => ListTile(
            title: Text(rows[i].values.skip(1).take(2).join(' · ')),
            subtitle: Text(rows[i].toString()),
          ),
        );
      },
    ),
  );
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
    builder: (d) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: controllers[i],
                keyboardType: labels[i].toLowerCase().contains('cent')
                    ? TextInputType.number
                    : null,
                decoration: InputDecoration(
                  labelText: labels[i],
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(d),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(d, controllers.map((e) => e.text).toList()),
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
  for (final c in controllers) {
    c.dispose();
  }
  return result;
}
