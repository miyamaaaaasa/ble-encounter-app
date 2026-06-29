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
  final int prefecture;
  final int rssi;
  final TemplateMessage template;
  final int peerBadgeLevel;

  const EncounterEvent({
    required this.time,
    required this.peerId,
    required this.macAddress,
    required this.name,
    required this.colorIndex,
    required this.prefecture,
    required this.rssi,
    this.template = const TemplateMessage(),
    this.peerBadgeLevel = 0,
  });
}

// ─── スキャナー ───────────────────────────────────────────────────────────────

class BleScanner {
  static const _mfId         = 0xFFFF;
  static const _magicPeer    = 0xBE;
  static const _magicProfile = 0xBF;
  static const _departureThresholdSecs = 60; // 60秒見えなくなったら切断とみなす

  final _encounterCtrl  = StreamController<EncounterEvent>.broadcast();
  final _departureCtrl  = StreamController<String>.broadcast();

  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _departureTimer;
  bool   _stopped = false;

  // peerId → 最後に見えた時刻（アクティブ中のみ追跡）
  final _activePeers  = <String, DateTime>{};
  // peerId → 今の検知セッション内で EncounterEvent を発行済みか（爆増防止）
  final _emittedPeers = <String>{};
  // macAddress → partial data（profile 未受信分）
  final _partialPeers = <String, _PartialData>{};

  Stream<EncounterEvent> get encounters => _encounterCtrl.stream;
  Stream<String>         get departures => _departureCtrl.stream;

  String _myPeerIdHex = PeerId.hex;

  // Phase3: 現在の自分のBLEトークン（ローテーション対応）
  void setOwnTokenHex(String hex) => _myPeerIdHex = hex;

