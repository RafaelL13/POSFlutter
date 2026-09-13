import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_app/core/app_services.dart';
import 'package:pos_app/core/authorization/app_role.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/design/app_spacing.dart';
import 'package:pos_app/core/design/components/app_components.dart';
import 'package:pos_app/features/users/data/user_repository.dart';

const userRoleLabels = <AppRole, String>{
  AppRole.administrator: 'Administrador',
  AppRole.manager: 'Gerente',
  AppRole.supervisor: 'Supervisor',
  AppRole.seller: 'Vendedor',
};
const userRoleDescriptions = <AppRole, String>{
  AppRole.administrator: 'Acceso completo a administración, usuarios, compras, inventario, caja, ventas y reportes según capabilities.',
  AppRole.manager:
      'Gestión operativa amplia, inventario, compras, caja, ventas y reportes.',
  AppRole.supervisor: 'Supervisión de operación, ventas, caja e inventario con permisos controlados.',
  AppRole.seller: 'POS, ventas propias y funciones operativas autorizadas.',
};

class UsersScreen extends StatefulWidget {
  const UsersScreen({this.loader, super.key});
  final Future<(List<UserSummary>, bool)> Function()? loader;
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late Future<(List<UserSummary>, bool)> _future = _load();
  bool _submitting = false;
  bool _dialogOpen = false;
  Future<(List<UserSummary>, bool)> _load() async {
    if (widget.loader case final loader?) return loader();
    final repository = UserRepository(appDatabase);
    final (users, authorization) = await (
      repository.list(),
      AuthorizationService(appDatabase).load(),
    ).wait;
    return (users, authorization.can(Capability.usersWrite));
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<(List<UserSummary>, bool)>(
        future: _future,
        builder: (context, snapshot) {
          final canManage = snapshot.data?.$2 ?? false;
          return AppPage(
            title: 'Usuarios',
            subtitle: canManage
                ? 'Administra el acceso del equipo a este negocio.'
                : 'Consulta los usuarios permitidos de este negocio.',
            scrollable: false,
            primaryAction: canManage
                ? AppPrimaryButton(
                    key: const Key('add-user'),
                    label: _submitting ? 'Guardando…' : 'Agregar usuario',
                    icon: Icons.person_add_alt_1,
                    onPressed: _submitting || _dialogOpen ? null : _create,
                  )
                : null,
            body: _body(snapshot),
          );
        },
      );

  Widget _body(AsyncSnapshot<(List<UserSummary>, bool)> snapshot) {
    if (snapshot.hasError) {
      return AppErrorState(
        message: 'No fue posible cargar los usuarios permitidos.',
        onRetry: _reload,
      );
    }
    if (!snapshot.hasData) {
      return const AppLoadingState(label: 'Cargando usuarios…');
    }
    final (users, canManage) = snapshot.data!;
    if (users.length <= 1 && canManage) {
      return AppEmptyState(
        icon: Icons.group_outlined,
        message: 'Aún no hay usuarios adicionales',
        action: AppPrimaryButton(
          label: 'Agregar usuario',
          icon: Icons.person_add_alt_1,
          onPressed: _submitting ? null : _create,
        ),
      );
    }
    return Card(
      child: ListView.separated(
        itemCount: users.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, index) => _UserRow(
          user: users[index],
          canManage: canManage,
          onEdit: () => _edit(users[index]),
          onToggle: () => _toggle(users[index]),
          onReset: () => _resetPassword(users[index]),
        ),
      ),
    );
  }

  Future<void> _create() async {
    if (_dialogOpen || _submitting) return;
    setState(() => _dialogOpen = true);
    final result = await showDialog<UserFormResult>(
      context: context,
      builder: (_) => const UserEditorDialog(),
    );
    if (mounted) setState(() => _dialogOpen = false);
    if (result == null) return;
    await _run(
      () =>
          UserRepository(appDatabase)
              .create(input: result.input, password: result.password!),
      'Usuario agregado correctamente.',
    );
  }

  Future<void> _edit(UserSummary user) async {
    final result = await showDialog<UserFormResult>(
      context: context,
      builder: (_) => UserEditorDialog(user: user),
    );
    if (result == null) return;
    await _run(
      () => UserRepository(appDatabase).update(user: user, input: result.input),
      'Usuario actualizado correctamente.',
    );
  }

  Future<void> _toggle(UserSummary user) async {
    if (user.active) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AppDialog(
          title: 'Desactivar usuario',
          destructive: true,
          content: Text(
            '${user.name} no podrá iniciar sesión hasta que sea reactivado.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Desactivar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await _run(
      () => UserRepository(appDatabase).update(
        user: user,
        input: UserInput(
          name: user.name,
          username: user.username,
          role: user.role,
          active: !user.active,
        ),
      ),
      user.active ? 'Usuario desactivado.' : 'Usuario activado.',
    );
  }

  Future<void> _resetPassword(UserSummary user) async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => PasswordResetDialog(userName: user.name),
    );
    if (password == null) return;
    await _run(
      () => UserRepository(appDatabase).resetPassword(user, password),
      'Contraseña restablecida correctamente.',
    );
  }

  Future<void> _run(Future<Object?> Function() action, String success) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(success)));
        _reload();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ArgumentError || error is StateError
                  ? error.toString().replaceFirst(
                      RegExp(r'^(Invalid argument\(s\)?: |Bad state: )'),
                      '',
                    )
                  : 'No se pudo completar la operación.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.canManage,
    required this.onEdit,
    required this.onToggle,
    required this.onReset,
  });
  final UserSummary user;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onReset;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.xs,
    ),
    leading: CircleAvatar(
      child: Text(user.name.characters.first.toUpperCase()),
    ),
    title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xxs,
      children: [
        Text('@${user.username}'),
        Chip(label: Text(userRoleLabels[user.role]!)),
        AppStatusChip(
          label: user.active ? 'Activo' : 'Inactivo',
          status: user.active ? AppStatus.active : AppStatus.inactive,
        ),
        if (user.lastActivity != null)
          Text(
            'Última actividad: ${DateFormat('dd/MM/yyyy HH:mm').format(user.lastActivity!.toLocal())}',
          ),
      ],
    ),
    trailing: canManage
        ? PopupMenuButton<String>(
            tooltip: 'Acciones de usuario',
            onSelected: (action) {
              if (action == 'edit') onEdit();
              if (action == 'toggle') onToggle();
              if (action == 'password') onReset();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Editar')),
              PopupMenuItem(
                value: 'toggle',
                child: Text(user.active ? 'Desactivar' : 'Activar'),
              ),
              const PopupMenuItem(
                value: 'password',
                child: Text('Restablecer contraseña'),
              ),
            ],
          )
        : null,
  );
}

