import 'package:flutter/material.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/authorization/special_authorization.dart';

Future<bool> runWithSpecialAuthorization({
  required BuildContext context,
  required Capability capability,
  required String operationLabel,
  required String reason,
  required Future<void> Function(SpecialAuthorizationGrant? grant) operation,
}) async {
  try {
    await operation(null);
    return true;
  } on AdditionalAuthorizationRequiredException {
    if (!context.mounted) return false;
    final grant = await showSpecialAuthorizationDialog(
      context: context,
      capability: capability,
      operationLabel: operationLabel,
      initialReason: reason,
    );
    if (grant == null) return false;
    await operation(grant);
    return true;
  }
}

Future<SpecialAuthorizationGrant?> showSpecialAuthorizationDialog({
  required BuildContext context,
  required Capability capability,
  required String operationLabel,
  String initialReason = '',
}) async {
  final username = TextEditingController();
  final password = TextEditingController();
  final reason = TextEditingController(text: initialReason);
  try {
    return await showDialog<SpecialAuthorizationGrant>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _SpecialAuthorizationDialog(
        capability: capability,
        operationLabel: operationLabel,
        username: username,
        password: password,
        reason: reason,
      ),
    );
  } finally {
    username.dispose();
    password.dispose();
    reason.dispose();
  }
}

class _SpecialAuthorizationDialog extends StatefulWidget {
  const _SpecialAuthorizationDialog({
    required this.capability,
    required this.operationLabel,
    required this.username,
    required this.password,
    required this.reason,
  });

  final Capability capability;
  final String operationLabel;
  final TextEditingController username;
  final TextEditingController password;
  final TextEditingController reason;

  @override
  State<_SpecialAuthorizationDialog> createState() =>
      _SpecialAuthorizationDialogState();
}

class _SpecialAuthorizationDialogState
    extends State<_SpecialAuthorizationDialog> {
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) => _AuthorizationDialogBody(
    operationLabel: widget.operationLabel,
    username: widget.username,
    password: widget.password,
    reason: widget.reason,
    busy: _busy,
    error: _error,
    onCancel: () => Navigator.pop(context),
    onAuthorize: _authorize,
  );

  Future<void> _authorize() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = SpecialAuthorizationService(appDatabase);
      final requirement = SpecialAuthorizationService.requirementFor(
        widget.capability,
      );
      final grant =
          requirement == SpecialAuthorizationRequirement.reauthentication
          ? await service.reauthenticate(
              capability: widget.capability,
              username: widget.username.text,
              password: widget.password.text,
              reason: widget.reason.text,
            )
          : await service.authorizeSecondUser(
              capability: widget.capability,
              username: widget.username.text,
              password: widget.password.text,
              reason: widget.reason.text,
            );
      if (mounted) Navigator.pop(context, grant);
    } on SpecialAuthorizationException catch (exception) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _messageFor(exception.failure);
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'No fue posible registrar la autorización.';
        });
      }
    }
  }
}

String _messageFor(SpecialAuthorizationFailure failure) => switch (failure) {
  SpecialAuthorizationFailure.invalidCredentials =>
    'Las credenciales no son válidas.',
  SpecialAuthorizationFailure.authorizerNotAllowed =>
    'El usuario indicado no tiene permiso para autorizar esta operación.',
  SpecialAuthorizationFailure.selfAuthorization =>
    'No puedes autorizar tu propia operación.',
  _ => 'No fue posible registrar la autorización.',
};

class _AuthorizationDialogBody extends StatelessWidget {
  const _AuthorizationDialogBody({
    required this.operationLabel,
    required this.username,
    required this.password,
    required this.reason,
    required this.busy,
    required this.error,
    required this.onCancel,
    required this.onAuthorize,
  });

  final String operationLabel;
  final TextEditingController username;
  final TextEditingController password;
  final TextEditingController reason;
  final bool busy;
  final String? error;
  final VoidCallback onCancel;
  final VoidCallback onAuthorize;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Autorización requerida'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(operationLabel),
          const SizedBox(height: 8),
          const Text('Esta operación requiere autorización de un responsable.'),
          const SizedBox(height: 16),
          TextField(
            controller: username,
            enabled: !busy,
            decoration: const InputDecoration(
              labelText: 'Usuario autorizador',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: password,
            enabled: !busy,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Contraseña',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: reason,
            enabled: !busy,
            decoration: const InputDecoration(
              labelText: 'Motivo',
              border: OutlineInputBorder(),
            ),
          ),
          if (error case final message?) ...[
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : onCancel,
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: busy ? null : onAuthorize,
        child: const Text('Autorizar'),
      ),
    ],
  );
}
