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

  /// iOSの画面ロック中にネイティブ側が拾ったトークンを回収する（取り出すと消える）。
  /// Dartのサイクルはロック中に止まるため、その間の検出はここから受け取る。
  Future<List<({String hex, DateTime at})>> drainBackgroundTokens() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return const [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('drainBackgroundTokens');
      return [
        for (final e in raw ?? const [])
          if (e is List && e.length >= 2 && e[0] is String && e[1] is num)
            (hex: e[0] as String,
             at: DateTime.fromMillisecondsSinceEpoch((e[1] as num).toInt())),
      ];
    } catch (e) {
      debugPrint('[BleAdvertiser] drainBackgroundTokens: $e');
      return const [];
    }
  }
}