class UserFormResult {
  const UserFormResult(this.input, this.password);
  final UserInput input;
  final String? password;
}

class UserEditorDialog extends StatefulWidget {
  const UserEditorDialog({this.user, super.key});
  final UserSummary? user;
  @override
  State<UserEditorDialog> createState() => _UserEditorDialogState();
}

class _UserEditorDialogState extends State<UserEditorDialog> {
  final formKey = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.user?.name);
  late final username = TextEditingController(text: widget.user?.username);
  final password = TextEditingController();
  final confirmation = TextEditingController();
  AppRole? role;
  late bool active = widget.user?.active ?? true;
  bool submitted = false;
  bool get creating => widget.user == null;
  @override
  void initState() {
    super.initState();
    role = widget.user?.role;
  }

  @override
  void dispose() {
    name.dispose();
    username.dispose();
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: creating ? 'Agregar usuario' : 'Editar usuario',
    content: SizedBox(
      width: 620,
      child: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                label: 'Nombre completo',
                controller: name,
                required: true,
                validator: _required,
              ),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                label: 'Usuario',
                controller: username,
                required: true,
                helperText: 'Letras, números, punto, guion o guion bajo.',
                validator: (value) =>
                    UserRepository.validateUsername(value ?? ''),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (creating) ...[
                AppTextField(
                  label: 'Contraseña',
                  controller: password,
                  obscureText: true,
                  required: true,
                  validator: _password,
                ),
                const SizedBox(height: AppSpacing.sm),
                AppTextField(
                  label: 'Confirmar contraseña',
                  controller: confirmation,
                  obscureText: true,
                  required: true,
                  validator: (value) => value != password.text
                      ? 'Las contraseñas no coinciden.'
                      : _required(value),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              DropdownButtonFormField<AppRole>(
                key: const Key('user-role-combobox'),
                initialValue: role,
                decoration: const InputDecoration(
                  labelText: 'Tipo de usuario *',
                ),
                items: AppRole.values
                    .map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(userRoleLabels[item]!),
                      ),
                    )
                    .toList(),
                validator: (value) =>
                    value == null ? 'Selecciona un tipo de usuario.' : null,
                onChanged: (value) => setState(() => role = value),
              ),
              if (role != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    userRoleDescriptions[role!]!,
                    key: const Key('role-description'),
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Usuario activo'),
                subtitle: const Text(
                  'Puede iniciar sesión y operar según su rol.',
                ),
                value: active,
                onChanged: (value) => setState(() => active = value),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      AppPrimaryButton(
        key: const Key('save-user'),
        label: creating ? 'Agregar usuario' : 'Guardar cambios',
        onPressed: _submit,
      ),
    ],
  );
  String? _required(String? value) =>
      (value?.trim().isEmpty ?? true) ? 'Este campo es obligatorio.' : null;
  String? _password(String? value) {
    if (value == null || value.length < 8) return 'Usa al menos 8 caracteres.';
    return null;
  }

  void _submit() {
    if (submitted) return;
    if (!(formKey.currentState?.validate() ?? false) || role == null) return;
    submitted = true;
    Navigator.pop(
      context,
      UserFormResult(
        UserInput(
          name: name.text.trim(),
          username: UserRepository.normalizeUsername(username.text),
          role: role!,
          active: active,
        ),
        creating ? password.text : null,
      ),
    );
  }
}

class PasswordResetDialog extends StatefulWidget {
  const PasswordResetDialog({required this.userName, super.key});
  final String userName;
  @override
  State<PasswordResetDialog> createState() => _PasswordResetDialogState();
}

class _PasswordResetDialogState extends State<PasswordResetDialog> {
  final formKey = GlobalKey<FormState>();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  @override
  void dispose() {
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: 'Restablecer contraseña',
    content: SizedBox(
      width: 480,
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Define una contraseña nueva para ${widget.userName}.'),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Nueva contraseña',
              controller: password,
              obscureText: true,
              validator: (value) => (value?.length ?? 0) < 8
                  ? 'Usa al menos 8 caracteres.'
                  : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              label: 'Confirmar contraseña',
              controller: confirmation,
              obscureText: true,
              validator: (value) => value != password.text
                  ? 'Las contraseñas no coinciden.'
                  : null,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      AppPrimaryButton(
        label: 'Restablecer contraseña',
        onPressed: () {
          if (formKey.currentState?.validate() ?? false) {
            Navigator.pop(context, password.text);
          }
        },
      ),
    ],
  );
}
