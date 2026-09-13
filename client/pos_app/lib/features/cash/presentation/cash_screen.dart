import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/design/app_spacing.dart';
import 'package:pos_app/core/design/components/app_components.dart';
import 'package:pos_app/core/utils/money.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/features/cash/data/cash_read_repository.dart';
import 'package:pos_app/features/cash/data/cash_repository.dart';
import 'package:pos_app/shared/presentation/special_authorization_dialog.dart';

class CashScreen extends StatefulWidget {
  const CashScreen({this.database, super.key});

  final AppDatabase? database;
  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  CashSessionSummary? _summary;
  EffectiveCapabilities _caps = const EffectiveCapabilities.denied();
  bool _loading = true, _busy = false;
  Object? _error;

  AppDatabase get _database => widget.database ?? appDatabase;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final summary = await CashReadRepository(_database).currentSummary();
      final caps = await AuthorizationService(_database).load();
      if (mounted) {
        setState(() {
          _summary = summary;
          _caps = caps;
          _loading = false;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _mutate(Future<bool> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (await action()) {
        await _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(success)));
        }
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_friendly(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Caja',
    subtitle:
        'Controla el efectivo y concilia tu turno sin depender de Internet.',
    body: _loading
        ? const AppLoadingState(label: 'Consultando caja…')
        : _error != null
        ? AppErrorState(
            message: 'No se pudo consultar la caja.',
            onRetry: _refresh,
          )
        : _summary == null
        ? _closed()
        : _open(_summary!),
  );

  Widget _closed() => AppEmptyState(
    icon: Icons.point_of_sale_outlined,
    message: 'No hay una caja abierta en este dispositivo.',
    action: _caps.can(Capability.cashOpen)
        ? AppPrimaryButton(
            label: 'Abrir caja',
            icon: Icons.lock_open_outlined,
            onPressed: _busy ? null : _openDialog,
          )
        : const Text('No tienes permiso para abrir una caja.'),
  );

  Widget _open(CashSessionSummary s) {
    final cards = <(String, String, IconData)>[
      (
        'Efectivo esperado',
        formatMoney(s.expectedCashCents),
        Icons.account_balance_wallet_outlined,
      ),
      (
        'Saldo inicial',
        formatMoney(s.openingBalanceCents),
        Icons.flag_outlined,
      ),
      (
        'Ventas en efectivo',
        formatMoney(s.cashSalesCents),
        Icons.payments_outlined,
      ),
      (
        'Gastos en efectivo',
        formatMoney(s.cashExpensesCents),
        Icons.receipt_long_outlined,
      ),
      (
        'Entradas manuales',
        formatMoney(s.manualInCents),
        Icons.add_circle_outline,
      ),
      (
        'Retiros manuales',
        formatMoney(s.manualOutCents),
        Icons.remove_circle_outline,
      ),
      (
        'Ventas con tarjeta',
        formatMoney(s.paymentSummary.cardCents),
        Icons.credit_card,
      ),
      (
        'Transferencias',
        formatMoney(s.paymentSummary.transferCents),
        Icons.account_balance_outlined,
      ),
      ('Número de ventas', '${s.saleCount}', Icons.shopping_bag_outlined),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppStatusChip(
                    label: 'Caja abierta',
                    status: AppStatus.active,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    s.userName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    'Abierta ${DateFormat('dd/MM/yyyy HH:mm').format(s.openedAt.toLocal())}',
                  ),
                ],
              ),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (_caps.can(Capability.cashDeposit))
                    AppSecondaryButton(
                      label: 'Entrada de efectivo',
                      icon: Icons.add,
                      onPressed: _busy
                          ? null
                          : () => _movementDialog(
                              ManualCashMovementType.deposit,
                              s,
                            ),
                    ),
                  if (_caps.can(Capability.cashWithdrawal))
                    AppSecondaryButton(
                      label: 'Retiro de efectivo',
                      icon: Icons.remove,
                      onPressed: _busy
                          ? null
                          : () => _movementDialog(
                              ManualCashMovementType.withdrawal,
                              s,
                            ),
                    ),
                  if (_caps.can(Capability.cashClose))
                    AppPrimaryButton(
                      label: 'Cerrar y conciliar',
                      icon: Icons.lock_outline,
                      onPressed: _busy ? null : () => _closeDialog(s),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (_, constraints) {
            final width = constraints.maxWidth >= 900
                ? (constraints.maxWidth - 32) / 3
                : constraints.maxWidth >= 560
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final c in cards)
                  SizedBox(
                    width: width,
                    height: 132,
                    child: AppKpiCard(label: c.$1, value: c.$2, icon: c.$3),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.xl),
        AppSection(
          title: 'Movimientos recientes',
          child: s.movements.isEmpty
              ? const AppEmptyState(
                  message: 'Aún no hay movimientos en este turno.',
                )
              : AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [for (final m in s.movements) _MovementTile(m)],
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _openDialog() async {
    final value = await showDialog<int>(
      context: context,
      builder: (_) => const _MoneyDialog(
        title: 'Abrir caja',
        label: 'Saldo inicial',
        action: 'Abrir caja',
        allowZero: true,
      ),
    );
    if (value != null) {
      await _mutate(() async {
        await CashRepository(_database).open(value);
        return true;
      }, 'Caja abierta correctamente.');
    }
  }

  Future<void> _movementDialog(
    ManualCashMovementType type,
    CashSessionSummary s,
  ) async {
    final input = await showDialog<_MovementInput>(
      context: context,
      builder: (_) =>
          _MovementDialog(type: type, available: s.expectedCashCents),
    );
    if (input == null || !mounted) return;
    final cap = type == ManualCashMovementType.deposit
        ? Capability.cashDeposit
        : Capability.cashWithdrawal;
    await _mutate(
      () => runWithSpecialAuthorization(
        context: context,
        capability: cap,
        operationLabel: type == ManualCashMovementType.deposit
            ? 'Registrar entrada de efectivo'
            : 'Registrar retiro de efectivo',
        reason: input.reason,
        operation: (grant) async => CashRepository(_database).addManualMovement(
          type: type,
          amountCents: input.cents,
          reason: input.reason,
          authorizationGrant: grant,
        ),
      ),
      type == ManualCashMovementType.deposit
          ? 'Entrada registrada.'
          : 'Retiro registrado.',
    );
  }

  Future<void> _closeDialog(CashSessionSummary s) async {
    final counted = await showDialog<int>(
      context: context,
      builder: (_) => _CloseDialog(expected: s.expectedCashCents),
    );
    if (counted == null || !mounted) return;
    await _mutate(() async {
      if (counted == s.expectedCashCents) {
        await CashRepository(_database).close(counted);
        return true;
      }
      return runWithSpecialAuthorization(
        context: context,
        capability: Capability.cashCloseWithDifference,
        operationLabel: 'Cerrar caja con diferencia',
        reason:
            'Arqueo con diferencia de ${formatMoney(counted - s.expectedCashCents)}',
        operation: (grant) =>
            CashRepository(_database).close(counted, authorizationGrant: grant),
      );
    }, 'Caja cerrada y conciliada.');
  }
}

class _MoneyDialog extends StatefulWidget {
  const _MoneyDialog({
    required this.title,
    required this.label,
    required this.action,
    this.allowZero = false,
  });
  final String title, label, action;
  final bool allowZero;
  @override
  State<_MoneyDialog> createState() => _MoneyDialogState();
}

class _MoneyDialogState extends State<_MoneyDialog> {
  final form = GlobalKey<FormState>(), controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: form,
        child: AppTextField(
          label: widget.label,
          controller: controller,
          required: true,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (v) => _moneyError(v, allowZero: widget.allowZero),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, parseMoneyToCents(controller.text));
          }
        },
        child: Text(widget.action),
      ),
    ],
  );
}

