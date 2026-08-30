import 'package:flutter/material.dart';
import 'package:pos_app/core/design/app_colors.dart';
import 'package:pos_app/core/design/app_sizes.dart';
import 'package:pos_app/core/design/app_spacing.dart';
import 'package:pos_app/shared/presentation/app_navigation_drawer.dart';

class AppPage extends StatelessWidget {
  const AppPage({
    required this.title,
    required this.body,
    this.subtitle,
    this.actions = const [],
    this.primaryAction,
    this.showNavigation = true,
    this.scrollable = true,
    super.key,
  });
  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;
  final Widget? primaryAction;
  final bool showNavigation;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final horizontal = MediaQuery.sizeOf(context).width >= 900
        ? AppSpacing.xxl
        : AppSpacing.md;
    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            AppSpacing.lg,
            horizontal,
            AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            subtitle!,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  ?primaryAction,
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              if (scrollable)
                Expanded(child: SingleChildScrollView(child: body))
              else
                Expanded(child: body),
            ],
          ),
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('POS Flutter'), actions: actions),
      drawer: showNavigation ? const AppNavigationDrawer() : null,
      body: SafeArea(child: content),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    super.key,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding, child: child),
  );
}

class AppKpiCard extends StatelessWidget {
  const AppKpiCard({
    required this.label,
    required this.value,
    required this.icon,
    super.key,
  });
  final String label;
  final String value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: AppSpacing.sm),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.xxs),
        Text(value, style: Theme.of(context).textTheme.titleLarge),
      ],
    ),
  );
}

class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => icon == null
      ? FilledButton(onPressed: onPressed, child: Text(label))
      : FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        );
}

class AppSecondaryButton extends StatelessWidget {
  const AppSecondaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => icon == null
      ? OutlinedButton(onPressed: onPressed, child: Text(label))
      : OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        );
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    required this.label,
    this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.helperText,
    this.required = false,
    super.key,
  });
  final String label;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? helperText;
  final bool required;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    obscureText: obscureText,
    keyboardType: keyboardType,
    decoration: InputDecoration(
      labelText: required ? '$label *' : label,
      helperText: helperText,
    ),
  );
}

enum AppStatus { active, inactive, pending, synced, warning, error }

class AppStatusChip extends StatelessWidget {
  const AppStatusChip({required this.label, required this.status, super.key});
  final String label;
  final AppStatus status;
  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      AppStatus.active ||
      AppStatus.synced => (AppColors.success, Icons.check_circle_outline),
      AppStatus.pending => (AppColors.warning, Icons.schedule),
      AppStatus.warning => (AppColors.warning, Icons.warning_amber_rounded),
      AppStatus.error => (AppColors.error, Icons.error_outline),
      AppStatus.inactive => (
        Theme.of(context).colorScheme.outline,
        Icons.remove_circle_outline,
      ),
    };
    return Chip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(label),
      side: BorderSide(color: color.withValues(alpha: .35)),
      backgroundColor: color.withValues(alpha: .08),
    );
  }
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.message,
    this.action,
    this.icon = Icons.inbox_outlined,
    super.key,
  });
  final String message;
  final Widget? action;
  final IconData icon;
  @override
  Widget build(BuildContext context) =>
      _AppState(icon: icon, message: message, action: action);
}

class AppErrorState extends StatelessWidget {
  const AppErrorState({
    this.message = 'No se pudieron cargar los datos.',
    this.onRetry,
    super.key,
  });
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => _AppState(
    icon: Icons.error_outline,
    message: message,
    color: AppColors.error,
    action: onRetry == null
        ? null
        : AppSecondaryButton(label: 'Reintentar', onPressed: onRetry),
  );
}

class AppLoadingState extends StatelessWidget {
  const AppLoadingState({this.label = 'Cargando…', super.key});
  final String label;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.md),
          Text(label),
        ],
      ),
    ),
  );
}

class _AppState extends StatelessWidget {
  const _AppState({
    required this.icon,
    required this.message,
    this.action,
    this.color,
  });
  final IconData icon;
  final String message;
  final Widget? action;
  final Color? color;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 48,
            color: color ?? Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.lg),
            action!,
          ],
        ],
      ),
    ),
  );
}

class AppSection extends StatelessWidget {
  const AppSection({required this.title, required this.child, super.key});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: AppSpacing.sm),
      child,
    ],
  );
}

class AppDialog extends StatelessWidget {
  const AppDialog({
    required this.title,
    required this.content,
    required this.actions,
    this.destructive = false,
    super.key,
  });
  final String title;
  final Widget content;
  final List<Widget> actions;
  final bool destructive;
  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: destructive
        ? const Icon(Icons.warning_amber_rounded, color: AppColors.error)
        : null,
    title: Text(title),
    content: content,
    actions: actions,
  );
}
