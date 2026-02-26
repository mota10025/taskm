// ── 設定 ──
// config.js から API_URL と API_KEY を読み込む（gitignore対象）
// config.js が未定義の場合のフォールバック
if (typeof API_URL === "undefined" || typeof API_KEY === "undefined") {
  console.error("config.js が読み込まれていません。web/config.js を作成してください。");
}

const STATUSES = ["未着手", "進行中", "今日やる", "完了"];
const STATUS_COLORS = {
  未着手: "#9b9b9b",
  進行中: "#6ba3d6",
  今日やる: "#d4a76a",
  完了: "#7bc8a4",
};

// ── State ──
let allTasks = [];
let filters = { priorities: new Set(), categories: new Set() };
let editingTask = null;
let editingSubtasks = [];
let pollingTimer = null;

// ── API ──
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

async function fetchTasks() {
  try {
    const { data } = await api("/tasks?show_all=true&include_subtasks=true");
    allTasks = data;
    renderBoard();
    showError("");
  } catch (e) {
    showError(e.message);
  }
}

function showError(msg) {
  document.getElementById("error-message").textContent = msg;
}

// ── Render ──
function renderBoard() {
  const board = document.getElementById("kanban-board");
  board.innerHTML = "";

  for (const status of STATUSES) {
    const tasks = filterTasks(allTasks.filter((t) => t.status === status));
    board.appendChild(createColumn(status, tasks));
  }
}

function filterTasks(tasks) {
  return tasks.filter((t) => {
    if (filters.priorities.size > 0 && !filters.priorities.has(t.priority)) return false;
    if (filters.categories.size > 0 && !filters.categories.has(t.category)) return false;
    return true;
  });
}

function createColumn(status, tasks) {
  const col = document.createElement("div");
  col.className = "kanban-column";
  col.dataset.status = status;

  // Drag-over styling
  const color = STATUS_COLORS[status];
  col.style.setProperty("--col-color", color);

  col.innerHTML = `
    <div class="column-header">
      <div class="status-dot" style="background:${color}"></div>
      <span class="column-title">${status}</span>
      <span class="column-count">${tasks.length}</span>
    </div>
    <div class="card-list"></div>
    <div class="column-footer">
      <button class="add-task-btn" data-status="${status}">+ 新規タスク</button>
    </div>
  `;

  const cardList = col.querySelector(".card-list");
  for (const task of tasks) {
    cardList.appendChild(createCard(task));
  }

  // Drop target
  col.addEventListener("dragover", (e) => {
    e.preventDefault();
    col.classList.add("drag-over");
    col.style.outlineColor = `${color}80`;
  });
  col.addEventListener("dragleave", () => {
    col.classList.remove("drag-over");
  });
  col.addEventListener("drop", async (e) => {
    e.preventDefault();
    col.classList.remove("drag-over");
    const taskId = e.dataTransfer.getData("text/plain");
    if (taskId) {
      await moveTask(Number(taskId), status);
    }
  });

  // Add task button
  col.querySelector(".add-task-btn").addEventListener("click", () => {
    showAddForm(col, status);
  });

  return col;
}

function createCard(task) {
  const card = document.createElement("div");
  card.className = "task-card";
  card.draggable = true;
  card.dataset.id = task.id;

  // Drag events
  card.addEventListener("dragstart", (e) => {
    e.dataTransfer.setData("text/plain", String(task.id));
    card.classList.add("dragging");
  });
  card.addEventListener("dragend", () => {
    card.classList.remove("dragging");
  });

  // Click to edit
  card.addEventListener("click", () => openEditModal(task));

  let html = `<div class="card-name">${escapeHtml(task.name)}</div>`;

  // Badges
  const badges = [];
  if (task.priority) {
    badges.push(`<span class="badge badge-priority-${task.priority}">${task.priority}</span>`);
  }
  if (task.category) {
    badges.push(`<span class="badge badge-category badge-category-${task.category}">${task.category}</span>`);
  }
  if (task.memo) {
    badges.push(`<span class="card-memo-icon">📝</span>`);
  }
  if (badges.length > 0) {
    html += `<div class="card-badges">${badges.join("")}</div>`;
  }

  // Due date
  if (task.due_date) {
    const isOverdue = task.status !== "完了" && task.due_date < todayStr();
    html += `<div class="card-due${isOverdue ? " overdue" : ""}">📅 ${task.due_date.replace(/-/g, "/")}</div>`;
  }

  // Subtasks
  if (task.subtasks && task.subtasks.length > 0) {
    const done = task.subtasks.filter((s) => s.status === "完了").length;
    html += `<div class="card-subtasks">☐ サブタスク (${done}/${task.subtasks.length})</div>`;
  }

  card.innerHTML = html;
  return card;
}

