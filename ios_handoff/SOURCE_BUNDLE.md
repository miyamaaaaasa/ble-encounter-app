# Android ソースコードバンドル
## iOS 開発者向け参照資料

---

## pubspec.yaml

```yaml
name: ble_encounter
description: BLEすれ違い検知アプリ
publish_to: 'none'
version: 1.2.0+4

environment:
  sdk: '>=3.3.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
  flutter_blue_plus: ^1.32.12
  path_provider: ^2.1.4
  shared_preferences: ^2.3.2
  share_plus: ^9.0.0
  permission_handler: ^11.3.1
  uuid: ^4.4.2
  url_launcher: ^6.3.0
  image_picker: ^1.1.2
  flutter_image_compress: ^2.3.0
  package_info_plus: ^8.1.0
  flutter_local_notifications: ^17.2.3
  timezone: ^0.9.4
```

---

## lib/core/constants.dart

```dart
class Constants {
  static const serviceUuid = 'A7B3C9D1-E5F0-4A2B-8C6D-9E1F3A5B7C2D';
  static const methodChannel = 'com.example.ble_encounter/ble_advertiser';
  static const maxDisplayLogs = 50;
}
```

---

## lib/core/peer_id.dart

```dart
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class PeerId {
  PeerId._();
  static const _prefKey = 'device_uid_v1';
  static Uint8List? _bytes;
  static String? _hex;

  static Uint8List get bytes { assert(_bytes != null); return _bytes!; }
  static String get hex {
    _hex ??= _bytes!.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return _hex!;
  }
  static String get shortHex => hex.substring(hex.length - 4);

  static Future<void> init() async {
    if (_bytes != null) return;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKey);
    if (stored != null && stored.length == 32) {
      _hex = stored;
      _bytes = Uint8List.fromList(
        List.generate(16, (i) => int.parse(stored.substring(i*2, i*2+2), radix: 16)),
      );
    } else {
      const uuid = Uuid();
      _bytes = Uint8List.fromList(uuid.v4obj().toBytes());
      _hex = _bytes!.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      await prefs.setString(_prefKey, _hex!);
    }
  }
}
```

---

## lib/models/own_profile.dart

```dart
import 'dart:convert';
import 'dart:typed_data';

class OwnProfile {
  final String name;
  final String message;
  final int colorIndex;
  final String? iconPath;
  final DateTime? registeredAt;

  const OwnProfile({
    required this.name,
    this.message = '',
    this.colorIndex = 0,
    this.iconPath,
    this.registeredAt,
  });

  // BLE Scan Response Payload
  // Format: [0xBF][colorIdx][name ASCII ≤10 bytes][0x00][message ASCII ≤14 bytes]
  Uint8List toScanPayload() {
    const totalAvail = 24; // 27 byte limit - 2 header - 1 separator
    const nameMax = 10;
    final nameBytes = _trimUtf8(utf8.encode(name), nameMax);
    final msgMax = (totalAvail - nameBytes.length).clamp(0, 14);
    final msgBytes = _trimUtf8(utf8.encode(message), msgMax);

    final out = BytesBuilder();
    out.addByte(0xBF);
    out.addByte(colorIndex & 0xFF);
    out.add(nameBytes);
    out.addByte(0x00);
    out.add(msgBytes);
    return out.takeBytes();
  }

  static List<int> _trimUtf8(List<int> bytes, int maxLen) {
    if (bytes.length <= maxLen) return bytes;
    int len = maxLen;
    while (len > 0 && (bytes[len] & 0xC0) == 0x80) len--;
    return bytes.sublist(0, len);
  }

  Map<String, dynamic> toMap() => {
    'n': name, 'm': message, 'c': colorIndex,
    if (iconPath != null) 'i': iconPath,
    if (registeredAt != null) 'r': registeredAt!.toIso8601String(),
  };
  String toStorageJson() => jsonEncode(toMap());

  static OwnProfile fromStorageJson(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    return OwnProfile(
      name: m['n'] as String? ?? '',
      message: m['m'] as String? ?? '',
      colorIndex: m['c'] as int? ?? 0,
      iconPath: m['i'] as String?,
      registeredAt: m['r'] != null ? DateTime.tryParse(m['r'] as String) : null,
    );
  }

  OwnProfile copyWith({String? name, String? message, int? colorIndex,
      String? iconPath, DateTime? registeredAt, bool clearIcon = false}) =>
      OwnProfile(
        name: name ?? this.name,
        message: message ?? this.message,
        colorIndex: colorIndex ?? this.colorIndex,
        iconPath: clearIcon ? null : (iconPath ?? this.iconPath),
        registeredAt: registeredAt ?? this.registeredAt,
      );
}
```

---

## lib/models/encounter_record.dart

