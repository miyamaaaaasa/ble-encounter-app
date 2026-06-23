import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../core/peer_id.dart';
import '../models/template_message.dart';

// ─── イベント ─────────────────────────────────────────────────────────────────

class EncounterEvent {
  final DateTime time;
  final String peerId;
  final String macAddress;
  final String name;
  final int colorIndex;
  final int rssi;
  final TemplateMessage template;

  const EncounterEvent({
    required this.time,
    required this.peerId,
    required this.macAddress,
    required this.name,
    required this.colorIndex,
    required this.rssi,
    this.template = const TemplateMessage(),
  });
}

// ─── スキャナー ───────────────────────────────────────────────────────────────

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
      androidScanMode: AndroidScanMode.lowLatency,
      continuousUpdates: true,
    );

    _scanSub = FlutterBluePlus.onScanResults.listen(
      (results) {
        for (final r in results) _processResult(r);
      },
      onError: (e) => debugPrint('[BleScanner] error: $e'),
    );
  }

  Future<void> stop() async {
    await _scanSub?.cancel();
    _scanSub = null;
    if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    _emittedPeers.clear();
    _partialPeers.clear();
  }

  void dispose() {
    _scanSub?.cancel();
    _controller.close();
  }

  void _processResult(ScanResult result) {
    final mac = result.device.remoteId.str;
    final mfData = result.advertisementData.manufacturerData;

    // flutter_blue_plus は scan response を primary ad の同じ manufacturer ID に結合して届ける。
    // フォーマット: [0xBE][peerId 16B][0xFF][0xFE][0xBF][color][name...][0x00][ts][th][td][tp]
    final payload = mfData[_mfId];
    if (payload == null || payload.length < 17 || payload[0] != _magicPeer) return;

    final peerId = payload
        .skip(1)
        .take(16)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    if (peerId == _myPeerIdHex) return;

    String? name;
    int colorIndex = 0;
    TemplateMessage template = const TemplateMessage();

    if (payload.length >= 21 &&
        payload[17] == 0xFF &&
        payload[18] == 0xFE &&
        payload[19] == _magicProfile) {
      colorIndex = payload[20] & 0xFF;
      final dataBytes = payload.length > 21 ? payload.sublist(21) : <int>[];
      final sepIdx = dataBytes.indexOf(0x00);
      if (sepIdx >= 0) {
        name = sepIdx > 0
            ? utf8.decode(dataBytes.sublist(0, sepIdx), allowMalformed: true).trim()
            : '';
        // 0x00 の後ろ 4 バイトが定型文インデックス
        if (dataBytes.length >= sepIdx + 5) {
          template = TemplateMessage(
            statusIndex:   dataBytes[sepIdx + 1] & 0xFF,
            hobbyCategory: dataBytes[sepIdx + 2] & 0xFF,
            hobbyDetail:   dataBytes[sepIdx + 3] & 0xFF,
            phraseIndex:   dataBytes[sepIdx + 4] & 0xFF,
          );
        }
      } else {
        name = dataBytes.isNotEmpty
            ? utf8.decode(dataBytes, allowMalformed: true).trim()
            : '';
      }
      debugPrint('[BleScanner] FULL mac=$mac id=${peerId.substring(28)} name=$name');
    } else if (payload.length >= 20 && payload[17] == _magicProfile) {
      colorIndex = payload[18] & 0xFF;
      final dataBytes = payload.length > 19 ? payload.sublist(19) : <int>[];
      final sepIdx = dataBytes.indexOf(0x00);
      if (sepIdx >= 0) {
        name = sepIdx > 0
            ? utf8.decode(dataBytes.sublist(0, sepIdx), allowMalformed: true).trim()
            : '';
        if (dataBytes.length >= sepIdx + 5) {
          template = TemplateMessage(
            statusIndex:   dataBytes[sepIdx + 1] & 0xFF,
            hobbyCategory: dataBytes[sepIdx + 2] & 0xFF,
            hobbyDetail:   dataBytes[sepIdx + 3] & 0xFF,
            phraseIndex:   dataBytes[sepIdx + 4] & 0xFF,
          );
        }
      } else {
        name = dataBytes.isNotEmpty
            ? utf8.decode(dataBytes, allowMalformed: true).trim()
            : '';
      }
      debugPrint('[BleScanner] FULL2 mac=$mac id=${peerId.substring(28)} name=$name');
    } else {
      _partialPeers[mac] = _PartialData(peerId: peerId, rssi: result.rssi);
      return;
    }

    final partial = _partialPeers[mac];
    final finalRssi = partial?.rssi ?? result.rssi;
    _tryEmit(peerId, mac, name ?? '', colorIndex, template, finalRssi);
  }

  void _tryEmit(String peerId, String mac, String name,
      int colorIndex, TemplateMessage template, int rssi) {
    if (_emittedPeers.contains(peerId)) return;
    if (name.isEmpty) return;
    _emittedPeers.add(peerId);
    debugPrint('[BleScanner] ENCOUNTER id=${peerId.substring(28)} name=$name');
    _controller.add(EncounterEvent(
      time: DateTime.now(),
      peerId: peerId,
      macAddress: mac,
      name: name,
      colorIndex: colorIndex,
      template: template,
      rssi: rssi,
    ));
  }
}

class _PartialData {
  final String peerId;
  final int rssi;
  const _PartialData({required this.peerId, required this.rssi});
}
