import 'dart:convert';
import 'dart:typed_data';

import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/utils/id_generator.dart';
import 'package:pos_app/database/app_database.dart';

const int businessLogoMaxBytes = 256 * 1024;
const List<int> businessBrandColors = [
  0x1565C0,
  0x3949AB,
  0x00897B,
  0x2E7D32,
  0xEF6C00,
  0xC62828,
  0x7B1FA2,
  0x455A64,
];

final class BusinessBranding {
  const BusinessBranding({
    required this.businessId,
    required this.businessGlobalId,
    required this.displayName,
    this.logoBytes,
    this.logoMimeType,
    this.primaryColor,
    this.updatedAt,
    this.branchName,
    this.deviceName,
    this.deviceMode,
  });

  const BusinessBranding.fallback()
    : businessId = null,
      businessGlobalId = null,
      displayName = 'POS Flutter',
      logoBytes = null,
      logoMimeType = null,
      primaryColor = null,
      updatedAt = null,
      branchName = null,
      deviceName = null,
      deviceMode = null;

  final int? businessId;
  final String? businessGlobalId;
  final String displayName;
  final Uint8List? logoBytes;
  final String? logoMimeType;
  final int? primaryColor;
  final DateTime? updatedAt;
  final String? branchName;
  final String? deviceName;
  final String? deviceMode;
}

final class BusinessBrandingRepository {
  BusinessBrandingRepository(this._database, {IdGenerator? ids})
    : _ids = ids ?? const UuidV7Generator();

  final AppDatabase _database;
  final IdGenerator _ids;

  Future<BusinessBranding> read() async {
    final db = await _database.open();
    final deviceSetting = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['local_device_global_id'],
      limit: 1,
    );
    final deviceGlobalId = deviceSetting.isEmpty
        ? null
        : deviceSetting.first['value'] as String?;
    final rows = deviceGlobalId == null
        ? await db.rawQuery(
            '''SELECT b.* FROM businesses b ORDER BY b.id LIMIT 1''',
          )
        : await db.rawQuery(
            '''SELECT b.*, br.name branch_name, d.name device_name, d.mode device_mode
               FROM devices d JOIN branches br ON br.id=d.branch_id
               JOIN businesses b ON b.id=br.business_id
               WHERE d.global_id=? LIMIT 1''',
            [deviceGlobalId],
          );
    if (rows.isEmpty) return const BusinessBranding.fallback();
    final row = rows.first;
    final configured = (row['display_name'] as String?)?.trim();
    return BusinessBranding(
      businessId: row['id'] as int,
      businessGlobalId: row['global_id'] as String,
      displayName: configured == null || configured.isEmpty
          ? row['name'] as String
          : configured,
      logoBytes: row['logo_blob'] as Uint8List?,
      logoMimeType: row['logo_mime_type'] as String?,
      primaryColor: row['primary_color'] as int?,
      updatedAt: DateTime.tryParse(row['branding_updated_at'] as String? ?? ''),
      branchName: row['branch_name'] as String?,
      deviceName: row['device_name'] as String?,
      deviceMode: row['device_mode'] as String?,
    );
  }

  static String validateLogo(Uint8List bytes) {
    if (bytes.isEmpty) throw ArgumentError('El logo estÃ¡ vacÃ­o.');
    if (bytes.length > businessLogoMaxBytes) {
      throw ArgumentError('El logo no debe superar 256 KiB.');
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 12 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
      return 'image/webp';
    }
    throw ArgumentError('Selecciona una imagen PNG, JPEG o WebP vÃ¡lida.');
  }

  Future<void> save({
    required String displayName,
    required Uint8List? logoBytes,
    required int? primaryColor,
  }) async {
    final effective = await AuthorizationService(_database)
        .require(Capability.businessWrite);
    final context = effective.context!;
    final name = displayName.trim();
    if (name.isEmpty || name.length > 160) {
      throw ArgumentError(
        'El nombre comercial es obligatorio y admite hasta 160 caracteres.',
      );
    }
    if (primaryColor != null && !businessBrandColors.contains(primaryColor)) {
      throw ArgumentError('Selecciona un color de la paleta disponible.');
    }
    final mime = logoBytes == null ? null : validateLogo(logoBytes);
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.criticalTransaction((tx) async {
      final current = (await tx.query(
        'businesses',
        where: 'id = ?',
        whereArgs: [context.businessId],
        limit: 1,
      )).single;
      await tx.update(
        'businesses',
        {
          'display_name': name,
          'logo_blob': logoBytes,
          'logo_mime_type': mime,
          'primary_color': primaryColor,
          'branding_updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [context.businessId],
      );
      final payload = {
        'globalId': context.businessGlobalId,
        'name': current['name'],
        'active': current['active'] == 1,
        'updatedAt': now,
        'baseServerVersion': current['server_version'],
        'displayName': name,
        'logoBase64': logoBytes == null ? null : base64Encode(logoBytes),
        'logoMimeType': mime,
        'primaryColor': primaryColor,
        'brandingUpdatedAt': now,
      };
      final serverVersion = current['server_version'] as int;
      if (serverVersion == 0) {
        final pendingCreates = await tx.query(
          'sync_queue',
          columns: ['id', 'payload_json'],
          where: "entity_type = ? AND entity_global_id = ? AND operation = ? AND status = ? AND retry_count = 0 AND last_attempt_at IS NULL AND requires_action = 0",
          whereArgs: [
            'Business',
            context.businessGlobalId,
            'Create',
            'Pending',
          ],
          orderBy: 'id ASC',
        );
        if (pendingCreates.length == 1) {
          final create = pendingCreates.single;
          final createPayload = Map<String, Object?>.from(
            jsonDecode(create['payload_json'] as String) as Map,
          );
          createPayload
            ..['name'] = current['name']
            ..['active'] = current['active'] == 1
            ..['updatedAt'] = now
            ..['displayName'] = name
            ..['logoBase64'] = logoBytes == null
                ? null
                : base64Encode(logoBytes)
            ..['logoMimeType'] = mime
            ..['primaryColor'] = primaryColor
            ..['brandingUpdatedAt'] = now;
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
        'entity_type': 'Business',
        'entity_global_id': context.businessGlobalId,
        'operation': 'Update',
        'payload_version': 1,
        'payload_json': jsonEncode(payload),
        'created_at': now,
      });
    });
  }
}
