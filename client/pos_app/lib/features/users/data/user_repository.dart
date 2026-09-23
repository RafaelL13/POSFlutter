import 'dart:convert';

import 'package:pos_app/core/authorization/app_role.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/security/password_hasher.dart';
import 'package:pos_app/core/utils/id_generator.dart';
import 'package:pos_app/database/app_database.dart';

final class UserSummary {
  const UserSummary({
    required this.id,
    required this.globalId,
    required this.name,
    required this.username,
    required this.role,
    required this.active,
    this.lastActivity,
  });
  final int id;
  final String globalId;
  final String name;
  final String username;
  final AppRole role;
  final bool active;
  final DateTime? lastActivity;
}

final class UserInput {
  const UserInput({
    required this.name,
    required this.username,
    required this.role,
    required this.active,
  });
  final String name;
  final String username;
  final AppRole role;
  final bool active;
}

final class UserRepository {
  UserRepository(this._db, {IdGenerator? ids, PasswordHasher? hasher})
    : _ids = ids ?? const UuidV7Generator(),
      _hasher = hasher ?? PasswordHasher();
  final AppDatabase _db;
  final IdGenerator _ids;
  final PasswordHasher _hasher;

  static String normalizeUsername(String value) => value.trim().toLowerCase();
  static String? validateUsername(String value) {
    final normalized = normalizeUsername(value);
    if (normalized.isEmpty) {
      return 'El usuario es obligatorio.';
    }
    if (!RegExp(r'^[a-z0-9._-]{3,50}$').hasMatch(normalized)) {
      return 'Usa de 3 a 50 caracteres: letras, nÃºmeros, punto, guion o guion bajo.';
    }
    return null;
  }

  Future<List<UserSummary>> list() async {
    final auth = await AuthorizationService(_db).require(Capability.usersRead);
    final database = await _db.open();
    final rows = await database.rawQuery(
      '''SELECT u.id,u.global_id,u.name,u.username,u.role,u.active,
      (SELECT MAX(activity_at) FROM (
        SELECT s.sale_datetime activity_at FROM sales s WHERE s.user_id=u.id
        UNION ALL SELECT c.opened_at FROM cash_sessions c WHERE c.user_id=u.id
        UNION ALL SELECT e.expense_date FROM expenses e WHERE e.user_id=u.id
      )) last_activity
      FROM users u WHERE u.business_id=? ORDER BY u.active DESC,u.name''',
      [auth.context!.businessId],
    );
    return rows.map(_summary).toList(growable: false);
  }

  Future<String> create({
    required UserInput input,
    required String password,
  }) async {
    final auth = await AuthorizationService(_db).require(Capability.usersWrite);
    _validate(input, password: password);
    final context = auth.context!;
    final username = normalizeUsername(input.username);
    final passwordHash = await _hasher.hash(password);
    final globalId = _ids.newId();
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.criticalTransaction((tx) async {
      await tx.insert('users', {
        'global_id': globalId,
        'business_id': context.businessId,
        'name': input.name.trim(),
        'username': username,
        'password_hash': passwordHash.hash,
        'password_salt': passwordHash.salt,
        'role': input.role.wireValue,
        'active': input.active ? 1 : 0,
        'created_at': now,
        'updated_at': now,
      });
      await _enqueue(
        tx,
        globalId,
        context.businessGlobalId,
        input.copyWith(username: username),
        passwordHash,
        now,
        'Create',
        null,
      );
    });
    return globalId;
  }

