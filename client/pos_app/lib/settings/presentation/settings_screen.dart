import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/design/app_spacing.dart';
import 'package:pos_app/core/design/components/app_components.dart';
import 'package:pos_app/features/branding/data/business_branding_repository.dart';
import 'package:pos_app/features/branding/presentation/brand_logo.dart';
import 'package:pos_app/features/branding/presentation/branding_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _name = TextEditingController();
  Uint8List? _logo;
  int? _color;
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = ref
        .watch(businessBrandingProvider)
        .whenOrNull(data: (branding) => branding);
    if (!_loaded && value != null) {
      _loaded = true;
      _name.text = value.displayName;
      _logo = value.logoBytes;
      _color = value.primaryColor;
    }
    return AppPage(
      title: 'Configuración del negocio',
      subtitle: 'Personaliza la identidad visible en este dispositivo y los demás equipos.',
      body: value == null
          ? const AppLoadingState(label: 'Cargando configuración…')
          : AppCard(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      key: const Key('branding-name'),
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Nombre comercial',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Logo',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    BrandLogo(
                      branding: BusinessBranding(
                        businessId: value.businessId,
                        businessGlobalId: value.businessGlobalId,
                        displayName: _name.text,
                        logoBytes: _logo,
                      ),
                      size: 88,
                    ),
                    Wrap(
                      spacing: AppSpacing.sm,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _saving ? null : _pickLogo,
                          icon: const Icon(Icons.image_outlined),
                          label: const Text('Seleccionar logo'),
                        ),
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => setState(() => _logo = null),
                          child: const Text('Quitar logo'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Color principal',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final color in businessBrandColors)
                          ChoiceChip(
                            key: Key('branding-color-$color'),
                            label: const SizedBox(width: 24, height: 24),
                            avatar: CircleAvatar(
                              backgroundColor: Color(0xFF000000 | color),
                            ),
                            selected: _color == color,
                            onSelected: _saving
                                ? null
                                : (_) => setState(() => _color = color),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Wrap(
                      spacing: AppSpacing.sm,
                      children: [
                        FilledButton(
                          key: const Key('branding-save'),
                          onPressed: _saving ? null : _save,
                          child: Text(_saving ? 'Guardando…' : 'Guardar'),
                        ),
                        OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => setState(() {
                                  _logo = null;
                                  _color = null;
                                  _name.text = value.displayName;
                                }),
                          child: const Text(
                            'Restaurar apariencia predeterminada',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _pickLogo() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null) return;

    final bytes = await image.readAsBytes();

    try {
      BusinessBrandingRepository.validateLogo(bytes);
      if (!mounted) return;
      setState(() => _logo = bytes);
    } on ArgumentError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message.toString())));
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await BusinessBrandingRepository(
        appDatabase,
      ).save(displayName: _name.text, logoBytes: _logo, primaryColor: _color);
      ref.invalidate(businessBrandingProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Configuración guardada. Los cambios se sincronizarán cuando haya conexión.',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $error')));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}
