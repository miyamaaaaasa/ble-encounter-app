import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../core/peer_id.dart';

// ─── イベント ─────────────────────────────────────────────────────────────────

class EncounterEvent {
  final DateTime time;
  final String peerId;
  final String macAddress;
  final String name;
  final String message;
  final int colorIndex;
  final int rssi;

  const EncounterEvent({
    required this.time,
    required this.peerId,
    required this.macAddress,
    required this.name,
    this.message = '',
    required this.colorIndex,
    required this.rssi,
  });
}

// ─── スキャナー ───────────────────────────────────────────────────────────────

class BleScanner {
  static const _mfId = 0xFFFF;   // peerId & merged scan response
  static const _magicPeer    = 0xBE;
  static const _magicProfile = 0xBF;

  final _controller = StreamController<EncounterEvent>.broadcast();
  StreamSubscription<List<ScanResult>>? _scanSub;

  // 発火済み peerId（重複発火防止。stop() でリセット）
  final _emittedPeers = <String>{};

  // peerId のみ受信済みで name 未取得の端末（scan response 未マージ時の暫定保存）
  final _partialPeers = <String, _PartialData>{};  // mac → partial

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

    // flutter_blue_plus は scan response を primary ad の同じ manufacturer ID エントリに
    // 結合して届ける。フォーマット:
    //   [0]      = 0xBE (peerId magic)
    //   [1..16]  = peerId (16 bytes)
    //   [17]     = 0xFF  \
    //   [18]     = 0xFE  / scan response manufacturer ID (0xFEFF) little-endian
    //   [19]     = 0xBF (profile magic)
    //   [20]     = colorIndex
    //   [21..]   = name UTF-8
    final payload = mfData[_mfId];
    if (payload == null || payload.length < 17 || payload[0] != _magicPeer) return;

    // peerId を抽出
    final peerId = payload
        .skip(1)
        .take(16)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    if (peerId == _myPeerIdHex) return;  // 自分自身は無視

    // プロフィールを抽出（scan response が結合済みかチェック）
    String? name;
    String message = '';
    int colorIndex = 0;

    if (payload.length >= 21 &&
        payload[17] == 0xFF &&
        payload[18] == 0xFE &&
        payload[19] == _magicProfile) {
      // 結合済みフォーマット: [FF][FE][BF][color][name 0x00 msg] or [FF][FE][BF][color][name (legacy)]
      colorIndex = payload[20] & 0xFF;
      final dataBytes = payload.length > 21 ? payload.sublist(21) : <int>[];
      // 0x00 セパレータを探す（新フォーマット）
      final sepIdx = dataBytes.indexOf(0x00);
      if (sepIdx >= 0) {
        name = sepIdx > 0
            ? utf8.decode(dataBytes.sublist(0, sepIdx), allowMalformed: true).trim()
            : '';
        message = sepIdx + 1 < dataBytes.length
            ? utf8.decode(dataBytes.sublist(sepIdx + 1), allowMalformed: true).trim()
            : '';
      } else {
        // 旧フォーマット（0x00 なし）: 全バイトが name
        name = dataBytes.isNotEmpty
            ? utf8.decode(dataBytes, allowMalformed: true).trim()
            : '';
        message = '';
      }
      debugPrint('[BleScanner] FULL mac=$mac id=${peerId.substring(28)} name=$name msg=$message color=$colorIndex rssi=${result.rssi}');
    } else if (payload.length >= 20 && payload[17] == _magicProfile) {
      // 結合フォーマット 2: [BF][color][name 0x00 msg] (ID bytes なし)
      colorIndex = payload[18] & 0xFF;
      final dataBytes = payload.length > 19 ? payload.sublist(19) : <int>[];
      final sepIdx = dataBytes.indexOf(0x00);
      if (sepIdx >= 0) {
        name = sepIdx > 0 ? utf8.decode(dataBytes.sublist(0, sepIdx), allowMalformed: true).trim() : '';
        message = sepIdx + 1 < dataBytes.length
            ? utf8.decode(dataBytes.sublist(sepIdx + 1), allowMalformed: true).trim()
            : '';
      } else {
        name = dataBytes.isNotEmpty ? utf8.decode(dataBytes, allowMalformed: true).trim() : '';
        message = '';
      }
      debugPrint('[BleScanner] FULL2 mac=$mac id=${peerId.substring(28)} name=$name');
    } else {
      // peerId のみ（scan response 未マージ）→ 蓄積して待つ
      _partialPeers[mac] = _PartialData(peerId: peerId, rssi: result.rssi);
      debugPrint('[BleScanner] peerId_only mac=$mac id=${peerId.substring(28)} rssi=${result.rssi}');
      return;
    }

    // 過去に保存した partial の rssi を使いたい場合のマージ
    final partial = _partialPeers[mac];
    final finalRssi = partial?.rssi ?? result.rssi;

    _tryEmit(peerId, mac, name ?? '', message, colorIndex, finalRssi);
  }

  void _tryEmit(String peerId, String mac, String name, String message, int colorIndex, int rssi) {
    if (_emittedPeers.contains(peerId)) return;
    if (name.isEmpty) return;
    _emittedPeers.add(peerId);
    debugPrint('[BleScanner] ENCOUNTER id=${peerId.substring(28)} name=$name');
    _controller.add(EncounterEvent(
      time: DateTime.now(),
      peerId: peerId,
      macAddress: mac,
      name: name,
      message: message,
      colorIndex: colorIndex,
      rssi: rssi,
    ));
  }
}

class _PartialData {
  final String peerId;
  final int rssi;
  const _PartialData({required this.peerId, required this.rssi});
}