// ── Add Task ──
function showAddForm(col, status) {
  const footer = col.querySelector(".column-footer");
  footer.innerHTML = `
    <div class="add-form">
      <input type="text" placeholder="タスク名..." autofocus>
      <div class="add-form-actions">
        <button class="btn-secondary add-cancel">キャンセル</button>
        <button class="btn-primary add-save">追加</button>
      </div>
    </div>
  `;

  const input = footer.querySelector("input");
  input.focus();

  const save = async () => {
    const name = input.value.trim();
    if (!name) return;
    try {
      await api("/tasks", {
        method: "POST",
        body: JSON.stringify({ name, status }),
      });
      await fetchTasks();
    } catch (e) {
      showError(e.message);
    }
  };

  footer.querySelector(".add-save").addEventListener("click", save);
  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter") save();
    if (e.key === "Escape") fetchTasks(); // re-render resets footer
  });
  footer.querySelector(".add-cancel").addEventListener("click", () => fetchTasks());
}

// ── Move Task (drag-and-drop) ──
async function moveTask(taskId, newStatus) {
  try {
    if (newStatus === "完了") {
      await api(`/tasks/${taskId}/complete`, {
        method: "POST",
        body: JSON.stringify({ complete_subtasks: false }),
      });
    } else {
      await api(`/tasks/${taskId}`, {
        method: "PUT",
        body: JSON.stringify({ status: newStatus }),
      });
    }
    await fetchTasks();
  } catch (e) {
    showError(e.message);
  }
}

// ── Edit Modal ──
function openEditModal(task) {
  editingTask = task;
  editingSubtasks = task.subtasks ? [...task.subtasks] : [];

  document.getElementById("edit-name").value = task.name;
  document.getElementById("edit-status").value = task.status;
  document.getElementById("edit-priority").value = task.priority || "";
  document.getElementById("edit-category").value = task.category || "";
  document.getElementById("edit-due-date").value = task.due_date || "";
  document.getElementById("edit-tags").value = task.tags || "";
  document.getElementById("edit-memo").value = task.memo || "";

  renderSubtaskList();
  document.getElementById("edit-modal").classList.remove("hidden");
}

function closeEditModal() {
  document.getElementById("edit-modal").classList.add("hidden");
  editingTask = null;
  editingSubtasks = [];
}

function renderSubtaskList() {
  const list = document.getElementById("subtask-list");
  const countEl = document.getElementById("subtask-count");
  list.innerHTML = "";

  if (editingSubtasks.length > 0) {
    const done = editingSubtasks.filter((s) => s.status === "完了").length;
    countEl.textContent = `(${done}/${editingSubtasks.length})`;
  } else {
    countEl.textContent = "";
  }

  for (const st of editingSubtasks) {
    const item = document.createElement("div");
    item.className = "subtask-item";
    item.innerHTML = `
      <input type="checkbox" class="subtask-check" ${st.status === "完了" ? "checked" : ""}>
      <span class="subtask-name ${st.status === "完了" ? "completed" : ""}">${escapeHtml(st.name)}</span>
      <button class="subtask-delete">🗑</button>
    `;
    item.querySelector(".subtask-check").addEventListener("change", async (e) => {
      const newStatus = e.target.checked ? "完了" : "未着手";
      try {
        if (newStatus === "完了") {
          await api(`/tasks/${st.id}/complete`, {
            method: "POST",
            body: JSON.stringify({}),
          });
        } else {
          await api(`/tasks/${st.id}`, {
            method: "PUT",
            body: JSON.stringify({ status: newStatus }),
          });
        }
        st.status = newStatus;
        renderSubtaskList();
      } catch (e) {
        showError(e.message);
      }
    });
    item.querySelector(".subtask-delete").addEventListener("click", async () => {
      try {
        await api(`/tasks/${st.id}`, { method: "DELETE" });
        editingSubtasks = editingSubtasks.filter((s) => s.id !== st.id);
        renderSubtaskList();
      } catch (e) {
        showError(e.message);
      }
    });
    list.appendChild(item);
  }
}

