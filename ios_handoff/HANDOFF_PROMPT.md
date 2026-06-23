# iOS すれ違い通信アプリ 引き継ぎドキュメント
## Android 版との相互通信を実現する iOS アプリの開発

---

## 1. アプリ概要

ニンテンドー3DS の「すれ違い通信」を再現する匿名 BLE アプリ。
近くにいる人（BLE 範囲内）を自動検出し、名前と一言メッセージを交換する。
サーバー不使用・GPS 不使用・BLE アドバタイズのみで動作。

### 主要機能
- BLE スキャン + アドバタイズによる匿名すれ違い検出
- デバイス固有の永続 UUID（アプリ再起動でも同一人物と認識）
- 1時間クールダウン（同一人物を連続カウントしない）
- 今日の遭遇人数表示（大きな数字）
- 図鑑（全期間の遭遇履歴）
- 通知（すれ違い即時通知・毎日の集計通知）

---

## 2. BLE プロトコル仕様（最重要）

### 2.1 Android が送信するパケット

**プライマリアドバタイズ（ADV_IND）**
```
Manufacturer ID : 0xFFFF  (little-endian で [FF][FF])
Payload         : [0xBE][peerId 16 bytes]  = 17 bytes 固定
```

**スキャンレスポンス（SCAN_RSP）**
```
Manufacturer ID : 0xFEFF  (little-endian で [FF][FE])
Payload         : [0xBF][colorIdx][name ASCII ≤10 bytes][0x00][message ASCII ≤14 bytes]
                  合計最大 27 bytes
```

フィールド定義：
- `0xBE` : peerId マジックバイト
- `peerId` : 16 bytes の UUID（デバイス固定・ランダム生成・初回のみ変わる）
- `0xBF` : プロフィールマジックバイト
- `colorIdx` : 0〜5 のアバターカラーインデックス
- `name` : ASCII 文字列（最大 10 bytes = 10 文字）
- `0x00` : セパレータ
- `message` : ASCII 文字列（最大 14 bytes）

### 2.2 Android のスキャン側がどう受信するか

`flutter_blue_plus` は プライマリ ad と スキャンレスポンスを **manufacturer ID `0xFFFF` の下に結合** して返す：

```
[0xBE]          peerId magic
[peerId 16]     デバイス固定 UUID
[0xFF][0xFE]    スキャンレスポンスの manufacturer ID (little-endian)
[0xBF]          プロフィール magic
[colorIdx]      カラーインデックス
[name bytes]    ASCII 名前
[0x00]          セパレータ
[msg bytes]     ASCII メッセージ
```

### 2.3 iOS 側の制約と必要な対応

⚠️ **iOS の CoreBluetooth は Manufacturer Data をアドバタイズに含めることができない。**

iOS が広告できるのは：
- Service UUID
- Local Name（バックグラウンドでは不可）
- Service Data

したがって **iOS は以下のフォーマットで広告する**：

**iOS アドバタイズ案（Service UUID + Service Data 使用）**

```
Service UUID   : A7B3C9D1-E5F0-4A2B-8C6D-9E1F3A5B7C2D  (128-bit)
Service Data   : [0xBE][peerId 16 bytes][0xBF][colorIdx][name ASCII ≤10 bytes][0x00][message ASCII ≤14 bytes]
```

- `0xBE` : peerId マジック（peerId が続くことを示す）
- `peerId` : 16 bytes UUID
- `0xBF` : プロフィールマジック
- 以降は Android の Scan Response と同じフォーマット

**バックグラウンドでも動作するため Service UUID を必ず含めること。**

### 2.4 Android スキャン側への追加変更（本プロジェクトでも要変更）

Android スキャナーが iOS 端末を検出するためには、Service UUID `A7B3C9D1-E5F0-4A2B-8C6D-9E1F3A5B7C2D` のサービスデータも解析する必要がある。

Android 側 `scanner.dart` の `_processResult` に以下を追加（変更依頼として残す）：

```dart
// iOS デバイスの検出（Service Data 経由）
final serviceData = result.advertisementData.serviceData;
final iosUuid = Guid('A7B3C9D1-E5F0-4A2B-8C6D-9E1F3A5B7C2D');
final iosPayload = serviceData[iosUuid];
if (iosPayload != null && iosPayload.length >= 18 && 
    iosPayload[0] == 0xBE && iosPayload[17] == 0xBF) {
  // iosPayload[1..16] = peerId, [17] = 0xBF, [18] = colorIdx, [19..] = name/0x00/msg
  // 既存の _tryEmit と同じ処理に渡す
}
```

