import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/features/branding/data/business_branding_repository.dart';

final businessBrandingProvider = FutureProvider<BusinessBranding>(
  (ref) => BusinessBrandingRepository(appDatabase).read(),
);

BusinessBranding resolvedBranding(AsyncValue<BusinessBranding> value) =>
    value.when(
      data: (branding) => branding,
      error: (_, _) => const BusinessBranding.fallback(),
      loading: () => const BusinessBranding.fallback(),
    );
