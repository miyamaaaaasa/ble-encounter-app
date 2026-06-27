# iOS タスク一覧

> **Android担当AIが書く。iOS担当AIが読んで実装する。**
> 完了したタスクは `[完了]` に更新して push すること。

---

## 現在のバージョン対応状況

| 対象 | Androidバージョン | iOS実装済みバージョン |
|---|---|---|
| Flutter/Dartコード | v1.5.13+20 | v1.2.0相当（要更新） |
| BleAdvertiserChannel（Swift） | ✅ Kotlin実装済み | ❌ 未実装 |
| GattPlugin（Swift） | ✅ Kotlin実装済み | ❌ 未実装 |
| 通知（iOS対応） | ✅ Android実装済み | ❌ 未実装 |

---

## 優先タスク

---

### [完了] TASK-001: BleAdvertiserChannel.swift の新規作成

**優先度**: 🔴 最高（これがないとアプリ起動時クラッシュ）  
**対象バージョン**: v1.2.0 → v1.5.13対応に必須  
**ブロック状況**: このタスク完了まで他のBLE機能は動かない

**内容**:

`ios/Runner/BleAdvertiserChannel.swift` を新規作成し、Xcodeの Runner グループに追加する。

実装するMethodChannel: `com.example.ble_encounter/ble_advertiser`

実装必須メソッド:
- `startAdvertise(peerId: Data, profilePayload: Data)` → CBPeripheralManager でアドバタイズ開始
- `stopAdvertise()` → アドバタイズ停止
- `startForegroundService()` → **iOS では何もしない（nil を返すだけ）**
- `stopForegroundService()` → **iOS では何もしない（nil を返すだけ）**

**Service UUID**: `A7B3C9D1-E5F0-4A2B-8C6D-9E1F3A5B7C2D`

**アドバタイズデータ（iOS制限あり）**:
- フォアグラウンド時: `CBAdvertisementDataServiceUUIDsKey` + `CBAdvertisementDataLocalNameKey`
- バックグラウンド時: serviceUUID のみ（iOS制限 = Overflow Area）

**完全な実装コード**: `SYNC/IOS_HANDOFF.md` の「2-3」セクションを参照。

**完了条件**:
- [ ] `ios/Runner/BleAdvertiserChannel.swift` が存在する
- [ ] Xcodeで Runner ターゲットに追加されている（Target Membership にチェック）
- [ ] `flutter build ios --no-codesign` が成功する
- [ ] 実機で起動して `MissingPluginException` が出ない

---

### [完了] TASK-002: AppDelegate.swift の修正

**優先度**: 🔴 最高（TASK-001と同時に実施）  
**対象バージョン**: v1.5.13

**内容**:

`ios/Runner/AppDelegate.swift` を以下の内容に置き換える：

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
    // flutter_local_notifications: フォアグラウンドでも通知を表示する
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    GeneratedPluginRegistrant.register(with: self)

    // BLEアドバタイズ MethodChannel を登録
    let controller = window?.rootViewController as! FlutterViewController
    let _ = BleAdvertiserChannel(messenger: controller.binaryMessenger)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // フォアグラウンドでも通知バナーを表示する
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound, .badge])
  }
}
```

**完了条件**:
- [ ] `AppDelegate.swift` が上記内容になっている
- [ ] ビルドが通る

---

### [完了] TASK-003: Info.plist の通知権限追記

**優先度**: 🟡 高  
**対象バージョン**: v1.5.13

**内容**:

`ios/Runner/Info.plist` の `<dict>` 内に以下を追記（`NSBluetoothAlwaysUsageDescription` の前後どこでも可）：

```xml
<key>NSUserNotificationUsageDescription</key>
<string>すれ違い通知のためにお知らせを送信します</string>
```

また `UIBackgroundModes` の `<array>` に `fetch` を追加：

```xml
<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-central</string>
    <string>bluetooth-peripheral</string>
    <string>fetch</string>   <!-- ← 追加 -->
