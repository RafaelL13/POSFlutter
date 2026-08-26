import 'package:pos_app/core/context/local_app_context.dart';
import 'package:pos_app/core/network/cloud_api_client.dart';
import 'package:pos_app/core/storage/secure_token_store.dart';
import 'package:pos_app/database/app_database.dart';

final class CloudBootstrapService {
  CloudBootstrapService(this._db,this._api,{SecureTokenStore? tokens}):_tokens=tokens??const SecureTokenStore();
  final AppDatabase _db; final CloudApiClient _api; final SecureTokenStore _tokens;
  Future<void> tryBootstrap() async {
    try {
      final ctx=await LocalAppContext.load(_db); if(!ctx.isAdministrator||ctx.isAdminReadOnly)return;
      final db=await _db.open();
      final rows=await db.rawQuery('SELECT b.name business_name,br.name branch_name,d.name device_name,u.name user_name,u.username,u.password_hash,u.password_salt FROM businesses b JOIN branches br ON br.business_id=b.id JOIN devices d ON d.branch_id=br.id JOIN users u ON u.business_id=b.id WHERE b.id=? AND br.id=? AND d.id=? AND u.id=? LIMIT 1',[ctx.businessId,ctx.branchId,ctx.deviceId,ctx.userId]);
      if(rows.isEmpty)return;final r=rows.first;
      final j=await _api.post('/api/bootstrap',{'businessGlobalId':ctx.businessGlobalId,'businessName':r['business_name'],'branchGlobalId':ctx.branchGlobalId,'branchName':r['branch_name'],'deviceGlobalId':ctx.deviceGlobalId,'deviceName':r['device_name'],'userGlobalId':ctx.userGlobalId,'userName':r['user_name'],'username':r['username'],'passwordHash':r['password_hash'],'passwordSalt':r['password_salt']},authenticated:false);
      final access=j['accessToken']?.toString(),refresh=j['refreshToken']?.toString();if(access!=null&&refresh!=null)await _tokens.save(accessToken:access,refreshToken:refresh);
    } catch (_) {}
  }
}
