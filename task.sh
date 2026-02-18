#!/bin/bash
DB="$HOME/workspace/task/tasks.db"

usage() {
  echo "Usage:"
  echo "  task.sh list [--all]                    タスク一覧（未完了のみ。--allで全件）"
  echo "  task.sh add \"タスク名\" [options]        タスク追加"
  echo "    --due YYYY-MM-DD                       期限"
  echo "    --category カテゴリ                     SPECRA/業務委託/個人"
  echo "    --priority 優先度                       高/中/低"
  echo "    --status ステータス                     未着手/進行中/今日やる"
  echo "    --parent ID                            親タスクID"
  echo "    --tags タグ                             カンマ区切り"
  echo "  task.sh done <id>                        完了にする"
  echo "  task.sh update <id> [options]             タスク更新"
  echo "    --name \"新しい名前\""
  echo "    --due YYYY-MM-DD"
  echo "    --category カテゴリ"
  echo "    --priority 優先度"
  echo "    --status ステータス"
  echo "    --memo \"メモ内容\""
  echo "  task.sh delete <id>                      タスク削除"
  echo "  task.sh show <id>                        タスク詳細"
  echo "  task.sh export                           JSONエクスポート"
  echo "  task.sh board                            ブラウザでカンバンボード表示"
  exit 1
}

cmd_list() {
  local where="WHERE status NOT IN ('完了','アーカイブ')"
  if [ "$1" = "--all" ]; then
    where=""
  fi
  sqlite3 -header -column "$DB" "
    SELECT id, name, status, priority, category, due_date
    FROM tasks $where
    ORDER BY
      CASE status
        WHEN '今日やる' THEN 1
        WHEN '進行中' THEN 2
        WHEN '未着手' THEN 3
        WHEN '完了' THEN 4
        WHEN 'アーカイブ' THEN 5
      END,
      CASE priority
        WHEN '高' THEN 1
        WHEN '中' THEN 2
        WHEN '低' THEN 3
        ELSE 4
      END,
      due_date ASC;
  "
}

cmd_add() {
  local name="$1"; shift
  local due="" category="" priority="" status="未着手" parent="" tags=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --due) due="$2"; shift 2;;
      --category) category="$2"; shift 2;;
      --priority) priority="$2"; shift 2;;
      --status) status="$2"; shift 2;;
      --parent) parent="$2"; shift 2;;
      --tags) tags="$2"; shift 2;;
      *) echo "Unknown option: $1"; exit 1;;
    esac
  done
  sqlite3 "$DB" "INSERT INTO tasks (name, status, priority, category, due_date, parent_task_id, tags)
    VALUES ('$name', '$status', $([ -n "$priority" ] && echo "'$priority'" || echo "NULL"), $([ -n "$category" ] && echo "'$category'" || echo "NULL"), $([ -n "$due" ] && echo "'$due'" || echo "NULL"), $([ -n "$parent" ] && echo "$parent" || echo "NULL"), $([ -n "$tags" ] && echo "'$tags'" || echo "NULL"));"
  echo "タスクを追加しました (ID: $(sqlite3 "$DB" 'SELECT last_insert_rowid();'))"
  auto_export
}

cmd_done() {
  local id="$1"
  sqlite3 "$DB" "UPDATE tasks SET status='完了', completed_date=date('now','localtime'), updated_at=datetime('now','localtime') WHERE id=$id;"
  echo "タスク $id を完了にしました"
  auto_export
}

cmd_update() {
  local id="$1"; shift
  local sets=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) sets+=("name='$2'"); shift 2;;
      --due) sets+=("due_date='$2'"); shift 2;;
      --category) sets+=("category='$2'"); shift 2;;
      --priority) sets+=("priority='$2'"); shift 2;;
      --status) sets+=("status='$2'"); shift 2;;
      --memo) sets+=("memo='$2'"); shift 2;;
      *) echo "Unknown option: $1"; exit 1;;
    esac
  done
  sets+=("updated_at=datetime('now','localtime')")
  local set_str=$(IFS=','; echo "${sets[*]}")
  sqlite3 "$DB" "UPDATE tasks SET $set_str WHERE id=$id;"
  echo "タスク $id を更新しました"
  auto_export
}

cmd_delete() {
  local id="$1"
  local name=$(sqlite3 "$DB" "SELECT name FROM tasks WHERE id=$id;")
  sqlite3 "$DB" "DELETE FROM tasks WHERE id=$id;"
  echo "タスク $id ($name) を削除しました"
  auto_export
}

cmd_show() {
  local id="$1"
  sqlite3 -header -column "$DB" "SELECT * FROM tasks WHERE id=$id;"
}

cmd_export() {
  sqlite3 "$DB" "
    SELECT json_group_array(json_object(
      'id', id,
      'name', name,
      'status', status,
      'priority', priority,
      'category', category,
      'due_date', due_date,
      'completed_date', completed_date,
      'parent_task_id', parent_task_id,
      'tags', tags,
      'memo', memo
    ))
    FROM tasks
    WHERE status NOT IN ('完了','アーカイブ');
  "
}

auto_export() {
  local dir="$(dirname "$0")"
  cmd_export > "$dir/tasks.json"
}

cmd_board() {
  local dir="$(dirname "$0")"
  local json_data
  json_data=$(cmd_export)
  local out="$dir/board_view.html"
  # board.htmlのloadTasks前にTASKS_DATAを埋め込んだHTMLを生成
  sed "s|</head>|<script>const TASKS_DATA = ${json_data};</script></head>|" "$dir/board.html" > "$out"
  open "$out"
}

case "${1:-}" in
  list) shift; cmd_list "$@";;
  add) shift; cmd_add "$@";;
  done) shift; cmd_done "$@";;
  update) shift; cmd_update "$@";;
  delete) shift; cmd_delete "$@";;
  show) shift; cmd_show "$@";;
  export) shift; cmd_export "$@";;
  board) shift; cmd_board "$@";;
  *) usage;;
esac
