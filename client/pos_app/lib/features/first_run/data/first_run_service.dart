import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:pos_app/core/security/password_hasher.dart';
import 'package:pos_app/core/utils/id_generator.dart';
import 'package:pos_app/database/app_database.dart';

final class FirstRunService {
  FirstRunService(this._db,{IdGenerator? ids,PasswordHasher? hasher}):_ids=ids??const UuidV7Generator(),_hasher=hasher??PasswordHasher();
  final AppDatabase _db; final IdGenerator _ids; final PasswordHasher _hasher;
  Future<bool> configured() async {final db=await _db.open();final r=await db.rawQuery("SELECT COUNT(*) c FROM businesses");return (r.first['c'] as int)>0;}
  Future<void> createBusiness({required String businessName,required String adminName,required String username,required String password,required String deviceName}) async {
    final hash=await _hasher.hash(password); final now=DateTime.now().toUtc().toIso8601String();
    await _db.criticalTransaction((tx) async {
      final businessGid=_ids.newId(),branchGid=_ids.newId(),deviceGid=_ids.newId(),userGid=_ids.newId();
      final businessId=await tx.insert('businesses',{'global_id':businessGid,'name':businessName.trim(),'created_at':now,'updated_at':now});
      final branchId=await tx.insert('branches',{'global_id':branchGid,'business_id':businessId,'name':'Principal','created_at':now,'updated_at':now});
      await tx.insert('devices',{'global_id':deviceGid,'branch_id':branchId,'name':deviceName.trim(),'mode':'PointOfSale','created_at':now,'updated_at':now});
      await tx.insert('users',{'global_id':userGid,'business_id':businessId,'name':adminName.trim(),'username':username.trim(),'password_hash':hash.hash,'password_salt':hash.salt,'role':'Administrator','created_at':now,'updated_at':now});
      for(final entry in {'local_device_global_id':deviceGid,'active_user_global_id':userGid,'configured':'1','local_session_authenticated':'0'}.entries){await tx.insert('app_settings',{'key':entry.key,'value':entry.value,'updated_at':now},conflictAlgorithm:ConflictAlgorithm.replace);}
      final payload={'globalId':businessGid,'name':businessName.trim(),'active':true,'updatedAt':now,'serverVersion':0};
      await tx.insert('sync_queue',{'global_id':_ids.newId(),'entity_type':'Business','entity_global_id':businessGid,'operation':'Create','payload_version':1,'payload_json':jsonEncode(payload),'created_at':now});
    });
  }
}
