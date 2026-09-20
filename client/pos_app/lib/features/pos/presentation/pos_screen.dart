import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/design/app_breakpoints.dart';
import 'package:pos_app/core/design/app_colors.dart';
import 'package:pos_app/core/design/app_spacing.dart';
import 'package:pos_app/core/design/components/app_components.dart';
import 'package:pos_app/core/utils/money.dart';
import 'package:pos_app/features/payments/domain/sale_payment.dart';
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
    // Dashboard opens POS with `go('/pos')`, so this route has no previous
    // page to pop back to. Always handle Android back explicitly instead of
    // allowing the root navigator to close the activity.
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _handleBackNavigation();
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Nueva venta'),
        actions: [
          if (controller.lines.isNotEmpty)
            if (MediaQuery.sizeOf(context).width < 600)
              IconButton(
                key: const Key('pos-clear-sale'),
                tooltip: 'Vaciar venta',
                onPressed: _clearCart,
                icon: const Icon(Icons.delete_sweep_outlined),
              )
            else
              TextButton.icon(
                key: const Key('pos-clear-sale'),
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
    if (!controller.canCheckout) {
      final reason = controller.checkoutBlockReason;
      if (reason != null) _message(reason);
      return;
    }

    final paymentLabel = _paymentModeLabel(controller.paymentMode);
    final paymentBreakdown = List<SalePaymentInput>.of(
      controller.paymentInputs,
    );
    final hadCash = controller.cashPaymentCents > 0;
    final changeCents = controller.changeCents;

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
            const SizedBox(height: AppSpacing.xs),
            Text('Forma de pago: $paymentLabel'),
            const SizedBox(height: AppSpacing.xs),
            for (final payment in paymentBreakdown)
              Text(
                '${_paymentMethodLabel(payment.method)}: '
                '${formatMoney(payment.amountCents)}',
              ),
            if (hadCash) ...[
              const SizedBox(height: AppSpacing.xs),
              Text('Cambio: ${formatMoney(changeCents)}'),
            ],
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

  Future<void> _handleBackNavigation() async {
    if (controller.lines.isEmpty) {
      if (mounted) context.go('/dashboard');

      return;
    }
    if (await _confirmDiscard()) {
      controller.clear();
      if (mounted) context.go('/dashboard');
    }
  }

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
              hintText: 'Nombre, código/SKU o código de barras',
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
                '${product.code} · ${product.categoryName ?? 'Sin categoría'}',
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
    required this.onInvalidQuantity,
  });

  final PosController controller;
  final VoidCallback onCheckout;
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
          flex: 5,
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
        Flexible(
          flex: 6,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MoneyRow(
                  label: 'Subtotal',
                  cents: controller.totals.subtotalCents,
                ),
                if (controller.lines.isNotEmpty &&
                    controller.bootstrap!.capabilities.can(
                      Capability.saleDiscount,
                    ))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('pos-discount'),
                      onPressed: controller.isSubmitting
                          ? null
                          : () => _editDiscount(context),
                      icon: const Icon(Icons.discount_outlined),
                      label: Text(
                        controller.discountCents == 0
                            ? 'Agregar descuento'
                            : 'Editar descuento',
                      ),
                    ),
                  ),
                if (controller.discountCents > 0)
                  _MoneyRow(
                    label: 'Descuento',
                    cents: -controller.discountCents,
                  ),
                _MoneyRow(
                  label: 'Total',
                  cents: controller.totals.totalCents,
                  emphasized: true,
                ),
                if (controller.lines.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _PaymentSection(controller: controller),
                ],
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  height: 56,
                  child: AppPrimaryButton(
                    key: const Key('pos-checkout'),
                    label: controller.isSubmitting
                        ? 'Registrando…'
                        : _checkoutButtonLabel(controller),
                    icon: Icons.payments_outlined,
                    onPressed: controller.canCheckout ? onCheckout : null,
                  ),
                ),
                if (!controller.isSubmitting &&
                    controller.checkoutBlockReason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      controller.checkoutBlockReason!,
                      key: const Key('pos-checkout-help'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _editDiscount(BuildContext context) async {
    final input = TextEditingController(
      text: controller.discountCents == 0
          ? ''
          : _centsInput(controller.discountCents),
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

class _PaymentSection extends StatelessWidget {
  const _PaymentSection({required this.controller});

  final PosController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Forma de pago', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: AppSpacing.xs),
      Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          _PaymentChoice(
            key: const Key('pos-payment-cash'),
            label: 'Efectivo',
            icon: Icons.payments_outlined,
            selected: controller.paymentMode == PosPaymentMode.cash,
            enabled: !controller.isSubmitting,
            onSelected: () => controller.setPaymentMode(PosPaymentMode.cash),
          ),
          _PaymentChoice(
            key: const Key('pos-payment-card'),
            label: 'Tarjeta',
            icon: Icons.credit_card_outlined,
            selected: controller.paymentMode == PosPaymentMode.card,
            enabled: !controller.isSubmitting,
            onSelected: () => controller.setPaymentMode(PosPaymentMode.card),
          ),
          _PaymentChoice(
            key: const Key('pos-payment-transfer'),
            label: 'Transferencia',
            icon: Icons.account_balance_outlined,
            selected: controller.paymentMode == PosPaymentMode.transfer,
            enabled: !controller.isSubmitting,
            onSelected: () =>
                controller.setPaymentMode(PosPaymentMode.transfer),
          ),
          _PaymentChoice(
            key: const Key('pos-payment-mixed'),
            label: 'Mixto',
            icon: Icons.call_split_outlined,
            selected: controller.paymentMode == PosPaymentMode.mixed,
            enabled: !controller.isSubmitting,
            onSelected: () => controller.setPaymentMode(PosPaymentMode.mixed),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      switch (controller.paymentMode) {
        PosPaymentMode.cash => _CashTenderEditor(
          controller: controller,
          cashDueCents: controller.totals.totalCents,
        ),
        PosPaymentMode.card => _SingleNonCashPaymentSummary(
          icon: Icons.credit_card_outlined,
          label: 'Tarjeta',
          totalCents: controller.totals.totalCents,
          message: 'No modifica el efectivo esperado en caja.',
        ),
        PosPaymentMode.transfer => _SingleNonCashPaymentSummary(
          icon: Icons.account_balance_outlined,
          label: 'Transferencia',
          totalCents: controller.totals.totalCents,
          message: 'No modifica el efectivo esperado en caja.',
        ),
        PosPaymentMode.mixed => _MixedPaymentEditor(controller: controller),
      },
    ],
  );
}

class _PaymentChoice extends StatelessWidget {
  const _PaymentChoice({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onSelected,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    avatar: Icon(icon, size: 18),
    label: Text(label),
    selected: selected,
    onSelected: enabled
        ? (value) {
            if (value) onSelected();
          }
        : null,
  );
}

class _CashTenderEditor extends StatelessWidget {
  const _CashTenderEditor({
    required this.controller,
    required this.cashDueCents,
  });

  final PosController controller;
  final int cashDueCents;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        key: ValueKey(
          'pos-received-${controller.paymentInputRevision}-${controller.paymentMode.name}',
        ),
        initialValue: controller.receivedCents == 0
            ? ''
            : _centsInput(controller.receivedCents),
        enabled: !controller.isSubmitting,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'Efectivo recibido',
          prefixText: r'$ ',
          suffixIcon: IconButton(
            key: const Key('pos-cash-exact'),
            tooltip: 'Usar importe exacto',
            onPressed: controller.isSubmitting || cashDueCents <= 0
                ? null
                : controller.setReceivedExact,
            icon: const Icon(Icons.done_all),
          ),
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
      Row(
        children: [
          Expanded(
            child: Text(
              'A cubrir en efectivo',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              formatMoney(cashDueCents),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
      _MoneyRow(label: 'Cambio', cents: controller.changeCents),
    ],
  );
}

class _SingleNonCashPaymentSummary extends StatelessWidget {
  const _SingleNonCashPaymentSummary({
    required this.icon,
    required this.label,
    required this.totalCents,
    required this.message,
  });

  final IconData icon;
  final String label;
  final int totalCents;
  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label por ${formatMoney(totalCents)}',
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label · ${formatMoney(totalCents)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(message, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MixedPaymentEditor extends StatelessWidget {
  const _MixedPaymentEditor({required this.controller});

  final PosController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _PaymentAmountField(
        fieldKey: 'pos-mixed-cash',
        label: 'Efectivo',
        icon: Icons.payments_outlined,
        valueCents: controller.mixedCashCents,
        revision: controller.paymentInputRevision,
        enabled: !controller.isSubmitting,
        onChanged: (value) =>
            controller.setMixedPaymentCents(PaymentMethod.cash, value),
        onFillRemaining: () =>
            controller.fillMixedRemaining(PaymentMethod.cash),
      ),
      const SizedBox(height: AppSpacing.xs),
      _PaymentAmountField(
        fieldKey: 'pos-mixed-card',
        label: 'Tarjeta',
        icon: Icons.credit_card_outlined,
        valueCents: controller.mixedCardCents,
        revision: controller.paymentInputRevision,
        enabled: !controller.isSubmitting,
        onChanged: (value) =>
            controller.setMixedPaymentCents(PaymentMethod.card, value),
        onFillRemaining: () =>
            controller.fillMixedRemaining(PaymentMethod.card),
      ),
      const SizedBox(height: AppSpacing.xs),
      _PaymentAmountField(
        fieldKey: 'pos-mixed-transfer',
        label: 'Transferencia',
        icon: Icons.account_balance_outlined,
        valueCents: controller.mixedTransferCents,
        revision: controller.paymentInputRevision,
        enabled: !controller.isSubmitting,
        onChanged: (value) =>
            controller.setMixedPaymentCents(PaymentMethod.transfer, value),
        onFillRemaining: () =>
            controller.fillMixedRemaining(PaymentMethod.transfer),
      ),
      const SizedBox(height: AppSpacing.xs),
      _MoneyRow(label: 'Asignado', cents: controller.allocatedPaymentCents),
      if (controller.paymentDifferenceCents >= 0)
        _MoneyRow(label: 'Restante', cents: controller.paymentDifferenceCents)
      else
        _MoneyRow(label: 'Excede', cents: -controller.paymentDifferenceCents),
      if (controller.mixedCashCents > 0) ...[
        const SizedBox(height: AppSpacing.xs),
        _CashTenderEditor(
          controller: controller,
          cashDueCents: controller.mixedCashCents,
        ),
      ],
    ],
  );
}

class _PaymentAmountField extends StatelessWidget {
  const _PaymentAmountField({
    required this.fieldKey,
    required this.label,
    required this.icon,
    required this.valueCents,
    required this.revision,
    required this.enabled,
    required this.onChanged,
    required this.onFillRemaining,
  });

  final String fieldKey;
  final String label;
  final IconData icon;
  final int valueCents;
  final int revision;
  final bool enabled;
  final ValueChanged<int> onChanged;
  final VoidCallback onFillRemaining;

  @override
  Widget build(BuildContext context) => TextFormField(
    key: ValueKey('$fieldKey-$revision'),
    initialValue: valueCents == 0 ? '' : _centsInput(valueCents),
    enabled: enabled,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    textInputAction: TextInputAction.next,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      prefixText: r'$ ',
      suffixIcon: IconButton(
        tooltip: 'Completar restante con $label',
        onPressed: enabled ? onFillRemaining : null,
        icon: const Icon(Icons.auto_fix_high_outlined),
      ),
    ),
    onChanged: (value) {
      try {
        onChanged(parseMoneyToCents(value));
      } on Object {
        onChanged(0);
      }
    },
  );
}

String _checkoutButtonLabel(PosController controller) {
  final total = formatMoney(controller.totals.totalCents);
  return switch (controller.paymentMode) {
    PosPaymentMode.cash => 'Cobrar $total',
    PosPaymentMode.card => 'Cobrar con tarjeta $total',
    PosPaymentMode.transfer => 'Registrar transferencia $total',
    PosPaymentMode.mixed => 'Cobrar pago mixto $total',
  };
}

String _paymentModeLabel(PosPaymentMode mode) => switch (mode) {
  PosPaymentMode.cash => 'Efectivo',
  PosPaymentMode.card => 'Tarjeta',
  PosPaymentMode.transfer => 'Transferencia',
  PosPaymentMode.mixed => 'Mixto',
};

String _paymentMethodLabel(PaymentMethod method) => switch (method) {
  PaymentMethod.cash => 'Efectivo',
  PaymentMethod.card => 'Tarjeta',
  PaymentMethod.transfer => 'Transferencia',
};

String _centsInput(int cents) {
  final negative = cents < 0;
  final absolute = cents.abs();
  final whole = absolute ~/ 100;
  final fraction = (absolute % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}$whole.$fraction';
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
      children: [
        Expanded(
          child: Text(
            label,
            style: emphasized ? Theme.of(context).textTheme.titleLarge : null,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            formatMoney(cents),
            textAlign: TextAlign.end,
            style: emphasized
                ? Theme.of(context).textTheme.headlineSmall
                : null,
          ),
        ),
      ],
    ),
  );
}
