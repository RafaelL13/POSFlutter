import 'package:pos_app/database/app_database.dart';

final class LocalAppContext {
  const LocalAppContext({required this.businessId, required this.businessGlobalId, required this.branchId, required this.branchGlobalId, required this.deviceId, required this.deviceGlobalId, required this.deviceMode, required this.userId, required this.userGlobalId, required this.role});
  final int businessId; final String businessGlobalId; final int branchId; final String branchGlobalId;
  final int deviceId; final String deviceGlobalId; final String deviceMode; final int userId; final String userGlobalId; final String role;
  bool get isAdminReadOnly => deviceMode == 'AdminReadOnly';
  bool get isAdministrator => role == 'Administrator';

  static Future<LocalAppContext> load(AppDatabase database) async {
    final db = await database.open();
    final settings = {for (final r in await db.query('app_settings')) r['key'] as String: r['value'] as String};
    final deviceGlobal = settings['local_device_global_id'];
    final userGlobal = settings['active_user_global_id'];
    if (deviceGlobal == null || userGlobal == null) throw StateError('El contexto local no está configurado.');
    const sql = 'SELECT b.id business_id,b.global_id business_gid,br.id branch_id,br.global_id branch_gid,'
        ' d.id device_id,d.global_id device_gid,d.mode device_mode,'
        ' u.id user_id,u.global_id user_gid,u.role role'
        ' FROM devices d JOIN branches br ON br.id=d.branch_id JOIN businesses b ON b.id=br.business_id'
        ' JOIN users u ON u.business_id=b.id'
        ' WHERE d.global_id=? AND u.global_id=? AND d.active=1 AND u.active=1 LIMIT 1';
    final rows = await db.rawQuery(sql,[deviceGlobal,userGlobal]);
    if (rows.isEmpty) throw StateError('No se encontró el contexto activo.');
    final r=rows.first;
    return LocalAppContext(businessId:r['business_id'] as int,businessGlobalId:r['business_gid'] as String,branchId:r['branch_id'] as int,branchGlobalId:r['branch_gid'] as String,deviceId:r['device_id'] as int,deviceGlobalId:r['device_gid'] as String,deviceMode:r['device_mode'] as String,userId:r['user_id'] as int,userGlobalId:r['user_gid'] as String,role:r['role'] as String);
  }
}
