import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'core/peer_id.dart';
import 'services/notification_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // デバイス固有 UID を SharedPreferences から復元（または新規生成）
  await PeerId.init();

  // 通知システム初期化
  await NotificationService.init();

  FlutterBluePlus.setLogLevel(LogLevel.warning, color: false);

  runApp(
    const ProviderScope(
      child: App(),
    ),
  );
}
