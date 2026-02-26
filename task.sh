#!/bin/bash
DB="$HOME/workspace/task/tasks.db"

sqlite_exec() {
  sqlite3 "$DB" "PRAGMA foreign_keys=ON; $1"
}

sqlite_exec_table() {
  sqlite3 -header -column "$DB" "PRAGMA foreign_keys=ON; $1"
}

sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

sql_text_or_null() {
  local value="$1"
  if [ -z "$value" ]; then
    printf "NULL"
  else
    printf "'%s'" "$(sql_escape "$value")"
  fi
}

require_numeric_id() {
  local id="$1"
  if ! [[ "$id" =~ ^[0-9]+$ ]]; then
    echo "IDは数値で指定してください: $id" >&2
    exit 1
  fi
}

validate_status() {
  local val="$1"
  case "$val" in
    未着手|進行中|今日やる|完了|アーカイブ) ;;
    *) echo "無効なステータス: $val（未着手/進行中/今日やる/完了/アーカイブ）" >&2; exit 1;;
  esac
}

validate_priority() {
  local val="$1"
  case "$val" in
    高|中|低) ;;
    *) echo "無効な優先度: $val（高/中/低）" >&2; exit 1;;
  esac
}

validate_category() {
  local val="$1"
  case "$val" in
    SPECRA|業務委託|個人) ;;
    *) echo "無効なカテゴリ: $val（SPECRA/業務委託/個人）" >&2; exit 1;;
  esac
}

validate_date() {
  local val="$1"
  if ! [[ "$val" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "無効な日付形式: $val（YYYY-MM-DD）" >&2; exit 1
  fi
}

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
  sqlite_exec_table "
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
  if [ -n "$parent" ]; then
    require_numeric_id "$parent"
  fi
  # ホワイトリスト検証
  [ -n "$status" ] && validate_status "$status"
  [ -n "$priority" ] && validate_priority "$priority"
  [ -n "$category" ] && validate_category "$category"
  [ -n "$due" ] && validate_date "$due"

  local name_sql status_sql priority_sql category_sql due_sql tags_sql parent_sql
  name_sql=$(sql_text_or_null "$name")
  status_sql=$(sql_text_or_null "$status")
  priority_sql=$(sql_text_or_null "$priority")
  category_sql=$(sql_text_or_null "$category")
  due_sql=$(sql_text_or_null "$due")
  tags_sql=$(sql_text_or_null "$tags")
  parent_sql=${parent:-NULL}

  local inserted_id
  inserted_id=$(sqlite_exec "
    INSERT INTO tasks (name, status, priority, category, due_date, parent_task_id, tags)
    VALUES (${name_sql}, ${status_sql}, ${priority_sql}, ${category_sql}, ${due_sql}, ${parent_sql}, ${tags_sql});
    SELECT last_insert_rowid();
  ")
  echo "タスクを追加しました (ID: $inserted_id)"
  auto_export
}

cmd_done() {
  local id="$1"
  require_numeric_id "$id"
  sqlite_exec "UPDATE tasks SET status='完了', completed_date=date('now','localtime'), updated_at=datetime('now','localtime') WHERE id=$id;"
  echo "タスク $id を完了にしました"
  auto_export
}

cmd_update() {
  local id="$1"; shift
  require_numeric_id "$id"
  local sets=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) sets+=("name=$(sql_text_or_null "$2")"); shift 2;;
      --due) validate_date "$2"; sets+=("due_date=$(sql_text_or_null "$2")"); shift 2;;
      --category) validate_category "$2"; sets+=("category=$(sql_text_or_null "$2")"); shift 2;;
      --priority) validate_priority "$2"; sets+=("priority=$(sql_text_or_null "$2")"); shift 2;;
      --status) validate_status "$2"; sets+=("status=$(sql_text_or_null "$2")"); shift 2;;
      --memo) sets+=("memo=$(sql_text_or_null "$2")"); shift 2;;
      *) echo "Unknown option: $1"; exit 1;;
    esac
  done
  sets+=("updated_at=datetime('now','localtime')")
  local set_str=$(IFS=','; echo "${sets[*]}")
  sqlite_exec "UPDATE tasks SET $set_str WHERE id=$id;"
  echo "タスク $id を更新しました"
  auto_export
}

cmd_delete() {
  local id="$1"
  require_numeric_id "$id"
  local name
  name=$(sqlite_exec "SELECT name FROM tasks WHERE id=$id;")
  sqlite_exec "
    DELETE FROM tasks WHERE parent_task_id=$id;
    DELETE FROM tasks WHERE id=$id;
  "
  echo "タスク $id ($name) を削除しました"
  auto_export
}

cmd_show() {
  local id="$1"
  require_numeric_id "$id"
  sqlite_exec_table "SELECT * FROM tasks WHERE id=$id;"
}

cmd_export() {
  sqlite_exec "
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
  # sedやawkへの直接展開を避け、テンプレート置換で安全に埋め込む
  local script_tag="<script>const TASKS_DATA = ${json_data};</script>"
  local tmpfile
  tmpfile=$(mktemp)
  # </head>の行を分割して、スクリプトタグを挿入
  while IFS= read -r line; do
    case "$line" in
      *"</head>"*)
        printf '%s\n' "${line%%</head>*}${script_tag}</head>${line#*</head>}"
        ;;
      *)
        printf '%s\n' "$line"
        ;;
    esac
  done < "$dir/board.html" > "$tmpfile"
  mv "$tmpfile" "$out"
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