class _MovementInput {
  const _MovementInput(this.cents, this.reason);
  final int cents;
  final String reason;
}

class _MovementDialog extends StatefulWidget {
  const _MovementDialog({required this.type, required this.available});
  final ManualCashMovementType type;
  final int available;
  @override
  State<_MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends State<_MovementDialog> {
  final form = GlobalKey<FormState>(),
      amount = TextEditingController(),
      reason = TextEditingController();
  @override
  void dispose() {
    amount.dispose();
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final withdrawal = widget.type == ManualCashMovementType.withdrawal;
    return AlertDialog(
      title: Text(withdrawal ? 'Retiro de efectivo' : 'Entrada de efectivo'),
      content: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (withdrawal)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Text('Disponible: ${formatMoney(widget.available)}'),
                ),
              AppTextField(
                label: 'Monto',
                controller: amount,
                required: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) {
                  final error = _moneyError(v);
                  if (error != null) return error;
                  if (withdrawal && parseMoneyToCents(v!) > widget.available) {
                    return 'El retiro supera el efectivo disponible.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Motivo',
                controller: reason,
                required: true,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Escribe el motivo.' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(
                context,
                _MovementInput(
                  parseMoneyToCents(amount.text),
                  reason.text.trim(),
                ),
              );
            }
          },
          child: Text(withdrawal ? 'Registrar retiro' : 'Registrar entrada'),
        ),
      ],
    );
  }
}

