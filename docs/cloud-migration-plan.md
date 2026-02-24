# TaskM クラウド移行計画: Cloudflare D1 + Pages + Workers

## Context

現在のTaskMはローカルSQLite直接アクセス（CLI / macOSアプリ / MCPサーバー）のみ。
Webブラウザからもカンバンボードを閲覧・操作したい。

Cloudflare D1（SQLite互換サーバーレスDB）+ Pages（静的フロントエンド）+ Workers（REST API）で実現する。
ユーザーは1人、無料枠内で十分収まる。

## アーキテクチャ

```
┌─────────────┐    ┌──────────────────┐    ┌────────────┐
│  ブラウザ     │───▶│  Cloudflare Pages │    │            │
│  (カンバン)   │    │  (静的HTML/JS)    │───▶│  Cloudflare │
└─────────────┘    └──────────────────┘    │  Workers    │
                                           │  (REST API) │
┌─────────────┐                            │             │──▶ Cloudflare D1
│  task.sh    │───────────────────────────▶│             │    (SQLite)
│  (CLI)      │    curl                    │             │
└─────────────┘                            │             │
                                           │             │
┌─────────────┐                            │             │
│  MCP Server │───────────────────────────▶│             │
│  (Claude)   │    fetch()                 └─────────────┘
└─────────────┘
                                           ┌─────────────┐
┌─────────────┐                            │  Cloudflare  │
│  iPhone     │───▶ Remote MCP ───────────▶│  Workers     │
│  Claude App │                            │  (MCP Server)│
└─────────────┘                            └─────────────┘
```

## 認証方式: APIキー + Cloudflare Access（二重認証）

- **第1層: Cloudflare Access** — Googleログインで認証。自分のGoogleアカウントだけ許可
- **第2層: APIキー** — `X-API-Key`ヘッダー（Workers Secretに保存）

## ディレクトリ構成（新規追加分）

```
~/workspace/task/
├── workers/                    # Cloudflare Workers API
│   ├── wrangler.toml
│   ├── package.json
│   ├── tsconfig.json
│   ├── src/
│   │   ├── index.ts            # Honoルーター
│   │   ├── routes/tasks.ts     # /api/tasks/* ハンドラ
│   │   ├── middleware/auth.ts   # APIキー認証
│   │   └── types.ts
│   └── migrations/
│       └── 0001_init.sql       # D1スキーマ
├── web/                        # Cloudflare Pages（静的カンバンUI）
│   ├── index.html
│   ├── style.css
│   └── app.js                  # Vanilla JS（フレームワーク不使用）
```

## 実装フェーズ

### Phase 1: Workers API（バックエンド）

Honoフレームワーク（~14KB、Workers向け軽量ルーター）でREST APIを構築。

| メソッド | パス                      | 説明                                     |
| -------- | ------------------------- | ---------------------------------------- |
| GET      | /api/tasks                | 一覧（フィルタ: status, category, priority, show_all） |
| GET      | /api/tasks/:id            | 詳細（サブタスク含む）                   |
| POST     | /api/tasks                | 追加                                     |
| PUT      | /api/tasks/:id            | 更新                                     |
| POST     | /api/tasks/:id/complete   | 完了（サブタスク一括完了オプション）     |
| DELETE   | /api/tasks/:id            | 削除（サブタスクもカスケード削除）       |

タイムスタンプはWorker側で`Asia/Tokyo`タイムゾーンで生成（D1は`datetime('now','localtime')`をデフォルト値に使えないため）。

### Phase 2: データ移行

```bash
# ローカルDBからINSERT文をエクスポート
sqlite3 tasks.db ".dump tasks" | grep "^INSERT" > data_export.sql

# D1作成・スキーマ適用・データインポート
wrangler d1 create taskm
wrangler d1 execute taskm --file=workers/migrations/0001_init.sql
wrangler d1 execute taskm --file=data_export.sql
```

### Phase 3: Workers デプロイ + Cloudflare Access設定

```bash
cd workers && wrangler deploy
wrangler secret put API_KEY   # openssl rand -hex 32 で生成
```

Cloudflare Zero Trust管理画面でアプリケーションポリシーを設定:
- Workers APIとPages両方を対象にする
- 許可条件: 自分のGoogleメールアドレスのみ

### Phase 4: Pages フロントエンド（Webカンバンボード）

- **Vanilla JS + CSS（ビルドステップ不要）**
- macOSアプリと同じダークテーマ
- 4カラム: 未着手 / 進行中 / 今日やる / 完了
- HTML5 Drag and Drop APIでドラッグ&ドロップ
- タスク編集モーダル、フィルタバー（優先度・カテゴリ）
- 5秒間隔ポーリングでリアルタイム更新

```bash
wrangler pages project create taskm-web
wrangler pages deploy web/ --project-name=taskm-web
```

### Phase 5: 既存クライアント更新（後日対応）

| クライアント      | 変更内容                                                |
| ----------------- | ------------------------------------------------------- |
| task.sh           | `sqlite3` → `curl` + Workers API                       |
| mcp-server        | Workers上にRemote MCPサーバーとしてデプロイ             |
| TaskM macOSアプリ | DatabaseManager → APIClient（URLSession + async/await） |

**Remote MCP化により、iPhoneのClaudeアプリからもタスク追加が可能になる。**

## 無料枠の余裕

| リソース            | 無料枠          | 想定使用量   |
| ------------------- | --------------- | ------------ |
| Workers リクエスト  | 10万/日         | ~500/日      |
| D1 読み取り         | 500万/日        | ~1,000/日    |
| D1 書き込み         | 10万/日         | ~50/日       |
| D1 ストレージ       | 5GB             | ~100KB       |
| Pages リクエスト    | 無制限          | —            |
| Cloudflare Access   | 50ユーザー無料  | 1ユーザー    |

## 検証方法

1. `wrangler dev`でローカルWorkers起動 → curlで全APIエンドポイントをテスト
2. `web/index.html`をブラウザで開き、ドラッグ&ドロップ・編集・追加・削除を確認
3. デプロイ後、本番URLでCloudflare Access認証 → カンバンボード動作確認
