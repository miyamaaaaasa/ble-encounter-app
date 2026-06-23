import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../core/constants.dart';

/// Kotlin の BluetoothLeAdvertiser を Platform Channel 経由で操作するラッパー。
class BleAdvertiser {
  static const _channel = MethodChannel(Constants.methodChannel);

  Future<void> startAdvertise(Uint8List peerId, Uint8List profilePayload) async {
    await _channel.invokeMethod<void>('startAdvertise', {
      'peerId': peerId,
      'profilePayload': profilePayload,
    });
  }

  Future<void> stopAdvertise() async {
    await _channel.invokeMethod<void>('stopAdvertise');
  }

  Future<void> startForegroundService() async {
    await _channel.invokeMethod<void>('startForegroundService');
  }

  Future<void> stopForegroundService() async {
    await _channel.invokeMethod<void>('stopForegroundService');
  }
}
