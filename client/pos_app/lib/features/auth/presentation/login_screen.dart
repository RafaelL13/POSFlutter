import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_app/app/route_access_service.dart';
import 'package:pos_app/app/route_authorization.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/authorization/authorization_providers.dart';
import 'package:pos_app/core/context/local_app_context.dart';
import 'package:pos_app/core/design/app_sizes.dart';
import 'package:pos_app/core/design/app_spacing.dart';
import 'package:pos_app/core/design/components/app_components.dart';
import 'package:pos_app/features/auth/data/auth_repository.dart';
import 'package:pos_app/features/auth/data/cloud_auth_service.dart';
import 'package:pos_app/features/auth/data/cloud_bootstrap_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _u = TextEditingController(), _p = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _u.dispose();
    _p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.formMaxWidth),
          child: AppCard(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.storefront,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Bienvenido',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Ingresa para continuar en POS Flutter',
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AppTextField(
                    label: 'Usuario',
                    controller: _u,
                    required: true,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'Contraseña',
                    controller: _p,
                    obscureText: true,
                    required: true,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  SizedBox(
                    width: double.infinity,
                    child: AppPrimaryButton(
                      label: _busy ? 'Ingresando…' : 'Iniciar sesión',
                      onPressed: _busy ? null : _login,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.offline_bolt_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          'La operación local continúa disponible sin conexión.',
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  Future<void> _login() async {
    setState(() => _busy = true);
    try {
      LocalAppContext? current;
      try {
        current = await LocalAppContext.load(appDatabase);
      } catch (_) {}
      if (current?.isAdminReadOnly == true) {
        final ok = await CloudAuthService(
          appDatabase,
          cloudApiClient,
        ).login(_u.text, _p.text);
        if (!ok) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Se requiere conexión y credenciales administrativas válidas.',
                ),
              ),
            );
          }
          return;
        }
        if (!mounted) {
          return;
        }
        ref.invalidate(effectiveCapabilitiesProvider);
        final access = await RouteAccessService(appDatabase).load();
        if (mounted) {
          context.go(RouteAuthorization.authorizedHome(access.capabilities));
        }
        return;
      }
      final session = await AuthRepository(appDatabase).login(_u.text, _p.text);
      if (session == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Credenciales incorrectas.')),
          );
        }
        return;
      }
      await CloudBootstrapService(appDatabase, cloudApiClient).tryBootstrap();
      await CloudAuthService(
        appDatabase,
        cloudApiClient,
      ).tryLogin(_u.text, _p.text);
      if (!mounted) {
        return;
      }
      ref.invalidate(effectiveCapabilitiesProvider);
      final access = await RouteAccessService(appDatabase).load();
      if (mounted) {
        context.go(RouteAuthorization.authorizedHome(access.capabilities));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}
