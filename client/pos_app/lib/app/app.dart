import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_app/app/router.dart';
import 'package:pos_app/core/design/app_theme.dart';
import 'package:pos_app/features/branding/presentation/branding_providers.dart';

class PosApp extends ConsumerWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = resolvedBranding(ref.watch(businessBrandingProvider));
    final color = branding.primaryColor == null
        ? null
        : Color(0xFF000000 | branding.primaryColor!);
    return MaterialApp.router(
      title: branding.displayName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightFromSeed(color),
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
