import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_app/app/router.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/design/app_theme.dart';
import 'package:pos_app/features/branding/presentation/branding_providers.dart';

class PosApp extends ConsumerStatefulWidget {
  const PosApp({super.key});

  @override
  ConsumerState<PosApp> createState() => _PosAppState();
}

class _PosAppState extends ConsumerState<PosApp> with WidgetsBindingObserver {
  static const _periodicSyncInterval = Duration(minutes: 1);

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _periodicSyncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        _synchronizeBestEffort();
      }
    });

    _periodicSyncTimer = Timer.periodic(
      _periodicSyncInterval,
      (_) => _synchronizeBestEffort(),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _synchronizeBestEffort();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _synchronizeBestEffort();
    }
  }

  void _synchronizeBestEffort() {
    unawaited(
      syncService.synchronize().onError((Object error, StackTrace stackTrace) {
        // Automatic synchronization must never interrupt local POS operation.
      }),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _periodicSyncTimer?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
