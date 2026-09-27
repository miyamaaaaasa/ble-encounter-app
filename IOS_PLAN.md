# IOS_PLAN.md — iOS版の開発計画

Macを入手したので iOS 版に着手する。最終更新: 2026-09-26

---

## 最初に理解すべき制約

このアプリはトークンを **manufacturer data**（`[0xBE][token 16byte]`）で流している。
**iOSのCoreBluetoothはmanufacturer dataをアドバタイズできない**（流せるのは
ローカル名とサービスUUIDのみ）。つまり現行方式はiOSでは実装不可能。

さらに背面動作には次の非対称がある。

| 経路 | 可否 |
|---|---|
| iOS(背面) が Android を検出 | ○ サービスUUID指定スキャンは背面でも動く |
| **Android が iOS(背面) を検出** | **× 不可能**。iOSは背面時、広告をApple独自形式の領域へ移すため他社端末は復号できない |
| iOS(背面) ↔ iOS(背面) | ○ ただし検出は遅い（数十秒〜数分） |
| いずれか前面 | ○ |

**中央の行はプロトコルをどう変えても解決しない。OSの仕様。**

---

## 解決方針: すれ違いを「相互記録」にする（実装済み）

片方向の検出でも双方の出会いとして成立させることで、上記の非対称を無効化する。

- AがBのトークンを解決 → サーバーがB側にも「Aとすれ違った」を記録
- iOS(背面)がAndroidを検出できれば、その1回で両者の出会いが成立する
- AndroidがiOS(背面)を見られなくても問題にならない

プライバシー上は等価（どちらの記録も「2台が近くにあった」という同じ事実。
位置も正確な時刻も持たない）。Android同士でも取りこぼしが減る副次効果がある。

| 実装 | 状態 |
|---|---|
| `mutual_encounters` テーブル | 済 |
| `recordMutualEncounters()`（resolve時に相手側へ記録） | 済 |
| `GET /v1/encounters/mutual` | 済 |
| 48時間で自動削除 | 済（メンテナンスgoroutine） |
| アプリ側の取り込み | 済（`_mergeMutualEncounters()`。実機確認は未） |

検証済み: AがBのトークンを解決すると、B側の `/v1/encounters/mutual` にAが現れ、
A側には現れない（自分で検出済みのため二重にならない）。

---

## 実機検証結果（2026-09-26）

iPhone 15（iOS 27.0）＋ Pixel 5 ＋ A202SH で、**iOSを「見つける専門」として参加させる構成**を検証した。

| 検証 | 結果 |
|---|---|
| iPhoneでの起動・画面表示・サーバー登録 | OK |
| iPhoneの「スキャン中」表示 | OK（beta1.11.0+51 で修正後） |
| **iPhone が Android(A202SH) を検出** | **OK** — サーバーに `Yuki <- iPhone15` を記録 |
| **iPhone が Android(Pixel) を検出** | **OK** — `PixelA <- iPhone15` |
| **Android側アプリが相互記録を取り込む** | **OK** — Pixelで `[Mutual] merged 2 encounters` |

**Swiftを1行も書かずに、iPhone↔Androidのすれ違いが両者に成立した。**
Android側はiPhoneの電波を一度も受けていない（iPhoneは電波を出していない）が、
相互記録によって出会いが残る。

### 追加検証（beta1.12.0+52・iOS側アドバタイズ実装後）

iOSはサービスUUIDのみを流し、トークンはGATTのcharacteristicで渡す方式を実装
（`ios/Runner/AppDelegate.swift` の `BleAdvertiserPlugin`、受信側は `scanner.dart` の
`_readTokenViaGatt`）。iPhone 15（iOS 27.0）＋ iPad Pro 12.9 第2世代（iPadOS 17.7）＋ Pixel 5 で確認。

