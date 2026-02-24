CREATE TABLE IF NOT EXISTS tasks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT '未着手',
  priority TEXT,
  category TEXT,
  due_date TEXT,
  completed_date TEXT,
  parent_task_id INTEGER,
  tags TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  memo TEXT,
  FOREIGN KEY (parent_task_id) REFERENCES tasks(id)
);
