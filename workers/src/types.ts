export type Bindings = {
  DB: D1Database;
  API_KEY: string;
  OAUTH_KV: KVNamespace;
  ALLOWED_EMAIL: string;
  ALLOWED_ORIGINS?: string; // カンマ区切りの許可オリジン
};

export interface Task {
  id: number;
  name: string;
  status: string;
  priority: string | null;
  category: string | null;
  due_date: string | null;
  completed_date: string | null;
  parent_task_id: number | null;
  tags: string | null;
  memo: string | null;
  sort_order: number;
  created_at: string;
  updated_at: string;
}

export interface TaskWithSubtasks extends Task {
  subtasks: Task[];
}

export interface Category {
  name: string;
  color: string;
  text_color: string;
  created_at: string;
  updated_at: string;
}
