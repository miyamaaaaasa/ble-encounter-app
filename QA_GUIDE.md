# QA_GUIDE.md — AIレビュー工程とチェックリスト

目的: 「開発者が寝ている間でもAIが自己チェックできる」QA体制。
実行手段: `bash tool/qa_smoke.sh`（機械検出）＋ AIによるスクショ読解（目視相当）。

最終更新: 2026-10-17

---

## QAゲート（コミット前に必ず通す）

```
Gate0 レビュー  AIコードレビュー（下記チェックリスト。差分に対して実施）
Gate1 静的     flutter analyze エラー0（tool/dev.ps1 check）＋ flutter test 全パス
Gate2 起動     qa_smoke.sh: 更新成功 + 前面Activity + 有効PNG + プロセス生存 + FATAL/Exception 0件
Gate3 巡回     qa_smoke.sh の5タブスクショ＋移動先の画面確認をAIが読解し下表を適用
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
| today | 開門前は人数/相手非表示、公開後だけ出会い。正確な遭遇時刻を表示しない |
| plaza | 住民・ドット絵・プロフィール導線、気配の非公開維持 |
| game | 近日公開表示と既存カケラ導線。動かないゲームを合格扱いしない |
| catalog | 公開済みユーザー、ドット絵、バッジへの導線 |
| self | 名前・ドット絵・自己紹介、編集・設定への導線 |
| バッジ/カケラ/設定 | 上記タブからの移動先で保存/復元・夜空・通知設定・削除を確認 |

Android7/14共通で `dumpsys window` のmCurrentFocusを確認する（`dumpsys window windows` はAndroid14で情報が欠落する）。
実機がロック中なら操作を停止し、本人のロック解除を待つ。PINを取得しない。
`bash tool/test_qa_smoke.sh` はロック画面/欠落focus/正常VMログの誤判定を防ぐ回帰検査。
インストール失敗をskipしない。古い端末は非ストリーミングで更新し、uninstallやclear dataで既存データを消さない。

### ダークモード検査（テーマ切替後に再巡回）
- [ ] 全タブで文字が読める（藍地に焦げ茶文字＝NG検出対象）
- [ ] SoftPanel/GameDock/吹き出しが夜色に追従
- [ ] カケラ画面は昼夜共通の夜空でOK

---

## Gate0: AIコードレビュー チェックリスト（コミット前・差分対象）

| 観点 | 具体チェック |
|---|---|
| null安全 | `!` 強制解放の根拠 / fromMap系のnull・型違い耐性（不正入力→フォールバック） |
| 永続化漏れ | 新しいユーザー状態は save + 起動時 load + `_v1`キー命名になっているか。メモリだけに置いていないか |
| BLE影響 | scanner/advertiser/cycle への変更は _cycleOnActive ガード・_emittedPeers（爆増防止）・token-only payload を壊していないか |
| 状態管理 | setStateの範囲は最小か（全画面毎秒rebuild禁止）。Notifierのstate直接mutate禁止（copyWith） |
| 非同期 | await後の `mounted` チェック / Future内のsetState前ガード / 多重実行ガード（isResolving等） |
| パフォーマンス | 毎フレーム/毎秒処理は対象Widgetを最小化（AnimatedBuilder/専用StatefulWidget化）。build内での重い計算・I/O禁止 |
| メモリリーク | Timer/AnimationController/StreamSubscription/PageController は dispose必須。static ValueNotifierは意図の明記 |
| 世界観 | 正確な時刻/位置表現・Material部品・ハードコード色（Palette外）の混入なし |

実績: このゲートで検出→修正済みの例
- 祝福演出が起動時ストレージ復元でも発火（didUpdateWidgetの条件不備）→ _warmup導入
- Today全画面が毎秒rebuild（_clockTimer）→ _CountdownText分離で該当Textのみ更新
- 住民の向き反転がイニシャルを鏡文字化 → 画像のみflip

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

## 2026-10-06 UI巡回の更新
今日／広場／ゲーム／図鑑／じぶんを巡回。バッジは図鑑、カケラはゲーム、設定とプロフィール編集はじぶんから開く。OSの夜設定だけでなくアプリ内のテーマ設定を確認する（保存したライト設定はOS設定より優先）。背景の昼夜は端末時刻に従い、UI配色と独立する。
