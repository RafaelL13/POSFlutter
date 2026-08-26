abstract interface class BackupProvider {Future<String> createBackup();Future<void> restoreBackup(String path);}
