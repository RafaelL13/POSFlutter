const List<String> schemaV4Statements = [
  r'''CREATE TABLE special_authorization_grants(id INTEGER PRIMARY KEY AUTOINCREMENT,global_id TEXT NOT NULL UNIQUE,capability TEXT NOT NULL,requirement TEXT NOT NULL CHECK(requirement IN('SecondUserAuthorization','Reauthentication')),performed_by_user_global_id TEXT NOT NULL,authorized_by_user_global_id TEXT NOT NULL,business_global_id TEXT NOT NULL,device_global_id TEXT NOT NULL,reason TEXT NOT NULL CHECK(length(trim(reason))>0),authorized_at TEXT NOT NULL,consumed_at TEXT,operation TEXT,entity_type TEXT,entity_global_id TEXT)''',
  r'''CREATE INDEX ix_special_authorization_unconsumed ON special_authorization_grants(global_id,consumed_at)''',
];