---

## 3. ペイロード解析（iOS 実装）

### iOS でのスキャン（Android 端末検出）

```swift
func centralManager(_ central: CBCentralManager,
                    didDiscover peripheral: CBPeripheral,
                    advertisementData: [String: Any],
                    rssi RSSI: NSNumber) {
    
    // Android デバイスの検出
    if let mfData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
       mfData.count >= 19 {
        
        let idLo = mfData[0]  // 0xFF
        let idHi = mfData[1]  // 0xFF  → manufacturer ID = 0xFFFF
        
        if idLo == 0xFF && idHi == 0xFF && mfData[2] == 0xBE {
            // peerId: bytes 3..18
            let peerId = mfData.subdata(in: 3..<19).hexString
            
            // プロフィール部分を探す（スキャンレスポンス結合済み、またはアクティブスキャン）
            // mfData[19]==0xFF, mfData[20]==0xFE, mfData[21]==0xBF のパターンを確認
            if mfData.count >= 23 && mfData[19] == 0xFF && mfData[20] == 0xFE && mfData[21] == 0xBF {
                let colorIdx = Int(mfData[22])
                let profileBytes = mfData.subdata(in: 23..<mfData.count)
                let (name, message) = parseNameAndMessage(profileBytes)
                // → encounter イベントとして処理
            }
        }
    }
    
    // iOS デバイスの検出（自分自身を除く）
    let targetUUID = CBUUID(string: "A7B3C9D1-E5F0-4A2B-8C6D-9E1F3A5B7C2D")
    if let svcData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
       let payload = svcData[targetUUID],
       payload.count >= 18,
       payload[0] == 0xBE, payload[17] == 0xBF {
        
        let peerId = payload.subdata(in: 1..<17).hexString
        let colorIdx = Int(payload[18])
        let profileBytes = payload.subdata(in: 19..<payload.count)
        let (name, message) = parseNameAndMessage(profileBytes)
        // → encounter イベントとして処理
    }
}

func parseNameAndMessage(_ bytes: Data) -> (String, String) {
    if let sepIdx = bytes.firstIndex(of: 0x00) {
        let name = String(bytes: bytes[..<sepIdx], encoding: .utf8)?.trimmingCharacters(in: .whitespaces) ?? ""
        let msgStart = bytes.index(after: sepIdx)
        let msg = msgStart < bytes.endIndex
            ? String(bytes: bytes[msgStart...], encoding: .utf8)?.trimmingCharacters(in: .whitespaces) ?? ""
            : ""
        return (name, msg)
    }
    return (String(bytes: bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespaces) ?? "", "")
}
```

### iOS でのアドバタイズ

```swift
// peerId（16 bytes）とプロフィールペイロードを組み立てる
let serviceUUID = CBUUID(string: "A7B3C9D1-E5F0-4A2B-8C6D-9E1F3A5B7C2D")

var serviceData = Data()
serviceData.append(0xBE)                    // magic
serviceData.append(contentsOf: peerIdBytes) // 16 bytes
serviceData.append(0xBF)                    // profile magic
serviceData.append(UInt8(colorIndex))       // color
serviceData.append(contentsOf: nameBytes)   // ASCII name ≤10 bytes
serviceData.append(0x00)                    // separator
serviceData.append(contentsOf: msgBytes)    // ASCII message ≤14 bytes

let advertisingData: [String: Any] = [
    CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
    CBAdvertisementDataServiceDataKey: [serviceUUID: serviceData],
    // LocalName はバックグラウンドでは含めない
]

peripheralManager.startAdvertising(advertisingData)
```

---

## 4. データモデル

### 自分のプロフィール（UserDefaults に保存）

```swift
struct OwnProfile: Codable {
    var name: String        // ASCII only, max 10 chars
    var message: String     // ASCII only, max 20 chars
    var colorIndex: Int     // 0〜5
    var registeredAt: Date  // 初回登録日
}
// Key: "own_profile_v1"
```

### デバイス固有 UUID（永続）

