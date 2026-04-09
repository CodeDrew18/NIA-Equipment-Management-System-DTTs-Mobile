import 'dart:convert';

import 'package:ems/models/api_config.dart';
import 'package:ems/services/app_notification_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class FcmService {
  FcmService._();

  static final FcmService instance = FcmService._();

  bool _initialized = false;

  static String _resolveTitle(RemoteMessage message) {
    return message.notification?.title ??
        message.data['title']?.toString() ?? '';
    // 'New Transportation Request';
  }

  static String _resolveBody(RemoteMessage message) {
    return message.notification?.body ?? message.data['body']?.toString() ?? '';
    // 'You have a new transportation request.';
  }

  static Future<void> handleBackgroundMessage(RemoteMessage message) async {
    await Firebase.initializeApp();

    // Avoid duplicate notifications when backend already sends notification payload.
    if (message.notification != null) {
      return;
    }

    await AppNotificationService.showNewTransportationRequest(
      title: _resolveTitle(message),
      body: _resolveBody(message),
    );
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _initialized = true;

    await FirebaseMessaging.instance.setAutoInitEnabled(true);
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.instance.onTokenRefresh.listen((_) {
      syncTokenWithBackend();
    });

    await syncTokenWithBackend();
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    await AppNotificationService.showNewTransportationRequest(
      title: _resolveTitle(message),
      body: _resolveBody(message),
    );
  }

  Future<String> getCurrentToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      return token?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> syncTokenWithBackend() async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token')?.trim() ?? '';
    if (authToken.isEmpty) {
      return;
    }

    final fcmToken = await getCurrentToken();
    if (fcmToken.isEmpty) {
      return;
    }

    try {
      await http.post(
        ApiConfig.fcmTokenUri(),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'fcm_token': fcmToken}),
      );
    } catch (_) {
      // Keep silent to avoid blocking UX when token sync fails.
    }
  }

  Future<void> clearTokenFromBackend() async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token')?.trim() ?? '';
    if (authToken.isEmpty) {
      return;
    }

    try {
      await http.delete(
        ApiConfig.fcmTokenUri(),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );
    } catch (_) {
      // Keep silent to avoid blocking logout flow when token clear fails.
    }
  }

  Future<void> logoutFromBackend() async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token')?.trim() ?? '';
    if (authToken.isEmpty) {
      return;
    }

    try {
      await http.post(
        ApiConfig.logoutUri(),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );
    } catch (_) {
      // Keep silent to avoid blocking logout flow when server logout fails.
    }
  }
}
