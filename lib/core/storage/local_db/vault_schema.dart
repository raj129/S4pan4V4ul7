class VaultSchema {
  static const int schemaVersion = 1;

  static const List<String> createStatements = [
    _vaultTable,
    _photosTable,
    _albumsTable,
    _tagsTable,
    _photoTagsTable,
    _thumbnailsTable,
    _syncStateTable,
    _backupStateTable,
    _encryptionVersionsTable,
    _importJobsTable,
    _shareExportsTable,
    _trashItemsTable,
    _appSettingsTable,
    _securityEventsTable,
    _photosIndexes,
    _tagsIndexes,
    _photoTagsIndexes,
    _trashIndexes,
  ];

  static const String _vaultTable = '''
CREATE TABLE IF NOT EXISTS vault (
  id TEXT PRIMARY KEY,
  mode TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  vmk_wrap_version INTEGER NOT NULL,
  active_encryption_version INTEGER NOT NULL
);''';

  static const String _photosTable = '''
CREATE TABLE IF NOT EXISTS photos (
  id TEXT PRIMARY KEY,
  original_filename TEXT NOT NULL,
  created_time_ms INTEGER NOT NULL,
  imported_time_ms INTEGER NOT NULL,
  modified_time_ms INTEGER NOT NULL,
  source TEXT NOT NULL,
  album_id TEXT,
  favorite INTEGER NOT NULL DEFAULT 0,
  encrypted_file_path TEXT NOT NULL,
  thumbnail_path TEXT NOT NULL,
  thumbnail_nonce TEXT NOT NULL,
  photo_nonce TEXT NOT NULL,
  wrapped_dek TEXT NOT NULL,
  encryption_version INTEGER NOT NULL,
  sync_status TEXT NOT NULL,
  backup_status TEXT NOT NULL,
  checksum_sha256 TEXT NOT NULL,
  file_size INTEGER NOT NULL,
  mime_type TEXT NOT NULL,
  is_trashed INTEGER NOT NULL DEFAULT 0,
  trash_expires_at_ms INTEGER,
  deleted_tombstone_at_ms INTEGER
);''';

  static const String _albumsTable = '''
CREATE TABLE IF NOT EXISTS albums (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);''';

  static const String _tagsTable = '''
CREATE TABLE IF NOT EXISTS tags (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL
);''';

  static const String _photoTagsTable = '''
CREATE TABLE IF NOT EXISTS photo_tags (
  photo_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  PRIMARY KEY (photo_id, tag_id)
);''';

  static const String _thumbnailsTable = '''
CREATE TABLE IF NOT EXISTS thumbnails (
  id TEXT PRIMARY KEY,
  photo_id TEXT NOT NULL,
  encrypted_path TEXT NOT NULL,
  nonce TEXT NOT NULL,
  encryption_version INTEGER NOT NULL,
  width INTEGER NOT NULL,
  height INTEGER NOT NULL,
  checksum_sha256 TEXT NOT NULL
);''';

  static const String _syncStateTable = '''
CREATE TABLE IF NOT EXISTS sync_state (
  object_id TEXT PRIMARY KEY,
  object_type TEXT NOT NULL,
  local_version INTEGER NOT NULL,
  remote_version INTEGER,
  state TEXT NOT NULL,
  retry_count INTEGER NOT NULL DEFAULT 0,
  updated_at_ms INTEGER NOT NULL
);''';

  static const String _backupStateTable = '''
CREATE TABLE IF NOT EXISTS backup_state (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL
);''';

  static const String _encryptionVersionsTable = '''
CREATE TABLE IF NOT EXISTS encryption_versions (
  version INTEGER PRIMARY KEY,
  cipher TEXT NOT NULL,
  kdf TEXT NOT NULL,
  params_json TEXT NOT NULL,
  active INTEGER NOT NULL DEFAULT 0
);''';

  static const String _importJobsTable = '''
CREATE TABLE IF NOT EXISTS import_jobs (
  id TEXT PRIMARY KEY,
  source TEXT NOT NULL,
  total_items INTEGER NOT NULL,
  completed_items INTEGER NOT NULL,
  failed_items INTEGER NOT NULL,
  status TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);''';

  static const String _shareExportsTable = '''
CREATE TABLE IF NOT EXISTS share_exports (
  id TEXT PRIMARY KEY,
  photo_id TEXT,
  export_mode TEXT NOT NULL,
  package_path TEXT NOT NULL,
  expires_at_ms INTEGER,
  created_at_ms INTEGER NOT NULL
);''';

  static const String _trashItemsTable = '''
CREATE TABLE IF NOT EXISTS trash_items (
  photo_id TEXT PRIMARY KEY,
  moved_at_ms INTEGER NOT NULL,
  expires_at_ms INTEGER NOT NULL,
  sync_delete_pending INTEGER NOT NULL DEFAULT 0
);''';

  static const String _appSettingsTable = '''
CREATE TABLE IF NOT EXISTS app_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL
);''';

  static const String _securityEventsTable = '''
CREATE TABLE IF NOT EXISTS security_events (
  id TEXT PRIMARY KEY,
  event_type TEXT NOT NULL,
  severity TEXT NOT NULL,
  occurred_at_ms INTEGER NOT NULL,
  details_json TEXT
);''';

  static const String _photosIndexes = '''
CREATE INDEX IF NOT EXISTS idx_photos_imported ON photos(imported_time_ms DESC);
CREATE INDEX IF NOT EXISTS idx_photos_created ON photos(created_time_ms DESC);
CREATE INDEX IF NOT EXISTS idx_photos_album_created ON photos(album_id, created_time_ms DESC);
CREATE INDEX IF NOT EXISTS idx_photos_favorite_created ON photos(favorite, created_time_ms DESC);
CREATE INDEX IF NOT EXISTS idx_photos_sync_modified ON photos(sync_status, modified_time_ms);
CREATE INDEX IF NOT EXISTS idx_photos_trashed_expiry ON photos(is_trashed, trash_expires_at_ms);
''';

  static const String _tagsIndexes = '''
CREATE UNIQUE INDEX IF NOT EXISTS idx_tags_name ON tags(name);
''';

  static const String _photoTagsIndexes = '''
CREATE UNIQUE INDEX IF NOT EXISTS idx_photo_tags_pair ON photo_tags(photo_id, tag_id);
CREATE INDEX IF NOT EXISTS idx_photo_tags_tag ON photo_tags(tag_id);
''';

  static const String _trashIndexes = '''
CREATE INDEX IF NOT EXISTS idx_trash_expiry ON trash_items(expires_at_ms);
''';
}
