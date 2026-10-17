# sure. 広告の導入・運用手順

更新: 2026-10-18 / beta1.13.12+65。AdMobの申込み・本番登録・ストア公開は未実施。

## 今回の実装

- `google_mobile_ads: 9.1.0`。Android/iOS共通のバナーと開門後インタースティシャル。
- 通常ビルドは `ADS_ENABLED=false`（既定）。アプリから広告SDKの初期化・広告リクエストをしない。
- 実機検証用は `--dart-define=ADS_ENABLED=true`。既定の `ADS_TEST_MODE=true` ではGoogle公式サンプルのアプリID・広告ユニットだけを使い、収益は発生しない。
- 全画面広告は、開門結果の保存に成功し、利用者が結果を閉じた後だけ。未読み込み・通信エラー・背景では即スキップし、後から突然表示しない。
- 同じ開門・過去の開門は繰り返さず、最低10分空ける。通常のタブ切替・結果再閲覧・シェアからは出さない。広告を見なくても既に保存された出会いは失われない。
- バナーはホームの専用領域に1枚だけ。コンテンツとタブに重ねない。「広告」ラベルと間隔を置き、失敗時は領域ごと隠す。
- 初回チュートリアル・登録・プロフィール編集・設定・開門結果・共有画像にはバナーを置かない。

## 全年齢向けというユーザー決定

13歳未満を含む。年齢や誕生日を新規収集せず、全員の広告を `AgeRestrictedTreatment.child`、最大レーティングG、非パーソナライズとして要求する。AndroidのAAID/AdServices関連権限をマニフェストのマージから除外し、iOSでは追跡許可を新規要求しない。

プロフィール・BLEトークン・すれ違い相手・時刻・履歴は広告リクエストに渡さない。ただし広告SDK自体はIP・端末情報・広告操作/診断等を送信し得るため、匿名BLE機能と同じ「外部送信なし」とは説明しない。設定画面とプライバシーポリシーに明示する。

本番は起動ごとにUMPの同意情報を更新し、必要なフォームを表示、`canRequestAds()`を確認してからSDKを初期化する。取得失敗は広告なしで続行。必要な場合は設定にUMPプライバシー選択の再表示入口を出す。テストIDには公開者のUMPメッセージが存在しないため、サンプルユニット限定でUMPを省略する。本番IDで省略する設定はない。

**本番開始前に**対象年齢・子ども向け申告、必要な年齢確認、Familiesの形式要件（5秒後に閉じられる等）と配信設定を確認する。全員を子ども向け扱いにするコードだけでストア審査に通るとは保証しない。メディエーションは未導入。

## 利用者本人が行う申込み

1. [Google AdMob](https://admob.google.com/home/)で自分のGoogleアカウントから申込み、居住国・支払・本人情報を確認する。パスワードをAIやチャットに渡す必要はない。
2. AndroidとiOSを別アプリとして登録する。内部IDは既存の `jp.hajimemashite.app` のまま。ストア未公開の場合もその状態を正しく申告する。
3. 各OSで「バナー」「インタースティシャル」を1つずつ作る。必要なのは2個のアプリID（`~`を含む）と4個の広告ユニットID（`/`を含む）。IDは秘密鍵ではない。
4. プライバシーとメッセージ、子ども向け・対象年齢、コンテンツブロック、全画面広告の配信形式と頻度を設定する。必要なUMPメッセージを公開する。
5. ストアとのリンク・app-ads.txt/アプリ所有権確認など、管理画面に表示される審査項目を完了する。Play Consoleの「広告あり」、データセーフティ、対象年齢・Families、App StoreのApp Privacyを実際のSDK構成で更新する。

アカウント契約・支払・ストア提出は今回自動実行していない。

## 本番への切替

最初にAndroid `android/app/src/main/AndroidManifest.xml` の `com.google.android.gms.ads.APPLICATION_ID` とiOS `ios/Runner/Info.plist` の `GADApplicationIdentifier` を、各OSの本番アプリIDへ置換する。サンプルIDのままでは本番開始しない。

Androidのビルド例（実IDを設定し、末尾のオプションごとにスペースを置く）:

```powershell
flutter build appbundle --release --dart-define=ADS_ENABLED=true --dart-define=ADS_TEST_MODE=false --dart-define=ADMOB_ANDROID_BANNER_ID=YOUR_ANDROID_BANNER_ID --dart-define=ADMOB_ANDROID_INTERSTITIAL_ID=YOUR_ANDROID_INTERSTITIAL_ID
```

iOSも同じスイッチに `ADMOB_IOS_BANNER_ID` と `ADMOB_IOS_INTERSTITIAL_ID` を指定する。アプリIDはDartのIDと別物。本番ユニット不足・形式不正・サンプルID指定時は広告初期化をしない。本番配信が不安定な場合は `ADS_ENABLED=false` で従来どおり広告なしに戻せる。

公式テストID以外で開発・クリック検証を行わない。本番広告の自己クリックは行わない。

## 検証と未確認範囲

beta1.13.12+65のFlutter84件、Android3実機の5タブ/起動ログ検査が成功。実機でテストバナー、Pixel10エミュレータで開門結果終了→テスト全画面広告→Close→元画面を確認した。本番広告・本番UMPの審査/配信確認とは区別する。

広告頻度、子ども向け/G/非パーソナライズ設定、無効版でネイティブSDKを呼ばないことを自動テストする。広告の閉じ方・実際のバナー寸法と誤タップ防止は実機で別途確認する。接続Macは今回SSHタイムアウトのためiOSのPod解決・Xcodeビルドは未確認。iOS最低対応OSやSKAdNetwork等は、実際のPod解決・審査設定を確認してから決定する。

## 一次資料

- [公式Flutter導入手順](https://developers.google.com/admob/flutter/quick-start)
- [同意取得（UMP）](https://developers.google.com/admob/flutter/privacy)
- [子ども向け・年齢設定](https://developers.google.com/admob/flutter/targeting)
- [Families広告要件](https://support.google.com/googleplay/android-developer/answer/9893335?hl=en)
- [Families SDKの現在の対象](https://support.google.com/googleplay/android-developer/answer/12955712?hl=en)
- [SDKのデータ開示](https://developers.google.com/admob/android/privacy/play-data-disclosure)

資料確認日: 2026-10-18。申込み画面の最新案内と、公開時点のポリシーを優先する。
