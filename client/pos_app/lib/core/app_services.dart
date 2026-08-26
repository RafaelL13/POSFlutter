import 'package:pos_app/core/network/cloud_api_client.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/sync/remote_sync_repository.dart';
import 'package:pos_app/sync/sync_repository.dart';
import 'package:pos_app/sync/sync_service.dart';

final appDatabase = AppDatabase();
final cloudApiClient = CloudApiClient();
final localSyncRepository = SyncRepository(database: appDatabase);
final remoteSyncRepository = RemoteSyncRepository(cloudApiClient);
final syncService = SyncService(database: appDatabase, local: localSyncRepository, remote: remoteSyncRepository);
