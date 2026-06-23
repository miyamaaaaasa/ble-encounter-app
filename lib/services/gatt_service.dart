import 'package:flutter/services.dart';

class GattService {
  static const _channel = MethodChannel('com.example.ble_encounter/gatt');

  Future<void> startServer(String profileJson) =>
      _channel.invokeMethod('startGattServer', {'profileJson': profileJson});

  Future<void> stopServer() => _channel.invokeMethod('stopGattServer');

  Future<void> updateProfile(String profileJson) =>
      _channel.invokeMethod('updateProfile', {'profileJson': profileJson});

  /// Returns profile JSON from peer, or null on failure/timeout.
  Future<String?> readPeerProfile(String macAddress) =>
      _channel.invokeMethod<String?>('readPeerProfile', {'mac': macAddress});

  Future<void> showEncounterNotification(String name) =>
      _channel.invokeMethod('showEncounterNotification', {'name': name});
}
