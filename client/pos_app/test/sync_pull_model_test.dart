import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/sync/sync_pull.dart';
void main(){test('pull conserva cursor monotónico y payload',(){final b=SyncPullBatch.fromJson({'nextCursor':103,'hasMore':false,'serverTime':'2026-08-25T00:00:00Z','changes':[{'cursor':103,'entityType':'Product','entityGlobalId':'p','operation':'Update','version':4,'changedAt':'2026-08-25T00:00:00Z','payload':{'globalId':'p'}}]});expect(b.nextCursor,103);expect(b.changes.single.cursor,103);expect(b.changes.single.version,4);});}
