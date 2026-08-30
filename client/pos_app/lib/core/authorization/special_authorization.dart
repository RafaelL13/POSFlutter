import 'dart:convert';

import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/app_role.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/authorization/role_policy.dart';
import 'package:pos_app/core/security/password_hasher.dart';
import 'package:pos_app/core/utils/id_generator.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:sqflite/sqflite.dart';

enum SpecialAuthorizationRequirement {
  secondUserAuthorization('SecondUserAuthorization'),
  reauthentication('Reauthentication');

  const SpecialAuthorizationRequirement(this.storageValue);
  final String storageValue;
}

enum SpecialAuthorizationFailure {
  invalidCredentials,
  authorizerNotAllowed,
  selfAuthorization,
  invalidRequest,
  invalidGrant,
  consumedGrant,
}

final class SpecialAuthorizationException implements Exception {
  const SpecialAuthorizationException(this.failure);
  final SpecialAuthorizationFailure failure;

  @override
  String toString() => 'SpecialAuthorizationException: ${failure.name}';
}

final class SpecialAuthorizationGrant {
  const SpecialAuthorizationGrant({
    required this.globalId,
    required this.capability,
    required this.requirement,
    required this.performedByUserGlobalId,
    required this.authorizedByUserGlobalId,
    required this.businessGlobalId,
    required this.deviceGlobalId,
    required this.reason,
    required this.authorizedAt,
  });

  final String globalId;
  final Capability capability;
  final SpecialAuthorizationRequirement requirement;
  final String performedByUserGlobalId;
  final String authorizedByUserGlobalId;
  final String businessGlobalId;
  final String deviceGlobalId;
  final String reason;
  final DateTime authorizedAt;

  Map<String, Object?> toAuditJson() => {
    'authorizationGlobalId': globalId,
    'capability': capability.name,
    'requirement': requirement.storageValue,
    'performedByUserGlobalId': performedByUserGlobalId,
    'authorizedByUserGlobalId': authorizedByUserGlobalId,
    'businessGlobalId': businessGlobalId,
    'deviceGlobalId': deviceGlobalId,
    'reason': reason,
    'authorizedAt': authorizedAt.toUtc().toIso8601String(),
  };
}

final class PreparedSpecialAuthorization {
  const PreparedSpecialAuthorization._({this.grant});
  const PreparedSpecialAuthorization.direct() : this._();
  const PreparedSpecialAuthorization.granted(SpecialAuthorizationGrant grant)
    : this._(grant: grant);

  final SpecialAuthorizationGrant? grant;
  bool get isDirect => grant == null;
}

final class SpecialAuthorizationService {
  SpecialAuthorizationService(
    this._database, {
    PasswordHasher? hasher,
    IdGenerator? ids,
    DateTime Function()? clock,
  }) : _hasher = hasher ?? PasswordHasher(),
       _ids = ids ?? const UuidV7Generator(),
       _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final PasswordHasher _hasher;
  final IdGenerator _ids;
  final DateTime Function() _clock;

  static SpecialAuthorizationRequirement requirementFor(
    Capability capability,
  ) => switch (capability) {
    Capability.saleCancel ||
    Capability.saleDiscount ||
    Capability.inventoryAdjust ||
    Capability.cashCloseWithDifference ||
    Capability.cashWithdrawal ||
    Capability.productPriceChange =>
      SpecialAuthorizationRequirement.secondUserAuthorization,
    Capability.backupRestore =>
      SpecialAuthorizationRequirement.reauthentication,
    _ => throw const SpecialAuthorizationException(
      SpecialAuthorizationFailure.invalidRequest,
    ),
  };