class _CloseDialog extends StatefulWidget {
  const _CloseDialog({required this.expected});
  final int expected;
  @override
  State<_CloseDialog> createState() => _CloseDialogState();
}

class _CloseDialogState extends State<_CloseDialog> {
  final form = GlobalKey<FormState>(), counted = TextEditingController();
  int? cents;
  @override
  void dispose() {
    counted.dispose();
    super.dispose();
  }

  void preview() {
    if (form.currentState!.validate()) {
      setState(() => cents = parseMoneyToCents(counted.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final difference = cents == null ? null : cents! - widget.expected;
    final status = difference == null
        ? 'Ingresa el efectivo contado'
        : difference == 0
        ? 'Caja cuadrada'
        : difference > 0
        ? 'Sobrante: ${formatMoney(difference)}'
        : 'Faltante: ${formatMoney(-difference)}';
    return AlertDialog(
      title: const Text('Cerrar y conciliar caja'),
      content: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Efectivo esperado',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Text(
                formatMoney(widget.expected),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                label: 'Efectivo contado',
                controller: counted,
                required: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) => _moneyError(v, allowZero: true),
                onFieldSubmitted: (_) => preview(),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                status,
                key: const Key('cash-difference-preview'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        OutlinedButton(
          onPressed: preview,
          child: const Text('Calcular diferencia'),
        ),
        FilledButton(
          onPressed: () {
            preview();
            if (form.currentState!.validate()) Navigator.pop(context, cents);
          },
          child: const Text('Confirmar cierre'),
        ),
      ],
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile(this.movement);
  final CashMovementSummary movement;
  @override
  Widget build(BuildContext context) {
    final out = movement.amountCents < 0;
    return ListTile(
      leading: Icon(
        out ? Icons.arrow_circle_down_outlined : Icons.arrow_circle_up_outlined,
      ),
      title: Text(_movementLabel(movement.type)),
      subtitle: Text(
        '${DateFormat('dd/MM HH:mm').format(movement.movementDate.toLocal())}${movement.notes == null || movement.notes!.isEmpty ? '' : ' · ${movement.notes}'}',
      ),
      trailing: Text(
        '${out ? '−' : '+'}${formatMoney(movement.amountCents.abs())}',
        style: TextStyle(
          color: out
              ? Theme.of(context).colorScheme.error
              : Colors.green.shade700,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

String _movementLabel(String type) => switch (type) {
  'Sale' => 'Venta',
  'Expense' => 'Gasto',
  'Cancellation' => 'Cancelación',
  'ManualIn' => 'Entrada de efectivo',
  'ManualOut' => 'Retiro de efectivo',
  _ => 'Movimiento de caja',
};
String? _moneyError(String? value, {bool allowZero = false}) {
  try {
    final cents = parseMoneyToCents(value ?? '');
    if (cents < 0 || (!allowZero && cents == 0)) {
      return allowZero
          ? 'El monto no puede ser negativo.'
          : 'El monto debe ser mayor que cero.';
    }
  } on FormatException catch (error) {
    return error.message;
  }
  return null;
}

String _friendly(Object error) {
  if (error is AuthorizationDeniedException) {
    return 'No tienes permiso para realizar esta operación.';
  }
  if (error is StateError) return error.message;
  if (error is ArgumentError) {
    return error.message?.toString() ?? 'Datos inválidos.';
  }
  return 'No se pudo completar la operación. Inténtalo nuevamente.';
}
