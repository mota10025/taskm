const { McpServer } = require("@modelcontextprotocol/sdk/server/mcp.js");
const { StdioServerTransport } = require("@modelcontextprotocol/sdk/server/stdio.js");
const { z } = require("zod");
const Database = require("better-sqlite3");
const path = require("path");
const os = require("os");

const DB_PATH = path.join(os.homedir(), "workspace", "task", "tasks.db");

// 永続接続（better-sqlite3は同期的なので並行ツール呼び出しは自動的に直列化される）
const db = new Database(DB_PATH);
db.pragma("foreign_keys = ON");
db.pragma("journal_mode = WAL");
db.pragma("busy_timeout = 10000");
db.pragma("synchronous = NORMAL");

// クリーンシャットダウン
process.on("exit", () => db.close());
process.on("SIGINT", () => { db.close(); process.exit(0); });
process.on("SIGTERM", () => { db.close(); process.exit(0); });

function formatDate() {
  const now = new Date();
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, "0");
  const d = String(now.getDate()).padStart(2, "0");
  const h = String(now.getHours()).padStart(2, "0");
  const mi = String(now.getMinutes()).padStart(2, "0");
  const s = String(now.getSeconds()).padStart(2, "0");
  return { date: `${y}-${m}-${d}`, datetime: `${y}-${m}-${d} ${h}:${mi}:${s}` };
}

const server = new McpServer({
  name: "taskm",
  version: "1.0.0",
});

