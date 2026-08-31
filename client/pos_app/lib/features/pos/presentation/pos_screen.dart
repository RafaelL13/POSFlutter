import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/design/app_breakpoints.dart';
import 'package:pos_app/core/design/app_colors.dart';
import 'package:pos_app/core/design/app_spacing.dart';
import 'package:pos_app/core/design/components/app_components.dart';
import 'package:pos_app/core/utils/money.dart';
import 'package:pos_app/features/pos/data/pos_catalog_repository.dart';
import 'package:pos_app/features/pos/data/pos_repository.dart';
import 'package:pos_app/features/pos/domain/cart.dart';
import 'package:pos_app/features/pos/presentation/pos_controller.dart';
import 'package:pos_app/shared/presentation/app_navigation_drawer.dart';
import 'package:pos_app/shared/presentation/special_authorization_dialog.dart';
import 'package:pos_app/sync/presentation/sync_status_panel.dart';
import 'package:pos_app/sync/sync_health.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({this.controller, this.syncSummary, super.key});
  final PosController? controller;
  final SyncSummary? syncSummary;
  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  late final PosController controller =
      widget.controller ??
      PosController(
        load: PosCatalogRepository(appDatabase).load,
        completeSale: PosRepository(appDatabase).completeSale,
      );
  final search = TextEditingController();
  bool get ownsController => widget.controller == null;

  @override
  void initState() {
    super.initState();
    controller.addListener(_refresh);
    if (controller.bootstrap == null) controller.initialize();
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    if (ownsController) controller.dispose();
    search.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: controller.lines.isEmpty,
    onPopInvokedWithResult: (didPop, _) async {
      if (!didPop && await _confirmDiscard()) {
        if (context.mounted) context.pop();
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Nueva venta'),
        actions: [
          if (controller.lines.isNotEmpty)
            TextButton.icon(
              onPressed: _clearCart,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Vaciar venta'),
            ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      drawer: const AppNavigationDrawer(),
      body: SafeArea(child: _body()),
    ),
  );

  Widget _body() {
    if (controller.loading) {
      return const AppLoadingState(label: 'Preparando punto de venta…');
    }
    if (controller.error != null && controller.bootstrap == null) {
      return AppErrorState(
        message: controller.error!,
        onRetry: controller.initialize,
      );
    }
    final bootstrap = controller.bootstrap!;
    return Column(
      children: [
        _OperationalHeader(
          bootstrap: bootstrap,
          syncSummary: widget.syncSummary,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final landscape = constraints.maxWidth >= AppBreakpoints.expanded;
              final catalog = _CatalogPanel(
                controller: controller,
                search: search,
                onDenied: _stockDenied,
              );
              final cart = _CartPanel(
                controller: controller,
                onCheckout: _checkout,
                onClear: _clearCart,
                onInvalidQuantity: _invalidQuantity,
              );
              if (!landscape && constraints.maxHeight < 900) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: Column(
                    children: [
                      SizedBox(height: 430, child: catalog),
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(height: 540, child: cart),
                    ],
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: landscape
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 7, child: catalog),
                          const SizedBox(width: AppSpacing.md),
                          SizedBox(width: 390, child: cart),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(flex: 6, child: catalog),
                          const SizedBox(height: AppSpacing.sm),
                          Expanded(flex: 5, child: cart),
                        ],
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _checkout() async {
    if (controller.bootstrap?.cashOpen != true) {
      _message('Necesitas abrir caja antes de vender.');
      return;
    }
    CompletedSale? completed;
    final ok = await runWithSpecialAuthorization(
      context: context,
      capability: Capability.saleDiscount,
      operationLabel: 'Aplicar descuento en venta',
      reason: 'Descuento autorizado en punto de venta',
      operation: (grant) async {
        completed = await controller.submit(authorizationGrant: grant);
      },
    );
    if (!ok || completed == null || !mounted) {
      if (controller.error != null) _message(controller.error!);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: 'Venta registrada',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 56,
              color: AppColors.success,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Total: ${formatMoney(completed!.totalCents)}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
        actions: [
          AppPrimaryButton(
            label: 'Nueva venta',
            onPressed: () => Navigator.pop(dialogContext),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmDiscard() async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AppDialog(
          title: 'Descartar venta actual',
          destructive: true,
          content: const Text(
            'Hay productos en la venta actual. ¿Deseas descartarla?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Continuar venta'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Descartar'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _clearCart() async {
    if (await _confirmDiscard()) controller.clear();
  }

  void _stockDenied() => _message('No hay suficiente existencia disponible.');
  void _invalidQuantity() => _message(
    'Ingresa una cantidad entera entre 1 y la existencia disponible.',
  );
  void _message(String value) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
}

class _OperationalHeader extends StatelessWidget {
  const _OperationalHeader({required this.bootstrap, this.syncSummary});
  final PosBootstrap bootstrap;
  final SyncSummary? syncSummary;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    child: AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.xs,
        children: [
          AppStatusChip(
            label: bootstrap.cashOpen ? 'Caja abierta' : 'Caja cerrada',
            status: bootstrap.cashOpen ? AppStatus.active : AppStatus.warning,
          ),
          Text(
            '${bootstrap.branchName} · ${bootstrap.userName}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          SizedBox(width: 260, child: SyncStatusPanel(summary: syncSummary)),
          if (!bootstrap.cashOpen &&
              bootstrap.capabilities.can(Capability.cashOpen))
            AppSecondaryButton(
              label: 'Abrir caja',
              icon: Icons.lock_open_outlined,
              onPressed: () => context.go('/cash'),
            ),
        ],
      ),
    ),
  );
}

class _CatalogPanel extends StatelessWidget {
  const _CatalogPanel({
    required this.controller,
    required this.search,
    required this.onDenied,
  });
  final PosController controller;
  final TextEditingController search;
  final VoidCallback onDenied;
  @override
  Widget build(BuildContext context) {
    final products = controller.visibleProducts;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('pos-search'),
            controller: search,
            autofocus: true,
            onChanged: controller.setSearch,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: 'Buscar productos',
              hintText: 'Nombre o código',
              suffixIcon: search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpiar búsqueda',
                      onPressed: () {
                        search.clear();
                        controller.setSearch('');
                      },
                      icon: const Icon(Icons.clear),
                    ),
            ),
          ),
          if (controller.bootstrap!.categories.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('Todos'),
                    selected: controller.selectedCategoryId == null,
                    onSelected: (_) => controller.selectCategory(null),
                  ),
                  for (final category in controller.bootstrap!.categories)
                    Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.xs),
                      child: ChoiceChip(
                        label: Text(category.name),
                        selected: controller.selectedCategoryId == category.id,
                        onSelected: (_) =>
                            controller.selectCategory(category.id),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: products.isEmpty
                ? const AppEmptyState(
                    message: 'No hay productos que coincidan con la búsqueda.',
                    icon: Icons.search_off,
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth < 450
                          ? 1
                          : constraints.maxWidth >= 900
                          ? 4
                          : constraints.maxWidth >= 600
                          ? 3
                          : 2;
                      return GridView.builder(
                        itemCount: products.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          childAspectRatio: columns == 1 ? 2.2 : 1.35,
                          crossAxisSpacing: AppSpacing.sm,
                          mainAxisSpacing: AppSpacing.sm,
                        ),
                        itemBuilder: (_, index) => _ProductCard(
                          product: products[index],
                          onTap: () {
                            if (!controller.addProduct(products[index])) {
                              onDenied();
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onTap});
  final PosProduct product;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final available = product.stock > 0;
    return Card(
      child: InkWell(
        key: Key('pos-product-${product.id}'),
        onTap: available ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                product.code,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      formatMoney(product.priceCents),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  AppStatusChip(
                    label: available ? '${product.stock}' : 'Agotado',
                    status: available ? AppStatus.active : AppStatus.inactive,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({
    required this.controller,
    required this.onCheckout,
    required this.onClear,
    required this.onInvalidQuantity,
  });
  final PosController controller;
  final VoidCallback onCheckout;
  final VoidCallback onClear;
  final VoidCallback onInvalidQuantity;
  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Carrito', style: Theme.of(context).textTheme.titleLarge),
            Text(
              '${controller.lines.fold<int>(0, (sum, line) => sum + line.quantity)} artículos',
            ),
          ],
        ),
        const Divider(),
        Expanded(
          child: controller.lines.isEmpty
              ? const AppEmptyState(
                  message: 'Agrega productos para iniciar la venta.',
                  icon: Icons.shopping_cart_outlined,
                )
              : ListView.separated(
                  itemCount: controller.lines.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) => _CartRow(
                    line: controller.lines[index],
                    controller: controller,
                    onInvalidQuantity: onInvalidQuantity,
                  ),
                ),
        ),
        const Divider(),
        _MoneyRow(label: 'Subtotal', cents: controller.totals.subtotalCents),
        if (controller.lines.isNotEmpty &&
            controller.bootstrap!.capabilities.can(Capability.saleDiscount))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('pos-discount'),
              onPressed: () => _editDiscount(context),
              icon: const Icon(Icons.discount_outlined),
              label: Text(
                controller.discountCents == 0
                    ? 'Agregar descuento'
                    : 'Editar descuento',
              ),
            ),
          ),
        if (controller.discountCents > 0)
          _MoneyRow(label: 'Descuento', cents: -controller.discountCents),
        _MoneyRow(
          label: 'Total',
          cents: controller.totals.totalCents,
          emphasized: true,
        ),
        const SizedBox(height: AppSpacing.xs),
        TextFormField(
          key: const Key('pos-received'),
          initialValue: controller.receivedCents == 0
              ? ''
              : (controller.receivedCents / 100).toStringAsFixed(2),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Efectivo recibido (MXN)',
            prefixText: r'$ ',
          ),
          onChanged: (value) {
            try {
              controller.setReceivedCents(parseMoneyToCents(value));
            } on Object {
              controller.setReceivedCents(0);
            }
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        _MoneyRow(label: 'Cambio', cents: controller.changeCents),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 56,
          child: AppPrimaryButton(
            key: const Key('pos-checkout'),
            label: controller.isSubmitting
                ? 'Registrando…'
                : 'Cobrar ${formatMoney(controller.totals.totalCents)}',
            icon: Icons.payments_outlined,
            onPressed: controller.canCheckout ? onCheckout : null,
          ),
        ),
      ],
    ),
  );

  Future<void> _editDiscount(BuildContext context) async {
    final input = TextEditingController(
      text: controller.discountCents == 0
          ? ''
          : (controller.discountCents / 100).toStringAsFixed(2),
    );
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: 'Descuento',
        content: TextField(
          key: const Key('pos-discount-input'),
          controller: input,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Monto (MXN)',
            prefixText: r'$ ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          AppPrimaryButton(
            label: 'Aplicar',
            onPressed: () => Navigator.pop(dialogContext, input.text),
          ),
        ],
      ),
    );
    input.dispose();
    if (!context.mounted) return;
    if (value == null) return;
    try {
      if (!controller.setDiscount('${parseMoneyToCents(value)}')) {
        throw const FormatException();
      }
    } on Object {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ingresa un descuento válido que no exceda el subtotal.',
          ),
        ),
      );
    }
  }
}

