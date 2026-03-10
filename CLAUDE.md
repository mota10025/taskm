# タスク管理プロジェクト

## 概要
Cloudflare Workers + D1 をバックエンドとするタスク管理ツール。
macOSネイティブアプリ（SwiftUI）、CLI、Claude Desktop（MCP）の3つのインターフェースで操作可能。
Googleカレンダー連携（EventKit経由）も搭載。

## ブランチ構成
- `cloud` - デフォルトブランチ（API版 + Googleカレンダー統合）
- `main` - オフライン版（ローカルSQLite）

## ファイル構成
- `workers/` - Cloudflare Workers API（D1データベース）
- `web/` - Webフロントエンド
- `task.sh` - CLI操作スクリプト（ローカルSQLite用）
- `TaskM/` - macOSネイティブアプリ（SwiftUI）
  - `Database/DatabaseManager.swift` - APIクライアント（名前はDBだが実態はREST API通信）
  - `Services/CalendarService.swift` - EventKitラッパー（Googleカレンダー取得）
  - `ViewModels/CalendarViewModel.swift` - カレンダー状態管理
  - `ViewModels/KanbanViewModel.swift` - タスクカンバン状態管理
  - `Views/SidebarTabBar.swift` - サイドバータブ（タスク/カレンダー切替）
  - `Views/CalendarWeekView.swift` - Googleカレンダー週表示
  - `Secrets.swift` - APIキー（gitignore対象、コミット禁止）
- `mcp-server/` - Claude Desktop用MCPサーバー（Node.js、ローカルSQLite）

## API（Cloudflare Workers）
- ベースURL: `Secrets.apiURL`
- 認証: `X-API-Key` ヘッダー
- エンドポイント:
  - `GET /tasks` - タスク一覧（親タスク + カテゴリ情報）
  - `POST /tasks` - タスク追加
  - `PUT /tasks/:id` - タスク更新
  - `DELETE /tasks/:id` - タスク削除
  - `POST /tasks/:id/complete` - タスク完了（サブタスクも一括完了）
  - `GET /tasks/:id/subtasks` - サブタスク取得
  - `GET /categories` - カテゴリ一覧
  - `POST /categories` - カテゴリ追加
  - `PUT /categories/:id` - カテゴリ更新
  - `DELETE /categories/:id` - カテゴリ削除

## DBスキーマ（D1）

```sql
tasks (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  name          TEXT NOT NULL,
  status        TEXT DEFAULT '未着手',   -- 未着手/進行中/今日やる/完了/アーカイブ
  priority      TEXT,                    -- 高/中/低
  category      TEXT,                    -- 動的（APIのcategoriesテーブルから取得）
  due_date      TEXT,                    -- YYYY-MM-DD
  completed_date TEXT,
  parent_task_id INTEGER,
  tags          TEXT,                    -- カンマ区切り
  memo          TEXT,
  created_at    TEXT,
  updated_at    TEXT
)

categories (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  name          TEXT NOT NULL UNIQUE,
  color         TEXT,                    -- 背景色（hex）
  text_color    TEXT,                    -- テキスト色（hex）
  created_at    TEXT
)
```

## Claudeへの指示
- macOSアプリのデータソースはCloudflare Workers API（DatabaseManager.swift経由）
- タスク操作はMCPサーバー経由またはAPI直接呼び出しで行う
- `Secrets.swift` は絶対にコミットしない（APIキーを含む）
- ユーザーに「タスクを見せて」と言われたらMCPのlist_tasksを使う
- カテゴリはAPIから動的に取得される（ハードコードしない）