  Future<SpecialAuthorizationGrant> authorizeSecondUser({
    required Capability capability,
    required String username,
    required String password,
    required String reason,
  }) async {
    if (requirementFor(capability) !=
        SpecialAuthorizationRequirement.secondUserAuthorization) {
      throw const SpecialAuthorizationException(
        SpecialAuthorizationFailure.invalidRequest,
      );
    }
    final effective = await AuthorizationService(_database).load();
    final permission = effective.permissionFor(capability);
    if (permission == PermissionLevel.none) {
      throw AuthorizationDeniedException(capability);
    }
    if (permission != PermissionLevel.requiresAuthorization) {
      throw const SpecialAuthorizationException(
        SpecialAuthorizationFailure.invalidRequest,
      );
    }
    final ctx = effective.context!;
    final normalizedReason = _requiredReason(reason);
    final db = await _database.open();
    final rows = await db.query(
      'users',
      where: 'business_id=? AND username=? AND active=1',
      whereArgs: [ctx.businessId, username.trim()],
      limit: 1,
    );
    final authorizer = rows.isEmpty ? null : rows.first;
    if (authorizer == null || !await _validPassword(authorizer, password)) {
      throw const SpecialAuthorizationException(
        SpecialAuthorizationFailure.invalidCredentials,
      );
    }
    final authorizerGlobalId = authorizer['global_id'] as String;
    if (authorizerGlobalId == ctx.userGlobalId) {
      throw const SpecialAuthorizationException(
        SpecialAuthorizationFailure.selfAuthorization,
      );
    }
    final role = authorizer['role'] as String?;
    final authorizerPermission = RolePolicy.effectivePermission(
      role: AppRole.tryParse(role),
      deviceMode: ctx.parsedDeviceMode,
      capability: capability,
    );
    if (authorizerPermission != PermissionLevel.full) {
      throw const SpecialAuthorizationException(
        SpecialAuthorizationFailure.authorizerNotAllowed,
      );
    }
    return _persistGrant(
      capability: capability,
      requirement: SpecialAuthorizationRequirement.secondUserAuthorization,
      performedBy: ctx.userGlobalId,
      authorizedBy: authorizerGlobalId,
      businessGlobalId: ctx.businessGlobalId,
      deviceGlobalId: ctx.deviceGlobalId,
      reason: normalizedReason,
    );
  }

  Future<SpecialAuthorizationGrant> reauthenticate({
    required Capability capability,
    required String username,
    required String password,
    required String reason,
  }) async {
    if (requirementFor(capability) !=
        SpecialAuthorizationRequirement.reauthentication) {
      throw const SpecialAuthorizationException(
        SpecialAuthorizationFailure.invalidRequest,
      );
    }
    final effective = await AuthorizationService(_database).load();
    final permission = effective.permissionFor(capability);
    if (permission == PermissionLevel.none) {
      throw AuthorizationDeniedException(capability);
    }
    if (permission != PermissionLevel.requiresAuthorization) {
      throw const SpecialAuthorizationException(
        SpecialAuthorizationFailure.invalidRequest,
      );
    }
    final ctx = effective.context!;
    final normalizedReason = _requiredReason(reason);
    final db = await _database.open();
    final rows = await db.query(
      'users',
      where: 'id=? AND business_id=? AND username=? AND active=1',
      whereArgs: [ctx.userId, ctx.businessId, username.trim()],
      limit: 1,
    );
    final actor = rows.isEmpty ? null : rows.first;
    if (actor == null || !await _validPassword(actor, password)) {
      throw const SpecialAuthorizationException(
        SpecialAuthorizationFailure.invalidCredentials,
      );
    }
    return _persistGrant(
      capability: capability,
      requirement: SpecialAuthorizationRequirement.reauthentication,
      performedBy: ctx.userGlobalId,
      authorizedBy: ctx.userGlobalId,
      businessGlobalId: ctx.businessGlobalId,
      deviceGlobalId: ctx.deviceGlobalId,
      reason: normalizedReason,
    );
  }

