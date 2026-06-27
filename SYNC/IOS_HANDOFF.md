# iOS移植用・技術引き継ぎ仕様書
## はじめましてこんにちは (BLE Encounter App) — beta 1.5.13+20

> **このドキュメントは iOS担当AIが技術的な詳細を確認するためのもの。**
> タスク一覧・運用手順は `iOS_TASKS.md` と `ios_ai_prompt.md` を参照。

---

## 0. 最重要：移植の前提理解

### アーキテクチャ上の問題

BLEアドバタイズ機能が **Android専用のネイティブコード（Kotlin）** で書かれており、iOS に Swift 実装が存在しない。

```
lib/services/advertiser.dart
  └── MethodChannel('com.example.ble_encounter/ble_advertiser')
       ├── android/.../BleAdvertiserChannel.kt  ← 存在する
       └── ios/Runner/BleAdvertiserChannel.swift ← 存在しない ← 作る必要あり
```

BLEスキャン (`flutter_blue_plus`) は Flutter側でクロスプラットフォーム対応済み。

---

## 1. パッケージと iOS 対応状況

### pubspec.yaml（v1.5.13）

```yaml
flutter_riverpod: ^2.5.1
flutter_blue_plus: ^1.32.12    # BLEスキャン（クロスプラットフォーム）
path_provider: ^2.1.4
shared_preferences: ^2.3.2
share_plus: ^9.0.0
permission_handler: ^11.3.1
uuid: ^4.4.2
url_launcher: ^6.3.0
package_info_plus: ^8.1.0
flutter_local_notifications: ^17.2.3
timezone: ^0.9.4
```

| パッケージ | iOS対応 | 必要な追加設定 |
|---|---|---|
| `flutter_blue_plus` | ✅ | Info.plist にBluetooth権限必須 |
| `flutter_local_notifications` | ✅ | AppDelegate修正 + DarwinNotificationDetails |
| `permission_handler` | ✅ | Info.plist に各種権限キー必須 |
| `shared_preferences` 等 | ✅ | 不要 |
| `BleAdvertiser`（MethodChannel） | ❌ | **BleAdvertiserChannel.swift を書く** |
| `GattService`（MethodChannel） | ❌ | **GattPlugin.swift スタブを書く** |
| Android Foreground Service | ❌ | iOSには不要（no-op で対応） |

---

## 2. BLE プロトコル仕様（変更禁止）

| 項目 | 値 |
|---|---|
| **Service UUID** | `A7B3C9D1-E5F0-4A2B-8C6D-9E1F3A5B7C2D` |
| Manufacturer ID（Android scan response） | `0xFFFF` |
| Scan Response マジックバイト（peerId先頭） | `0xBE` |
| Scan Response プロフィールマーカー | `0xBF` |
| **Scan Response フォーマット** | `[0xBE][peerId 16B][0xBF][colorIdx 1B][prefecture 1B][name ASCII ≤7B]` |
| MethodChannel 名（アドバタイズ） | `com.example.ble_encounter/ble_advertiser` |
| MethodChannel 名（GATT） | `com.example.ble_encounter/gatt` |
| 開門時刻（固定） | 朝 9:00 / 昼 12:00 / 夜 21:00 |

---

## 3. iOS特有の制限

### BLEアドバタイズのバックグラウンド制限（最重要）

| 状態 | Androidの動作 | iOSの動作 |
|---|---|---|
| フォアグラウンド | serviceUUID + manufacturerData(0xFFFF) | serviceUUID + localName |
| バックグラウンド | Foreground Serviceにより継続 | **Overflow Areaのみ（serviceUUIDのみ）** |

**iOS バックグラウンドの Overflow Area**:
- バックグラウンドでは manufacturerData は送信不可
- serviceUUID のみが「Overflow Area」として送信される
- 相手が `scanForPeripherals(withServices: [serviceUUID])` でスキャンしている場合のみ検知可能
- **Android は Overflow Area を読めない**（Android → iOS バックグラウンド検知は困難）

**実装への影響**:
- iOS → Android 検知：Androidが完全なアドバタイズを受信可能 → ペイロード解析
- Android → iOS 検知（バックグラウンド）：serviceUUIDのみ受信 → GATT接続で補完が必要
- iOS → iOS 検知：Overflow Areaで互いに検知可能（serviceUUIDマッチ）

---

## 4. 作成・修正が必要なファイル