```dart
import 'dart:convert';

class EncounterRecord {
  final String peerId;
  final String name;
  final String message;
  final int colorIndex;
  final DateTime firstMet;
  final DateTime lastMet;
  final int meetCount;
  final int rssi;

  const EncounterRecord({
    required this.peerId, required this.name, required this.message,
    required this.colorIndex, required this.firstMet, required this.lastMet,
    required this.meetCount, required this.rssi,
  });

  EncounterRecord updatedWith({required DateTime lastMet, required int rssi,
      String? name, String? message}) =>
      EncounterRecord(
        peerId: peerId, name: name ?? this.name,
        message: message ?? this.message, colorIndex: colorIndex,
        firstMet: firstMet, lastMet: lastMet, meetCount: meetCount + 1, rssi: rssi,
      );

  Map<String, dynamic> toMap() => {
    'peerId': peerId, 'name': name, 'message': message, 'colorIndex': colorIndex,
    'firstMet': firstMet.toIso8601String(), 'lastMet': lastMet.toIso8601String(),
    'meetCount': meetCount, 'rssi': rssi,
  };

  static EncounterRecord fromMap(Map<String, dynamic> m) => EncounterRecord(
    peerId: m['peerId'] as String, name: m['name'] as String? ?? '????',
    message: m['message'] as String? ?? '',
    colorIndex: m['colorIndex'] as int? ?? 0,
    firstMet: DateTime.parse(m['firstMet'] as String),
    lastMet: DateTime.parse(m['lastMet'] as String),
    meetCount: m['meetCount'] as int? ?? 1, rssi: m['rssi'] as int? ?? -99,
  );

  static String encodeList(List<EncounterRecord> list) =>
      jsonEncode(list.map((e) => e.toMap()).toList());
  static List<EncounterRecord> decodeList(String json) {
    final list = jsonDecode(json) as List;
    return list.map((e) => EncounterRecord.fromMap(e as Map<String, dynamic>)).toList();
  }
}
```

---

## lib/services/scanner.dart

```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../core/peer_id.dart';

class EncounterEvent {
  final DateTime time;
  final String peerId;
  final String macAddress;
  final String name;
  final String message;
  final int colorIndex;
  final int rssi;
  const EncounterEvent({required this.time, required this.peerId,
    required this.macAddress, required this.name, this.message = '',
    required this.colorIndex, required this.rssi});
}

class BleScanner {
  static const _mfId = 0xFFFF;
  static const _magicPeer    = 0xBE;
  static const _magicProfile = 0xBF;

  final _controller = StreamController<EncounterEvent>.broadcast();
  StreamSubscription<List<ScanResult>>? _scanSub;
  final _emittedPeers = <String>{};
  final _partialPeers = <String, _PartialData>{};
  Stream<EncounterEvent> get encounters => _controller.stream;
  final String _myPeerIdHex = PeerId.hex;

  Future<void> start() async {
    _emittedPeers.clear();
    _partialPeers.clear();
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) return;
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
      await Future.delayed(const Duration(milliseconds: 300));
    }
    await FlutterBluePlus.startScan(
      androidScanMode: AndroidScanMode.lowLatency, continuousUpdates: true);
    _scanSub = FlutterBluePlus.onScanResults.listen(
      (results) { for (final r in results) _processResult(r); },
      onError: (e) => debugPrint('[BleScanner] error: $e'),
    );
  }

  Future<void> stop() async {
    await _scanSub?.cancel(); _scanSub = null;
    if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    _emittedPeers.clear(); _partialPeers.clear();
  }

  void dispose() { _scanSub?.cancel(); _controller.close(); }

  void _processResult(ScanResult result) {
    final mac = result.device.remoteId.str;
    final mfData = result.advertisementData.manufacturerData;
    // flutter_blue_plus merges primary ad (0xFFFF) + scan response (0xFEFF) into 0xFFFF:
    // [0xBE][peerId 16][0xFF][0xFE][0xBF][colorIdx][name...][0x00][msg...]
    final payload = mfData[_mfId];
    if (payload == null || payload.length < 17 || payload[0] != _magicPeer) return;

    final peerId = payload.skip(1).take(16)
        .map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    if (peerId == _myPeerIdHex) return;

    String? name;
    String message = '';
    int colorIndex = 0;

    if (payload.length >= 21 && payload[17] == 0xFF && payload[18] == 0xFE && payload[19] == _magicProfile) {
      colorIndex = payload[20] & 0xFF;
      final dataBytes = payload.length > 21 ? payload.sublist(21) : <int>[];
      final sepIdx = dataBytes.indexOf(0x00);
      if (sepIdx >= 0) {
        name = sepIdx > 0 ? utf8.decode(dataBytes.sublist(0, sepIdx), allowMalformed: true).trim() : '';
        message = sepIdx + 1 < dataBytes.length
            ? utf8.decode(dataBytes.sublist(sepIdx + 1), allowMalformed: true).trim() : '';
      } else {
        name = dataBytes.isNotEmpty ? utf8.decode(dataBytes, allowMalformed: true).trim() : '';
      }
    } else if (payload.length >= 20 && payload[17] == _magicProfile) {
      colorIndex = payload[18] & 0xFF;
      final dataBytes = payload.length > 19 ? payload.sublist(19) : <int>[];
      final sepIdx = dataBytes.indexOf(0x00);
      if (sepIdx >= 0) {
        name = sepIdx > 0 ? utf8.decode(dataBytes.sublist(0, sepIdx), allowMalformed: true).trim() : '';
        message = sepIdx + 1 < dataBytes.length
            ? utf8.decode(dataBytes.sublist(sepIdx + 1), allowMalformed: true).trim() : '';
      } else {
        name = dataBytes.isNotEmpty ? utf8.decode(dataBytes, allowMalformed: true).trim() : '';
      }
    } else {
      _partialPeers[mac] = _PartialData(peerId: peerId, rssi: result.rssi);
      return;
    }

    final partial = _partialPeers[mac];
    _tryEmit(peerId, mac, name ?? '', message, colorIndex, partial?.rssi ?? result.rssi);
  }

  void _tryEmit(String peerId, String mac, String name, String message, int colorIndex, int rssi) {
    if (_emittedPeers.contains(peerId)) return;
    if (name.isEmpty) return;
    _emittedPeers.add(peerId);
    _controller.add(EncounterEvent(time: DateTime.now(), peerId: peerId,
        macAddress: mac, name: name, message: message, colorIndex: colorIndex, rssi: rssi));
  }
}

class _PartialData { final String peerId; final int rssi;
  const _PartialData({required this.peerId, required this.rssi}); }
```

