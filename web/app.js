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
let categoryColors = {}; // { "SPECRA": { color: "#82b5d6", text_color: "#2a2a2a" }, ... } - APIから取得
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
    const res = await api("/tasks?show_all=true&include_subtasks=true");
    allTasks = res.data;
    // カテゴリ色をレスポンスから取得
    if (res.categories) {
      categoryColors = {};
      res.categories.forEach((c) => { categoryColors[c.name] = { color: c.color, text_color: c.text_color || "#2a2a2a" }; });
    }
    updateDynamicFilters();
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

  // Drop target – カード間の並び替えに対応
  cardList.addEventListener("dragover", (e) => {
    e.preventDefault();
    col.classList.add("drag-over");
    col.style.outlineColor = `${color}80`;

    // ドロップ位置インジケーター
    clearDropIndicators();
    const afterCard = getDragAfterElement(cardList, e.clientY);
    const indicator = document.createElement("div");
    indicator.className = "drop-indicator";
    if (afterCard) {
      cardList.insertBefore(indicator, afterCard);
    } else {
      cardList.appendChild(indicator);
    }
  });
  cardList.addEventListener("dragleave", (e) => {
    // cardList 外に出た場合のみクリア
    if (!cardList.contains(e.relatedTarget)) {
      col.classList.remove("drag-over");
      clearDropIndicators();
    }
  });
  cardList.addEventListener("drop", async (e) => {
    e.preventDefault();
    col.classList.remove("drag-over");
    clearDropIndicators();
    const taskId = e.dataTransfer.getData("text/plain");
    if (!taskId) return;

    const afterCard = getDragAfterElement(cardList, e.clientY);
    await moveAndReorder(Number(taskId), status, cardList, afterCard);
  });

  // カラム全体のフォールバック（カードリスト外にドロップした場合）
  col.addEventListener("dragover", (e) => {
    e.preventDefault();
  });
  col.addEventListener("drop", async (e) => {
    // cardList 内の drop で処理されなかった場合のフォールバック
    if (e.defaultPrevented) return;
    e.preventDefault();
    col.classList.remove("drag-over");
    clearDropIndicators();
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
    const catInfo = categoryColors[task.category] || { color: "#8a8a8a", text_color: "#2a2a2a" };
    badges.push(`<span class="badge badge-category" style="background:${catInfo.color};color:${catInfo.text_color}">${escapeHtml(task.category)}</span>`);
  }
  if (task.memo) {
    badges.push(`<span class="card-memo-icon">📝</span>`);
  }
  if (badges.length > 0) {
    html += `<div class="card-badges">${badges.join("")}</div>`;
  }

  // Tags
  if (task.tags) {
    const tagList = task.tags.split(",").map((t) => t.trim()).filter(Boolean);
    if (tagList.length > 0) {
      html += `<div class="card-tags">${tagList.map((t) => `<span class="tag">${escapeHtml(t)}</span>`).join("")}</div>`;
    }
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
    // 移動先カラムの末尾に追加するためのsort_orderを算出
    const tasksInTarget = allTasks.filter((t) => t.status === newStatus && t.id !== taskId);
    const maxOrder = tasksInTarget.reduce((max, t) => Math.max(max, t.sort_order || 0), -1);
    const newSortOrder = maxOrder + 1;

    if (newStatus === "完了") {
      await api(`/tasks/${taskId}/complete`, {
        method: "POST",
        body: JSON.stringify({ complete_subtasks: false }),
      });
    } else {
      await api(`/tasks/${taskId}`, {
        method: "PUT",
        body: JSON.stringify({ status: newStatus, sort_order: newSortOrder }),
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
  resetCategoryInput();
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
    const category = getCategoryValue();
    // カスタム入力で新規カテゴリの場合、categoriesテーブルにも登録
    if (category && !categoryColors[category]) {
      await api("/categories", {
        method: "POST",
        body: JSON.stringify({ name: category, color: "#8a8a8a" }),
      });
    }
    const body = {
      name: document.getElementById("edit-name").value.trim(),
      status: document.getElementById("edit-status").value,
      priority: document.getElementById("edit-priority").value || null,
      category,
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

// ── Category custom input toggle ──
const categorySelect = document.getElementById("edit-category");
const categoryCustom = document.getElementById("edit-category-custom");
const categoryToggle = document.getElementById("toggle-category-input");

categoryToggle.addEventListener("click", () => {
  const isCustomMode = !categoryCustom.classList.contains("hidden");
  if (isCustomMode) {
    // カスタム → select に戻す
    categoryCustom.classList.add("hidden");
    categorySelect.classList.remove("hidden");
    categoryToggle.textContent = "+ 新規カテゴリ";
    categoryCustom.value = "";
  } else {
    // select → カスタム入力に切り替え
    categorySelect.classList.add("hidden");
    categoryCustom.classList.remove("hidden");
    categoryToggle.textContent = "一覧から選択";
    categoryCustom.focus();
  }
});

function getCategoryValue() {
  const isCustomMode = !categoryCustom.classList.contains("hidden");
  if (isCustomMode) {
    return categoryCustom.value.trim() || null;
  }
  return categorySelect.value || null;
}

function resetCategoryInput() {
  categoryCustom.classList.add("hidden");
  categorySelect.classList.remove("hidden");
  categoryToggle.textContent = "+ 新規カテゴリ";
  categoryCustom.value = "";
}

// ── Dynamic Filters ──
function updateDynamicFilters() {
  // DBのcategoriesテーブルに登録されているカテゴリのみ使用
  const allCategories = Object.keys(categoryColors);

  // ドロップダウンメニューを再生成
  renderCategoryDropdown(allCategories);

  // 編集モーダルの select も更新
  const select = document.getElementById("edit-category");
  if (select) {
    const currentValue = select.value;
    select.innerHTML = '<option value="">なし</option>';
    for (const cat of allCategories) {
      const opt = document.createElement("option");
      opt.value = cat;
      opt.textContent = cat;
      select.appendChild(opt);
    }
    select.value = currentValue;
  }
}

function renderCategoryDropdown(allCategories) {
  const menu = document.getElementById("category-dropdown-menu");
  const countBadge = document.getElementById("category-selected-count");
  if (!menu) return;

  menu.innerHTML = "";
  for (const cat of allCategories) {
    const catInfo = categoryColors[cat] || { color: "#8a8a8a", text_color: "#2a2a2a" };
    const isSelected = filters.categories.has(cat);
    const item = document.createElement("div");
    item.className = "category-dropdown-item";
    item.innerHTML = `
      <span class="category-dropdown-check${isSelected ? " checked" : ""}">${isSelected ? "✓" : ""}</span>
      <span class="category-dropdown-dot" style="background:${catInfo.color}"></span>
      <span>${escapeHtml(cat)}</span>
    `;
    item.addEventListener("click", (e) => {
      e.stopPropagation();
      if (filters.categories.has(cat)) {
        filters.categories.delete(cat);
      } else {
        filters.categories.add(cat);
      }
      updateClearButton();
      renderBoard();
      // メニュー内のチェック状態を更新
      renderCategoryDropdown(allCategories);
    });
    menu.appendChild(item);
  }

  // 選択数バッジ更新
  if (filters.categories.size > 0) {
    countBadge.textContent = filters.categories.size;
    countBadge.classList.remove("hidden");
  } else {
    countBadge.classList.add("hidden");
  }
}

// ── Filters ──
// 優先度チップ
document.querySelectorAll('.filter-chip[data-filter="priority"]').forEach((chip) => {
  chip.addEventListener("click", () => {
    const value = chip.dataset.value;
    if (filters.priorities.has(value)) {
      filters.priorities.delete(value);
      chip.classList.remove("active");
    } else {
      filters.priorities.add(value);
      chip.classList.add("active");
    }
    updateClearButton();
    renderBoard();
  });
});

// カテゴリドロップダウン開閉
document.getElementById("category-dropdown-btn").addEventListener("click", (e) => {
  e.stopPropagation();
  const menu = document.getElementById("category-dropdown-menu");
  menu.classList.toggle("hidden");
});

// メニュー外クリックで閉じる
document.addEventListener("click", (e) => {
  const menu = document.getElementById("category-dropdown-menu");
  const dropdown = document.querySelector(".category-dropdown");
  if (dropdown && !dropdown.contains(e.target)) {
    menu.classList.add("hidden");
  }
});

document.getElementById("clear-filters").addEventListener("click", () => {
  filters.priorities.clear();
  filters.categories.clear();
  document.querySelectorAll(".filter-chip").forEach((c) => c.classList.remove("active"));
  // ドロップダウンのバッジも更新
  const countBadge = document.getElementById("category-selected-count");
  if (countBadge) countBadge.classList.add("hidden");
  updateClearButton();
  renderBoard();
});

function updateClearButton() {
  const btn = document.getElementById("clear-filters");
  btn.classList.toggle("hidden", filters.priorities.size === 0 && filters.categories.size === 0);
}

// ── Drag helpers ──
function getDragAfterElement(cardList, y) {
  const cards = [...cardList.querySelectorAll(".task-card:not(.dragging)")];
  let closest = null;
  let closestOffset = Number.NEGATIVE_INFINITY;

  for (const card of cards) {
    const box = card.getBoundingClientRect();
    const offset = y - box.top - box.height / 2;
    if (offset < 0 && offset > closestOffset) {
      closestOffset = offset;
      closest = card;
    }
  }
  return closest;
}

function clearDropIndicators() {
  document.querySelectorAll(".drop-indicator").forEach((el) => el.remove());
}

async function moveAndReorder(taskId, newStatus, cardList, afterCard) {
  const task = allTasks.find((t) => t.id === taskId);
  if (!task) return;

  const statusChanged = task.status !== newStatus;

  try {
    // ステータス変更があれば先に実行
    if (statusChanged) {
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
    }

    // DOMにドラッグ元カードがあれば挿入位置に移動（同カラム内用）
    const draggedCard = cardList.querySelector(`.task-card[data-id="${taskId}"]`);
    if (draggedCard) {
      if (afterCard) {
        cardList.insertBefore(draggedCard, afterCard);
      } else {
        cardList.appendChild(draggedCard);
      }
    }

    // カラム内の全カードの順序を取得
    const existingIds = new Set([...cardList.querySelectorAll(".task-card")].map((c) => Number(c.dataset.id)));

    // ステータス変更時はドラッグ元カードがDOMにないので、挿入位置を計算
    let orderedIds;
    if (!existingIds.has(taskId)) {
      const currentCards = [...cardList.querySelectorAll(".task-card")].map((c) => Number(c.dataset.id));
      if (afterCard) {
        const afterId = Number(afterCard.dataset.id);
        const idx = currentCards.indexOf(afterId);
        currentCards.splice(idx, 0, taskId);
      } else {
        currentCards.push(taskId);
      }
      orderedIds = currentCards;
    } else {
      orderedIds = [...cardList.querySelectorAll(".task-card")].map((c) => Number(c.dataset.id));
    }

    const orders = orderedIds.map((id, index) => ({ id, sort_order: index }));

    await api("/tasks-reorder", {
      method: "PUT",
      body: JSON.stringify({ orders }),
    });

    await fetchTasks();
  } catch (e) {
    showError(e.message);
    await fetchTasks();
  }
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

// ── Settings Modal (カテゴリ管理) ──
document.getElementById("settings-btn").addEventListener("click", () => {
  renderCategoryList();
  document.getElementById("settings-modal").classList.remove("hidden");
});
document.getElementById("settings-close").addEventListener("click", closeSettings);
document.getElementById("settings-backdrop").addEventListener("click", closeSettings);

function closeSettings() {
  document.getElementById("settings-modal").classList.add("hidden");
}

function renderCategoryList() {
  const list = document.getElementById("category-list");
  list.innerHTML = "";
  for (const [name, info] of Object.entries(categoryColors)) {
    const item = document.createElement("div");
    item.className = "category-list-item";
    item.innerHTML = `
      <input type="color" class="category-color-input" value="${info.color}" title="背景色">
      <input type="color" class="category-text-color-input" value="${info.text_color}" title="文字色">
      <span class="category-preview" style="background:${info.color};color:${info.text_color}">Aa</span>
      <input type="text" class="category-name-input" value="${escapeHtml(name)}">
      <button class="category-delete-btn" title="削除">&#128465;</button>
    `;
    // 背景色変更
    item.querySelector(".category-color-input").addEventListener("change", async (e) => {
      try {
        await api(`/categories/${encodeURIComponent(name)}`, {
          method: "PUT",
          body: JSON.stringify({ color: e.target.value }),
        });
        await fetchTasks();
        renderCategoryList();
      } catch (err) { showError(err.message); }
    });
    // 文字色変更
    item.querySelector(".category-text-color-input").addEventListener("change", async (e) => {
      try {
        await api(`/categories/${encodeURIComponent(name)}`, {
          method: "PUT",
          body: JSON.stringify({ text_color: e.target.value }),
        });
        await fetchTasks();
        renderCategoryList();
      } catch (err) { showError(err.message); }
    });
    // 名前変更
    const nameInput = item.querySelector(".category-name-input");
    nameInput.addEventListener("blur", async () => {
      const newName = nameInput.value.trim();
      if (newName && newName !== name) {
        try {
          await api(`/categories/${encodeURIComponent(name)}`, {
            method: "PUT",
            body: JSON.stringify({ name: newName }),
          });
          await fetchTasks();
          renderCategoryList();
        } catch (err) { showError(err.message); }
      }
    });
    nameInput.addEventListener("keydown", (e) => {
      if (e.key === "Enter") nameInput.blur();
    });
    // 削除
    item.querySelector(".category-delete-btn").addEventListener("click", async () => {
      if (!confirm(`カテゴリ「${name}」を削除しますか？`)) return;
      try {
        await api(`/categories/${encodeURIComponent(name)}`, { method: "DELETE" });
        await fetchTasks();
        renderCategoryList();
      } catch (err) { showError(err.message); }
    });
    list.appendChild(item);
  }
}

document.getElementById("add-category-btn").addEventListener("click", async () => {
  const nameInput = document.getElementById("new-category-name");
  const colorInput = document.getElementById("new-category-color");
  const textColorInput = document.getElementById("new-category-text-color");
  const name = nameInput.value.trim();
  if (!name) return;
  try {
    await api("/categories", {
      method: "POST",
      body: JSON.stringify({ name, color: colorInput.value, text_color: textColorInput.value }),
    });
    nameInput.value = "";
    colorInput.value = "#8a8a8a";
    textColorInput.value = "#2a2a2a";
    await fetchTasks();
    renderCategoryList();
  } catch (err) { showError(err.message); }
});

// ── Init ──
fetchTasks();
pollingTimer = setInterval(fetchTasks, 5000);