class _CartRow extends StatelessWidget {
  const _CartRow({
    required this.line,
    required this.controller,
    required this.onInvalidQuantity,
  });
  final CartLine line;
  final PosController controller;
  final VoidCallback onInvalidQuantity;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text('${formatMoney(line.unitPriceCents)} c/u'),
            ],
          ),
        ),
        IconButton(
          key: Key('pos-decrement-${line.productId}'),
          tooltip: 'Disminuir ${line.name}',
          onPressed: line.quantity > 1
              ? () => controller.decrement(line)
              : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Semantics(
          label: 'Cantidad de ${line.name}',
          child: InkWell(
            key: Key('pos-quantity-${line.productId}'),
            onTap: () => _editQuantity(context),
            child: SizedBox(
              width: 36,
              child: Text(
                '${line.quantity}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ),
        IconButton(
          key: Key('pos-increment-${line.productId}'),
          tooltip: 'Aumentar ${line.name}',
          onPressed: () {
            if (!controller.increment(line)) onInvalidQuantity();
          },
          icon: const Icon(Icons.add_circle_outline),
        ),
        SizedBox(
          width: 78,
          child: Text(formatMoney(line.totalCents), textAlign: TextAlign.end),
        ),
        IconButton(
          key: Key('pos-remove-${line.productId}'),
          tooltip: 'Eliminar ${line.name}',
          onPressed: () => controller.remove(line),
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
  );
  Future<void> _editQuantity(BuildContext context) async {
    final input = TextEditingController(text: '${line.quantity}');
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: 'Cantidad',
        content: TextField(
          key: const Key('pos-quantity-input'),
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            helperText: 'Disponible: ${line.availableStock ?? '—'}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          AppPrimaryButton(
            label: 'Aplicar',
            onPressed: () => Navigator.pop(dialogContext, input.text),
          ),
        ],
      ),
    );
    input.dispose();
    if (value != null && !controller.setQuantity(line, value)) {
      if (context.mounted) onInvalidQuantity();
    }
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.cents,
    this.emphasized = false,
  });
  final String label;
  final int cents;
  final bool emphasized;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: emphasized ? Theme.of(context).textTheme.titleLarge : null,
        ),
        Text(
          formatMoney(cents),
          style: emphasized ? Theme.of(context).textTheme.headlineSmall : null,
        ),
      ],
    ),
  );
}
