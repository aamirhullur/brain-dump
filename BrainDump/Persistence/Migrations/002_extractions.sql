PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS extractions (
  id TEXT PRIMARY KEY NOT NULL,
  fragment_id TEXT NOT NULL,
  asset_id TEXT,
  kind TEXT NOT NULL,
  content_text TEXT,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  FOREIGN KEY (fragment_id) REFERENCES fragments(id) ON DELETE CASCADE,
  FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_extractions_fragment_id ON extractions(fragment_id);
