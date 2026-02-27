import { Hono } from "hono";
import { z } from "zod";
import type { Bindings, Task, TaskWithSubtasks, Category } from "../types";
import { nowJST } from "../utils/date";

// バリデーションスキーマ
const statusEnum = z.enum(["未着手", "進行中", "今日やる", "完了", "アーカイブ"]);
const priorityEnum = z.enum(["高", "中", "低"]);
const categoryEnum = z.string().min(1);
const dateStr = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);

const createTaskSchema = z.object({
  name: z.string().min(1, "name は必須です。"),
  status: statusEnum.optional(),
  priority: priorityEnum.nullable().optional(),
  category: categoryEnum.nullable().optional(),
  due_date: dateStr.nullable().optional(),
  tags: z.string().nullable().optional(),
  memo: z.string().nullable().optional(),
  parent_task_id: z.number().int().positive().nullable().optional(),
});

const updateTaskSchema = z.object({
  name: z.string().min(1).optional(),
  status: statusEnum.optional(),
  priority: priorityEnum.nullable().optional(),
  category: categoryEnum.nullable().optional(),
  due_date: dateStr.nullable().optional(),
  tags: z.string().nullable().optional(),
  memo: z.string().nullable().optional(),
  sort_order: z.number().int().optional(),
});

const querySchema = z.object({
  show_all: z.enum(["true", "false"]).optional(),
  status: statusEnum.optional(),
  category: categoryEnum.optional(),
  priority: priorityEnum.optional(),
});

const tasks = new Hono<{ Bindings: Bindings }>();

// GET /tasks - タスク一覧
tasks.get("/tasks", async (c) => {
  const queryResult = querySchema.safeParse({
    show_all: c.req.query("show_all") || undefined,
    status: c.req.query("status") || undefined,
    category: c.req.query("category") || undefined,
    priority: c.req.query("priority") || undefined,
  });
  if (!queryResult.success) {
    return c.json({ success: false, error: queryResult.error.issues[0].message }, 400);
  }
  const { show_all, status, category, priority } = queryResult.data;
  const showAll = show_all === "true";

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

  sql += ` ORDER BY sort_order ASC, created_at ASC`;

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

  // カテゴリ一覧も一緒に返す
  const { results: cats } = await c.env.DB.prepare(
    "SELECT * FROM categories ORDER BY created_at ASC"
  ).all<Category>();

  return c.json({ success: true, data, categories: cats });
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
  const raw = await c.req.json().catch(() => null);
  if (!raw) {
    return c.json({ success: false, error: "無効なJSONです。" }, 400);
  }
  const parsed = createTaskSchema.safeParse(raw);
  if (!parsed.success) {
    return c.json({ success: false, error: parsed.error.issues[0].message }, 400);
  }
  const body = parsed.data;

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

  const raw = await c.req.json().catch(() => null);
  if (!raw) {
    return c.json({ success: false, error: "無効なJSONです。" }, 400);
  }
  const parsed = updateTaskSchema.safeParse(raw);
  if (!parsed.success) {
    return c.json({ success: false, error: parsed.error.issues[0].message }, 400);
  }
  const body = parsed.data;

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
  if (body.sort_order !== undefined) {
    sets.push("sort_order = ?");
    params.push(body.sort_order);
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

// PUT /tasks/reorder - タスク並び替え
const reorderSchema = z.object({
  orders: z.array(
    z.object({
      id: z.number().int().positive(),
      sort_order: z.number().int(),
    })
  ),
});

tasks.put("/tasks-reorder", async (c) => {
  const raw = await c.req.json().catch(() => null);
  if (!raw) {
    return c.json({ success: false, error: "無効なJSONです。" }, 400);
  }
  const parsed = reorderSchema.safeParse(raw);
  if (!parsed.success) {
    return c.json({ success: false, error: parsed.error.issues[0].message }, 400);
  }

  const { orders } = parsed.data;
  const { datetime } = nowJST();

  const stmts = orders.map((o) =>
    c.env.DB.prepare("UPDATE tasks SET sort_order = ?, updated_at = ? WHERE id = ?").bind(
      o.sort_order,
      datetime,
      o.id
    )
  );

  await c.env.DB.batch(stmts);

  return c.json({ success: true, message: "並び替えを保存しました。" });
});

export { tasks };