// Modal event listeners
document.getElementById("modal-close").addEventListener("click", closeEditModal);
document.getElementById("modal-cancel").addEventListener("click", closeEditModal);
document.querySelector(".modal-backdrop").addEventListener("click", closeEditModal);

document.getElementById("modal-save").addEventListener("click", async () => {
  if (!editingTask) return;
  try {
    const body = {
      name: document.getElementById("edit-name").value.trim(),
      status: document.getElementById("edit-status").value,
      priority: document.getElementById("edit-priority").value || null,
      category: document.getElementById("edit-category").value || null,
      due_date: document.getElementById("edit-due-date").value || null,
      tags: document.getElementById("edit-tags").value || null,
      memo: document.getElementById("edit-memo").value || null,
    };
    await api(`/tasks/${editingTask.id}`, {
      method: "PUT",
      body: JSON.stringify(body),
    });
    closeEditModal();
    await fetchTasks();
  } catch (e) {
    showError(e.message);
  }
});

document.getElementById("modal-delete").addEventListener("click", async () => {
  if (!editingTask) return;
  const msg = editingSubtasks.length > 0
    ? "サブタスクも一緒に削除されます。削除しますか？"
    : "このタスクを削除しますか？";
  if (!confirm(msg)) return;
  try {
    await api(`/tasks/${editingTask.id}`, { method: "DELETE" });
    closeEditModal();
    await fetchTasks();
  } catch (e) {
    showError(e.message);
  }
});

// Add subtask
document.getElementById("add-subtask-btn").addEventListener("click", addSubtask);
document.getElementById("new-subtask-name").addEventListener("keydown", (e) => {
  if (e.key === "Enter") addSubtask();
});

async function addSubtask() {
  const input = document.getElementById("new-subtask-name");
  const name = input.value.trim();
  if (!name || !editingTask) return;
  try {
    const { data } = await api("/tasks", {
      method: "POST",
      body: JSON.stringify({ name, parent_task_id: editingTask.id }),
    });
    editingSubtasks.push({ id: data.id, name, status: "未着手" });
    renderSubtaskList();
    input.value = "";
  } catch (e) {
    showError(e.message);
  }
}

// ── Filters ──
document.querySelectorAll(".filter-chip").forEach((chip) => {
  chip.addEventListener("click", () => {
    const type = chip.dataset.filter === "priority" ? "priorities" : "categories";
    const value = chip.dataset.value;
    if (filters[type].has(value)) {
      filters[type].delete(value);
      chip.classList.remove("active");
    } else {
      filters[type].add(value);
      chip.classList.add("active");
    }
    updateClearButton();
    renderBoard();
  });
});

document.getElementById("clear-filters").addEventListener("click", () => {
  filters.priorities.clear();
  filters.categories.clear();
  document.querySelectorAll(".filter-chip").forEach((c) => c.classList.remove("active"));
  updateClearButton();
  renderBoard();
});

function updateClearButton() {
  const btn = document.getElementById("clear-filters");
  btn.classList.toggle("hidden", filters.priorities.size === 0 && filters.categories.size === 0);
}

// ── Helpers ──
function escapeHtml(str) {
  const div = document.createElement("div");
  div.textContent = str;
  return div.innerHTML;
}

function todayStr() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

// ── Init ──
fetchTasks();
pollingTimer = setInterval(fetchTasks, 5000);
