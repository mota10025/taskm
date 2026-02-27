const { McpServer } = require("@modelcontextprotocol/sdk/server/mcp.js");
const { StdioServerTransport } = require("@modelcontextprotocol/sdk/server/stdio.js");
const { z } = require("zod");

// ── API設定 ──
const API_URL = process.env.TASKM_API_URL || "https://taskm-api.motaka2308.workers.dev";
const API_KEY = process.env.TASKM_API_KEY || "";

async function api(path, options = {}) {
  const res = await fetch(`${API_URL}/api${path}`, {
    ...options,
    headers: {
      "X-API-Key": API_KEY,
      "Content-Type": "application/json",
      ...options.headers,
    },
  });
  const data = await res.json();
  if (!data.success) throw new Error(data.error || "API error");
  return data;
}

const server = new McpServer({
  name: "taskm",
  version: "2.0.0",
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
    const params = new URLSearchParams();
    if (show_all) params.set("show_all", "true");
    if (status) params.set("status", status);
    if (category) params.set("category", category);
    if (priority) params.set("priority", priority);
    params.set("include_subtasks", "true");

    const { data: tasks } = await api(`/tasks?${params}`);

    // 親タスクだけ表示
    const parentTasks = tasks.filter((t) => !t.parent_task_id);

    if (parentTasks.length === 0) {
      return { content: [{ type: "text", text: "タスクはありません。" }] };
    }

    const lines = parentTasks.map((t) => {
      const parts = [`[${t.id}] ${t.name}`];
      parts.push(`  ステータス: ${t.status}`);
      if (t.priority) parts.push(`  優先度: ${t.priority}`);
      if (t.category) parts.push(`  カテゴリ: ${t.category}`);
      if (t.due_date) parts.push(`  期限: ${t.due_date}`);
      if (t.tags) parts.push(`  タグ: ${t.tags}`);

      if (t.subtasks && t.subtasks.length > 0) {
        const done = t.subtasks.filter((s) => s.status === "完了").length;
        parts.push(`  サブタスク: ${done}/${t.subtasks.length}`);
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
    try {
      const { data: task } = await api(`/tasks/${id}`);

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

      if (task.subtasks && task.subtasks.length > 0) {
        lines.push("");
        lines.push("サブタスク:");
        task.subtasks.forEach((s) => {
          const mark = s.status === "完了" ? "[x]" : "[ ]";
          lines.push(`  ${mark} [${s.id}] ${s.name}`);
        });
      }

      return { content: [{ type: "text", text: lines.join("\n") }] };
    } catch {
      return { content: [{ type: "text", text: `タスク ${id} は見つかりません。` }] };
    }
  }
);

// タスク追加
server.tool(
  "add_task",
  "新しいタスクを追加する",
  {
    name: z.string().describe("タスク名"),
    priority: z.enum(["高", "中", "低"]).optional().describe("優先度"),
    category: z.string().optional().describe("カテゴリ（例: SPECRA, 業務委託, 個人 など自由入力）"),
    due_date: z.string().optional().describe("期限（YYYY-MM-DD形式）"),
    status: z.enum(["未着手", "進行中", "今日やる"]).optional().describe("ステータス（デフォルト: 未着手）"),
    tags: z.string().optional().describe("タグ（カンマ区切り）"),
    memo: z.string().optional().describe("メモ（Markdown対応）"),
    parent_task_id: z.number().optional().describe("親タスクID（サブタスクの場合）"),
  },
  async ({ name, priority, category, due_date, status, tags, memo, parent_task_id }) => {
    const body = { name };
    if (status) body.status = status;
    if (priority) body.priority = priority;
    if (category) body.category = category;
    if (due_date) body.due_date = due_date;
    if (tags) body.tags = tags;
    if (memo) body.memo = memo;
    if (parent_task_id) body.parent_task_id = parent_task_id;

    const { data } = await api("/tasks", {
      method: "POST",
      body: JSON.stringify(body),
    });

    return {
      content: [{ type: "text", text: `タスクを追加しました (ID: ${data.id})\n名前: ${name}${priority ? `\n優先度: ${priority}` : ""}${category ? `\nカテゴリ: ${category}` : ""}${due_date ? `\n期限: ${due_date}` : ""}` }],
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
    category: z.string().nullable().optional().describe("カテゴリ（nullで解除、自由入力）"),
    due_date: z.string().nullable().optional().describe("期限（YYYY-MM-DD、nullで解除）"),
    tags: z.string().nullable().optional().describe("タグ（nullで解除）"),
    memo: z.string().nullable().optional().describe("メモ（nullで解除）"),
  },
  async ({ id, name, status, priority, category, due_date, tags, memo }) => {
    const body = {};
    if (name !== undefined) body.name = name;
    if (status !== undefined) body.status = status;
    if (priority !== undefined) body.priority = priority;
    if (category !== undefined) body.category = category;
    if (due_date !== undefined) body.due_date = due_date;
    if (tags !== undefined) body.tags = tags;
    if (memo !== undefined) body.memo = memo;

    await api(`/tasks/${id}`, {
      method: "PUT",
      body: JSON.stringify(body),
    });

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
    // まずタスク名を取得
    let taskName = "";
    try {
      const { data: task } = await api(`/tasks/${id}`);
      taskName = task.name;
    } catch {}

    await api(`/tasks/${id}/complete`, {
      method: "POST",
      body: JSON.stringify({ complete_subtasks: complete_subtasks || false }),
    });

    return { content: [{ type: "text", text: `タスク ${id}「${taskName}」を完了にしました。` }] };
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
    // まずタスク名を取得
    let taskName = "";
    try {
      const { data: task } = await api(`/tasks/${id}`);
      taskName = task.name;
    } catch {}

    await api(`/tasks/${id}`, { method: "DELETE" });

    return { content: [{ type: "text", text: `タスク ${id}「${taskName}」を削除しました。` }] };
  }
);

// サーバー起動
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch(console.error);
