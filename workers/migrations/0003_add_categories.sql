CREATE TABLE IF NOT EXISTS categories (
  name TEXT PRIMARY KEY,
  color TEXT NOT NULL,
  created_at TEXT,
  updated_at TEXT
);

INSERT INTO categories (name, color, created_at, updated_at) VALUES
  ('SPECRA', '#82b5d6', datetime('now'), datetime('now')),
  ('業務委託', '#d4c07a', datetime('now'), datetime('now')),
  ('個人', '#b8a0d2', datetime('now'), datetime('now'));
