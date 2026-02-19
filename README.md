# TaskM

ローカル完結のタスク管理システム。SQLite DBを中心に、macOSネイティブアプリ・CLI・Claude Desktop から操作できる。

## 構成

```
~/workspace/task/
├── tasks.db              # SQLiteデータベース（タスクデータ）
├── task.sh               # CLI操作スクリプト
├── TaskM/                # macOSネイティブアプリ（SwiftUI + GRDB）
├── mcp-server/           # Claude Desktop用MCPサーバー（Node.js）
├── CLAUDE.md             # Claude Code用の指示ファイル
└── TaskApp_Requirements.md  # 詳細仕様書
```

## セットアップ

### 前提条件

- macOS
- Xcode
- Node.js (v18以上)
- sqlite3 コマンド（macOS標準搭載）

### Claude Code でセットアップ（推奨）

このリポジトリを clone した後、Claude Code で以下のように依頼するだけでセットアップできます。

**初回セットアップ:**

> 「このプロジェクトのセットアップをして。tasks.db の初期化、mcp-server の npm install、Claude Desktop への MCP Server 登録をお願い」

**DBの初期化のみ:**

> 「tasks.db がないので、CLAUDE.md のスキーマを見て初期化して」

**MCP Server のセットアップのみ:**

> 「mcp-server の npm install をして、Claude Desktop の設定ファイル（claude_desktop_config.json）に taskm の MCP Server を登録して。node のフルパスは which node で確認して」

**macOS アプリのビルド:**

> Xcode で `TaskM/TaskM.xcodeproj` を開いてビルド（SPM で GRDB と MarkdownUI が自動取得される）

### 手動セットアップ

```bash
# 1. リポジトリをクローン
git clone https://github.com/mota10025/taskm.git ~/workspace/task
cd ~/workspace/task

# 2. データベースの初期化
sqlite3 tasks.db <<'SQL'
CREATE TABLE IF NOT EXISTS tasks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT '未着手',
  priority TEXT,
  category TEXT,
  due_date TEXT,
  completed_date TEXT,
  parent_task_id INTEGER,
  tags TEXT,
  memo TEXT,
  created_at TEXT DEFAULT (datetime('now','localtime')),
  updated_at TEXT DEFAULT (datetime('now','localtime')),
  FOREIGN KEY (parent_task_id) REFERENCES tasks(id)
);
PRAGMA journal_mode=WAL;
SQL

# 3. MCP Server の依存パッケージをインストール
cd mcp-server
npm install
cd ..

# 4. Claude Desktop の設定ファイルに MCP Server を登録
# ~/Library/Application Support/Claude/claude_desktop_config.json に以下を追加
# ※ command には `which node` で得られるフルパスを指定
```

```json
{
  "mcpServers": {
    "taskm": {
      "command": "/path/to/node",
      "args": ["/path/to/workspace/task/mcp-server/index.js"]
    }
  }
}
```

```bash
# 5. Claude Desktop を再起動

# 6. macOS アプリ
# Xcode で TaskM/TaskM.xcodeproj を開いてビルド
# 初回起動時にアクセシビリティ権限を許可
```

## 3つのインターフェース

### 1. macOS アプリ (TaskM)

SwiftUI製のカンバンボードアプリ。メニューバーに常駐し、Control キー2回押しで表示/非表示。

- 4カラム表示（未着手 / 進行中 / 今日やる / 完了）
- ドラッグ&ドロップでステータス変更
- タスク編集（DatePicker、Markdownメモ、サブタスク管理）
- 優先度・カテゴリでフィルタ
- 外部からのDB変更をリアルタイム検知・反映

**ビルド方法:**

1. Xcode で `TaskM/TaskM.xcodeproj` を開く
2. SPM で以下のパッケージを追加（初回のみ）
   - [GRDB](https://github.com/groue/GRDB.swift) (Up to Next Major Version 7.0.0)
   - [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui)
3. ビルド & 実行
4. アクセシビリティ権限を許可（システム設定 > プライバシーとセキュリティ）

### 2. CLI (task.sh)

```bash
./task.sh list                    # 一覧（未完了のみ）
./task.sh list --all              # 全件表示
./task.sh add "タスク名" --due 2026-02-20 --category SPECRA --priority 高
./task.sh done <id>               # 完了にする
./task.sh update <id> --status 進行中
./task.sh show <id>               # 詳細表示
./task.sh delete <id>             # 削除
```

### 3. Claude Desktop (MCP Server)

Claude Desktop アプリから自然言語でタスクを操作できる。

**セットアップ:**

Claude Code に以下を依頼するのが最も簡単:

> 「mcp-server のセットアップをして。npm install して Claude Desktop の設定ファイルに登録して」

手動で行う場合:

```bash
# 依存パッケージのインストール
cd mcp-server
npm install

# Claude Desktop の設定に追加
# ~/Library/Application Support/Claude/claude_desktop_config.json
```

```json
{
  "mcpServers": {
    "taskm": {
      "command": "/path/to/node",
      "args": ["/path/to/workspace/task/mcp-server/index.js"]
    }
  }
}
```

- `command` には Node.js のフルパスを指定（`which node` で確認）
- 設定後、Claude Desktop を再起動

**使い方（Claude Desktop で）:**

- 「タスクを見せて」
- 「○○というタスクを追加して、期限は来週金曜、優先度高で」
- 「タスク15を完了にして」
- 「業務委託のタスク一覧を見せて」

## データベース

- SQLite（`tasks.db`）にすべてのタスクデータを保存
- WALモード（複数プロセスからの同時アクセスに対応）
- `tasks.db-wal` と `tasks.db-shm` は自動生成されるファイル（削除しないこと）

詳細なスキーマやカラー定義は [TaskApp_Requirements.md](TaskApp_Requirements.md) を参照。

## 開発メモ

- macOS アプリのソースコードを変更したら Xcode でビルド
- MCP Server のコードを変更したら Claude Desktop を再起動
- `task.sh` は変更なしでそのまま動作
- すべてローカル完結（外部サーバー不要）
