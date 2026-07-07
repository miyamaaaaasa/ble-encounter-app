# QA_GUIDE.md — AIレビュー工程とチェックリスト

目的: 「開発者が寝ている間でもAIが自己チェックできる」QA体制。
実行手段: `bash tool/qa_smoke.sh`（機械検出）＋ AIによるスクショ読解（目視相当）。

最終更新: 2026-07-04

---

## QAゲート（コミット前に必ず通す）

```
Gate1 静的     flutter analyze エラー0（tool/dev.ps1 check）
Gate2 起動     qa_smoke.sh: プロセス生存 + FATAL/Exception 0件
Gate3 巡回     qa_smoke.sh の7タブスクショをAIが読解し下表を適用
Gate4 回帰     変更領域に応じた重点確認（下記マトリクス）
```
Gate2/3 で NG → 修正して Gate1 からやり直し。コミットしない。

---

## Gate3: スクショ読解チェックリスト（AI自己チェック）

各 `qa_out/<serial>/tab_*.png` に対して:

### 全画面共通
- [ ] クラッシュ画面・赤エラー(RenderFlex overflow の黄黒縞)が写っていない
- [ ] テキストの見切れ・重なりがない（…省略は許容）
- [ ] 背景がクリーム(昼)/藍(夜)で統一され、白/黒の「素の背景」が露出していない
- [ ] Material標準部品(青いリップル・素のAppBar)が新たに出現していない
- [ ] 正式ピクセルアイコンが表示されている（絵文字タブ・欠損□がない）
- [ ] 余白: 画面端20px基準、パネル間8-14pxが保たれている

### 画面別の要点
| タブ | 必須確認 |
|---|---|
| today | 開門3枚(朝昼夜アイコン+カウントダウンor開封ボタン)。人がいれば円弧カルーセル+吹き出し。正確な時刻(HH:MM)が出ていないこと |
| plaza | 広場シーン(空・地面・じぶん)。レベルバッジ表示。住民の文字が鏡文字でない |
| game | カートリッジ3枚カルーセル+ページドット |
| badge | 次の目標プログレス+コレクション棚 |
| kakera | 夜空テーマ維持・進捗パネル・電波解析ボタン |
| self | ドット絵 or イニシャルアバター、フォーム崩れなし |
| settings | 外観・ヘルプ/BLE/通知セクション。テーマ選択が現在値表示 |

### ダークモード検査（テーマ切替後に再巡回）
- [ ] 全タブで文字が読める（藍地に焦げ茶文字＝NG検出対象）
- [ ] SoftPanel/GameDock/吹き出しが夜色に追従
- [ ] カケラ画面は昼夜共通の夜空でOK

---

## Gate4: 変更領域別 回帰マトリクス

| 変更した領域 | 必ず確認する回帰ポイント |
|---|---|
| BLE(scanner/advertiser/providers) | `[Cycle] BLE ON/OFF`が周期通り / ENCOUNTERが1接近1回(爆増バグ再発なし) / hasProfile=false維持 |
| 時刻・ゲート関連 | gateTimeFor: 8:59→9時 / 11:59→12時 / 20:59→21時 / 21:01→翌9時 / **0時台→当日9時** / 18時台→21時 |
| 永続化(storage系) | アプリ強制終了(`am force-stop`)→再起動→データ残存(カケラ/アイコン/履歴/設定) |
| resolve系 | 機内モードで解析→「keeping N tokens」→復帰→自動解決 |
| テーマ/Palette | 昼夜両方で全タブ巡回（constにPalette色を入れていないか analyze で検出） |
| 通知 | ログに `gate notifications scheduled (exact)`（R8退行検出） |
| 署名/gradle | `install -r` がアンインストール無しで成功 |

---

## クラッシュ・エラー検出の運用

- 機械検出: qa_smoke.sh が `FATAL EXCEPTION / AndroidRuntime / flutter Exception|Error`
  をgrep（`server unreachable` はオフライン正常系として除外）
- null安全: analyzeで大半検出。実行時は上記grepで補足
- 検出時のAI手順: スタックトレース全文取得(`adb logcat -d | grep -A30 FATAL`) →
  原因コード特定 → 修正 → Gate1から再実行 → REPORTに「現象→原因→対処」を記録

## 無人夜間QAの回し方（テンプレDの実体）

1. `pwsh tool/dev.ps1 cycle`（bump→build→deploy→logs）
2. `bash tool/qa_smoke.sh`（昼テーマ巡回）
3. 設定でテーマ=夜に切替 → 再度 qa_smoke.sh（夜巡回）
4. スクショ全読解 → チェックリスト適用 → 問題は即修正してループ
5. 合格したら commit -F / push / REPORT更新して待機
