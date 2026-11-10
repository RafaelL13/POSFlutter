import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/utils/money.dart';
import 'package:pos_app/features/pos/data/web_combo_catalog_repository.dart';
import 'package:pos_app/features/pos/data/web_combo_checkout_repository.dart';

/// Online-only. Never writes to the offline SQLite sales queue.
class WebComboSaleDialog extends StatefulWidget {
  const WebComboSaleDialog({super.key});
  @override
  State<WebComboSaleDialog> createState() => _WebComboSaleDialogState();
}

class _WebComboSaleDialogState extends State<WebComboSaleDialog> {
  late final WebComboCatalogRepository catalog = WebComboCatalogRepository(cloudApiClient);
  late final WebComboCheckoutRepository checkout = WebComboCheckoutRepository(cloudApiClient);
  late Future<List<WebComboCatalogItem>> items = catalog.load();
  WebComboCatalogItem? selected;
  int quantity = 1;
  bool sending = false;
  String? error;
  String? intentKey;

  void changed() => setState(() { intentKey = null; error = null; });

  Future<void> submit() async {
    if (sending || selected == null) return;
    final chosen = selected!;
    final total = chosen.priceCents * quantity;
    final key = intentKey ?? const Uuid().v4();
    intentKey = key; // A retry of the same intent MUST preserve the key.
    setState(() { sending = true; error = null; });
    try {
      final result = await checkout.checkout(
        idempotencyKey: key,
        combos: [WebComboSelection(comboGlobalId: chosen.comboGlobalId,
            expectedServerVersion: chosen.serverVersion, quantity: quantity)],
        payments: [WebCheckoutPaymentSelection(method: 'Cash', amountCents: total)],
        receivedCashCents: total,
      );
      if (!mounted) return;
      if (result.totalCents != total) {
        // Server is authoritative: never silently accept a changed price.
        setState(() => error = 'El servidor devolvió un importe diferente. Venta ${result.folio}. Verifica la operación antes de reintentar.');
        return;
      }
      Navigator.of(context).pop(result);
    } catch (_) {
      if (mounted) setState(() => error = 'No se confirmó el cobro. Consulta el historial antes de cambiar el carrito; reintentar conserva la misma clave.');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Venta de combo en línea'),
    content: SizedBox(width: 440, child: FutureBuilder<List<WebComboCatalogItem>>(
      future: items,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return const Text('No se pudo consultar el catálogo. Se requiere conexión y sesión válidas.');
        final options = snapshot.data ?? [];
        if (options.isEmpty) return const Text('No hay combos activos disponibles.');
        return Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Combo'),
            initialValue: selected?.comboGlobalId,
            items: options.map((item) => DropdownMenuItem(value: item.comboGlobalId,
              child: Text(item.name, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: sending ? null : (id) => setState(() {
              selected = options.where((e) => e.comboGlobalId == id).firstOrNull;
              quantity = 1; intentKey = null; error = null;
            }),
          ),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Cantidad'),
            IconButton(onPressed: sending || quantity <= 1 ? null : () { quantity--; changed(); }, icon: const Icon(Icons.remove)),
            Text('$quantity'),
            IconButton(onPressed: sending || quantity >= 1000 ? null : () { quantity++; changed(); }, icon: const Icon(Icons.add)),
          ]),
          if (selected != null) Text('Efectivo exacto: ${formatMoney(selected!.priceCents * quantity)}'),
          const Text('Solo conexión en línea. No registra ventas offline.'),
          if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ]);
      },
    )),
    actions: [
      TextButton(onPressed: sending ? null : () => Navigator.pop(context), child: const Text('Cerrar')),
      FilledButton(onPressed: sending || selected == null ? null : submit,
        child: Text(sending ? 'Procesando...' : 'Cobrar efectivo')),
    ],
  );
}
