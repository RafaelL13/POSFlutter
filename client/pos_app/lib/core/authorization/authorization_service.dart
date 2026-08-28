import 'package:pos_app/core/authorization/app_role.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/authorization/device_mode.dart';
import 'package:pos_app/core/authorization/role_policy.dart';
import 'package:pos_app/core/context/local_app_context.dart';
import 'package:pos_app/database/app_database.dart';

typedef LocalAppContextLoader = Future<LocalAppContext> Function();

final class AuthorizationDeniedException implements Exception {
  const AuthorizationDeniedException(this.capability);

  final Capability capability;

  @override
  String toString() =>
      'AuthorizationDeniedException: ${capability.name} no está permitido.';
}

final class AdditionalAuthorizationRequiredException implements Exception {
  const AdditionalAuthorizationRequiredException(this.capability);

  final Capability capability;

  @override
  String toString() =>
      'AdditionalAuthorizationRequiredException: ${capability.name} requiere autorización adicional.';
}

final class EffectiveCapabilities {
  const EffectiveCapabilities._({this.context, this.role, this.deviceMode});

  const EffectiveCapabilities.denied() : this._();

  factory EffectiveCapabilities.fromContext(LocalAppContext context) {
    final role = context.parsedRole;
    final deviceMode = context.parsedDeviceMode;
    if (role == null || deviceMode == null) {
      return const EffectiveCapabilities.denied();
    }

    return EffectiveCapabilities._(
      context: context,
      role: role,
      deviceMode: deviceMode,
    );
  }

  final LocalAppContext? context;
  final AppRole? role;
  final DeviceMode? deviceMode;

  bool get hasValidContext =>
      context != null && role != null && deviceMode != null;

  PermissionLevel permissionFor(Capability capability) {
    if (!hasValidContext) {
      return PermissionLevel.none;
    }

    return RolePolicy.effectivePermission(
      role: role,
      deviceMode: deviceMode,
      capability: capability,
    );
  }

  bool can(Capability capability) =>
      permissionFor(capability) != PermissionLevel.none;

  bool requiresAdditionalAuthorization(Capability capability) =>
      permissionFor(capability) == PermissionLevel.requiresAuthorization;

  Set<Capability> get grantedCapabilities => {
    for (final capability in Capability.values)
      if (can(capability)) capability,
  };

  void require(Capability capability) {
    final permission = permissionFor(capability);
    if (permission == PermissionLevel.none) {
      throw AuthorizationDeniedException(capability);
    }
    if (permission == PermissionLevel.requiresAuthorization) {
      throw AdditionalAuthorizationRequiredException(capability);
    }
  }
}

final class AuthorizationService {
  AuthorizationService(AppDatabase database)
    : this.fromContextLoader(() => LocalAppContext.load(database));

  AuthorizationService.fromContextLoader(this._loadContext);

  final LocalAppContextLoader _loadContext;

  Future<EffectiveCapabilities> load() async {
    try {
      final context = await _loadContext();
      return EffectiveCapabilities.fromContext(context);
    } on Object {
      return const EffectiveCapabilities.denied();
    }
  }

  Future<EffectiveCapabilities> require(Capability capability) async {
    final effective = await load();
    effective.require(capability);
    return effective;
  }
}
