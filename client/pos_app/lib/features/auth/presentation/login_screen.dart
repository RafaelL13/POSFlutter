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
import 'package:pos_app/features/auth/data/background_cloud_login_coordinator.dart';
import 'package:pos_app/features/auth/data/cloud_auth_service.dart';
import 'package:pos_app/features/branding/presentation/brand_logo.dart';
import 'package:pos_app/features/branding/presentation/branding_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({
    this.localLogin,
    this.startBackgroundCloudLogin,
    this.loadAuthorizedHome,
    this.navigateTo,
    super.key,
  });

  final Future<LocalAuthSession?> Function(String, String)? localLogin;
  final void Function(String, String, String)? startBackgroundCloudLogin;
  final Future<String> Function()? loadAuthorizedHome;
  final void Function(BuildContext, String)? navigateTo;
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
  Widget build(BuildContext context) {
    final branding = resolvedBranding(ref.watch(businessBrandingProvider));
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
            const pagePadding = AppSpacing.md;
            final availableHeight =
                constraints.maxHeight - keyboardHeight - (pagePadding * 2);
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                pagePadding,
                pagePadding,
                pagePadding,
                pagePadding + keyboardHeight,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: availableHeight > 0 ? availableHeight : 0,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppSizes.formMaxWidth,
                    ),
                    child: AppCard(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            BrandLogo(branding: branding, size: 64),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              branding.displayName,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Sistema de punto de venta',
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
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Flexible(
                                  child: Text(
                                    'La operación local continúa disponible sin conexión.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                            if (branding.branchName != null ||
                                branding.deviceName != null) ...[
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                [
                                  branding.branchName,
                                  branding.deviceName,
                                ].whereType<String>().join(' · '),
                                style: Theme.of(context).textTheme.bodySmall,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

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
      final session =
          await (widget.localLogin ?? AuthRepository(appDatabase).login)(
            _u.text,
            _p.text,
          );
      if (session == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Credenciales incorrectas.')),
          );
        }
        return;
      }
      final startCloud =
          widget.startBackgroundCloudLogin ??
          (String username, String password, String userGlobalId) {
            BackgroundCloudLoginCoordinator(appDatabase, cloudApiClient).start(
              username: username,
              password: password,
              userGlobalId: userGlobalId,
            );
          };
      startCloud(_u.text, _p.text, session.userGlobalId);
      if (!mounted) {
        return;
      }
      ref.invalidate(effectiveCapabilitiesProvider);
      final destination =
          await widget.loadAuthorizedHome?.call() ??
          RouteAuthorization.authorizedHome(
            (await RouteAccessService(appDatabase).load()).capabilities,
          );
      if (mounted) {
        final navigate = widget.navigateTo;
        if (navigate == null) {
          context.go(destination);
        } else {
          navigate(context, destination);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}