  Future<void> start() async {
    _stopped = false;
    _activePeers.clear();
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

    // 15秒ごとに切断チェック
    _departureTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _checkDepartures();
    });
  }

  Future<void> stop() async {
    _stopped = true;
    _departureTimer?.cancel();
    _departureTimer = null;
    await _scanSub?.cancel();
    _scanSub = null;
    if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    _activePeers.clear();
    _emittedPeers.clear();
    _partialPeers.clear();
  }

  void dispose() {
    _stopped = true;
    _departureTimer?.cancel();
    _scanSub?.cancel();
    _encounterCtrl.close();
    _departureCtrl.close();
  }

  void _checkDepartures() {
    if (_stopped) return;
    final now       = DateTime.now();
    final departed  = <String>[];
    for (final entry in _activePeers.entries) {
      if (now.difference(entry.value).inSeconds >= _departureThresholdSecs) {
        departed.add(entry.key);
      }
    }
    for (final peerId in departed) {
      _activePeers.remove(peerId);
      _emittedPeers.remove(peerId); // 次回再接近時に再度 emit できるようリセット
      debugPrint('[BleScanner] DEPARTED id=${peerId.substring(28)}');
      _departureCtrl.add(peerId);
    }
  }

  void _processResult(ScanResult result) {
    final mac    = result.device.remoteId.str;
    final mfData = result.advertisementData.manufacturerData;

    final payload = mfData[_mfId];
    if (payload == null || payload.length < 17 || payload[0] != _magicPeer) return;

    final peerId = payload
        .skip(1)
        .take(16)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    if (peerId == _myPeerIdHex) return;

    // アクティブタイムスタンプを更新（すでに検知済みでも更新する）
    _activePeers[peerId] = DateTime.now();

    String? name;
    int colorIndex  = 0;
    int prefecture  = -1;
    TemplateMessage template = const TemplateMessage();

    int peerBadgeLevel = 0;
    if (payload.length >= 21 &&
        payload[17] == 0xFF &&
        payload[18] == 0xFE &&
        payload[19] == _magicProfile) {
      // レガシーフォーマット: [0xBE][peerId 16][0xFF][0xFE][0xBF][colorIdx][data...]
      colorIndex = payload[20] & 0xFF;
      final dataBytes = payload.length > 21 ? payload.sublist(21) : <int>[];
      (name, template, peerBadgeLevel) = _parseProfileBytes(dataBytes);
      debugPrint('[BleScanner] FULL id=${peerId.substring(28)} name=$name rssi=${result.rssi}dBm');
    } else if (payload.length >= 20 && payload[17] == _magicProfile) {
      // 新フォーマット: [0xBE][peerId 16][0xBF][colorIdx][prefecture?][name...]
      colorIndex = payload[18] & 0xFF;
      int offset = 19;
      // 次のバイトが都道府県コード範囲 (0-46) か 0xFF(未設定) なら読み込む
      if (payload.length > 19) {
        final pfByte = payload[19] & 0xFF;
        if (pfByte == 0xFF || pfByte <= 46) {
          prefecture = pfByte == 0xFF ? -1 : pfByte;
          offset = 20;
        }
      }
      final dataBytes = payload.length > offset ? payload.sublist(offset) : <int>[];
      (name, template, peerBadgeLevel) = _parseProfileBytes(dataBytes);
      debugPrint('[BleScanner] FULL2 mac=$mac id=${peerId.substring(28)} name=$name pref=$prefecture badge=$peerBadgeLevel');
    } else {
      _partialPeers[mac] = _PartialData(peerId: peerId, rssi: result.rssi);
      return;
    }

    final partial    = _partialPeers[mac];
    final finalRssi  = partial?.rssi ?? result.rssi;
    _tryEmit(peerId, mac, name ?? '', colorIndex, prefecture, template, finalRssi, peerBadgeLevel);
  }

  (String?, TemplateMessage, int) _parseProfileBytes(List<int> dataBytes) {
    final sepIdx = dataBytes.indexOf(0x00);
    String? name;
    TemplateMessage template = const TemplateMessage();
    int badgeLevel = 0;
    if (sepIdx >= 0) {
      name = sepIdx > 0
          ? utf8.decode(dataBytes.sublist(0, sepIdx), allowMalformed: true).trim()
          : '';
      if (dataBytes.length >= sepIdx + 5) {
        template = TemplateMessage(
          statusIndex:   _decodeByte(dataBytes[sepIdx + 1]),
          hobbyCategory: _decodeByte(dataBytes[sepIdx + 2]),
          hobbyDetail:   _decodeByte(dataBytes[sepIdx + 3]),
          phraseIndex:   _decodeByte(dataBytes[sepIdx + 4]),
        );
      }
      // バッジレベル（phraseの次のバイト）
      if (dataBytes.length >= sepIdx + 6) {
        badgeLevel = dataBytes[sepIdx + 5] & 0xFF;
      }
    } else {
      name = dataBytes.isNotEmpty
          ? utf8.decode(dataBytes, allowMalformed: true).trim()
          : '';
    }
    return (name, template, badgeLevel);
  }

  // 0xFF = 未回答（kNotSet = -1）
  static int _decodeByte(int b) => b == 0xFF ? -1 : b & 0xFF;

  void _tryEmit(String peerId, String mac, String name,
      int colorIndex, int prefecture, TemplateMessage template, int rssi,
      [int peerBadgeLevel = 0]) {
    if (name.isEmpty) return;
    if (_emittedPeers.contains(peerId)) return;
    _emittedPeers.add(peerId);
    debugPrint('[BleScanner] ENCOUNTER id=${peerId.substring(28)} name=$name rssi=${rssi}dBm badge=$peerBadgeLevel');
    _encounterCtrl.add(EncounterEvent(
      time: DateTime.now(),
      peerId: peerId,
      macAddress: mac,
      name: name,
      colorIndex: colorIndex,
      prefecture: prefecture,
      template: template,
      rssi: rssi,
      peerBadgeLevel: peerBadgeLevel,
    ));
  }
}

class _PartialData {
  final String peerId;
  final int rssi;
  const _PartialData({required this.peerId, required this.rssi});
}