| 経路 | 結果 | 証跡（サーバーの相互記録） |
|---|---|---|
| **iPhone → iPad** | **OK** | `iPad <- iPhone15` 9/26 21:17 |
| **iPad → iPhone** | **OK** | `iPhone15 <- iPad` 9/26 21:20 |
| **Android → iPhone（GATTで読む）** | **OK** | `iPhone15 <- PixelA` 9/26 16:45 |
| **Android → iPad（GATTで読む）** | **OK** | `iPad <- PixelA`／Pixelログ `GATT token id=739c` |

これで **iOS↔iOS、iOS↔Android の全組み合わせが画面オン時に成立**した。

検証中の落とし穴: Macのターミナルで前の `flutter run` が動いたままだと、次の
`flutter run -d <別端末>` が実行されない（`q` で終了してから実行する）。

**未確認: 画面ロック中（背面）での検出。** iOSは背面でスキャン頻度を大きく絞るため、実用上の検出率は別途測る必要がある。

---

## 残作業

### 1. アプリ側で相互記録を取り込む（済・実機確認は未）

`ApiService.fetchMutualEncounters()` と `_mergeMutualEncounters()` を実装済み。
`_autoResolveNow()` の**先頭**で呼ぶ（保留トークンが無くても実行する必要がある。
自分が誰も検出していなくても、相手が自分を検出している可能性があるため）。

**未検証**: 端末が接続されていないため実機での確認ができていない。
2台つないで、片方だけがもう片方を検出する状況を作って確かめること。

### 2. iOSのBLE実装（Swift）

Androidの `BleAdvertiserChannel.kt`(131行) に対応するものを Swift で書く。
`GattChannel` / `GattServerManager` / `GattClientManager` は現在Dart側から
呼ばれていない死にコードなので、移植不要。

| 機能 | iOSでの実装 |
|---|---|
| アドバタイズ | `CBPeripheralManager.startAdvertising`（サービスUUIDのみ） |
| トークンの受け渡し | GATTのcharacteristicとして公開し、相手が接続して読む |
| スキャン | `CBCentralManager.scanForPeripherals(withServices:)` ※背面では必ずUUID指定 |
| 背面復帰 | `CBCentralManagerOptionRestoreIdentifierKey` |

Android側にも、iOSから読めるようGATTサーバーの復活が必要になる可能性がある。
`ios_handoff/HANDOFF_PROMPT.md` に6月時点の詳細な設計メモがある。

### 3. iOSプロジェクトの土台（済）

| 項目 | 状態 |
|---|---|
| `ios/` ディレクトリ再生成 | 済 |
| Bundle ID `jp.hajimemashite.app` | 済 |
| 表示名「はじめましてこんにちは」 | 済 |
| `NSBluetoothAlwaysUsageDescription` | 済 |
| `UIBackgroundModes`（central/peripheral） | 済 |
| アプリアイコン | 未（`flutter_launcher_icons` の `ios: true` 化で生成できる） |

### 4. Mac側で最初にやること

```bash
# Xcode と CocoaPods が要る
xcode-select --install
sudo gem install cocoapods

git clone https://github.com/miyamaaaaasa/ble-encounter-app.git
cd ble-encounter-app
flutter pub get
cd ios && pod install && cd ..

# 実機で起動（無料アカウントでも自分の端末には入れられる。7日で失効）
flutter run --release
```

`flutter doctor` で Xcode 関連が緑になっていることを先に確認する。

---

## 費用と制約

| 項目 | 内容 |
|---|---|
| Apple Developer Program | **年額 $99**（Googleの$25買い切りと違い毎年かかる） |
| 登録なしでできること | 自分のiPhoneへのインストールと動作確認のみ（7日で失効・再インストール要） |
| 登録が必要なこと | TestFlight配布・App Store公開 |
| 審査 | Bluetoothの用途説明が必須。位置情報を使わない旨を明記済み |

---

関連: [ios_handoff/HANDOFF_PROMPT.md](ios_handoff/HANDOFF_PROMPT.md) /
[PLAY_RELEASE.md](PLAY_RELEASE.md) / [server/README.md](server/README.md)