---

## android/BleAdvertiserChannel.kt（Kotlin ネイティブ）

```kotlin
// Primary advertisement: manufacturerID=0xFFFF, payload=[0xBE][peerId 16bytes]
// Scan response:         manufacturerID=0xFEFF, payload=[0xBF][colorIdx][name ASCII ≤10][0x00][msg ASCII ≤14]

val settings = AdvertiseSettings.Builder()
    .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
    .setConnectable(true)   // scan response のために connectable=true 必須
    .setTimeout(0)
    .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
    .build()

// Primary ad: [0xBE][peerId 16bytes] = 17 bytes
val peerPayload = ByteArray(17)
peerPayload[0] = 0xBE.toByte()
System.arraycopy(peerId, 0, peerPayload, 1, 16)
val advData = AdvertiseData.Builder()
    .addManufacturerData(0xFFFF, peerPayload).build()

// Scan response: profilePayload = [0xBF][colorIdx][name][0x00][msg]
val scanResponse = AdvertiseData.Builder()
    .addManufacturerData(0xFEFF, profilePayload).build()

advertiser.startAdvertising(settings, advData, scanResponse, callback)
```

---

## アバターカラー定義（6色）

```swift
// iOS (SwiftUI)
let avatarColors: [Color] = [
    Color(hex: "378ADD"),  // index 0 - blue
    Color(hex: "1D9E75"),  // index 1 - green
    Color(hex: "D85A30"),  // index 2 - orange
    Color(hex: "BA7517"),  // index 3 - yellow-brown
    Color(hex: "534AB7"),  // index 4 - purple
    Color(hex: "D4537E"),  // index 5 - pink
]
```

---

## ロジック定義

### すれ違いカウント

```
同一 peerId で前回検出から 60分未満 → meetCount を増やさない
同一 peerId で 60分以上経過 → meetCount += 1、name/message を更新
新規 peerId → 新規レコード作成（meetCount = 1）
最大保存件数: 500件（最古を削除）
```

### レベルラベル

```
meetCount  0〜4  : "見かけた"
meetCount  5〜9  : "よく見る"
meetCount 10〜49 : "常連"
meetCount 50+   : "伝説"
```

### RSSI → 電波強度★

```
≥ -60 dBm : ★★★★★
≥ -70 dBm : ★★★★
≥ -80 dBm : ★★★
≥ -90 dBm : ★★
< -90 dBm : ★
```

### 時刻表示（匿名化）

```
経過 < 1時間  : "1時間以内に出会いました"
経過 < 1日    : "今日出会いました"
それ以上      : "YYYY/MM/DD"
```

---

## UserDefaults キー一覧

| キー | 型 | 内容 |
|---|---|---|
| `device_uid_v1` | String (32hex) | デバイス固有UUID（永続） |
| `own_profile_v1` | String (JSON) | 自分のプロフィール |
| `encounters_v1` | String (JSON) | すれ違いレコード配列 |
| `notif_hour` | Int | 毎日通知の時 |
| `notif_minute` | Int | 毎日通知の分 |
| `notif_daily_enabled` | Bool | 毎日通知 ON/OFF |
| `notif_encounter_enabled` | Bool | すれ違い即時通知 ON/OFF |
| `notif_update_enabled` | Bool | アプリ更新通知 ON/OFF |
| `notif_event_enabled` | Bool | イベント通知 ON/OFF |
