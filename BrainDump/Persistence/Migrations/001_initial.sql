PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS fragments (
  id TEXT PRIMARY KEY NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  source_type TEXT NOT NULL,
  title TEXT,
  user_note TEXT,
  status TEXT NOT NULL,
  primary_asset_id TEXT,
  deleted_at TEXT,
  FOREIGN KEY (primary_asset_id) REFERENCES assets(id)
);

CREATE TABLE IF NOT EXISTS assets (
  id TEXT PRIMARY KEY NOT NULL,
  fragment_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  sha256 TEXT NOT NULL,
  original_filename TEXT,
  mime_type TEXT,
  byte_size INTEGER NOT NULL,
  local_path TEXT,
  source_url TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (fragment_id) REFERENCES fragments(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_assets_fragment_id ON assets(fragment_id);
CREATE INDEX IF NOT EXISTS idx_fragments_created_at ON fragments(created_at);

CREATE TABLE IF NOT EXISTS jobs (
  id TEXT PRIMARY KEY NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  type TEXT NOT NULL,
  status TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  max_attempts INTEGER NOT NULL DEFAULT 3,
  available_at TEXT NOT NULL,
  started_at TEXT,
  finished_at TEXT,
  fragment_id TEXT,
  asset_id TEXT,
  payload_json TEXT NOT NULL DEFAULT '{}',
  last_error TEXT,
  FOREIGN KEY (fragment_id) REFERENCES fragments(id) ON DELETE CASCADE,
  FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_jobs_status_available ON jobs(status, available_at);
CREATE INDEX IF NOT EXISTS idx_jobs_fragment_id ON jobs(fragment_id);
