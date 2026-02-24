import { Hono } from "hono";
import type { Bindings, Task, TaskWithSubtasks } from "../types";

const tasks = new Hono<{ Bindings: Bindings }>();

function nowJST() {
  const now = new Date();
  const jst = new Date(now.getTime() + 9 * 60 * 60 * 1000);
  const y = jst.getUTCFullYear();
  const m = String(jst.getUTCMonth() + 1).padStart(2, "0");
  const d = String(jst.getUTCDate()).padStart(2, "0");
  const h = String(jst.getUTCHours()).padStart(2, "0");
  const mi = String(jst.getUTCMinutes()).padStart(2, "0");
  const s = String(jst.getUTCSeconds()).padStart(2, "0");
  return { date: `${y}-${m}-${d}`, datetime: `${y}-${m}-${d} ${h}:${mi}:${s}` };
}

// GET /tasks - タスク一覧
tasks.get("/tasks", async (c) => {
  const showAll = c.req.query("show_all") === "true";
  const status = c.req.query("status");
  const category = c.req.query("category");
  const priority = c.req.query("priority");

  let sql = "SELECT * FROM tasks WHERE parent_task_id IS NULL";
  const params: string[] = [];

  if (!showAll) {
    sql += " AND status NOT IN ('完了', 'アーカイブ')";
  }
  if (status) {
    sql += " AND status = ?";
    params.push(status);
  }
  if (category) {
    sql += " AND category = ?";
    params.push(category);
  }
  if (priority) {
    sql += " AND priority = ?";
    params.push(priority);
  }

  sql += ` ORDER BY
    CASE priority WHEN '高' THEN 0 WHEN '中' THEN 1 WHEN '低' THEN 2 ELSE 3 END,
    CASE WHEN due_date IS NULL THEN 1 ELSE 0 END,
    due_date`;

  const stmt = c.env.DB.prepare(sql);
  const { results: parentTasks } = await (params.length > 0
    ? stmt.bind(...params)
    : stmt
  ).all<Task>();

  // サブタスクを一括取得
  const { results: allSubtasks } = await c.env.DB.prepare(
    "SELECT * FROM tasks WHERE parent_task_id IS NOT NULL ORDER BY id"
  ).all<Task>();

  const subtaskMap = new Map<number, Task[]>();
  for (const st of allSubtasks) {
    const list = subtaskMap.get(st.parent_task_id!) || [];
    list.push(st);
    subtaskMap.set(st.parent_task_id!, list);
  }

  const data: TaskWithSubtasks[] = parentTasks.map((t) => ({
    ...t,
    subtasks: subtaskMap.get(t.id) || [],
  }));

  return c.json({ success: true, data });
});

// GET /tasks/:id - タスク詳細
tasks.get("/tasks/:id", async (c) => {
  const id = Number(c.req.param("id"));
  const task = await c.env.DB.prepare("SELECT * FROM tasks WHERE id = ?")
    .bind(id)
    .first<Task>();

  if (!task) {
    return c.json({ success: false, error: `タスク ${id} は見つかりません。` }, 404);
  }

  const { results: subtasks } = await c.env.DB.prepare(
    "SELECT * FROM tasks WHERE parent_task_id = ? ORDER BY id"
  )
    .bind(id)
    .all<Task>();

  return c.json({ success: true, data: { ...task, subtasks } });
});