```swift
// Key: "device_uid_v1"
// Value: 32文字の hex string（16 bytes UUID）
// 初回のみ UUID().uuidString から生成し、以降は UserDefaults から読む
func loadOrCreatePeerId() -> Data {
    let key = "device_uid_v1"
    if let hex = UserDefaults.standard.string(forKey: key), hex.count == 32 {
        return Data(hexString: hex)!
    }
    let bytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
    let data = Data(bytes)
    UserDefaults.standard.set(data.hexString, forKey: key)
    return data
}
```

### すれ違いレコード（UserDefaults / ローカル DB に保存）

```swift
struct EncounterRecord: Codable {
    var peerId: String      // 32文字 hex
    var name: String
    var message: String
    var colorIndex: Int
    var firstMet: Date
    var lastMet: Date
    var meetCount: Int
    var rssi: Int
}
// Key: "encounters_v1"
// Value: [EncounterRecord] を JSONEncoder でエンコード
```

### すれ違いカウントロジック

```swift
// 同一 peerId で 1 時間以内なら meetCount を増やさない
func shouldCount(existing: EncounterRecord?) -> Bool {
    guard let e = existing else { return true }
    return Date().timeIntervalSince(e.lastMet) >= 3600
}

// 同一 peerId が来たら upsert
func upsertEncounter(event: EncounterEvent) {
    if let existing = encounters[event.peerId] {
        if shouldCount(existing: existing) {
            encounters[event.peerId] = existing.updatedWith(event: event)
        }
    } else {
        encounters[event.peerId] = EncounterRecord(from: event)
    }
    saveEncounters()
}
```

---

## 5. UI 画面構成

### タブ構成（4タブ）

| タブ | 内容 |
|---|---|
| 今日 | 今日の遭遇人数（大きな数字）+ 一覧 |
| 図鑑 | 全期間の遭遇履歴（累計 N 人） |
| プロフィール | 名前・一言・アバターカラー |
| 設定 | 通知設定・バージョン表示 |

### プロフィール設定画面

- Name フィールド：**ASCII のみ**、最大 10 文字（日本語・絵文字を弾く）
- Message フィールド：**ASCII のみ**、最大 20 文字（URL OK）
- アバターカラー：6色から選択（プリセット）
  ```swift
  let avatarColors = [
      Color(hex: "#378ADD"),
      Color(hex: "#1D9E75"),
      Color(hex: "#D85A30"),
      Color(hex: "#BA7517"),
      Color(hex: "#534AB7"),
      Color(hex: "#D4537E"),
  ]
  ```
- アイコン画像のアップロード機能は**なし**（BLE で送信不可なため）

### 遭遇レベルラベル

```swift
func encounterLabel(meetCount: Int) -> String {
    switch meetCount {
    case 50...: return "伝説"
    case 10...: return "常連"
    case 5...:  return "よく見る"
    default:    return "見かけた"
    }
}
```

### 電波強度（★）

```swift
func rssiToStars(_ rssi: Int) -> Int {
    if rssi >= -60 { return 5 }
    if rssi >= -70 { return 4 }
    if rssi >= -80 { return 3 }
    if rssi >= -90 { return 2 }
    return 1
}
```

### 時刻表示（匿名化）

```swift
func formatEncounterTime(_ date: Date) -> String {
    let diff = Date().timeIntervalSince(date)
    if diff < 3600   { return "1時間以内に出会いました" }
    if diff < 86400  { return "今日出会いました" }
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy/MM/dd"
    return fmt.string(from: date)
}
```

---

## 6. 通知

### 通知種類

| 種類 | タイミング | 設定キー |
|---|---|---|
| すれ違い通知 | 遭遇即時 | `notif_encounter_enabled` |
| 本日の結果 | 毎日指定時刻（デフォルト 20:00） | `notif_daily_enabled` |
| アプリ更新 | 将来実装（プレースホルダー） | `notif_update_enabled` |
| イベント | 将来実装（プレースホルダー） | `notif_event_enabled` |

### 通知設定の保存

```swift
UserDefaults.standard.set(hour,    forKey: "notif_hour")
UserDefaults.standard.set(minute,  forKey: "notif_minute")
UserDefaults.standard.set(enabled, forKey: "notif_daily_enabled")
// etc.
```

### iOS 通知

