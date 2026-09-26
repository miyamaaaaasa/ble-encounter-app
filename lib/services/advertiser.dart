import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../core/constants.dart';

/// Kotlin の BluetoothLeAdvertiser を Platform Channel 経由で操作するラッパー。
///
/// ネイティブ実装はAndroidにしか無い。iOSで呼ぶと MissingPluginException になり、
/// 呼び出し側の起動処理ごと中断してスキャン（検出）まで止まってしまうため、
/// Android以外では何もしない。
///
/// iOSは当面「見つける専門」として参加する。iOSがAndroidを検出すれば、
/// サーバーの相互記録（/v1/encounters/mutual）によってAndroid側にも出会いが残る。
/// iOSから電波を出す実装（CoreBluetoothのPeripheral）は IOS_PLAN.md の残作業。
class BleAdvertiser {
  static const _channel = MethodChannel(Constants.methodChannel);

  static bool get _supported => defaultTargetPlatform == TargetPlatform.android;

  Future<void> startAdvertise(Uint8List peerId, Uint8List profilePayload) async {
    if (!_supported) return;
    await _channel.invokeMethod<void>('startAdvertise', {
      'peerId': peerId,
      'profilePayload': profilePayload,
    });
  }

  Future<void> stopAdvertise() async {
    if (!_supported) return;
    await _channel.invokeMethod<void>('stopAdvertise');
  }

  /// Androidのフォアグラウンドサービス（常駐通知）。iOSには相当する仕組みが無く、
  /// 背面動作は Info.plist の UIBackgroundModes で宣言する。
  Future<void> startForegroundService() async {
    if (!_supported) return;
    await _channel.invokeMethod<void>('startForegroundService');
  }

  Future<void> stopForegroundService() async {
    if (!_supported) return;
    await _channel.invokeMethod<void>('stopForegroundService');
  }
}
