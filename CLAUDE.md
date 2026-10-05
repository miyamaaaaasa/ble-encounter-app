# CLAUDE.md — はじめましてこんにちは（BLE Encounter App）

このリポジトリで作業するときの恒久ルール。詳細は各ドキュメントを参照。

## プロジェクト
「Bluetoothですれ違った人との出会いを楽しむコミュニティゲーム」。SNSではない。

## 絶対維持事項（破壊禁止）
GPS不使用 / BLE中心設計 / 匿名性 / 気配演出 / 開門システム（朝9・昼12・夜21）/
回転トークン方式 / プライバシー保護（数値の抽象化・正確な時刻や場所を出さない）

過去の修正（0時バグ・18時バグ・カウント爆増バグ・BLE安定化・R8対策・永続化群）を
壊さない。これらは `test/` の回帰テストで固定化済み。

## 標準サイクル
分析 → 実装 → `dev.ps1 check` → `dev.ps1 test` → `dev.ps1 build` → デプロイ →
QA（`qa_smoke.sh`）→ commit（`git commit -F <file>`）→ push → ドキュメント更新

## セッション終了時に必ず行うこと
1. 関連するソース資料・Obsidianノートの古い記述を現状と照合し、根拠のある範囲で更新する。未確認は未確認と書く
2. REPORT.md を更新（コード・検証・設計上の判断があった場合）
3. commit / push（意味のある改善単位ごと）
4. **各プロジェクト関連のユーザー発言と応答を、その都度Obsidianへ即時記録してから応答を完了する**。コード変更がなくても実行:
   ```
   python tool/obsidian_sync.py --session "<依頼・決定・応答の事実要約。秘密情報は含めない>"
   ```
   → vault (`H:\マイドライブ\obsirian\projects\ble-encounter-app/`) に資料・履歴・作業ログが記録される

`tool/obsidian_sync.py` はリポジトリ文書・Git履歴をミラーするだけで、会話内容や事実関係を自動推論しない。資料の現況確認・修正と、会話要約の記録を両方行う。旧 `projects/アプリ開発/` は重複アーカイブ。正本は `projects/ble-encounter-app/`。

## UI作業の追加ルール
- Todayを含め、既存7タブ・機能・操作・表示情報を独断で削除しない
- Todayのスキャン状態、お知らせ、気配、出会いカルーセルとメタデータ、三つの開門・カウントダウン・開封、過去30日履歴を維持
- 見た目のモックと実装仕様を区別し、省略・追加・変更を明記してから実装

## 参照ドキュメント
- [PROMPT_GUIDE.md](PROMPT_GUIDE.md) — 有効なルール全集（UI/UX/BLE/Git/命名）
- [WORKFLOW.md](WORKFLOW.md) — 開発工程と統合サイクル
- [QA_GUIDE.md](QA_GUIDE.md) — 4ゲートQA・AIコードレビュー観点
- [AUTO_TEST_PLAN.md](AUTO_TEST_PLAN.md) — 実機/エミュ役割分担・テストレシピ
- [ROADMAP.md](ROADMAP.md) / [ROADMAP_RECOMMENDATION.md](ROADMAP_RECOMMENDATION.md)
- [PLAZA_DESIGN.md](PLAZA_DESIGN.md) / [PREFECTURE_PLAN.md](PREFECTURE_PLAN.md)

## ツール
```powershell
pwsh tool/dev.ps1 <check|test|bump|build|deploy|logs|changelog|cycle|release>
bash  tool/qa_smoke.sh [serial]      # 無人スモークQA
python tool/qa_diff.py <serial>      # スクショ差分QA
python tool/asset_audit.py           # アセット監査
python tool/obsidian_sync.py         # Obsidian同期
```