</array>
```

**完了条件**:
- [ ] Info.plist に `NSUserNotificationUsageDescription` がある
- [ ] `UIBackgroundModes` に `fetch` がある

---

### [完了] TASK-004: XcodeのCapabilitiesでBackground Modes設定

**優先度**: 🔴 最高（GUIでやる必要あり）  
**対象バージョン**: 全バージョン共通

**内容**:

Xcodeを開いて以下を確認・設定する：

```
Runner.xcworkspace → Runner target → Signing & Capabilities
  → + Capability → "Background Modes" を追加
     ✅ Uses Bluetooth LE accessories
     ✅ Acts as a Bluetooth LE accessory
```

**これをやらないとバックグラウンドBLEが動かない。Info.plistを書くだけでは不十分。**

**完了条件**:
- [ ] Xcodeの Signing & Capabilities に Background Modes が表示されている
- [ ] 「Uses Bluetooth LE accessories」にチェックが入っている
- [ ] 「Acts as a Bluetooth LE accessory」にチェックが入っている

---

### [完了] TASK-005: notification_service.dart に iOS 通知対応を追加

**優先度**: 🟡 高  
**対象バージョン**: v1.5.13

**内容**:

`lib/services/notification_service.dart` を修正する。

**修正1**: `init()` の `InitializationSettings` に iOS設定を追加：

```dart
// 既存コード（android: のみ）
const android = AndroidInitializationSettings('@mipmap/ic_launcher');
await _plugin.initialize(
  const InitializationSettings(android: android),
  ...
);

// ↓ iOS追加後
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

**修正2**: 全 `NotificationDetails(android: ...)` に iOS設定を追加：

```dart
// 既存
NotificationDetails(android: AndroidNotificationDetails(...))

// ↓ iOS追加後
NotificationDetails(
  android: AndroidNotificationDetails(...),
  iOS: DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: sound,  // soundEnabled の値を使う
  ),
)
```

影響するメソッド: `scheduleGateNotifications()`, `scheduleEncounterNotification()`, `showEncounterNotification()`

**完了条件**:
- [ ] `DarwinInitializationSettings` が init() に追加されている
- [ ] 全通知メソッドに `DarwinNotificationDetails` が追加されている
- [ ] iOSでビルドが通る

---

### [完了] TASK-006: Dart側 flutter pub get & pod install でv1.5.13の依存関係を更新

**優先度**: 🟠 中（環境準備）  
**対象バージョン**: v1.5.13

**内容**:

```bash
flutter pub get
cd ios && pod install && cd ..
```

これにより `flutter_blue_plus: ^1.32.12`, `flutter_local_notifications: ^17.2.3` など最新依存が入る。

**完了条件**:
- [ ] `flutter pub get` が成功
- [ ] `pod install` が成功
- [ ] Podfile.lock が更新されている

---

### [完了] TASK-007: GattPlugin.swift のスタブ作成（後回し可）

**優先度**: 🟢 低（BLEスキャン動作確認後に実施）  
**対象バージョン**: v1.5.x

**内容**:

MethodChannel `com.example.ble_encounter/gatt` に対するiOSスタブを作成する。
まず全メソッドが `result(nil)` を返すだけの最小実装でよい。

```swift
// ios/Runner/GattPlugin.swift
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
            // TODO: 本実装。現在はスタブ。
            switch call.method {
            case "startGattServer", "stopGattServer",
                 "updateProfile", "showEncounterNotification":
                result(nil)
            case "readPeerProfile":
                result(nil)  // nilはプロフィール未取得を意味する
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
}
```

AppDelegate.swift の `BleAdvertiserChannel` 登録の後に `GattPlugin` も追加する：

```swift
let _ = BleAdvertiserChannel(messenger: controller.binaryMessenger)
let _ = GattPlugin(messenger: controller.binaryMessenger)  // ← 追加
```

**完了条件**:
- [ ] `GattPlugin.swift` が Runner ターゲットに追加されている
- [ ] アプリ起動時に `MissingPluginException: gatt` が出ない

---

## 完了済みタスク

（まだなし）

---

## 更新履歴

| 日付 | 更新者 | 内容 |
|---|---|---|
| 2026-06-28 | Android AI | 初版作成。TASK-001〜007を登録 |