  Future<void> update({
    required UserSummary user,
    required UserInput input,
  }) async {
    final auth = await AuthorizationService(_db).require(Capability.usersWrite);
    _validate(input);
    final context = auth.context!;
    final database = await _db.open();
    final rows = await database.query(
      'users',
      where: 'id=? AND global_id=? AND business_id=?',
      whereArgs: [user.id, user.globalId, context.businessId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Usuario inexistente.');
    final row = rows.single;
    if (user.role == AppRole.administrator &&
        user.active &&
        (input.role != AppRole.administrator || !input.active)) {
      await _requireAnotherAdministrator(context.businessId, user.id);
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final hash = PasswordHash(
      row['password_hash']! as String,
      row['password_salt']! as String,
    );
    await _db.criticalTransaction((tx) async {
      await tx.update(
        'users',
        {
          'name': input.name.trim(),
          'username': normalizeUsername(input.username),
          'role': input.role.wireValue,
          'active': input.active ? 1 : 0,
          'updated_at': now,
        },
        where: 'id=? AND global_id=? AND business_id=?',
        whereArgs: [user.id, user.globalId, context.businessId],
      );
      await _enqueue(
        tx,
        user.globalId,
        context.businessGlobalId,
        input.copyWith(username: normalizeUsername(input.username)),
        hash,
        now,
        'Update',
        row['server_version'] as int?,
      );
    });
  }

  Future<void> resetPassword(UserSummary user, String password) async {
    final auth = await AuthorizationService(_db).require(Capability.usersWrite);
    if (password.length < 8) {
      throw ArgumentError('La contraseÃ±a debe tener al menos 8 caracteres.');
    }
    final context = auth.context!;
    final database = await _db.open();
    final rows = await database.query(
      'users',
      where: 'id=? AND global_id=? AND business_id=?',
      whereArgs: [user.id, user.globalId, context.businessId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Usuario inexistente.');
    final row = rows.single;
    final hash = await _hasher.hash(password);
    final input = UserInput(
      name: row['name']! as String,
      username: row['username']! as String,
      role: AppRole.tryParse(row['role'] as String)!,
      active: row['active'] == 1,
    );
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.criticalTransaction((tx) async {
      await tx.update(
        'users',
        {
          'password_hash': hash.hash,
          'password_salt': hash.salt,
          'updated_at': now,
        },
        where: 'id=? AND global_id=? AND business_id=?',
        whereArgs: [user.id, user.globalId, context.businessId],
      );
      await _enqueue(
        tx,
        user.globalId,
        context.businessGlobalId,
        input,
        hash,
        now,
        'Update',
        row['server_version'] as int?,
      );
    });
  }

  void _validate(UserInput input, {String? password}) {
    if (input.name.trim().isEmpty) {
      throw ArgumentError('El nombre es obligatorio.');
    }
    final usernameError = validateUsername(input.username);
    if (usernameError != null) throw ArgumentError(usernameError);
    if (password != null && password.length < 8) {
      throw ArgumentError('La contraseÃ±a debe tener al menos 8 caracteres.');
    }
  }

  Future<void> _requireAnotherAdministrator(
    int businessId,
    int excludedId,
  ) async {
    final database = await _db.open();
    final rows = await database.rawQuery(
      "SELECT COUNT(*) count FROM users WHERE business_id=? AND role='Administrator' AND active=1 AND id<>?",
      [businessId, excludedId],
    );
    if ((rows.single['count']! as int) == 0) {
      throw StateError('Debe permanecer al menos un administrador activo.');
    }
  }

  Future<void> _enqueue(
    dynamic tx,
    String globalId,
    String businessGlobalId,
    UserInput input,
    PasswordHash hash,
    String now,
    String operation,
    int? version,
  ) async {
    final payload = {
      'globalId': globalId,
      'businessGlobalId': businessGlobalId,
      'name': input.name.trim(),
      'username': input.username,
      'passwordHash': hash.hash,
      'passwordSalt': hash.salt,
      'role': input.role.wireValue,
      'active': input.active,
      'updatedAt': now,
      'baseServerVersion': version,
    };

    if (operation == 'Update' && version == 0) {
      final pendingCreates = await tx.query(
        'sync_queue',
        columns: ['id', 'payload_json'],
        where: "entity_type = ? AND entity_global_id = ? AND operation = ? AND status = ? AND retry_count = 0 AND last_attempt_at IS NULL AND requires_action = 0",
        whereArgs: ['User', globalId, 'Create', 'Pending'],
        orderBy: 'id ASC',
      );
      if (pendingCreates.length == 1) {
        final create = pendingCreates.single;
        final createPayload = Map<String, Object?>.from(
          jsonDecode(create['payload_json'] as String) as Map,
        );
        createPayload
          ..['businessGlobalId'] = businessGlobalId
          ..['name'] = input.name.trim()
          ..['username'] = input.username
          ..['passwordHash'] = hash.hash
          ..['passwordSalt'] = hash.salt
          ..['role'] = input.role.wireValue
          ..['active'] = input.active
          ..['updatedAt'] = now;
        createPayload.remove('baseServerVersion');
        await tx.update(
          'sync_queue',
          {'payload_json': jsonEncode(createPayload)},
          where: 'id = ?',
          whereArgs: [create['id']],
        );
        return;
      }
    }

    await tx.insert('sync_queue', {
      'global_id': _ids.newId(),
      'entity_type': 'User',
      'entity_global_id': globalId,
      'operation': operation,
      'payload_version': 1,
      'payload_json': jsonEncode(payload),
      'created_at': now,
    });
  }

  UserSummary _summary(Map<String, Object?> row) => UserSummary(
    id: row['id']! as int,
    globalId: row['global_id']! as String,
    name: row['name']! as String,
    username: row['username']! as String,
    role: AppRole.tryParse(row['role'] as String)!,
    active: row['active'] == 1,
    lastActivity: DateTime.tryParse(row['last_activity'] as String? ?? ''),
  );
}

extension on UserInput {
  UserInput copyWith({String? username}) => UserInput(
    name: name,
    username: username ?? this.username,
    role: role,
    active: active,
  );
}