  Future<PreparedSpecialAuthorization> prepare({
    required EffectiveCapabilities effective,
    required Capability capability,
    SpecialAuthorizationGrant? grant,
  }) async {
    final permission = effective.permissionFor(capability);
    if (permission == PermissionLevel.none) {
      throw AuthorizationDeniedException(capability);
    }
    if (permission == PermissionLevel.full) {
      if (grant != null) {
        throw const SpecialAuthorizationException(
          SpecialAuthorizationFailure.invalidGrant,
        );
      }
      return const PreparedSpecialAuthorization.direct();
    }
    if (permission != PermissionLevel.requiresAuthorization) {
      throw AuthorizationDeniedException(capability);
    }
    if (grant == null) {
      throw AdditionalAuthorizationRequiredException(capability);
    }
    _validateGrantIdentity(effective, capability, grant);
    final db = await _database.open();
    final rows = await db.query(
      'special_authorization_grants',
      where: 'global_id=?',
      whereArgs: [grant.globalId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const SpecialAuthorizationException(
        SpecialAuthorizationFailure.invalidGrant,
      );
    }
    if (!_matchesPersistedGrant(rows.first, grant)) {
      throw const SpecialAuthorizationException(
        SpecialAuthorizationFailure.invalidGrant,
      );
    }
    if (rows.first['consumed_at'] != null) {
      throw const SpecialAuthorizationException(
        SpecialAuthorizationFailure.consumedGrant,
      );
    }
    return PreparedSpecialAuthorization.granted(grant);
  }

  Future<Map<String, Object?>?> consumeInTransaction(
    DatabaseExecutor tx, {
    required PreparedSpecialAuthorization prepared,
    required EffectiveCapabilities effective,
    required Capability capability,
    required String operation,
    required String entityType,
    required String entityGlobalId,
  }) async {
    final grant = prepared.grant;
    if (grant == null) return null;
    _validateGrantIdentity(effective, capability, grant);
    final consumedAt = _clock().toUtc().toIso8601String();
    final updated = await tx.update(
      'special_authorization_grants',
      {
        'consumed_at': consumedAt,
        'operation': operation,
        'entity_type': entityType,
        'entity_global_id': entityGlobalId,
      },
      where:
          'global_id=? AND capability=? AND requirement=? '
          'AND performed_by_user_global_id=? '
          'AND authorized_by_user_global_id=? '
          'AND business_global_id=? AND device_global_id=? '
          'AND reason=? AND authorized_at=? AND consumed_at IS NULL',
      whereArgs: [
        grant.globalId,
        grant.capability.name,
        grant.requirement.storageValue,
        grant.performedByUserGlobalId,
        grant.authorizedByUserGlobalId,
        grant.businessGlobalId,
        grant.deviceGlobalId,
        grant.reason,
        grant.authorizedAt.toUtc().toIso8601String(),
      ],
    );
    if (updated != 1) {
      throw const SpecialAuthorizationException(
        SpecialAuthorizationFailure.consumedGrant,
      );
    }
    final ctx = effective.context!;
    final details = {
      ...grant.toAuditJson(),
      'consumedAt': consumedAt,
      'operation': operation,
      'entityType': entityType,
      'entityGlobalId': entityGlobalId,
    };
    await tx.insert('audit_logs', {
      'global_id': _ids.newId(),
      'entity_type': entityType,
      'entity_global_id': entityGlobalId,
      'action': 'SpecialAuthorization',
      'user_id': ctx.userId,
      'device_id': ctx.deviceId,
      'created_at': consumedAt,
      'details_json': jsonEncode(details),
    });
    return details;
  }

  Future<void> recordAfterDatabaseRestore({
    required SpecialAuthorizationGrant grant,
    required EffectiveCapabilities effective,
    required Map<String, Object?> metadata,
    required String operation,
    required String entityType,
    required String entityGlobalId,
  }) async {
    _validateGrantIdentity(effective, grant.capability, grant);
    final ctx = effective.context!;
    final db = await _database.open();
    await db.transaction((tx) async {
      await tx.insert('special_authorization_grants', {
        'global_id': grant.globalId,
        'capability': grant.capability.name,
        'requirement': grant.requirement.storageValue,
        'performed_by_user_global_id': grant.performedByUserGlobalId,
        'authorized_by_user_global_id': grant.authorizedByUserGlobalId,
        'business_global_id': grant.businessGlobalId,
        'device_global_id': grant.deviceGlobalId,
        'reason': grant.reason,
        'authorized_at': grant.authorizedAt.toUtc().toIso8601String(),
        'consumed_at': metadata['consumedAt'],
        'operation': operation,
        'entity_type': entityType,
        'entity_global_id': entityGlobalId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      final users = await tx.query(
        'users',
        columns: ['id'],
        where: 'global_id=?',
        whereArgs: [ctx.userGlobalId],
        limit: 1,
      );
      final devices = await tx.query(
        'devices',
        columns: ['id'],
        where: 'global_id=?',
        whereArgs: [ctx.deviceGlobalId],
        limit: 1,
      );
      await tx.insert('audit_logs', {
        'global_id': _ids.newId(),
        'entity_type': entityType,
        'entity_global_id': entityGlobalId,
        'action': 'SpecialAuthorization',
        'user_id': users.isEmpty ? null : users.first['id'],
        'device_id': devices.isEmpty ? null : devices.first['id'],
        'created_at': metadata['consumedAt'],
        'details_json': jsonEncode(metadata),
      });
    });
  }

  Future<SpecialAuthorizationGrant> _persistGrant({
    required Capability capability,
    required SpecialAuthorizationRequirement requirement,
    required String performedBy,
    required String authorizedBy,
    required String businessGlobalId,
    required String deviceGlobalId,
    required String reason,
  }) async {
    final globalId = _ids.newId();
    final authorizedAt = _clock().toUtc();
    final grant = SpecialAuthorizationGrant(
      globalId: globalId,
      capability: capability,
      requirement: requirement,
      performedByUserGlobalId: performedBy,
      authorizedByUserGlobalId: authorizedBy,
      businessGlobalId: businessGlobalId,
      deviceGlobalId: deviceGlobalId,
      reason: reason,
      authorizedAt: authorizedAt,
    );
    final db = await _database.open();
    await db.insert('special_authorization_grants', {
      'global_id': globalId,
      'capability': capability.name,
      'requirement': requirement.storageValue,
      'performed_by_user_global_id': performedBy,
      'authorized_by_user_global_id': authorizedBy,
      'business_global_id': businessGlobalId,
      'device_global_id': deviceGlobalId,
      'reason': reason,
      'authorized_at': authorizedAt.toIso8601String(),
    });
    return grant;
  }

  void _validateGrantIdentity(
    EffectiveCapabilities effective,
    Capability capability,
    SpecialAuthorizationGrant grant,
  ) {
    final ctx = effective.context;
    if (ctx == null ||
        grant.capability != capability ||
        grant.requirement != requirementFor(capability) ||
        grant.performedByUserGlobalId != ctx.userGlobalId ||
        grant.businessGlobalId != ctx.businessGlobalId ||
        grant.deviceGlobalId != ctx.deviceGlobalId) {
      throw const SpecialAuthorizationException(
        SpecialAuthorizationFailure.invalidGrant,
      );
    }
  }

  Future<bool> _validPassword(
    Map<String, Object?> user,
    String password,
  ) async {
    try {
      return await _hasher.verify(
        password,
        user['password_hash'] as String,
        user['password_salt'] as String,
      );
    } on Object {
      return false;
    }
  }

  bool _matchesPersistedGrant(
    Map<String, Object?> row,
    SpecialAuthorizationGrant grant,
  ) =>
      row['capability'] == grant.capability.name &&
      row['requirement'] == grant.requirement.storageValue &&
      row['performed_by_user_global_id'] == grant.performedByUserGlobalId &&
      row['authorized_by_user_global_id'] == grant.authorizedByUserGlobalId &&
      row['business_global_id'] == grant.businessGlobalId &&
      row['device_global_id'] == grant.deviceGlobalId &&
      row['reason'] == grant.reason &&
      row['authorized_at'] == grant.authorizedAt.toUtc().toIso8601String();

  String _requiredReason(String reason) {
    final value = reason.trim();
    if (value.isEmpty) {
      throw const SpecialAuthorizationException(
        SpecialAuthorizationFailure.invalidRequest,
      );
    }
    return value;
  }
}
