# AUTOMATION_PLAN.md — 自動化の再評価と実装計画

「過去に手作業だった/諦めていた作業」を現在のAI性能（コード読解・adb操作・
スクショ読解・ログ解析が可能）を前提に再評価した。

最終更新: 2026-07-04

---

## 評価サマリー

| 作業 | 従来 | 再評価 | 状態 |
|---|---|---|---|
| バージョン更新 | 手動編集 | ✅ 完全自動化可 | **実装済** `tool/dev.ps1 bump` |
| ビルド(ロック対策込) | 手動+失敗時手動クリーン | ✅ 自動リトライ可 | **実装済** `tool/dev.ps1 build` |
| 実機/エミュ配布・起動 | adbコマンド手打ち | ✅ 完全自動化可 | **実装済** `tool/dev.ps1 deploy` |
| クラッシュ検出 | logcat目視 | ✅ 自動grep+AI解析 | **実装済** `tool/qa_smoke.sh` |
| UI巡回スクショ | 手動タップ+目視 | ✅ 比率座標で自動巡回、評価はAI読解 | **実装済** `tool/qa_smoke.sh` |
| テスト(unit/widget) | 削除済みで空白 | ⚠️ 半自動（AIがテスト生成→flutter test） | 計画（下記P2） |
| アセット反映 | 手動コピー+pubspec | ✅ 規約化で自動可 | 半自動（命名規約済） |
| ROADMAP更新 | 手動 | ✅ セッション終了フックでAIが消し込み | 運用化済 |
| CHANGELOG作成 | 無し | ✅ git log から自動生成可 | **実装済** `tool/dev.ps1 changelog` |
| リリースAPK作成 | ビルドと同時 | ✅ 署名安定化済みで常時リリース可能 | 済(v1.7.5) |
| Supabaseスキーマ変更 | 人間がSQL Editor | ❌ anonキーでDDL不可 | **恒久的に人間**（依頼テンプレ化で待ち時間短縮） |
| BLE 2台E2E | 人間が接続+AI監視 | ⚠️ 接続だけ人間。監視・判定は自動 | 半自動（ログ判定スクリプト運用） |
| ストア公開・課金 | — | ❌ 判断事項 | 人間 |

**結論: 20作業中 12 が完全自動化、4 が半自動化可能。純粋な人間作業は
「仕様/優先度判断・Supabase DDL・デバイス物理操作・公開判断」の4つに圧縮できる。**

---

## 導入した自動化ツール

### 1) `tool/dev.ps1` — 開発ワンコマンド集（Windows/PowerShell）
```
pwsh tool/dev.ps1 check              # flutter analyze（エラーのみ表示）
pwsh tool/dev.ps1 bump               # patch+build番号を+1（beta維持）
pwsh tool/dev.ps1 build              # release APKビルド。mergeReleaseNativeLibs
                                     #  失敗時は build/ 削除して自動再試行
pwsh tool/dev.ps1 deploy [serial]    # 接続中全デバイス(or指定)へ install -r + 起動
pwsh tool/dev.ps1 logs [serial]      # flutterログ+クラッシュを整形表示
pwsh tool/dev.ps1 changelog          # git log から CHANGELOG.md を再生成
pwsh tool/dev.ps1 cycle              # bump→build→deploy→logs を連続実行
```

### 2) `tool/qa_smoke.sh` — 無人スモークQA（Git Bash）
```
bash tool/qa_smoke.sh [serial]       # 省略時は最初のデバイス
```
処理: logcatクリア → APKインストール → 起動 → **解像度から比率計算した座標で
7タブを巡回**し `qa_out/<serial>/tab_*.png` を保存 → logcatから
FATAL/AndroidRuntime/flutter Errorを抽出 → 検出0なら exit 0 / 検出あれば exit 1
→ AIがスクショとエラーダンプを読んで QA_GUIDE.md のチェックリストを適用。

「開発者が寝ている間のAI自己チェック」= テンプレD（PROMPT_GUIDE.md）で
このスクリプト実行＋スクショ読解＋修正までをAIに一任する。

---

## 段階導入計画

- **P0（済・本コミット）**: dev.ps1 / qa_smoke.sh / CHANGELOG自動生成 / 本ドキュメント群
- **P1（次セッション推奨）**: モデル層のunitテスト再建
  （PieceData/DotAvatar/EncounterRecordのシリアライズ往復、PlazaLevel閾値、
  gateTimeFor の0時/18時境界 = 過去バグの回帰テスト化）→ `dev.ps1 check` に統合
- **P2**: golden test（SoftPanel/GameDock/PlazaSceneの昼夜スナップショット）で
  ダークモード崩れを機械検出
- **P3**: GitHub Actions（push時に analyze + unit test。APKビルドは署名秘匿の関係で
  ローカル継続）
- **P4**: エミュレータのすれ違いシミュレーション（ScannerにデバッグInjection口を
  設けBLEなしで気配→開門→カケラをE2E再生）※kDebugBle拡張