// タスク一覧
server.tool(
  "list_tasks",
  "タスク一覧を表示する。デフォルトは未完了のみ。",
  {
    show_all: z.boolean().optional().describe("完了・アーカイブも含めて全件表示"),
    status: z.string().optional().describe("ステータスでフィルタ（未着手/進行中/今日やる/完了/アーカイブ）"),
    category: z.string().optional().describe("カテゴリでフィルタ（SPECRA/業務委託/個人）"),
    priority: z.string().optional().describe("優先度でフィルタ（高/中/低）"),
  },
  async ({ show_all, status, category, priority }) => {
    let sql = "SELECT * FROM tasks WHERE parent_task_id IS NULL";
    const params = [];

    if (!show_all) {
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

    const tasks = db.prepare(sql).all(...params);

    if (tasks.length === 0) {
      return { content: [{ type: "text", text: "タスクはありません。" }] };
    }

    const lines = tasks.map((t) => {
      const parts = [`[${t.id}] ${t.name}`];
      parts.push(`  ステータス: ${t.status}`);
      if (t.priority) parts.push(`  優先度: ${t.priority}`);
      if (t.category) parts.push(`  カテゴリ: ${t.category}`);
      if (t.due_date) parts.push(`  期限: ${t.due_date}`);
      if (t.tags) parts.push(`  タグ: ${t.tags}`);

      const subtasks = db.prepare("SELECT * FROM tasks WHERE parent_task_id = ? ORDER BY id").all(t.id);
      if (subtasks.length > 0) {
        const done = subtasks.filter((s) => s.status === "完了").length;
        parts.push(`  サブタスク: ${done}/${subtasks.length}`);
      }
      return parts.join("\n");
    });

    return { content: [{ type: "text", text: lines.join("\n\n") }] };
  }
);

// タスク詳細
server.tool(
  "show_task",
  "タスクの詳細を表示する",
  {
    id: z.number().describe("タスクID"),
  },
  async ({ id }) => {
    const task = db.prepare("SELECT * FROM tasks WHERE id = ?").get(id);
    if (!task) {
      return { content: [{ type: "text", text: `タスク ${id} は見つかりません。` }] };
    }

    const lines = [
      `[${task.id}] ${task.name}`,
      `ステータス: ${task.status}`,
      `優先度: ${task.priority || "なし"}`,
      `カテゴリ: ${task.category || "なし"}`,
      `期限: ${task.due_date || "なし"}`,
      `タグ: ${task.tags || "なし"}`,
      `メモ: ${task.memo || "なし"}`,
      `作成日: ${task.created_at || "不明"}`,
      `更新日: ${task.updated_at || "不明"}`,
    ];

    if (task.completed_date) {
      lines.push(`完了日: ${task.completed_date}`);
    }

    const subtasks = db.prepare("SELECT * FROM tasks WHERE parent_task_id = ? ORDER BY id").all(id);
    if (subtasks.length > 0) {
      lines.push("");
      lines.push("サブタスク:");
      subtasks.forEach((s) => {
        const mark = s.status === "完了" ? "[x]" : "[ ]";
        lines.push(`  ${mark} [${s.id}] ${s.name}`);
      });
    }

    return { content: [{ type: "text", text: lines.join("\n") }] };
  }
);

// タスク追加
server.tool(
  "add_task",
  "新しいタスクを追加する",
  {
    name: z.string().describe("タスク名"),
    priority: z.enum(["高", "中", "低"]).optional().describe("優先度"),
    category: z.enum(["SPECRA", "業務委託", "個人"]).optional().describe("カテゴリ"),
    due_date: z.string().optional().describe("期限（YYYY-MM-DD形式）"),
    status: z.enum(["未着手", "進行中", "今日やる"]).optional().describe("ステータス（デフォルト: 未着手）"),
    tags: z.string().optional().describe("タグ（カンマ区切り）"),
    memo: z.string().optional().describe("メモ（Markdown対応）"),
    parent_task_id: z.number().optional().describe("親タスクID（サブタスクの場合）"),
  },
  async ({ name, priority, category, due_date, status, tags, memo, parent_task_id }) => {
    const { datetime } = formatDate();
    const result = db
      .prepare(
        `INSERT INTO tasks (name, status, priority, category, due_date, parent_task_id, tags, memo, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
      )
      .run(
        name,
        status || "未着手",
        priority || null,
        category || null,
        due_date || null,
        parent_task_id || null,
        tags || null,
        memo || null,
        datetime,
        datetime
      );

    return {
      content: [{ type: "text", text: `タスクを追加しました (ID: ${result.lastInsertRowid})\n名前: ${name}${priority ? `\n優先度: ${priority}` : ""}${category ? `\nカテゴリ: ${category}` : ""}${due_date ? `\n期限: ${due_date}` : ""}` }],
    };
  }
);

// タスク更新
server.tool(
  "update_task",
  "既存のタスクを更新する",
  {
    id: z.number().describe("タスクID"),
    name: z.string().optional().describe("タスク名"),
    status: z.enum(["未着手", "進行中", "今日やる", "完了", "アーカイブ"]).optional().describe("ステータス"),
    priority: z.enum(["高", "中", "低"]).nullable().optional().describe("優先度（nullで解除）"),
    category: z.enum(["SPECRA", "業務委託", "個人"]).nullable().optional().describe("カテゴリ（nullで解除）"),
    due_date: z.string().nullable().optional().describe("期限（YYYY-MM-DD、nullで解除）"),
    tags: z.string().nullable().optional().describe("タグ（nullで解除）"),
    memo: z.string().nullable().optional().describe("メモ（nullで解除）"),
  },
  async ({ id, name, status, priority, category, due_date, tags, memo }) => {
    const task = db.prepare("SELECT * FROM tasks WHERE id = ?").get(id);
    if (!task) {
      return { content: [{ type: "text", text: `タスク ${id} は見つかりません。` }] };
    }

    const { date, datetime } = formatDate();
    const sets = ["updated_at = ?"];
    const params = [datetime];

    if (name !== undefined) { sets.push("name = ?"); params.push(name); }
    if (status !== undefined) {
      sets.push("status = ?");
      params.push(status);
      if (status === "完了") {
        sets.push("completed_date = ?");
        params.push(date);
      }
    }
    if (priority !== undefined) { sets.push("priority = ?"); params.push(priority); }
    if (category !== undefined) { sets.push("category = ?"); params.push(category); }
    if (due_date !== undefined) { sets.push("due_date = ?"); params.push(due_date); }
    if (tags !== undefined) { sets.push("tags = ?"); params.push(tags); }
    if (memo !== undefined) { sets.push("memo = ?"); params.push(memo); }

    params.push(id);
    db.prepare(`UPDATE tasks SET ${sets.join(", ")} WHERE id = ?`).run(...params);

    return { content: [{ type: "text", text: `タスク ${id} を更新しました。` }] };
  }
);

// タスク完了
server.tool(
  "complete_task",
  "タスクを完了にする",
  {
    id: z.number().describe("タスクID"),
    complete_subtasks: z.boolean().optional().describe("サブタスクも一緒に完了にする"),
  },
  async ({ id, complete_subtasks }) => {
    const task = db.prepare("SELECT * FROM tasks WHERE id = ?").get(id);
    if (!task) {
      return { content: [{ type: "text", text: `タスク ${id} は見つかりません。` }] };
    }

    const { date, datetime } = formatDate();

    const completeOp = db.transaction(() => {
      if (complete_subtasks) {
        db.prepare(
          "UPDATE tasks SET status = '完了', completed_date = ?, updated_at = ? WHERE parent_task_id = ? AND status != '完了'"
        ).run(date, datetime, id);
      }
      db.prepare(
        "UPDATE tasks SET status = '完了', completed_date = ?, updated_at = ? WHERE id = ?"
      ).run(date, datetime, id);
    });
    completeOp();

    return { content: [{ type: "text", text: `タスク ${id}「${task.name}」を完了にしました。` }] };
  }
);

// タスク削除
server.tool(
  "delete_task",
  "タスクを削除する（サブタスクも一緒に削除される）",
  {
    id: z.number().describe("タスクID"),
  },
  async ({ id }) => {
    const task = db.prepare("SELECT * FROM tasks WHERE id = ?").get(id);
    if (!task) {
      return { content: [{ type: "text", text: `タスク ${id} は見つかりません。` }] };
    }

    const deleteOp = db.transaction(() => {
      db.prepare("DELETE FROM tasks WHERE parent_task_id = ?").run(id);
      db.prepare("DELETE FROM tasks WHERE id = ?").run(id);
    });
    deleteOp();

    return { content: [{ type: "text", text: `タスク ${id}「${task.name}」を削除しました。` }] };
  }
);

// サーバー起動
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch(console.error);
