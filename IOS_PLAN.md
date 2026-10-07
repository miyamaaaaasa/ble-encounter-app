# iOS版 — 現況と検証計画

最終更新: 2026-10-08 / 現行: beta1.13.5+58

## 2026-10-08 そらぴ・正式アイコン

既存CupertinoTabBar／5画面／Bundle ID／権限を維持。共通Flutter UIに正式そらぴを統合し、AppIcon.appiconsetへ正式夕暮れアイコンを反映。1024pxはRGB・alphaなし。今回MacへのSSHがタイムアウトしたため、下記1.13.4の署名なし成功を今回のビルド成功とは扱わない。再接続後に更新ソースのビルドとiPhone／iPadのLauncher・5ページ・両テーマを確認する。

## 今回のiOS更新

CupertinoTabBarで5画面を保持。タブ遷移のWidgetテスト合格。Macの別チェックアウト `~/development/ble-encounter-codex-accounts` で署名なしreleaseをビルド済み。元チェックアウトの未コミット署名変更は保持。
SSH署名はerrSecInternalComponentで失敗。自動ビルド用LaunchAgentの登録は未承認の永続化として自動承認レビューに拒否され、登録していない。実機はオフラインだったため署名付きインストール未完了。
MacのGUI Terminalで `cd ~/development/ble-encounter-codex-accounts && bash tool/ios_release.sh <device-id>` を実行できる。

以下のBLE記録は過去の検証と現在の未確認項目。

## 実装済み

- Bundle ID `jp.hajimemashite.app`、Flutter iOSプロジェクト、Bluetooth利用説明、`bluetooth-central` / `bluetooth-peripheral` background modes。
- iOSはサービスUUIDを広告し、読み取り専用GATT characteristicから回転トークンを返す。manufacturer dataはiOSから広告しない。
- iOSスキャンはサービスUUIDで端末を探し、必要な場合にGATT接続してトークンを読む。BLEペイロードにプロフィール情報を載せない。
- サーバーの相互すれ違い記録を取り込み、片方だけの検出を双方の履歴へ反映する仕組み。
- 画面ロック中向けのSwiftネイティブBLE処理と、復帰時に保留トークンをFlutter側へ渡す経路を `2381229` で追加。

## 実機確認済み

2026-09-26、iPhone 15 / iPad Pro / Pixel 5 で画面オンのiOS↔iOS、Android↔iOSの組み合わせを確認。iOS GATT経由のトークン取得ログとサーバー側の相互記録を確認した。

## 画面ロック中の検証状況

2026-09-27、2台を使ったロック中テストを実施。サーバーには両方向の相互記録が更新されたが、`mutual_encounters.met_at` は端末がトークンを照合した時刻であり、BLE検出時刻ではない。そのため、この結果だけではロック中に端末がトークンを捕捉したと結論できない。現在の判定は **未確認**。

次回はデバッグログに「ネイティブ捕捉時刻」「フォアグラウンド／バックグラウンド区分」「Flutterへの受け渡し完了」を記録し、端末内キューと照合する。正確な時刻はQA証跡に限り、相手向けUI/APIに公開しない。トークン自体や端末固有識別子はログに出さない。

## 次の確認項目

1. Swift実装がMac上でビルドでき、両端末に対象バージョンが入っていることを確認する。
2. 画面ロック中の広告・スキャンがOSにより停止／制限される条件と、アプリの明示停止時にネイティブ処理も止まることを確認する。
3. 保留トークンをFlutterの永続ストレージへ保存してからネイティブキューを消費する順序、重複排除、上限超過時の扱いを確認する。
4. iPhone↔iPadロック試験をログ付きで再実施する。サーバー記録時刻だけを背景検出の証拠にしない。
5. 画面オンのAndroid↔iOS既存経路、Android同士の間欠スキャン、開門・気配・プライバシー回帰を確認する。

## 開発環境メモ

- iOSビルド・署名はMacが必要。MacのGUI TerminalでXcode署名し、SSH上の署名エラーと実機ビルド結果を混同しない。
- iOS GitHub Actionsワークフローは、存在しないiOSプロジェクトを参照していたため削除済み。Android `release.yml` は別系統。
- 現在の運用コマンドや依存バージョンはリポジトリの `README.md` / `pubspec.yaml` とGitHub Actions設定を確認する。

関連: [iOS引き継ぎプロンプト](ios_handoff/HANDOFF_PROMPT.md) / [iOSソース資料](ios_handoff/SOURCE_BUNDLE.md) / [ROADMAP.md](ROADMAP.md)