// POST /tasks - タスク追加
tasks.post("/tasks", async (c) => {
  const body = await c.req.json<{
    name: string;
    status?: string;
    priority?: string;
    category?: string;
    due_date?: string;
    tags?: string;
    memo?: string;
    parent_task_id?: number;
  }>();

  if (!body.name) {
    return c.json({ success: false, error: "name は必須です。" }, 400);
  }

  const { datetime } = nowJST();
  const result = await c.env.DB.prepare(
    `INSERT INTO tasks (name, status, priority, category, due_date, parent_task_id, tags, memo, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  )
    .bind(
      body.name,
      body.status || "未着手",
      body.priority || null,
      body.category || null,
      body.due_date || null,
      body.parent_task_id || null,
      body.tags || null,
      body.memo || null,
      datetime,
      datetime
    )
    .run();

  return c.json(
    {
      success: true,
      data: { id: result.meta.last_row_id },
      message: `タスクを追加しました (ID: ${result.meta.last_row_id})`,
    },
    201
  );
});

// PUT /tasks/:id - タスク更新
tasks.put("/tasks/:id", async (c) => {
  const id = Number(c.req.param("id"));
  const task = await c.env.DB.prepare("SELECT * FROM tasks WHERE id = ?")
    .bind(id)
    .first<Task>();

  if (!task) {
    return c.json({ success: false, error: `タスク ${id} は見つかりません。` }, 404);
  }

  const body = await c.req.json<{
    name?: string;
    status?: string;
    priority?: string | null;
    category?: string | null;
    due_date?: string | null;
    tags?: string | null;
    memo?: string | null;
  }>();

  const { date, datetime } = nowJST();
  const sets: string[] = ["updated_at = ?"];
  const params: (string | number | null)[] = [datetime];

  if (body.name !== undefined) {
    sets.push("name = ?");
    params.push(body.name);
  }
  if (body.status !== undefined) {
    sets.push("status = ?");
    params.push(body.status);
    if (body.status === "完了") {
      sets.push("completed_date = ?");
      params.push(date);
    }
  }
  if (body.priority !== undefined) {
    sets.push("priority = ?");
    params.push(body.priority);
  }
  if (body.category !== undefined) {
    sets.push("category = ?");
    params.push(body.category);
  }
  if (body.due_date !== undefined) {
    sets.push("due_date = ?");
    params.push(body.due_date);
  }
  if (body.tags !== undefined) {
    sets.push("tags = ?");
    params.push(body.tags);
  }
  if (body.memo !== undefined) {
    sets.push("memo = ?");
    params.push(body.memo);
  }

  params.push(id);
  await c.env.DB.prepare(`UPDATE tasks SET ${sets.join(", ")} WHERE id = ?`)
    .bind(...params)
    .run();

  return c.json({ success: true, message: `タスク ${id} を更新しました。` });
});

// POST /tasks/:id/complete - タスク完了
tasks.post("/tasks/:id/complete", async (c) => {
  const id = Number(c.req.param("id"));
  const task = await c.env.DB.prepare("SELECT * FROM tasks WHERE id = ?")
    .bind(id)
    .first<Task>();

  if (!task) {
    return c.json({ success: false, error: `タスク ${id} は見つかりません。` }, 404);
  }

  const body = await c.req.json<{ complete_subtasks?: boolean }>().catch(() => ({}));
  const { date, datetime } = nowJST();

  const stmts: D1PreparedStatement[] = [];

  if (body.complete_subtasks) {
    stmts.push(
      c.env.DB.prepare(
        "UPDATE tasks SET status = '完了', completed_date = ?, updated_at = ? WHERE parent_task_id = ? AND status != '完了'"
      ).bind(date, datetime, id)
    );
  }

  stmts.push(
    c.env.DB.prepare(
      "UPDATE tasks SET status = '完了', completed_date = ?, updated_at = ? WHERE id = ?"
    ).bind(date, datetime, id)
  );

  await c.env.DB.batch(stmts);

  return c.json({
    success: true,
    message: `タスク ${id}「${task.name}」を完了にしました。`,
  });
});

// DELETE /tasks/:id - タスク削除
tasks.delete("/tasks/:id", async (c) => {
  const id = Number(c.req.param("id"));
  const task = await c.env.DB.prepare("SELECT * FROM tasks WHERE id = ?")
    .bind(id)
    .first<Task>();

  if (!task) {
    return c.json({ success: false, error: `タスク ${id} は見つかりません。` }, 404);
  }

  await c.env.DB.batch([
    c.env.DB.prepare("DELETE FROM tasks WHERE parent_task_id = ?").bind(id),
    c.env.DB.prepare("DELETE FROM tasks WHERE id = ?").bind(id),
  ]);

  return c.json({
    success: true,
    message: `タスク ${id}「${task.name}」を削除しました。`,
  });
});

export { tasks };
