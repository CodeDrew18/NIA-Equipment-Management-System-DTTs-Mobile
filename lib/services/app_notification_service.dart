import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';

class AppNotificationService {
  AppNotificationService._();

  static const String _channelGroupKey = 'ems_alerts_group';
  // Bump channel key so Android recreates channel settings with sound enabled.
  static const String _channelKey = 'transportation_updates_v2';
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    await AwesomeNotifications().initialize(
      null,
      [
        NotificationChannel(
          channelGroupKey: _channelGroupKey,
          channelKey: _channelKey,
          channelName: 'Transportation Updates',
          channelDescription:
              'Notifications for new transportation requests and DTT updates.',
          defaultColor: const Color(0xFF0D4C73),
          ledColor: Colors.white,
          importance: NotificationImportance.Max,
          channelShowBadge: true,
          playSound: true,
          defaultRingtoneType: DefaultRingtoneType.Notification,
          enableVibration: true,
        ),
      ],
      channelGroups: [
        NotificationChannelGroup(
          channelGroupKey: _channelGroupKey,
          channelGroupName: 'EMS Alerts',
        ),
      ],
      debug: false,
    );

    _initialized = true;
  }

  static Future<void> ensurePermission() async {
    await initialize();

    final isAllowed = await AwesomeNotifications().isNotificationAllowed();
    if (!isAllowed) {
      await AwesomeNotifications().requestPermissionToSendNotifications();
    }
  }

  static Future<void> showNewTransportationRequest({
    required String title,
    required String body,
  }) async {
    await initialize();

    final isAllowed = await AwesomeNotifications().isNotificationAllowed();
    if (!isAllowed) {
      return;
    }

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: DateTime.now().millisecondsSinceEpoch.remainder(1000000),
        channelKey: _channelKey,
        title: title,
        body: body,
        displayOnForeground: true,
        displayOnBackground: true,
        wakeUpScreen: true,
        category: NotificationCategory.Message,
        notificationLayout: NotificationLayout.Default,
      ),
    );
  }
}
