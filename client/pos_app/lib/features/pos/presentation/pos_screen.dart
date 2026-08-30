import 'package:flutter/material.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/utils/money.dart';
import 'package:pos_app/features/pos/data/pos_repository.dart';
import 'package:pos_app/features/pos/domain/cart.dart';
import 'package:pos_app/shared/presentation/app_navigation_drawer.dart';
import 'package:pos_app/core/design/app_breakpoints.dart';
import 'package:pos_app/core/design/app_spacing.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final lines = <CartLine>[];
  bool busy = false;

  Future<void> addProduct() async {
    final db = await appDatabase.open();

    final rows = await db.rawQuery('''
      SELECT
        p.id,
        p.global_id,
        p.name,
        p.sale_price_cents,
        COALESCE(SUM(l.available_quantity), 0) stock
      FROM products p
      LEFT JOIN inventory_lots l
        ON l.product_id = p.id
       AND l.active = 1
      WHERE p.active = 1
      GROUP BY p.id
      ORDER BY p.name
      LIMIT 100
      ''');

    if (!mounted) {
      return;
    }

    final row = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Selecciona producto'),
        children: rows
            .map(
              (product) => SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, product),
                child: Text(
                  '${product['name']} · '
                  'stock ${product['stock']} · '
                  '${formatMoney(product['sale_price_cents'] as int)}',
                ),
              ),
            )
            .toList(),
      ),
    );

    if (row == null || !mounted) {
      return;
    }

    setState(() {
      lines.add(
        CartLine(
          productId: row['id'] as int,
          productGlobalId: row['global_id'] as String,
          name: row['name'] as String,
          quantity: 1,
          unitPriceCents: row['sale_price_cents'] as int,
        ),
      );
    });
  }

  Future<void> _completeCashSale(int total) async {
    setState(() => busy = true);

    try {
      await PosRepository(appDatabase)
          .completeSale(lines, paymentMethod: 'Cash', receivedCents: total);

      if (!mounted) {
        return;
      }

      setState(lines.clear);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = calculateSaleTotals(lines).totalCents;

    return Scaffold(
      appBar: AppBar(title: const Text('Nueva venta')),
      drawer: const AppNavigationDrawer(),
      floatingActionButton: FloatingActionButton(
        onPressed: addProduct,
        child: const Icon(Icons.add),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              AppBreakpoints.ofWidth(constraints.maxWidth) ==
              AppLayoutSize.compact;
          final cart = Expanded(
            child: ListView.builder(
              itemCount: lines.length,
              itemBuilder: (context, index) {
                final line = lines[index];

                return ListTile(
                  title: Text(line.name),
                  subtitle: Text(formatMoney(line.unitPriceCents)),
                  trailing: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconButton(
                        onPressed: () {
                          setState(() {
                            line.quantity = line.quantity > 1
                                ? line.quantity - 1
                                : 1;
                          });
                        },
                        icon: const Icon(Icons.remove),
                      ),
                      Text('${line.quantity}'),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            line.quantity++;
                          });
                        },
                        icon: const Icon(Icons.add),
                      ),
                      Text(formatMoney(line.totalCents)),
                    ],
                  ),
                );
              },
            ),
          );
          final checkout = SizedBox(
            width: compact ? double.infinity : 320,
            height: compact ? 190 : null,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'TOTAL',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      formatMoney(total),
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: busy || lines.isEmpty
                          ? null
                          : () => _completeCashSale(total),
                      child: const Text('COBRAR EFECTIVO'),
                    ),
                  ],
                ),
              ),
            ),
          );
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: compact
                ? Column(
                    children: [
                      cart,
                      const SizedBox(height: AppSpacing.sm),
                      checkout,
                    ],
                  )
                : Row(
                    children: [
                      cart,
                      const SizedBox(width: AppSpacing.md),
                      checkout,
                    ],
                  ),
          );
        },
      ),
    );
  }
}
