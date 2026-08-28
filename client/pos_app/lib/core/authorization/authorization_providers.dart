import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';

final authorizationServiceProvider = Provider<AuthorizationService>(
  (ref) => AuthorizationService(appDatabase),
);

final effectiveCapabilitiesProvider =
    FutureProvider.autoDispose<EffectiveCapabilities>(
      (ref) => ref.watch(authorizationServiceProvider).load(),
    );