```swift
import UserNotifications

// すれ違い即時通知
func showEncounterNotification(name: String) {
    guard UserDefaults.standard.bool(forKey: "notif_encounter_enabled") else { return }
    let content = UNMutableNotificationContent()
    content.title = "すれ違いました！"
    content.body  = "\(name) さんとすれ違いました"
    content.sound = .default
    let request = UNNotificationRequest(identifier: UUID().uuidString,
                                        content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
}

// 毎日の集計通知（UNCalendarNotificationTrigger を使用）
func scheduleDailyNotification(hour: Int, minute: Int) {
    var comps = DateComponents()
    comps.hour   = hour
    comps.minute = minute
    let trigger  = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
    // ...
}
```

---

## 7. バックグラウンド動作

### Android
- Foreground Service で常駐
- `FOREGROUND_SERVICE_CONNECTED_DEVICE` permission

### iOS
- `CBCentralManagerOptionRestoreIdentifierKey` でバックグラウンド復元
- `CBPeripheralManagerOptionRestoreIdentifierKey` でアドバタイズ復元
- `Info.plist` に必須キー：
  ```xml
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>近くの人とすれ違い通信するために使用します</string>
  <key>UIBackgroundModes</key>
  <array>
    <string>bluetooth-central</string>
    <string>bluetooth-peripheral</string>
  </array>
  ```
- バックグラウンドでは Service UUID (`A7B3C9D1-E5F0-4A2B-8C6D-9E1F3A5B7C2D`) 指定スキャンのみ有効
- iOS がバックグラウンドで Android 端末を検出するには、Android 側が Service UUID を含む追加のアドバタイズを発行するか、GATT 接続経由にする必要がある（**既知の制約**）

---

## 8. バージョン管理ルール

- パッチ（右端）: バグ修正・小変更 → `1.1.1` → `1.1.2`
- マイナー（中央）: UI が変わる変更 → `1.1.x` → `1.2.0`
- バージョン文字列は `major.minor.patch` 形式（ビルド番号は表示しない）
- **毎回変更を加えるたびにバージョンを上げること**

---

## 9. Service UUID

```
A7B3C9D1-E5F0-4A2B-8C6D-9E1F3A5B7C2D
```

このUUIDは Android 側の `lib/core/constants.dart` にも定義されている。

---

## 10. 相互通信マトリクス

| 送信側 | 受信側 | 方式 | 動作 |
|---|---|---|---|
| Android | Android | Manufacturer Data (0xFFFF+0xFEFF) | ✅ 動作中 |
| Android | iOS (FG) | Manufacturer Data → iOS が読む | ✅ 動作可能 |
| Android | iOS (BG) | Service UUID なし → iOS スキャン不可 | ⚠️ 要対応 |
| iOS | Android | Service Data (Service UUID) → Android が読む | ⚠️ Android 側に追加実装必要 |
| iOS | iOS | Service Data (Service UUID) | ✅ 動作可能 |

**フルクロスプラットフォーム対応には Android scanner.dart の修正が必要（後述）。**

---

## 11. Android 側に必要な追加変更（iOS リリース時）

`lib/services/scanner.dart` の `_processResult` メソッドに iOS 端末検出を追加：

```dart
// iOS デバイスの検出（Service UUID 経由）
final serviceUuid = Guid('A7B3C9D1-E5F0-4A2B-8C6D-9E1F3A5B7C2D');
final iosPayload = result.advertisementData.serviceData[serviceUuid];
if (iosPayload != null && iosPayload.length >= 19 &&
    iosPayload[0] == 0xBE && iosPayload[17] == 0xBF) {
  final peerId = iosPayload
      .skip(1).take(16)
      .map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  if (peerId == _myPeerIdHex) return;
  final colorIndex = iosPayload[18] & 0xFF;
  final dataBytes = iosPayload.length > 19 ? iosPayload.sublist(19) : <int>[];
  final sepIdx = dataBytes.indexOf(0x00);
  final name = sepIdx > 0
      ? utf8.decode(dataBytes.sublist(0, sepIdx), allowMalformed: true).trim()
      : utf8.decode(dataBytes, allowMalformed: true).trim();
  final message = sepIdx >= 0 && sepIdx + 1 < dataBytes.length
      ? utf8.decode(dataBytes.sublist(sepIdx + 1), allowMalformed: true).trim()
      : '';
  _tryEmit(peerId, result.device.remoteId.str, name, message, colorIndex, result.rssi);
}
```

また、Android のアドバタイズにも Service UUID を追加することで iOS バックグラウンドから検出可能になる（`BleAdvertiserChannel.kt` の `advData` に `addServiceUuid` を追加）。
