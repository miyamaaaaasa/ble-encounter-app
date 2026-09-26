import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../core/constants.dart';

/// Kotlin の BluetoothLeAdvertiser を Platform Channel 経由で操作するラッパー。
///
/// ネイティブ実装: Android は BleAdvertiserChannel.kt、iOS は AppDelegate.swift の
/// BleAdvertiserPlugin。それ以外のプラットフォームでは何もしない
/// （未実装のまま呼ぶと MissingPluginException で起動処理ごと止まるため）。
///
/// iOSはトークンを電波に載せられないため、サービスUUIDのみを流し、
/// トークンはGATT経由で渡す（受信側の処理は scanner.dart の _readTokenViaGatt）。
class BleAdvertiser {
  static const _channel = MethodChannel(Constants.methodChannel);

  static bool get _supported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

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