### 4-1. `ios/Runner/BleAdvertiserChannel.swift`（新規作成）

```swift
import Flutter
import CoreBluetooth

class BleAdvertiserChannel: NSObject, CBPeripheralManagerDelegate {

    private let methodChannel: FlutterMethodChannel
    private var peripheralManager: CBPeripheralManager?
    private var pendingResult: FlutterResult?
    private var pendingPeerId: Data?
    private var pendingProfile: Data?

    static let restoreIdentifier = "com.example.ble_encounter.peripheral"
    static let serviceUUID = CBUUID(string: "A7B3C9D1-E5F0-4A2B-8C6D-9E1F3A5B7C2D")

    init(messenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(
            name: "com.example.ble_encounter/ble_advertiser",
            binaryMessenger: messenger
        )
        super.init()
        methodChannel.setMethodCallHandler(handleMethodCall)
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startAdvertise":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "args required", details: nil))
                return
            }
            let peerId = (args["peerId"] as! FlutterStandardTypedData).data
            let profile = (args["profilePayload"] as! FlutterStandardTypedData).data
            startAdvertise(peerId: peerId, profile: profile, result: result)

        case "stopAdvertise":
            stopAdvertise()
            result(nil)

        case "startForegroundService", "stopForegroundService":
            // iOS にフォアグラウンドサービスは存在しない。no-op。
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func startAdvertise(peerId: Data, profile: Data, result: @escaping FlutterResult) {
        stopAdvertise()
        pendingPeerId = peerId
        pendingProfile = profile
        pendingResult = result

        let options: [String: Any] = [
            CBPeripheralManagerOptionRestoreIdentifierKey: BleAdvertiserChannel.restoreIdentifier
        ]
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: options)
    }

    private func stopAdvertise() {
        peripheralManager?.stopAdvertising()
        peripheralManager = nil
        pendingPeerId = nil
        pendingProfile = nil
    }

    // MARK: - CBPeripheralManagerDelegate

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else {
            if peripheral.state == .poweredOff {
                pendingResult?(FlutterError(code: "BT_OFF", message: "Bluetooth is off", details: nil))
                pendingResult = nil
            }
            return
        }
        guard let profile = pendingProfile else { return }

        // localName: プロフィールペイロードの name フィールドから取得
        // フォーマット: [0xBF][colorIdx][prefecture][name ASCII ≤7B]
        let nameStart = 3
        let nameData = profile.count > nameStart
            ? profile.subdata(in: nameStart..<min(profile.count, nameStart + 7))
            : Data()
        let nameStr = String(data: nameData, encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters) ?? ""

        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [BleAdvertiserChannel.serviceUUID],
            CBAdvertisementDataLocalNameKey: nameStr.isEmpty ? "hello" : nameStr,
        ]

        peripheral.startAdvertising(advertisementData)
        pendingResult?(nil)
        pendingResult = nil
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            print("[BleAdv] startAdvertising error: \(error)")
        } else {
            print("[BleAdv] advertising started")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        print("[BleAdv] willRestoreState")
    }
}
```

**Xcodeへの追加手順**:
1. `ios/Runner/` にファイルを配置
2. Xcode で `Runner` グループを右クリック → Add Files to "Runner"
3. `BleAdvertiserChannel.swift` を選択、Target Membership の `Runner` にチェック

---

### 4-2. `ios/Runner/AppDelegate.swift`（置き換え）

```swift
import Flutter
import UIKit
import UserNotifications

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as! FlutterViewController
    let _ = BleAdvertiserChannel(messenger: controller.binaryMessenger)
    // TASK-007 完了後: let _ = GattPlugin(messenger: controller.binaryMessenger)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound, .badge])
  }
}
```

---

### 4-3. `ios/Runner/Info.plist`（追記）

**現在の Info.plist には以下がある（確認済み）**:
- `NSBluetoothAlwaysUsageDescription` ✅
- `NSBluetoothPeripheralUsageDescription` ✅
- `UIBackgroundModes: [bluetooth-central, bluetooth-peripheral]` ✅

**追加が必要**:

```xml
<!-- UIBackgroundModes 配列に fetch を追加 -->
<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-central</string>
    <string>bluetooth-peripheral</string>
    <string>fetch</string>   <!-- 追加 -->
</array>

<!-- 通知権限の説明文（任意だが推奨） -->
<key>NSUserNotificationUsageDescription</key>
<string>すれ違い通知のためにお知らせを送信します</string>
```

