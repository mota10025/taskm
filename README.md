# TaskM

タスク管理システム。macOSネイティブアプリ・CLI・Claude Desktop・iPhone Claudeアプリから操作できる。

## ブランチ構成

| ブランチ | 説明 |
|----------|------|
| `main` | **オフライン版** — ローカルSQLite完結。外部サーバー不要 |
| `cloud` | **クラウド版** — Cloudflare D1 + Workers API + Pages。どこからでもアクセス可能 |

### main（オフライン版）

- データは `tasks.db`（ローカルSQLite）に保存
- macOSアプリは GRDB で直接DBアクセス
- MCPサーバーは `better-sqlite3` で直接DBアクセス
- 外部ネットワーク不要

### cloud（クラウド版）

- データは Cloudflare D1（クラウドSQLite）に保存
- macOSアプリは Workers REST API 経由でアクセス
- MCPサーバーは Workers REST API 経由でアクセス
- Remote MCPサーバー搭載（OAuth 2.1認証付き）→ iPhone Claudeアプリ対応
- Webカンバンボード（Cloudflare Pages）

## 構成（cloud ブランチ）

```
~/workspace/task/
├── task.sh               # CLI操作スクリプト
├── TaskM/                # macOSネイティブアプリ（SwiftUI, API経由）
├── mcp-server/           # Claude Desktop用MCPサーバー（Node.js, API経由）
├── workers/              # Cloudflare Workers（REST API + Remote MCP + OAuth）
│   └── src/
│       ├── index.ts      # エントリポイント（ルーティング）
│       ├── routes/       # REST APIルート
│       ├── mcp/          # Remote MCPサーバー + OAuth認証
│       └── utils/        # 共有ユーティリティ
├── web/                  # Webカンバンボード（Cloudflare Pages）
├── CLAUDE.md             # Claude Code用の指示ファイル
└── TaskApp_Requirements.md  # 詳細仕様書
```

## セットアップ

### 前提条件

- macOS
- Xcode
- Node.js (v18以上)
- Cloudflare アカウント（Workers / D1 / Pages / KV を使用）

### 1. Cloudflare Workers API

```bash
cd workers
npm install
npx wrangler deploy
```

環境変数（Secret）の設定:

```bash
npx wrangler secret put API_KEY          # REST API認証キー
npx wrangler secret put ALLOWED_EMAIL    # OAuth認証で許可するメールアドレス
```

### 2. Webカンバンボード（Cloudflare Pages）

```bash
npx wrangler pages deploy web/ --project-name=taskm-web --branch=main
```

`web/config.js` を作成（gitignore対象）:

```javascript
const API_URL = location.hostname === "localhost"
  ? "http://localhost:8787"
  : "https://your-worker.workers.dev";
const API_KEY = "your-api-key";
```

### 3. Claude Desktop MCP Server

```bash
cd mcp-server
npm install
```

Claude Desktop の設定ファイル（`~/Library/Application Support/Claude/claude_desktop_config.json`）:

```json
{
  "mcpServers": {
    "taskm": {
      "command": "/path/to/node",
      "args": ["/path/to/workspace/task/mcp-server/index.js"],
      "env": {
        "TASKM_API_URL": "https://your-worker.workers.dev",
        "TASKM_API_KEY": "your-api-key"
      }
    }
  }
}
```

### 4. macOS アプリ

1. Xcode で `TaskM/TaskM.xcodeproj` を開く
2. Xcode Scheme の環境変数に `TASKM_API_URL` と `TASKM_API_KEY` を設定
3. ビルド & 実行
4. アクセシビリティ権限を許可（システム設定 > プライバシーとセキュリティ）

### 5. iPhone Claude アプリ（Remote MCP）

