# タスク管理プロジェクト

## 概要
SQLite + シェルスクリプトによるローカルタスク管理ツール。

## ファイル構成
- `tasks.db` - SQLiteデータベース（タスクデータ本体）
- `task.sh` - CLI操作スクリプト
- `TaskM/` - macOSネイティブアプリ（SwiftUI + GRDB）
- `mcp-server/` - Claude Desktop用MCPサーバー（Node.js）

## タスク操作（task.sh）

```bash
# 一覧表示（未完了のみ）
./task.sh list

# 全件表示（完了含む）
./task.sh list --all

# タスク追加
./task.sh add "タスク名" --due 2026-02-20 --category SPECRA --priority 高

# 完了にする
./task.sh done <id>

# タスク更新
./task.sh update <id> --status 進行中 --due 2026-02-20 --priority 中

# タスク詳細
./task.sh show <id>

# タスク削除
./task.sh delete <id>

# JSONエクスポート
./task.sh export
```

## DBスキーマ

```sql
tasks (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  name          TEXT NOT NULL,
  status        TEXT DEFAULT '未着手',   -- 未着手/進行中/今日やる/完了/アーカイブ
  priority      TEXT,                    -- 高/中/低
  category      TEXT,                    -- SPECRA/業務委託/個人
  due_date      TEXT,                    -- YYYY-MM-DD
  completed_date TEXT,
  parent_task_id INTEGER,
  tags          TEXT,                    -- カンマ区切り
  created_at    TEXT,
  updated_at    TEXT
)
```

## Claudeへの指示
- タスクの追加・更新・削除は `task.sh` 経由またはsqlite3コマンドで直接操作する
- ユーザーに「タスクを見せて」と言われたら `./task.sh list` を実行して結果を整形表示する
- タスクのステータス変更は `./task.sh update <id> --status ステータス名` を使う
- 完了にする場合は `./task.sh done <id>` を使う（completed_dateが自動設定される）

## Git操作時のGitHubアカウント

このリポジトリ（mota10025/taskm）を操作するときは、GitHubアカウント **mota10025** を使う。
このMacには別アカウント（miwa-takyoshi-gc）も登録されているが、このリポジトリへの権限がない。

- `origin` は SSH（`git@github.com:mota10025/taskm.git`）にしてある。SSH鍵は mota10025 で認証されるので、push/pull はそのままでよい
- HTTPS に戻さない。Keychain に保存された HTTPS 資格情報は miwa-takyoshi-gc のもので、push が 403 になる
- `gh` コマンド（PR作成など）を使う前に、アクティブアカウントを切り替える:

```bash
gh auth switch --user mota10025
```

- 作業が終わったら必要に応じて元に戻す: `gh auth switch --user miwa-takyoshi-gc`