---

### 4-4. `lib/services/notification_service.dart`（iOS対応追加）

**修正箇所 1**: `init()` メソッドの `InitializationSettings`:

```dart
// 変更前
const android = AndroidInitializationSettings('@mipmap/ic_launcher');
await _plugin.initialize(
  const InitializationSettings(android: android),
  ...
);

// 変更後
const android = AndroidInitializationSettings('@mipmap/ic_launcher');
const ios = DarwinInitializationSettings(
  requestAlertPermission: false,
  requestBadgePermission: false,
  requestSoundPermission: false,
);
await _plugin.initialize(
  const InitializationSettings(android: android, iOS: ios),
  ...
);
```

**修正箇所 2**: 全 `NotificationDetails` に iOS 設定を追加:

```dart
// 変更前
NotificationDetails(android: AndroidNotificationDetails(...))

// 変更後（sound, vibr 変数は既存のものを再利用）
NotificationDetails(
  android: AndroidNotificationDetails(...),
  iOS: DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: sound,
  ),
)
```

---

### 4-5. `ios/Podfile`（変更不要）

現在の設定で問題なし：
```ruby
platform :ios, '13.0'
```

---

## 5. GattPlugin.swift（スタブ実装、TASK-007）

```swift
import Flutter
import CoreBluetooth

class GattPlugin: NSObject {
    init(messenger: FlutterBinaryMessenger) {
        super.init()
        let channel = FlutterMethodChannel(
            name: "com.example.ble_encounter/gatt",
            binaryMessenger: messenger
        )
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "startGattServer", "stopGattServer",
                 "updateProfile", "showEncounterNotification":
                result(nil)
            case "readPeerProfile":
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
}
```

---

## 6. lib/services/advertiser.dart の呼び出し仕様（参考）

Flutter側からどう呼ばれているかの確認用：

```dart
// lib/services/advertiser.dart が呼ぶメソッド一覧
static const _channel = MethodChannel('com.example.ble_encounter/ble_advertiser');

// アドバタイズ開始
_channel.invokeMethod('startAdvertise', {
  'peerId': Uint8List,        // 16バイトのUUID
  'profilePayload': Uint8List, // [0xBF][colorIdx][prefecture][name...]
});

// アドバタイズ停止
_channel.invokeMethod('stopAdvertise');

// フォアグラウンドサービス（iOS では no-op で良い）
_channel.invokeMethod('startForegroundService');
_channel.invokeMethod('stopForegroundService');
```

---

## 7. Android実装の参考（Kotlin版）

`android/app/src/main/kotlin/com/example/ble_encounter/BleAdvertiserChannel.kt` が存在する。
Scan Response フォーマット（Kotlinコードより）:

```kotlin
// peerProfilePayload = ByteArray(20 + nameLen)
// [0] = 0xBE (magic)
// [1..16] = peerId bytes
// [17] = 0xBF (profile marker)
// [18] = colorIdx
// [19] = prefecture (0xFF if unknown)
// [20..] = name bytes (ASCII, max 7)
```

iOSでは manufacturerData でこのペイロードを送れないため、
- フォアグラウンド: localName で name を送る
- バックグラウンド: serviceUUID のみ（Overflow Area）
- プロフィール詳細: GATT接続で補完（将来実装）

---

## 8. デバッグ手順

```bash
# Step 1: クリーンビルド
flutter clean && flutter pub get
cd ios && pod install && cd ..

# Step 2: ビルド確認
flutter build ios --no-codesign

# Step 3: 実機デバッグ（Xcode経由）
open ios/Runner.xcworkspace
# Xcodeで実機を選択 → Cmd+R

# Xcodeコンソールフィルタ
# BleAdv / Notif / Error
```

### よくあるエラーと対処

| エラー | 対処 |
|---|---|
| `MissingPluginException: No implementation found for method startAdvertise` | BleAdvertiserChannel.swift がXcodeターゲットに追加されていない |
| `CBPeripheralManager state: unauthorized` | Info.plist の NSBluetooth*UsageDescription 確認 |
| `UNUserNotificationCenter: authorization not determined` | permission_handler で通知権限をリクエストしているか確認 |
| pod install エラー | `pod repo update` 後に再実行 |
| Swift コンパイルエラー | Xcodeのビルドターゲット iOS 13.0 を確認 |
