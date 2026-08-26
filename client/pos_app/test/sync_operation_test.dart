import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/sync/sync_operation.dart';
void main(){test('retry count y payload sobreviven lectura SQLite',(){final r=SyncOperationRecord.fromRow({'id':7,'global_id':'op','entity_type':'Sale','entity_global_id':'sale','operation':'Create','payload_version':1,'payload_json':'{"totalCents":90000}','retry_count':3});expect(r.retryCount,3);expect(r.payload['totalCents'],90000);expect(r.toJson()['globalId'],'op');});}
