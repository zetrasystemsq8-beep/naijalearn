// lib/notification_service.dart
//
// Local push notifications for NaijaLearn.
//
// Uses flutter_local_notifications (+ timezone) for on-device scheduled
// and instant notifications — no backend/FCM project needed, so this
// works immediately without extra server setup. Covers:
//   - Daily study reminder (user-configurable time)
//   - Streak-at-risk alert (fires once, late afternoon, if goal not met)
//   - Daily Challenge available ping
//   - Battle events: opponent joined, someone requested a subject edit,
//     scheduled battle starting soon, it's your turn
//
// Notification IDs are fixed constants per notification "kind" so
// re-scheduling naturally replaces the old one instead of stacking
// duplicates.
//
// REQUIRES THESE PACKAGES in pubspec.yaml:
//   flutter_local_notifications: ^17.2.2
//   timezone: ^0.9.4
//
// REQUIRES THESE PERMISSIONS:
//   Android: POST_NOTIFICATIONS (13+), SCHEDULE_EXACT_ALARM (optional,
//     for precise daily reminder timing) in AndroidManifest.xml
//   iOS: none extra — handled via requestPermissions() at runtime

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

class NotificationIds {
  static const int dailyReminder = 1001;
  static const int streakAtRisk = 1002;
  static const int dailyChallenge = 1003;
  static const int battleGeneric = 2000; // + battle-specific offset if needed
  static const int scheduledBattle = 3000;
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const String _prefsEnabledKey = 'notifications_enabled';
  static const String _prefsHourKey = 'notifications_reminder_hour';
  static const String _prefsMinuteKey = 'notifications_reminder_minute';

  /// Call once from main() before runApp(). Safe to call multiple times.
  Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false, // we ask explicitly via requestPermissions()
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);

    await _plugin.initialize(initSettings);
    _initialized = true;

    // Re-arm the daily reminder on every app start (harmless if already set —
    // scheduling with the same id replaces the previous one).
    final enabled = await notificationsEnabled();
    if (enabled) {
      final time = await reminderTime();
      await scheduleDailyReminder(hour: time.hour, minute: time.minute);
    }
  }

  /// Requests OS-level notification permission. Call after onboarding or
  /// the first time the user opts in from Settings.
  Future<bool> requestPermissions() async {
    if (Platform.isIOS) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    } else if (Platform.isAndroid) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      return granted ?? true;
    }
    return true;
  }

  Future<bool> notificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsEnabledKey) ?? true;
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabledKey, enabled);
    if (enabled) {
      final time = await reminderTime();
      await scheduleDailyReminder(hour: time.hour, minute: time.minute);
    } else {
      await _plugin.cancel(NotificationIds.dailyReminder);
      await _plugin.cancel(NotificationIds.streakAtRisk);
      await _plugin.cancel(NotificationIds.dailyChallenge);
    }
  }

  Future<TimeOfDay> reminderTime() async {
    final prefs = await SharedPreferences.getInstance();
    final hour = prefs.getInt(_prefsHourKey) ?? 18;
    final minute = prefs.getInt(_prefsMinuteKey) ?? 0;
    return TimeOfDay(hour: hour, minute: minute);
  }

  Future<void> setReminderTime(TimeOfDay time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsHourKey, time.hour);
    await prefs.setInt(_prefsMinuteKey, time.minute);
    await scheduleDailyReminder(hour: time.hour, minute: time.minute);
  }

  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  NotificationDetails get _defaultDetails => const NotificationDetails(
        android: AndroidNotificationDetails(
          'naijalearn_general',
          'NaijaLearn',
          channelDescription: 'Study reminders and battle alerts',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );

  /// Repeats daily at the given local time — "Time to practice!" nudge.
  Future<void> scheduleDailyReminder({required int hour, required int minute}) async {
    await _plugin.zonedSchedule(
      NotificationIds.dailyReminder,
      '📚 Time to practice!',
      "Keep your streak alive — a few questions today keeps you sharp.",
      _nextInstanceOf(hour, minute),
      _defaultDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// One-off alert fired from app logic (e.g. AppProvider) when it's late
  /// in the day, the streak is >0, and no questions have been answered yet.
  Future<void> showStreakAtRisk(int streak) async {
    if (!await notificationsEnabled()) return;
    await _plugin.show(
      NotificationIds.streakAtRisk,
      '🔥 Your $streak-day streak is at risk!',
      'Answer a few questions before the day ends to keep it going.',
      _defaultDetails,
    );
  }

  Future<void> showDailyChallengeReady() async {
    if (!await notificationsEnabled()) return;
    await _plugin.show(
      NotificationIds.dailyChallenge,
      '🎯 Daily Challenge ready',
      'A fresh set of questions is waiting for you.',
      _defaultDetails,
    );
  }

  /// Generic instant notification — used for battle events.
  Future<void> showInstant({required int id, required String title, required String body}) async {
    if (!await notificationsEnabled()) return;
    await _plugin.show(id, title, body, _defaultDetails);
  }

  /// Schedules a one-off alert shortly before a scheduled battle starts.
  Future<void> scheduleBattleStartReminder({
    required String battleId,
    required DateTime scheduledAt,
    required String subjectsLabel,
  }) async {
    if (!await notificationsEnabled()) return;
    final leadTime = scheduledAt.subtract(const Duration(minutes: 5));
    if (leadTime.isBefore(DateTime.now())) return;

    final id = NotificationIds.scheduledBattle + (battleId.hashCode % 500);
    final tzTime = tz.TZDateTime.from(leadTime, tz.local);

    await _plugin.zonedSchedule(
      id,
      '⚔️ Battle starting soon',
      'Your $subjectsLabel battle starts in 5 minutes — get ready!',
      tzTime,
      _defaultDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> cancelAll() => _plugin.cancelAll();
}
