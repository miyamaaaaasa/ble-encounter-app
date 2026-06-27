import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const dailyChannelId     = 'daily_result';
  static const eventChannelId     = 'event_info';
  static const encounterChannelId = 'encounter_detect';

  static const _gateNotifBase = 100;

  static const prefEncounterEnabled = 'notif_encounter_enabled';
  static const prefUpdateEnabled    = 'notif_update_enabled';
  static const prefEventEnabled     = 'notif_event_enabled';
  static const prefSoundEnabled     = 'notif_sound_enabled';
  static const prefVibrationEnabled = 'notif_vibration_enabled';

  // 3開門時刻（固定: 朝9時, 昼12時, 夜21時）
  static const gateHours = [9, 12, 21];

  static bool _initialized = false;

  static void Function()? onDailyNotificationTap;

  static tz.Location _location() {
    try { return tz.local; } catch (_) {}
    try { return tz.getLocation('Asia/Tokyo'); } catch (_) {}
    return tz.UTC;
  }

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      tz.initializeTimeZones();
      try { tz.setLocalLocation(tz.getLocation('Asia/Tokyo')); } catch (_) {}

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios),
        onDidReceiveNotificationResponse: (response) {
          final id = response.id ?? -1;
          if (id >= _gateNotifBase && id < _gateNotifBase + 25) {
            onDailyNotificationTap?.call();
          }
        },
      );

      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          dailyChannelId, '開門通知',
          description: '朝・昼・夜の開門時刻をお知らせします',
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
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          encounterChannelId, 'すれ違い検知',
          description: 'すれ違いを検知したときに通知します',
          importance: Importance.low,
          enableVibration: false,
          playSound: false,
        ),
      );
    } catch (e) {
      debugPrint('[Notif] init error: $e');
    }
  }

  // 朝・昼・夜ゲート通知（3回/日）
  static Future<void> scheduleGateNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sound = prefs.getBool(prefSoundEnabled) ?? true;
      final vibr  = prefs.getBool(prefVibrationEnabled) ?? true;
      final loc   = _location();
      final now   = tz.TZDateTime.now(loc);

      for (final hour in gateHours) {
        var scheduled = tz.TZDateTime(loc, now.year, now.month, now.day, hour);
        if (scheduled.isBefore(now)) {
          scheduled = scheduled.add(const Duration(days: 1));
        }
        await _plugin.zonedSchedule(
          _gateNotifBase + hour,
          _gateTitle(hour),
          '今日のすれ違い通信結果をご確認ください',
          scheduled,
          NotificationDetails(
            android: AndroidNotificationDetails(
              dailyChannelId, '開門通知',
              importance: Importance.defaultImportance,
              playSound: sound,
              enableVibration: vibr,
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: sound,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }
      debugPrint('[Notif] gate notifications scheduled');
    } catch (e) {
      debugPrint('[Notif] scheduleGateNotifications error: $e');
    }
  }

  static String _gateTitle(int hour) => switch (hour) {
    9  => '朝の開門 🌅',
    12 => '昼の開門 ☀️',
    21 => '夜の開門 🌙',
    _  => '開門通知',
  };

  // すれ違い検知通知（切断後 delayMinutes 後）
  static Future<void> scheduleEncounterNotification({
    required String peerId,
    required int delayMinutes,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(prefEncounterEnabled) ?? true)) return;

      final notifId = peerId.hashCode.abs() % 200 + 300;
      final now     = tz.TZDateTime.now(_location());
      final at      = now.add(Duration(minutes: delayMinutes));
      final nextH   = _nextGateHour();
      final hh      = nextH.toString().padLeft(2, '0');

      await _plugin.zonedSchedule(
        notifId,
        'すれ違いを検知しました',
        '誰かとすれ違いました。$hh:00 に確認できます',
        at,
        NotificationDetails(
          android: const AndroidNotificationDetails(
            encounterChannelId, 'すれ違い検知',
            importance: Importance.low,
            playSound: false,
            enableVibration: false,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: false,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('[Notif] scheduleEncounter: $e');
    }
  }

  static int _nextGateHour() {
    final h = DateTime.now().hour;
    if (h < 9)  return 9;
    if (h < 12) return 12;
    if (h < 21) return 21;
    return 9;
  }

  static Future<void> showEventNotification({
    required String title,
    required String body,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(prefEventEnabled) ?? true)) return;
      final sound = prefs.getBool(prefSoundEnabled) ?? true;
      final vibr  = prefs.getBool(prefVibrationEnabled) ?? true;

      await _plugin.show(
        200, title, body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            eventChannelId, 'イベント・お知らせ',
            importance: Importance.high,
            playSound: sound,
            enableVibration: vibr,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: sound,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[Notif] showEvent: $e');
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
        encounterEnabled: prefs.getBool(prefEncounterEnabled) ?? true,
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
  final bool encounterEnabled;
  final bool updateEnabled;
  final bool eventEnabled;
  final bool soundEnabled;
  final bool vibrationEnabled;

  NotifSettings({
    this.encounterEnabled = true,
    this.updateEnabled    = true,
    this.eventEnabled     = true,
    this.soundEnabled     = true,
    this.vibrationEnabled = true,
  });
}
