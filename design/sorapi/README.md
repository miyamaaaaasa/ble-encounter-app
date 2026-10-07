# そらぴ正式導入 — beta1.13.5+58

更新: 2026-10-08。今回の正本。既存5ページ／5タブを維持し、案内役の表示だけを統合する。

## 調査と変更範囲

既存OnboardingScreen、TodayScreen、GateRevealScreen、PlazaScene、GameCenter／CatalogScreen、PuzzleBoardScreen、HomeScreenのIndexedStackを確認。共通PixelWorld／PixelDoor／UserIcon、既存時刻・権限・完了フラグ・遷移を再利用。BLE、遭遇モデル、AppNotifier、API、DB、通知、アカウント管理は変更しない。CupertinoTabBarも維持する。

## 正式素材と再生成

- `source-sheet.png`: ユーザー提供の正式そらぴ素材の原本。実行時には読み込まない。
- `assets/branding/app_icon_source.png`: ユーザー提供の完成済み夕暮れアイコン原本。
- `assets/branding/app_icon.png`: 原本の透明角だけを夕方色で合成した不透明画像。構図・キャラクターを描き直さない。
- `tool/prepare_sorapi.py`: 原本の指定セルから文字／隣接セルの端を除き、透明128×144pxへnearestで揃える。`crops.json`が切り出し座標の記録。別デザインの生成は行わない。
- Runtime PNG18枚: idle／blink／look／wait／sit／sleep／wave／jump／happy／trouble／think／book／discover／walk_0〜4。原本・確認シートはAPKへ含めない。
- 再生成: `python tool/prepare_sorapi.py`。原本からの再生成後はcontact sheetと全ポーズの輪郭を再確認する。

Androidはmdpi〜xxxhdpi、Launcher＋Adaptive foreground/background。Adaptive foregroundは16%insetで主要キャラクターを中央に残す。iOSは既存AppIcon.appiconsetのiPhone／iPad／1024pxアイコン。1024pxはRGBでalphaなし。
`dart run flutter_launcher_icons`で再生成できるが、使用中の0.14.4がproject.pbxprojの`ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS`をYESからAppIconへ誤変換したため、今回2箇所をYESへ戻した。再実行時も差分を点検する。署名・Bundle ID・アプリ名を変更しない。

## 状態の対応

| 場面 | 表示 | データへの影響 |
|---|---|---|
| チュートリアル1 | 手を振って歓迎 | 案内役と明記 |
| 2 | 5フレーム歩行 | 他人は既存見本／シルエット |
| 3 | 後ろ姿で門を待つ | 時刻はgateHours、遭遇データを読まない |
| 4 | 手を振って初対面／再会を案内 | 見本の住民はそらぴに置換しない |
| 5 | 夜の門で送り出す | 既存完了フラグ・権限導線のまま |
| 今日 | 門待ち／5分前は考える／BLE停止時は困る | 非公開人数をリアクションに使わない |
| 広場 | 花の近くで座る | residentsリストへ加えない |
| 開門中 | 門の横で待つ／新規は喜ぶ／再会は手を振る | 既存reveal呼び出しを維持 |
| 結果 | 0人は座る、1人以上喜ぶ、再会手を振る、10人以上ジャンプ | 公開済み結果だけを使う |
| 図鑑Empty | 本を読む | ユーザーとして登録しない |
| カケラEmpty／読み込み | 考える／歩く | PuzzleProviderはそのまま |
| ゲーム | 小さく応援 | 近日公開の状態を維持 |
| 設定・フォーム | 追加しない | 情報操作を邪魔しない |

手振り・喜びは提供静止ポーズ＋1pxの上下、ジャンプは最大6px。新しい未提供フレームを生成していない。sleep／discoverは素材として整理したが、今回は専用のランダム睡眠・カケラ獲得演出を追加していない。

## 軽量化と安全性

SorapiはUIだけのWidgetでEncounterRecordを参照しない。18枚の小画像をnearest表示しRepaintBoundaryで分離。歩行／待機差分／軽い喜びだけ180ms周期。静止ポーズにはTimerを作らない。非表示タブはTickerMode、背景移行／別route／スクロール画面外／OS動き抑制ではTimerを停止する。画面外から戻ると再開しdispose時に解除。
既存背景・パララックス内の配置を使い、文字／ボタンに重ねない。人数・履歴・レベルにそらぴを加えない。開門前の人数・人物一覧を増やさず、正常BLEのヘッダーに常時ステータスを戻さない。文字SEなし。

## 確認とTODO

- Flutter55テスト成功。0時／18時／重複、保存、削除状態、5タブ、5ページ・文字拡大2倍・両テーマ、結果0/1/8/24人の公開情報だけ表示、skip保存1回、動き抑制／非表示タブ停止を含む。
- Android release APK59.2MB。静的解析エラー0・既存85件。アセット参照欠損0。iOS1024pxは不透明、各Contents参照ファイルの実在を確認。
- Pixel 10で両テーマのチュートリアル全5ページ・再閲覧終了とデータ保持、ライトToday／広場を確認。最終APKの夜テーマ5タブ・生存・対象例外ログ0、Launcherで夕暮れアイコンも確認済み。
- 実機は未接続、MacのTailscale SSHがtimeout。iOSの今回のビルド／iPhone／iPad表示、Android実機Launcher／BLE相互通信は未確認。
- 開門演出のUI既読は既存`_celebrated`がセッション内だけ。再起動をまたぐ祝福抑止は未実装のまま。今回のそらぴ表示で保存・開門判定を変更せず、別途UI既読の永続化を行う必要がある。
- 仕様の「3時間インターバル」と既存の「BLE2分ごと・解析3分ごと」は異なる。今回タイミングは変更していない。
- 正式な石造り門・分割背景は既存TODO。そらぴに合わせて門を作り直さない。

この更新はキャラクターとアイコンの統合であり、未検証項目を含むため全実機での完了とは扱わない。
