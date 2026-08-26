const List<String> schemaV2Statements = [
  r'''ALTER TABLE businesses ADD COLUMN server_version INTEGER NOT NULL DEFAULT 0 CHECK(typeof(server_version)='integer' AND server_version>=0)''',
  r'''ALTER TABLE branches ADD COLUMN server_version INTEGER NOT NULL DEFAULT 0 CHECK(typeof(server_version)='integer' AND server_version>=0)''',
  r'''ALTER TABLE devices ADD COLUMN server_version INTEGER NOT NULL DEFAULT 0 CHECK(typeof(server_version)='integer' AND server_version>=0)''',
  r'''ALTER TABLE users ADD COLUMN server_version INTEGER NOT NULL DEFAULT 0 CHECK(typeof(server_version)='integer' AND server_version>=0)''',
  r'''ALTER TABLE categories ADD COLUMN server_version INTEGER NOT NULL DEFAULT 0 CHECK(typeof(server_version)='integer' AND server_version>=0)''',
  r'''ALTER TABLE suppliers ADD COLUMN server_version INTEGER NOT NULL DEFAULT 0 CHECK(typeof(server_version)='integer' AND server_version>=0)''',
  r'''ALTER TABLE products ADD COLUMN server_version INTEGER NOT NULL DEFAULT 0 CHECK(typeof(server_version)='integer' AND server_version>=0)''',
  r'''CREATE TABLE sync_conflicts(id INTEGER PRIMARY KEY AUTOINCREMENT,global_id TEXT NOT NULL UNIQUE,entity_type TEXT NOT NULL,entity_global_id TEXT NOT NULL,source TEXT NOT NULL CHECK(source IN('Push','Pull')),local_operation_global_id TEXT,local_payload_json TEXT NOT NULL,remote_payload_json TEXT NOT NULL,remote_version INTEGER NOT NULL CHECK(typeof(remote_version)='integer' AND remote_version>=0),remote_cursor INTEGER,detected_at TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'Pending' CHECK(status IN('Pending','ResolvedLocal','ResolvedRemote','Dismissed')))''',
  r'''INSERT OR IGNORE INTO app_settings(key,value,updated_at) VALUES('sync_pull_cursor','0','1970-01-01T00:00:00Z')''',
  r'''CREATE INDEX ix_sync_conflicts_pending ON sync_conflicts(status,entity_type,entity_global_id)''',
];