1. [claude.ai](https://claude.ai) の Settings → Connectors → Add Custom Connector
2. URL: `https://your-worker.workers.dev/mcp`
3. OAuth認証画面でメールアドレスを入力して認可
4. iPhoneのClaudeアプリに自動同期

## インターフェース

### 1. Webカンバンボード

Cloudflare Pagesでホストされるブラウザ向けカンバンボード。

- 4カラム表示（未着手 / 進行中 / 今日やる / 完了）
- ドラッグ&ドロップでステータス変更
- タスク編集・追加・削除
- 優先度・カテゴリでフィルタ

### 2. macOS アプリ (TaskM)

SwiftUI製のカンバンボードアプリ。メニューバーに常駐し、Control キー2回押しで表示/非表示。Workers API経由でD1にアクセス。

- 4カラム表示（未着手 / 進行中 / 今日やる / 完了）
- ドラッグ&ドロップでステータス変更
- タスク編集（DatePicker、Markdownメモ、サブタスク管理）
- 優先度・カテゴリでフィルタ
- 5秒間隔のポーリングでデータ同期

### 3. CLI (task.sh)

```bash
./task.sh list                    # 一覧（未完了のみ）
./task.sh list --all              # 全件表示
./task.sh add "タスク名" --due 2026-02-20 --category SPECRA --priority 高
./task.sh done <id>               # 完了にする
./task.sh update <id> --status 進行中
./task.sh show <id>               # 詳細表示
./task.sh delete <id>             # 削除
```

### 4. Claude Desktop (MCP Server)

Claude Desktop アプリから自然言語でタスクを操作。Workers API経由でD1にアクセス。

**使い方:**

- 「タスクを見せて」
- 「○○というタスクを追加して、期限は来週金曜、優先度高で」
- 「タスク15を完了にして」
- 「業務委託のタスク一覧を見せて」

### 5. iPhone Claude アプリ (Remote MCP)

Remote MCPサーバー（OAuth 2.1認証付き）経由で、iPhoneのClaudeアプリからタスクを操作。Claude Desktopと同じ6つのツールが利用可能。

## セキュリティ

### 認証の全体像

```text
┌─────────────────┐     X-API-Key        ┌──────────────────────┐
│ macOSアプリ      │ ──────────────────→  │                      │
├─────────────────┤                       │  Cloudflare Workers  │
│ Claude Desktop  │ ──────────────────→  │  (REST API)          │
│ (ローカルMCP)    │     X-API-Key        │  /api/*              │
└─────────────────┘                       └──────────────────────┘
                                                    ↑
┌─────────────────┐     Bearer Token      ┌──────────────────────┐
│ iPhone Claude   │ ──────────────────→  │  Cloudflare Workers  │
│ (Remote MCP)    │     (OAuth 2.1)       │  /mcp                │
└─────────────────┘                       └──────────────────────┘

┌─────────────────┐     Zero Trust        ┌──────────────────────┐
│ ブラウザ         │ ──────────────────→  │  Cloudflare Pages    │
│ (Webカンバン)    │     (Cloudflare      │  (静的HTML/JS)        │
└─────────────────┘      Access)          └──────────────────────┘
```

### 1. Webカンバンボード — Cloudflare Zero Trust

Cloudflare Access（Zero Trust）でPages全体を保護し、許可されたユーザーのみアクセス可能にする。

**設定手順:**

1. [Cloudflare Zero Trust ダッシュボード](https://one.dash.cloudflare.com/) にアクセス
2. **Access** → **Applications** → **Add an application**
3. **Self-hosted** を選択
4. 設定:
   - Application name: `TaskM Web`
   - Application domain: `your-project.pages.dev`
   - Session Duration: 任意（例: 24時間）
5. **Policy** を追加:
   - Policy name: `Allow owner`
   - Action: **Allow**
   - Include: **Emails** → 自分のメールアドレスを入力
6. **Authentication** → **One-time PIN**（メールにワンタイムPINが届く方式）

これにより、`your-project.pages.dev` へのアクセス時にCloudflare Accessのログイン画面が表示され、許可されたメールアドレスでのみ閲覧可能になる。

### 2. REST API — APIキー認証

macOSアプリとClaude Desktop MCPサーバーからのアクセスは `X-API-Key` ヘッダーで認証。

- Workers の環境変数（Secret）`API_KEY` と照合
- すべての `/api/*` エンドポイントに適用

```bash
# APIキーの設定
cd workers
npx wrangler secret put API_KEY
```

**クライアント側の設定:**

| クライアント | 設定場所 |
| --- | --- |
| macOSアプリ | Xcode Scheme 環境変数 `TASKM_API_KEY` |
| Claude Desktop MCP | `claude_desktop_config.json` の `env.TASKM_API_KEY` |
| Webカンバンボード | `web/config.js`（gitignore対象） |

### 3. Remote MCPサーバー — OAuth 2.1 + PKCE

iPhoneのClaudeアプリからのアクセスはOAuth 2.1で認証。

**認証フロー:**

1. Claudeアプリが `/mcp` に接続 → 401応答でOAuth認証を要求
2. Claudeアプリがブラウザを開き `/authorize` へリダイレクト
3. ユーザーがメールアドレスを入力（`ALLOWED_EMAIL` と照合）
4. 認可コード発行 → PKCE検証 → アクセストークン + リフレッシュトークン発行
5. 以降はBearerトークンで自動認証

**トークンの有効期限:**

| トークン | 有効期限 | 保存先 |
| --- | --- | --- |
| 認可コード | 5分 | Cloudflare KV |
| アクセストークン | 1時間 | Cloudflare KV |
| リフレッシュトークン | 90日 | Cloudflare KV |

**準拠規格:**

- OAuth 2.1 + PKCE（S256）
- Dynamic Client Registration（RFC 7591）
- OAuth Authorization Server Metadata（RFC 8414）
- Protected Resource Metadata（RFC 9728）

**アクセス制限の設定:**

```bash
cd workers
npx wrangler secret put ALLOWED_EMAIL    # 許可するメールアドレス（1つ）
```

### 4. Claude.ai での Remote MCP 接続設定

1. PCブラウザで [claude.ai](https://claude.ai) にアクセス
2. **Settings** → **Connectors** → **Add Custom Connector**
3. 以下を入力:
   - Name: `TaskM`（任意）
   - URL: `https://your-worker.workers.dev/mcp`
4. **Connect** をクリック → OAuth認証画面が表示される
5. 許可されたメールアドレスを入力して **認証する** をクリック
6. 接続完了 → iPhoneのClaudeアプリにも自動同期される

**利用可能なツール（6つ）:**

| ツール | 説明 |
| --- | --- |
| `list_tasks` | タスク一覧（フィルタ: status, category, priority, show_all） |
| `show_task` | タスク詳細（サブタスク含む） |
| `add_task` | タスク追加 |
| `update_task` | タスク更新 |
| `complete_task` | タスク完了（サブタスク一括完了オプション） |
| `delete_task` | タスク削除（サブタスクもカスケード） |

### セキュリティに関する注意事項

- `web/config.js` はAPIキーを含むため `.gitignore` 対象。リポジトリにコミットしないこと
- Workers のSecret（`API_KEY`, `ALLOWED_EMAIL`）はCloudflareダッシュボードまたは `wrangler secret` で管理
- macOSアプリのAPIキーはInfo.plistまたはXcode Scheme環境変数で設定（ソースコードにハードコードしない）

## データベース

- Cloudflare D1（SQLite互換）にすべてのタスクデータを保存
- Workers REST API経由でCRUD操作
- OAuth認証トークンはCloudflare KVに保存

詳細なスキーマやカラー定義は [TaskApp_Requirements.md](TaskApp_Requirements.md) を参照。

## 技術スタック

| コンポーネント | 技術 |
| --- | --- |
| データベース | Cloudflare D1 |
| REST API | Cloudflare Workers + Hono |
| Remote MCP | MCP SDK + WebStandard Transport |
| OAuth認証 | OAuth 2.1 + PKCE + KV |
| Webフロント | Cloudflare Pages（静的HTML/JS） |
| macOSアプリ | SwiftUI + URLSession |
| ローカルMCP | Node.js + MCP SDK |
| CLI | Bash + sqlite3 |
