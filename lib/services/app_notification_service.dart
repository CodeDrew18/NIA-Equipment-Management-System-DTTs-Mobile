import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';

class AppNotificationService {
  AppNotificationService._();

  static const String _channelGroupKey = 'ems_alerts_group';
  // Keep this key in sync with AndroidManifest default channel id.
  static const String defaultChannelKey = 'transportation_updates_v2';
  static const String _channelKey = defaultChannelKey;
  static const String _notificationIcon = 'resource://mipmap/launcher_icon';
  static const String _notificationLargeIcon = 'asset://assets/ems_logo_1.png';
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    await AwesomeNotifications().initialize(
      _notificationIcon,
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
        icon: _notificationIcon,
        largeIcon: _notificationLargeIcon,
        title: title,
        body: body,
        displayOnForeground: true,
        displayOnBackground: true,
        wakeUpScreen: true,
        category: NotificationCategory.Message,
        notificationLayout: NotificationLayout.BigText,
      ),
    );
  }
}
