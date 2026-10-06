# はじめての散歩 — チュートリアルUI

更新: 2026-10-06 / beta1.13.3+56
正本: REQUIREMENTS.md。reference.pngはデザイン参照専用で、アプリ素材として切り抜かない。

## 既存実装の確認
- lib/ui/onboarding_screen.dart: 旧9ページ、onboarding_done_v1をSharedPreferencesへ保存。
- lib/app.dart: フラグ読み込み → チュートリアル → 初回プロフィール → HomeScreen（今日）。
- lib/providers/ble_providers.dart: 初回プロフィール保存後、既存_autoStart → requestPermissions。
- lib/ui/settings_screen.dart: 再閲覧終了時にNavigator.pop。プロフィールや履歴の初期化なし。
- UserIcon / DotAvatarView / PixelWorld / PixelDoor / PixelPanelを再利用。
- 開門時刻表示はNotificationService.gateHoursを利用（画像の数値を転記しない）。

## UI構成
1. 昼の入口: ようこそ、門と自分のドット絵。
2. 広場を歩く: 自分・デモ住民・固定のシルエット、BluetoothとGPS不使用。
3. 夕方の門: 朝昼夜と既存時刻、正体を伏せた気配。実際の遭遇データを読まない。
4. 出会い: 初対面・再会の吹き出し、軽い喜び、図鑑の見本。DMの表現なし。
5. 夜の入口: Bluetooth利用理由、GPS不使用、本名・連絡先不要、広場をはじめる。

スワイプ／つぎへ／5点インジケーター。スキップは最終説明ページへ移動する。
開始時は従来の完了フラグを保存してonDoneを呼ぶ。初期設定／OS権限要求は従来どおり。
再閲覧では既存のNavigator.popを呼び、権限要求・プロフィール保存・初期化を行わない。
保存中は二重タップを抑制し、失敗時は再試行できる。初回フラグを更新移行でリセットしない。

## デザイン
本編のパレット・角丸8pxパネル・コーラル主ボタンを利用。
背景は共通広場の昼夜を連続的にクロスフェード。夕方は薄い色調。
空・風景・前景を既存パララックス強度で少し移動し、自分は数pxだけ上下左右に移動。
OSのアニメーション抑制設定では背景移動・住民待機を停止しページ移動を短縮する。
テキスト・操作は動く背景から独立。SafeArea、説明の縦スクロール、固定下部ボタン。
テーマは既存Palette.nightでライト／ダーク対応。絵文字なし。

## 正式アセットTODO
- チュートリアル専用の分割昼／夕方／夜背景（現在は共通昼夜の中景）。
- 石造りのアーチ・閉門／開門（現在は本編のCanvas仮門）。
- 歩行／向き変更のキャラクターフレーム（現在は保存済み自分の絵＋小さな移動）。
- 他ユーザーのデモ住民（現在は既存デフォルトスマイル、実ユーザーデータを使わない）。
- 図鑑の見開き・再会のピクセルエフェクト（現在は独自パネルと線画）。

本編UI、BLE、権限管理、API、保存モデル、通知、開門判定は変更しない。

## 検証画面
- [ライト・入口](implemented-light.png)
- [ダーク・入口](implemented-dark.png)
- [ダーク・夜の入口](implemented-night.png)
- [ライト・夜の入口](implemented-night-light-theme.png)

Pixel 10で両テーマ5ページを巡回。50テスト成功、解析エラー0、release APK成功。実機／iOSの今回更新は未検証。
