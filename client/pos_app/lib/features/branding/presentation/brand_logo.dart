import 'package:flutter/material.dart';
import 'package:pos_app/features/branding/data/business_branding_repository.dart';

class BrandLogo extends StatelessWidget {
  const BrandLogo({required this.branding, this.size = 56, super.key});
  final BusinessBranding branding;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bytes = branding.logoBytes;
    if (bytes == null || bytes.isEmpty) return _fallback(context);
    return SizedBox.square(
      dimension: size,
      child: Image.memory(
        bytes,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _fallback(context),
      ),
    );
  }

  Widget _fallback(BuildContext context) => Icon(
    Icons.storefront,
    size: size * .75,
    color: Theme.of(context).colorScheme.primary,
  );
}
