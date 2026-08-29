import 'package:sqflite/sqflite.dart';
import 'package:pos_app/core/security/password_hasher.dart';
import 'package:pos_app/database/app_database.dart';

final class LocalAuthSession { const LocalAuthSession(this.userGlobalId,this.role); final String userGlobalId; final String role; }
final class AuthRepository {
  AuthRepository(this._db,{PasswordHasher? hasher}):_hasher=hasher??PasswordHasher(); final AppDatabase _db; final PasswordHasher _hasher;
  Future<LocalAuthSession?> login(String username,String password) async {final db=await _db.open();final rows=await db.query('users',where:'username = ? AND active=1',whereArgs:[username.trim()],limit:1);if(rows.isEmpty)return null;final r=rows.first;if(!await _hasher.verify(password,r['password_hash'] as String,r['password_salt'] as String))return null;final now=DateTime.now().toUtc().toIso8601String();await db.transaction((tx) async {await tx.insert('app_settings',{'key':'active_user_global_id','value':r['global_id'],'updated_at':now},conflictAlgorithm:ConflictAlgorithm.replace);await tx.insert('app_settings',{'key':'local_session_authenticated','value':'1','updated_at':now},conflictAlgorithm:ConflictAlgorithm.replace);});return LocalAuthSession(r['global_id'] as String,r['role'] as String);}
}
