# TaskM

Cloudflare Workers + D1 をバックエンドとするタスク管理システム。macOSネイティブアプリ・CLI・Claude Desktop から操作できる。Googleカレンダー連携も搭載。

## 構成

```
~/workspace/task/
├── workers/              # Cloudflare Workers API（D1データベース）
├── web/                  # Webフロントエンド
├── TaskM/                # macOSネイティブアプリ（SwiftUI）
├── mcp-server/           # Claude Desktop用MCPサーバー（Node.js）
├── task.sh               # CLI操作スクリプト（ローカルSQLite用）
├── CLAUDE.md             # Claude Code用の指示ファイル
└── TaskApp_Requirements.md  # 詳細仕様書
```

## ブランチ構成

- `cloud` - デフォルトブランチ（API版 + Googleカレンダー統合）
- `main` - オフライン版（ローカルSQLite）

## セットアップ

### 前提条件

- macOS
- Xcode
- Node.js (v18以上)

### macOS アプリ

1. Xcode で `TaskM/TaskM.xcodeproj` を開く
2. `TaskM/TaskM/Secrets.swift` を作成（テンプレート）:

```swift
enum Secrets {
    static let apiURL = "https://your-worker.workers.dev"
    static let apiKey = "your-api-key"
}
```

3. ビルド & 実行
4. アクセシビリティ権限を許可（システム設定 > プライバシーとセキュリティ）
5. カレンダー機能を使う場合はカレンダー権限も許可

### MCP Server（Claude Desktop 連携）

```bash
cd mcp-server
npm install
```

Claude Desktop の設定ファイル（`~/Library/Application Support/Claude/claude_desktop_config.json`）に追加:

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

## 3つのインターフェース

### 1. macOS アプリ (TaskM)

SwiftUI製のカンバンボードアプリ。メニューバーに常駐し、Control キー2回押しで表示/非表示。

- 4カラム表示（未着手 / 進行中 / 今日やる / 完了）
- ドラッグ&ドロップでステータス変更
- スライドパネルでタスク編集（Markdownメモ、サブタスク管理）
- 優先度・カテゴリでフィルタ（カテゴリはAPIから動的取得）
- カテゴリ管理（追加・色設定・削除）
- Googleカレンダー週表示（EventKit経由、閲覧・作成・編集・削除）
- サイドバータブでタスク/カレンダー切替
- Cloudflare Workers API経由でデータ同期

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

**使い方（Claude Desktop で）:**

- 「タスクを見せて」
- 「○○というタスクを追加して、期限は来週金曜、優先度高で」
- 「タスク15を完了にして」
- 「業務委託のタスク一覧を見せて」

## データベース

- Cloudflare D1（クラウド）をメインのデータソースとして使用
- macOSアプリはREST API経由でD1にアクセス
- MCP ServerはローカルSQLite（`tasks.db`）を使用

## 開発メモ

- macOS アプリのソースコードを変更したら Xcode でビルド
- MCP Server のコードを変更したら Claude Desktop を再起動
- `Secrets.swift` はgitignore対象（APIキーを含むためコミット禁止）
- Workers APIの変更は `wrangler deploy` でデプロイ
