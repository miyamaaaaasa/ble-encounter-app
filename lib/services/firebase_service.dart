import 'package:flutter/foundation.dart';
import 'notification_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Firebase Cloud Messaging (FCM) サービス
//
// 【有効化手順】
// 1. https://console.firebase.google.com でプロジェクト作成
// 2. Android アプリを追加（パッケージ名: com.example.ble_encounter）
// 3. google-services.json を android/app/ に配置
// 4. pubspec.yaml に追加:
//      firebase_core: ^3.0.0
//      firebase_messaging: ^15.0.0
// 5. android/build.gradle の dependencies に追加:
//      classpath 'com.google.gms:google-services:4.4.2'
// 6. android/app/build.gradle の末尾に追加:
//      apply plugin: 'com.google.gms.google-services'
// 7. main.dart で Firebase.initializeApp() を呼ぶ（下記コメント参照）
// 8. このファイルの TODO を実装に差し替える
// ─────────────────────────────────────────────────────────────────────────────

class FirebaseService {
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // TODO: Firebase セットアップ完了後にコメントを外す
    // try {
    //   await Firebase.initializeApp(
    //     options: DefaultFirebaseOptions.currentPlatform,
    //   );
    //
    //   // バックグラウンド/終了時ハンドラ
    //   FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
    //
    //   // フォアグラウンド受信
    //   FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    //
    //   // FCMトークン取得（サーバーへ送信）
    //   final token = await FirebaseMessaging.instance.getToken();
    //   debugPrint('[FCM] token: $token');
    // } catch (e) {
    //   debugPrint('[FCM] init error: $e');
    // }

    debugPrint('[FCM] stub mode — configure Firebase to enable push notifications');
  }

  // フォアグラウンドでメッセージを受信したとき
  static Future<void> _onForegroundMessage(dynamic message) async {
    // TODO: FirebaseMessaging パッケージ導入後に実装
    // final title = message.notification?.title ?? 'お知らせ';
    // final body  = message.notification?.body  ?? '';
    // await NotificationService.showEventNotification(title: title, body: body);
  }

  // イベント通知をローカル通知で表示（設定 OFF のときはスキップ）
  static Future<void> showEventIfEnabled({
    required String title,
    required String body,
  }) async {
    await NotificationService.showEventNotification(
        title: title, body: body);
  }
}

// バックグラウンドハンドラ（トップレベル関数必須）
// TODO: Firebase 導入後にコメントを外す
// @pragma('vm:entry-point')
// Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
//   await Firebase.initializeApp();
//   debugPrint('[FCM] background: ${message.messageId}');
// }
