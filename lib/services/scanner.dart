import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/constants.dart';
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

  // ─── iOS端末からのトークン取得（GATT経由）───────────────────────────
  // iOSは電波にトークン（manufacturer data）を載せられないため、サービスUUIDだけを
  // 流している。そういう端末を見つけたら接続してcharacteristicからトークンを読む。
  // 接続は重くバッテリーも使うので、同時に1台・結果はキャッシュして使い回す。
  static final _serviceGuid   = Guid(Constants.serviceUuid);
  static final _tokenCharGuid = Guid(Constants.tokenCharUuid);
  static const _gattGrace     = Duration(seconds: 2);   // Android誤認防止の猶予
  static const _gattTokenTtl  = Duration(minutes: 30);  // 読んだトークンの再利用期間
  static const _gattRetryWait = Duration(seconds: 60);  // 失敗後に再挑戦するまで

  // remoteId → GATTで読んだトークン（接続せずに再利用するため）
  final _gattTokens       = <String, ({String hex, DateTime readAt})>{};
  // remoteId → トークン無しの電波を最初に見た時刻
  final _noTokenFirstSeen = <String, DateTime>{};
  // remoteId → 次にGATTを試してよい時刻
  final _gattNextTry      = <String, DateTime>{};
  // GATT読み取りの対象外（電波にトークンを載せている＝Android、または対応外の端末）
  final _skipGatt         = <String>{};
  bool _gattBusy = false;

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
    _noTokenFirstSeen.clear();
    final now = DateTime.now();
    _gattTokens.removeWhere((_, v) => now.difference(v.readAt) > _gattTokenTtl);
    _gattNextTry.removeWhere((_, t) => now.isAfter(t));
    if (_skipGatt.length > 500) _skipGatt.clear(); // AndroidのMACは入れ替わるので溜まる

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) return;

    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
      await Future.delayed(const Duration(milliseconds: 300));
    }

    await FlutterBluePlus.startScan(
      // iOSはバックグラウンドでスキャンを続けるにはサービスUUIDの指定が必須。
      // Android側の広告にはサービスUUIDが入っているので、これで取りこぼさない。
      // Androidは従来どおり無指定（挙動を変えない）。
      withServices: defaultTargetPlatform == TargetPlatform.iOS
          ? [Guid(Constants.serviceUuid)]
          : const [],
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
    if (payload == null || payload.length < 17 || payload[0] != _magicPeer) {
      // トークンが載っていない＝iOS端末の可能性。GATTで読みに行くか判断する
      _maybeReadViaGatt(result);
      return;
    }
    // 電波にトークンを載せている端末（Android）はGATT読み取りの対象外
    _skipGatt.add(mac);

    final peerId = payload
        .skip(1)
        .take(16)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    if (peerId == _myPeerIdHex) return;

    // アクティブタイムスタンプを更新（すでに検知済みでも更新する）
    _activePeers[peerId] = DateTime.now();

    // サーバーファースト: BLEではトークンのみ交換。プロフィールはサーバーから取得。
    // トークン検出時点ではプロフィール情報なしで即座にイベント発行。
    String name = '';
    int colorIndex  = 0;
    int prefecture  = -1;
    TemplateMessage template = const TemplateMessage();
    int peerBadgeLevel = 0;

    // レガシー互換: プロフィール付きペイロードも解析可能（旧バージョンとの共存）
    if (payload.length >= 21 &&
        payload[17] == 0xFF &&
        payload[18] == 0xFE &&
        payload[19] == _magicProfile) {
      colorIndex = payload[20] & 0xFF;
      final dataBytes = payload.length > 21 ? payload.sublist(21) : <int>[];
      final (n1, t1, b1) = _parseProfileBytes(dataBytes);
      name = n1 ?? ''; template = t1; peerBadgeLevel = b1;
    } else if (payload.length >= 20 && payload[17] == _magicProfile) {
      colorIndex = payload[18] & 0xFF;
      int offset = 19;
      if (payload.length > 19) {
        final pfByte = payload[19] & 0xFF;
        if (pfByte == 0xFF || pfByte <= 46) {
          prefecture = pfByte == 0xFF ? -1 : pfByte;
          offset = 20;
        }
      }
      final dataBytes = payload.length > offset ? payload.sublist(offset) : <int>[];
      final (n2, t2, b2) = _parseProfileBytes(dataBytes);
      name = n2 ?? ''; template = t2; peerBadgeLevel = b2;
    }
    // トークンのみペイロード（サーバーファースト版）: name は空のまま

    debugPrint('[BleScanner] TOKEN mac=$mac id=${peerId.substring(28)} hasProfile=${name.isNotEmpty}');

    final partial    = _partialPeers[mac];
    final finalRssi  = partial?.rssi ?? result.rssi;
    // サーバーファースト: name が空でもトークンイベントを発行（PendingScanStorage に保存するため）
    _tryEmitToken(peerId, mac, name, colorIndex, prefecture, template, finalRssi, peerBadgeLevel);
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

  /// トークンを載せていない電波を見つけたとき、GATTで読みに行くかを判断する。
  void _maybeReadViaGatt(ScanResult result) {
    final id = result.device.remoteId.str;
    if (_skipGatt.contains(id)) return;

    // iOSでのスキャンはサービスUUIDで絞り込んでいるので、届いた時点で対象。
    // （iOS同士の背面広告はUUIDが特殊な領域に入り、一覧に出ないことがある）
    final hasService = defaultTargetPlatform == TargetPlatform.iOS ||
        result.advertisementData.serviceUuids.contains(_serviceGuid);
    if (!hasService) return;

    final now = DateTime.now();
    final cached = _gattTokens[id];
    if (cached != null && now.difference(cached.readAt) < _gattTokenTtl) {
      _onTokenFound(cached.hex, id, result.rssi); // 接続せずに再利用
      return;
    }

    // Androidの電波は「サービスUUID」と「トークン」が別パケットで届く。
    // トークン側が届く前の一瞬をiOSと誤認して接続しないよう、少し様子を見る。
    final first = _noTokenFirstSeen.putIfAbsent(id, () => now);
    if (now.difference(first) < _gattGrace) return;

    if (_gattBusy) return;
    final next = _gattNextTry[id];
    if (next != null && now.isBefore(next)) return;

    _readTokenViaGatt(result.device, result.rssi);
  }

  Future<void> _readTokenViaGatt(BluetoothDevice device, int rssi) async {
    final id = device.remoteId.str;
    _gattBusy = true;
    _gattNextTry[id] = DateTime.now().add(_gattRetryWait); // 失敗時の既定
    var found = false;
    try {
      await device.connect(timeout: const Duration(seconds: 6), mtu: null);
      final services = await device.discoverServices(timeout: 8);
      for (final svc in services) {
        if (svc.uuid != _serviceGuid) continue;
        for (final c in svc.characteristics) {
          if (c.uuid != _tokenCharGuid) continue;
          final v = await c.read(timeout: 5);
          if (v.length >= 16) {
            final hex = v
                .take(16)
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join();
            _gattTokens[id] = (hex: hex, readAt: DateTime.now());
            _gattNextTry.remove(id);
            found = true;
            debugPrint('[BleScanner] GATT token id=${hex.substring(28)} dev=$id');
            _onTokenFound(hex, id, rssi);
          }
        }
      }
      // 接続できたのにトークンが無い＝このアプリの端末ではない。以後は試さない
      if (!found) _skipGatt.add(id);
    } catch (e) {
      debugPrint('[BleScanner] GATT read failed dev=$id: $e');
    } finally {
      try { await device.disconnect(); } catch (_) {}
      _gattBusy = false;
    }
  }

  void _onTokenFound(String peerId, String mac, int rssi) {
    if (peerId == _myPeerIdHex) return;
    _activePeers[peerId] = DateTime.now();
    _tryEmitToken(peerId, mac, '', 0, -1, const TemplateMessage(), rssi);
  }

  void _tryEmitToken(String peerId, String mac, String name,
      int colorIndex, int prefecture, TemplateMessage template, int rssi,
      [int peerBadgeLevel = 0]) {
    if (_emittedPeers.contains(peerId)) return;
    _emittedPeers.add(peerId);
    debugPrint('[BleScanner] ENCOUNTER id=${peerId.substring(28)} name=${name.isEmpty ? "(token-only)" : name} rssi=${rssi}dBm');
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
