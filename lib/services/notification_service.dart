import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const dailyChannelId   = 'daily_result';
  static const eventChannelId   = 'event_info';
  static const _dailyNotifId    = 100;

  static const prefHour             = 'notif_hour';
  static const prefDailyEnabled     = 'notif_daily_enabled';
  static const prefUpdateEnabled    = 'notif_update_enabled';
  static const prefEventEnabled     = 'notif_event_enabled';
  static const prefSoundEnabled     = 'notif_sound_enabled';
  static const prefVibrationEnabled = 'notif_vibration_enabled';
  static const prefLastTimeChange   = 'last_time_change_date';

  // 選択可能な固定時刻（チート防止のため4択のみ）
  static const fixedHours = [0, 9, 12, 18];

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      tz.initializeTimeZones();
      try { tz.setLocalLocation(tz.getLocation('Asia/Tokyo')); } catch (_) {}

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(const InitializationSettings(android: android));

      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          dailyChannelId, '本日の通信結果',
          description: '毎日の通信結果をお知らせします',
          importance: Importance.defaultImportance,
        ),
      );
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          eventChannelId, 'イベント・お知らせ',
          description: 'アプリからのお知らせ',
          importance: Importance.high,
        ),
      );
    } catch (e) {
      debugPrint('[Notif] init error: $e');
    }
  }

  // ── 時刻変更の7日ロック ─────────────────────────────────────────────────────

  static Future<bool> canChangeTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString(prefLastTimeChange);
      if (s == null) return true;
      final last = DateTime.parse(s);
      return DateTime.now().difference(last).inHours >= 168;
    } catch (_) {
      return true;
    }
  }

  static Future<DateTime?> nextAllowedChangeDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString(prefLastTimeChange);
      if (s == null) return null;
      return DateTime.parse(s).add(const Duration(days: 7));
    } catch (_) {
      return null;
    }
  }

  static Future<void> _recordTimeChange() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefLastTimeChange, DateTime.now().toIso8601String());
  }

  // ── 日次通知スケジュール ────────────────────────────────────────────────────

  static Future<void> scheduleDailyNotification({required int hour}) async {
    try {
      await _plugin.cancel(_dailyNotifId);

      tz.TZDateTime now;
      try { now = tz.TZDateTime.now(tz.local); }
      catch (_) { now = tz.TZDateTime.now(tz.UTC); }

      tz.TZDateTime scheduled;
      try { scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour); }
      catch (_) { scheduled = tz.TZDateTime(tz.UTC, now.year, now.month, now.day, hour); }

      if (scheduled.isBefore(now)) scheduled = scheduled.add(const Duration(days: 1));

      final prefs = await SharedPreferences.getInstance();
      final sound  = prefs.getBool(prefSoundEnabled) ?? true;
      final vibr   = prefs.getBool(prefVibrationEnabled) ?? true;

      await _plugin.zonedSchedule(
        _dailyNotifId,
        '本日の通信結果',
        '今日のすれ違い通信結果をご確認ください',
        scheduled,
        NotificationDetails(
          android: AndroidNotificationDetails(
            dailyChannelId, '本日の通信結果',
            importance: Importance.defaultImportance,
            playSound: sound,
            enableVibration: vibr,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );

      await prefs.setInt(prefHour, hour);
      await prefs.setBool(prefDailyEnabled, true);
    } catch (e) {
      debugPrint('[Notif] schedule: $e');
    }
  }

  // 時刻変更（7日ロックチェック済みで呼ぶこと）
  static Future<void> changeHour(int hour) async {
    await _recordTimeChange();
    await scheduleDailyNotification(hour: hour);
  }

  static Future<void> cancelDailyNotification() async {
    try {
      await _plugin.cancel(_dailyNotifId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefDailyEnabled, false);
    } catch (e) {
      debugPrint('[Notif] cancel: $e');
    }
  }

  static Future<void> setPref(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e) {
      debugPrint('[Notif] setPref: $e');
    }
  }

  // イベント通知（サーバー/FCM から呼ばれる想定）
  static Future<void> showEventNotification({
    required String title,
    required String body,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final eventEnabled = prefs.getBool(prefEventEnabled) ?? true;
      if (!eventEnabled) return;

      final sound = prefs.getBool(prefSoundEnabled) ?? true;
      final vibr  = prefs.getBool(prefVibrationEnabled) ?? true;

      await _plugin.show(
        200,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            eventChannelId, 'イベント・お知らせ',
            importance: Importance.high,
            playSound: sound,
            enableVibration: vibr,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[Notif] showEvent: $e');
    }
  }

  static Future<NotifSettings> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return NotifSettings(
        hour:             prefs.getInt(prefHour) ?? 18,
        dailyEnabled:     prefs.getBool(prefDailyEnabled) ?? true,
        updateEnabled:    prefs.getBool(prefUpdateEnabled) ?? true,
        eventEnabled:     prefs.getBool(prefEventEnabled) ?? true,
        soundEnabled:     prefs.getBool(prefSoundEnabled) ?? true,
        vibrationEnabled: prefs.getBool(prefVibrationEnabled) ?? true,
      );
    } catch (_) {
      return NotifSettings();
    }
  }
}

class NotifSettings {
  final int hour;
  final bool dailyEnabled;
  final bool updateEnabled;
  final bool eventEnabled;
  final bool soundEnabled;
  final bool vibrationEnabled;

  NotifSettings({
    this.hour = 18,
    this.dailyEnabled = true,
    this.updateEnabled = true,
    this.eventEnabled = true,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
  });
}
