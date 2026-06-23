import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'scanner.dart';

/// 検知イベントを CSV ファイルへ追記するロガー。
/// 列: time, peerId, rssi
class EncounterLogger {
  File? _file;
  int _count = 0;

  int get count => _count;
  String? get filePath => _file?.path;

  Future<void> initialize() async {
    final dir = await getApplicationDocumentsDirectory();
    // 実験ごとに別ファイルを作成（タイムスタンプをファイル名に使用）
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    _file = File('${dir.path}/encounter_$ts.csv');
    await _file!.writeAsString('time,peerId,rssi\n');
    _count = 0;
  }

  Future<void> log(EncounterEvent event) async {
    if (_file == null) return;
    final line =
        '${event.time.toIso8601String()},${event.peerId},${event.rssi}\n';
    await _file!.writeAsString(line, mode: FileMode.append);
    _count++;
  }
}
