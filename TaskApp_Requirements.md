# TaskM - タスク管理システム 仕様書

## 概要
SQLite DBを中心としたローカルタスク管理システム。
以下の3つのインターフェースからタスクを操作でき、リアルタイムで同期する。

1. **macOS ネイティブアプリ** (SwiftUI) - カンバンボードUI
2. **CLI** (`task.sh`) - シェルスクリプトによるコマンドライン操作
3. **Claude Desktop** (MCP Server) - 自然言語でタスク操作

## 技術スタック

### macOS アプリ (`TaskM/`)
- SwiftUI + AppKit (メニューバー常駐、フローティングウィンドウ)
- GRDB (DatabasePool) - SQLiteアクセス
- MarkdownUI - メモのMarkdownレンダリング
- Xcode プロジェクト (SPMで依存管理)

### CLI (`task.sh`)
- Bash + sqlite3 コマンド

### MCP Server (`mcp-server/`)
- Node.js
- @modelcontextprotocol/sdk
- better-sqlite3

## データ

### 保存場所
- ファイル: `~/workspace/task/tasks.db`
- 形式: SQLite
- ジャーナルモード: WAL (Write-Ahead Logging)
  - 複数プロセスからの同時読み書きに対応
  - `tasks.db-wal` と `tasks.db-shm` ファイルが自動生成される（削除不可）
  - 全プロセスが `PRAGMA journal_mode=WAL` を設定

### スキーマ
```sql
CREATE TABLE tasks (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  name           TEXT NOT NULL,
  status         TEXT NOT NULL DEFAULT '未着手',  -- 未着手/進行中/今日やる/完了/アーカイブ
  priority       TEXT,                            -- 高/中/低
  category       TEXT,                            -- SPECRA/業務委託/個人
  due_date       TEXT,                            -- YYYY-MM-DD
  completed_date TEXT,                            -- YYYY-MM-DD
  parent_task_id INTEGER,                         -- サブタスクの親タスクID
  tags           TEXT,                            -- カンマ区切り
  memo           TEXT,                            -- Markdown形式
  created_at     TEXT DEFAULT (datetime('now','localtime')),
  updated_at     TEXT DEFAULT (datetime('now','localtime')),
  FOREIGN KEY (parent_task_id) REFERENCES tasks(id)
);
```

### 同時アクセス制御
- WALモード: 読み取りと書き込みが同時に可能
- DatabasePool (GRDB): 並行読み取り + 直列書き込み
- busy_timeout: 10秒（ロック待機）
- 全プロセス共通設定: `PRAGMA synchronous=NORMAL`

## macOS アプリ仕様

### 起動・表示
- メニューバー常駐（Dockには表示しない）
- **Control キー2回押し**（0.5秒以内）でウィンドウをトグル表示/非表示
  - CGEvent tap によるグローバルキーイベント監視
  - 他のアプリがフォーカス中でも反応
- フローティングウィンドウ（NSPanel）
- アクセシビリティ権限が必要

### リアルタイム更新
- DispatchSource でDBファイル + WALファイルの変更を監視
- フォールバック: 3秒間隔のポーリング（更新日時チェック）
- デバウンス: 1秒（連続操作の衝突防止）
- 外部プロセス（CLI, MCP Server）による変更も自動反映

### カンバンボードUI
- 4カラム: 未着手 / 進行中 / 今日やる / 完了
- カード表示: タスク名、期限、優先度ラベル、カテゴリラベル、サブタスク数、メモアイコン
- ドラッグ&ドロップでステータス変更
- フィルタバー: 優先度（高/中/低）、カテゴリ（SPECRA/業務委託/個人）
- ダークテーマ（中間色ベース）

### カラー定義
| 要素 | 色 |
|------|-----|
| 背景 | #191919 |
| カラム背景 | #252525 |
| カード背景 | #525252 |
| カードボーダー | #666666 |
| タスク名テキスト | #e8e8e8 |
| 期限テキスト（通常） | #cccccc |
| 期限テキスト（期限切れ） | #e8c84a（黄色・太字） |
| 未着手ドット | #9b9b9b |
| 進行中ドット | #6ba3d6 |
| 今日やるドット | #d4a76a |
| 完了ドット | #7bc8a4 |
| 優先度・高 | #d4837b |
| 優先度・中 | #d4a76a |
| 優先度・低 | #7bc8a4 |
| カテゴリ・SPECRA | #82b5d6 |
| カテゴリ・業務委託 | #d4c07a |
| カテゴリ・個人 | #b8a0d2 |

- ラベルスタイル: 色背景 + ダークグレー文字（#2a2a2a）

### タスク編集
- カードクリックで編集モーダル表示
- 編集項目: タスク名、ステータス、期限（DatePicker）、優先度、カテゴリ、タグ、メモ
- メモ: 編集/プレビュー切替（MarkdownUIでレンダリング）
- サブタスク: 追加・チェックボックスでトグル・削除
- 削除: 確認ダイアログあり（サブタスクも一緒に削除）
- 完了時: 未完了サブタスクがある場合は確認ダイアログ

### タスク追加
- 各カラム下部に「+ 新規タスク」ボタン
- インラインフォームでタスク名入力

### ソート順
- 優先度順（高 > 中 > 低 > なし）
- 同優先度内は期限順（早い順、期限なしは後ろ）
- サブタスクはid順

## CLI仕様 (`task.sh`)

```bash
./task.sh list              # 一覧（未完了のみ）
./task.sh list --all        # 全件（完了含む）
./task.sh add "タスク名" --due 2026-02-20 --category SPECRA --priority 高
./task.sh done <id>         # 完了にする
./task.sh update <id> --status 進行中 --due 2026-02-20 --priority 中
./task.sh show <id>         # 詳細表示
./task.sh delete <id>       # 削除
./task.sh export            # JSONエクスポート
```

## MCP Server仕様 (`mcp-server/`)

Claude Desktop アプリから自然言語でタスク操作するためのMCPサーバー。

### セットアップ
Claude Codeに依頼して開発・設定を行う。
- `mcp-server/` ディレクトリに Node.js プロジェクトとして実装
- `~/Library/Application Support/Claude/claude_desktop_config.json` に登録
- Node.jsのフルパスを指定（`~/.nodebrew/current/bin/node` など環境依存）

### 提供ツール
| ツール名 | 説明 |
|----------|------|
| `list_tasks` | タスク一覧（フィルタ: ステータス/カテゴリ/優先度） |
| `show_task` | タスク詳細表示 |
| `add_task` | タスク追加（名前、優先度、カテゴリ、期限、タグ、メモ、サブタスク） |
| `update_task` | タスク更新 |
| `complete_task` | タスク完了（サブタスク一括完了オプション） |
| `delete_task` | タスク削除（サブタスクも削除） |

### 実装方針
- 永続的な単一DB接続（毎回開閉しない）
- `db.transaction()` で複数操作を原子的に実行
- WALモード + busy_timeout=10秒

## サブタスク仕様

- `parent_task_id` カラムによる親子関係（1階層のみ）
- カンバンボード上では親タスクのカード内に折りたたみ表示
- 展開で一覧表示、完了数/全体数を表示
- サブタスクは独立カードとしてカラムに表示しない

## 将来の拡張（今回は対象外）
- iPhone連携（iCloud経由）
- Cloudflare D1移行（マルチデバイス対応）
- メニューバーアイコンクリックでクイックビュー
- 通知（期限切れアラート）
- サブタスクの複数階層対応
