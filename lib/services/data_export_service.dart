import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/app_badge.dart';
import '../models/encounter_record.dart';
import '../models/game_data.dart';
import '../models/own_profile.dart';

class DataExportService {
  static const _version = 1;

  // 全データをJSONファイルとして共有
  static Future<void> exportAll({
    required OwnProfile? profile,
    required List<EncounterRecord> encounters,
    required List<AppBadge> badges,
    required GameData gameData,
  }) async {
    final data = {
      'version': _version,
      'exportedAt': DateTime.now().toIso8601String(),
      'appName': 'ble_encounter',
      'profile': profile?.toMap(),
      'encounters': encounters.map((e) => e.toMap()).toList(),
      'badges': badges.map((b) => b.toMap()).toList(),
      'gameData': gameData.toJson(),
    };

    final json = const JsonEncoder.withIndent('  ').convert(data);
    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    final fname =
        'hello_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.json';
    final file = File('${dir.path}/$fname');
    await file.writeAsString(json, encoding: utf8);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: 'はじめましてこんにちは バックアップデータ',
    );
    debugPrint('[Export] exported ${encounters.length} encounters, ${badges.length} badges');
  }

  // JSONファイルを選択してインポート
  static Future<ImportResult?> importFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.first.path;
    if (path == null) return null;

    final content = await File(path).readAsString(encoding: utf8);
    return _parseJson(content);
  }

  static ImportResult _parseJson(String content) {
    final map = jsonDecode(content) as Map<String, dynamic>;
    if (map['appName'] != 'ble_encounter') {
      throw const FormatException('このファイルはこのアプリのバックアップではありません');
    }
    return ImportResult(
      profile: map['profile'] != null
          ? OwnProfile.fromMap(map['profile'] as Map<String, dynamic>)
          : null,
      encounters: (map['encounters'] as List? ?? [])
          .map((e) => EncounterRecord.fromMap(e as Map<String, dynamic>))
          .toList(),
      badges: (map['badges'] as List? ?? [])
          .map((b) => AppBadge.fromMap(b as Map<String, dynamic>))
          .toList(),
      gameData: map['gameData'] != null
          ? GameData.fromJson(map['gameData'] as Map<String, dynamic>)
          : GameData.empty(),
      exportedAt: map['exportedAt'] != null
          ? DateTime.tryParse(map['exportedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class ImportResult {
  final OwnProfile? profile;
  final List<EncounterRecord> encounters;
  final List<AppBadge> badges;
  final GameData gameData;
  final DateTime exportedAt;

  const ImportResult({
    required this.profile,
    required this.encounters,
    required this.badges,
    required this.gameData,
    required this.exportedAt,
  });
}
