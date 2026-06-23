import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const dailyChannelId = 'daily_result';
  static const _dailyNotifId = 100;

  static const prefHour          = 'notif_hour';
  static const prefMinute        = 'notif_minute';
  static const prefDailyEnabled  = 'notif_daily_enabled';
  static const prefUpdateEnabled = 'notif_update_enabled';
  static const prefEventEnabled  = 'notif_event_enabled';

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      tz.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));
      } catch (_) {}

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(const InitializationSettings(android: android));

      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          dailyChannelId,
          '本日の通信結果',
          description: '毎日の通信結果をお知らせします',
          importance: Importance.defaultImportance,
        ),
      );
    } catch (e) {
      debugPrint('[Notif] init error: $e');
    }
  }

  static Future<void> scheduleDailyNotification({
    required int hour,
    required int minute,
  }) async {
    try {
      await _plugin.cancel(_dailyNotifId);

      tz.TZDateTime now;
      try {
        now = tz.TZDateTime.now(tz.local);
      } catch (_) {
        now = tz.TZDateTime.now(tz.UTC);
      }

      tz.TZDateTime scheduled;
      try {
        scheduled =
            tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
      } catch (_) {
        scheduled =
            tz.TZDateTime(tz.UTC, now.year, now.month, now.day, hour, minute);
      }

      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }

      await _plugin.zonedSchedule(
        _dailyNotifId,
        '本日の通信結果',
        '今日のすれ違い通信結果をご確認ください',
        scheduled,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            dailyChannelId,
            '本日の通信結果',
            importance: Importance.defaultImportance,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(prefHour, hour);
      await prefs.setInt(prefMinute, minute);
      await prefs.setBool(prefDailyEnabled, true);
    } catch (e) {
      debugPrint('[Notif] schedule: $e');
    }
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

  static Future<NotifSettings> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return NotifSettings(
        hour:          prefs.getInt(prefHour) ?? 21,
        minute:        prefs.getInt(prefMinute) ?? 0,
        dailyEnabled:  prefs.getBool(prefDailyEnabled) ?? true,
        updateEnabled: prefs.getBool(prefUpdateEnabled) ?? true,
        eventEnabled:  prefs.getBool(prefEventEnabled) ?? true,
      );
    } catch (_) {
      return NotifSettings();
    }
  }
}

class NotifSettings {
  final int hour;
  final int minute;
  final bool dailyEnabled;
  final bool updateEnabled;
  final bool eventEnabled;

  NotifSettings({
    this.hour = 21,
    this.minute = 0,
    this.dailyEnabled = true,
    this.updateEnabled = true,
    this.eventEnabled = true,
  });
}
