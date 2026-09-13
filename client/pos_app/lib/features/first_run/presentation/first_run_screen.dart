import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/design/app_breakpoints.dart';
import 'package:pos_app/core/design/app_spacing.dart';
import 'package:pos_app/core/design/components/app_components.dart';
import 'package:pos_app/features/first_run/data/enrollment_repository.dart';
import 'package:pos_app/features/first_run/data/first_run_service.dart';

class FirstRunScreen extends StatefulWidget {
  const FirstRunScreen({super.key});
  @override
  State<FirstRunScreen> createState() => _FirstRunScreenState();
}

class _FirstRunScreenState extends State<FirstRunScreen> {
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _redirect();
  }

  Future<void> _redirect() async {
    if (await FirstRunService(appDatabase).configured() && mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= AppBreakpoints.expanded;
          final welcome = _WelcomePanel(
            busy: _busy,
            onCreate: _newBusiness,
            onConnect: _enroll,
          );
          const guide = _GettingStartedPanel();
          return SingleChildScrollView(
            padding: EdgeInsets.all(wide ? AppSpacing.xxl : AppSpacing.md),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1240),
                child: wide
                    ? IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(flex: 5, child: welcome),
                            const SizedBox(width: AppSpacing.lg),
                            const Expanded(flex: 6, child: guide),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          welcome,
                          const SizedBox(height: AppSpacing.md),
                          guide,
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    ),
  );

  Future<void> _newBusiness() async {
    final values = await _form(context, [
      'Nombre del negocio',
      'Nombre administrador',
      'Usuario',
      'Contraseña',
      'Nombre dispositivo',
    ], secretIndex: 3);
    if (values == null) return;
    setState(() => _busy = true);
    try {
      await FirstRunService(appDatabase).createBusiness(
        businessName: values[0],
        adminName: values[1],
        username: values[2],
        password: values[3],
        deviceName: values[4],
      );
      if (mounted) context.go('/login');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enroll() async {
    final values = await _form(context, [
      'Código de invitación',
      'Usuario administrador',
      'Contraseña',
      'Nombre dispositivo',
    ], secretIndex: 2);
    if (values == null) return;
    setState(() => _busy = true);
    try {
      await EnrollmentRepository(appDatabase, cloudApiClient).redeem(
        code: values[0],
        username: values[1],
        password: values[2],
        deviceName: values[3],
      );
      if (mounted) {
        context.go('/cloud-admin');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No fue posible conectar el dispositivo. Verifica invitación y credenciales.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<List<String>?> _form(
    BuildContext context,
    List<String> labels, {
    required int secretIndex,
  }) async {
    final formKey = GlobalKey<FormState>();
    final controllers = List.generate(
      labels.length,
      (_) => TextEditingController(),
    );
    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: labels.length == 5
            ? 'Configurar nuevo negocio'
            : 'Conectar dispositivo',
        content: SizedBox(
          width: 440,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < labels.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: AppTextField(
                        label: labels[i],
                        controller: controllers[i],
                        obscureText: i == secretIndex,
                        required: true,
                        validator: (value) => (value?.trim().isEmpty ?? true)
                            ? 'Este campo es obligatorio.'
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          AppPrimaryButton(
            label: 'Continuar',
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(
                  dialogContext,
                  controllers.map((e) => e.text.trim()).toList(),
                );
              }
            },
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final controller in controllers) {
      controller.dispose();
    }
    return result;
  }
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel({
    required this.busy,
    required this.onCreate,
    required this.onConnect,
  });
  final bool busy;
  final VoidCallback onCreate;
  final VoidCallback onConnect;
  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(AppSpacing.xxl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.storefront_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Tu negocio, listo para vender',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Configura este dispositivo y empieza a operar con ventas, compras e inventario, incluso sin conexión.',
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.xl),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: busy ? null : onCreate,
            icon: const Icon(Icons.add_business_outlined),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(busy ? 'Configurando…' : 'Configurar nuevo negocio'),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: busy ? null : onConnect,
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text('Conectar a negocio existente'),
            ),
          ),
        ),
      ],
    ),
  );
}

class _GettingStartedPanel extends StatelessWidget {
  const _GettingStartedPanel();
  static const steps = <(IconData, String, String)>[
    (
      Icons.category_outlined,
      'Crea categorías',
      'Organiza el catálogo para encontrar productos rápido.',
    ),
    (
      Icons.local_shipping_outlined,
      'Registra proveedores',
      'Identifica de quién compras cada mercancía.',
    ),
    (
      Icons.inventory_2_outlined,
      'Crea productos',
      'Define código, nombre, precio de venta y stock mínimo.',
    ),
    (
      Icons.shopping_cart_checkout_outlined,
      'Agrega existencias',
      'Registra una compra o entrada para aumentar el stock.',
    ),
    (
      Icons.account_balance_wallet_outlined,
      'Abre la caja',
      'Prepara el turno y el efectivo inicial.',
    ),
    (
      Icons.point_of_sale_outlined,
      'Comienza a vender',
      'FIFO controlará las salidas automáticamente.',
    ),
  ];
  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(AppSpacing.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Primeros pasos',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Sigue esta ruta para dejar el negocio listo.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        for (var index = 0; index < steps.length; index++)
          Padding(
            padding: EdgeInsets.only(
              bottom: index == steps.length - 1 ? 0 : AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Icon(steps[index].$1, size: 22),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        steps[index].$2,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(steps[index].$3),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
