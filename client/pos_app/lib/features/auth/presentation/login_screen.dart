import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_app/app/route_access_service.dart';
import 'package:pos_app/app/route_authorization.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/authorization/authorization_providers.dart';
import 'package:pos_app/core/context/local_app_context.dart';
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
    body: Center(
      child: SizedBox(
        width: 420,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'INICIAR SESIÓN',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _u,
                  decoration: const InputDecoration(
                    labelText: 'Usuario',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _p,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _login,
                  child: const Text('ENTRAR'),
                ),
              ],
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
