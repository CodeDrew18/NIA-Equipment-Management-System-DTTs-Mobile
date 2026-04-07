import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:ems/models/api_config.dart';
import 'package:ems/models/sqflite_config.dart';
import 'package:ems/services/app_notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class DttProvider extends ChangeNotifier {
  static const String _knownTicketKeysStorageKey = 'dtt_known_ticket_keys_v1';

  final Connectivity _connectivity = Connectivity();

  final List<Map<String, dynamic>> _tickets = [];
  final List<Map<String, dynamic>> _notificationFeed = [];
  final Set<String> _knownTicketKeys = <String>{};

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _pollingTimer;

  bool _started = false;
  bool _isOnline = true;
  bool _isBusy = false;
  bool _isSyncingPending = false;
  String? _errorMessage;
  int _unreadNotifications = 0;

  List<Map<String, dynamic>> get tickets => List.unmodifiable(_tickets);
  List<Map<String, dynamic>> get notificationFeed =>
      List.unmodifiable(_notificationFeed);

  bool get isOnline => _isOnline;
  bool get isBusy => _isBusy;
  bool get isSyncingPending => _isSyncingPending;
  String? get errorMessage => _errorMessage;
  int get unreadNotifications => _unreadNotifications;

  Future<void> start() async {
    if (_started) {
      return;
    }

    _started = true;
    await _refreshConnectivityStatus();
    await _loadKnownTicketKeysFromStorage();

    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      result,
    ) async {
      final currentlyOnline = _hasConnection(result);
      if (_isOnline != currentlyOnline) {
        _isOnline = currentlyOnline;
        notifyListeners();
      }

      if (currentlyOnline) {
        await syncPendingTickets();
        await fetchTickets(isAutoRefresh: true);
      }
    });

    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 25), (_) async {
      if (_isOnline) {
        await fetchTickets(isAutoRefresh: true);
      }
    });

    await syncPendingTickets();
    await fetchTickets(isAutoRefresh: false);
  }

  Future<void> stop() async {
    _pollingTimer?.cancel();
    _pollingTimer = null;

    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;

    _started = false;
  }

  Future<void> reset({bool clearPersistedKeys = false}) async {
    _tickets.clear();
    _notificationFeed.clear();
    _knownTicketKeys.clear();
    _unreadNotifications = 0;
    _errorMessage = null;

    if (clearPersistedKeys) {
      await _clearKnownTicketKeysFromStorage();
    }

    notifyListeners();
  }

  Future<void> markNotificationsRead() async {
    if (_unreadNotifications == 0) {
      return;
    }

    _unreadNotifications = 0;
    notifyListeners();
  }

  Future<void> manualRefresh() async {
    await syncPendingTickets();
    await fetchTickets(isAutoRefresh: false);
  }

  Future<void> onTicketUpdated() async {
    await syncPendingTickets();
    await fetchTickets(isAutoRefresh: false);
  }

  Future<void> fetchTickets({required bool isAutoRefresh}) async {
    final connectivityResult = await _connectivity.checkConnectivity();
    final currentlyOnline = _hasConnection(connectivityResult);

    if (!currentlyOnline) {
      _isOnline = false;
      if (!isAutoRefresh) {
        _errorMessage =
            'You are offline. Connect to the internet to load trip tickets.';
      }
      notifyListeners();
      return;
    }

    _isOnline = true;
    if (!isAutoRefresh) {
      _isBusy = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      final response = await http.get(
        ApiConfig.dailyTripTicketsUri(),
        headers: await _buildHeaders(),
      );

      dynamic payload;
      if (response.body.trim().isNotEmpty) {
        payload = jsonDecode(response.body);
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final fetchedTickets = _extractTicketList(payload);
        await _handleNewTicketNotifications(fetchedTickets);

        _tickets
          ..clear()
          ..addAll(fetchedTickets);

        _errorMessage = null;
      } else {
        _errorMessage = _extractMessage(
          payload,
          fallback: 'Failed to load trip tickets.',
        );
      }
    } catch (_) {
      _errorMessage = 'Unable to connect to server. Please try again.';
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<int> syncPendingTickets() async {
    if (_isSyncingPending) {
      return 0;
    }

    final connectivityResult = await _connectivity.checkConnectivity();
    if (!_hasConnection(connectivityResult)) {
      _isOnline = false;
      notifyListeners();
      return 0;
    }

    _isOnline = true;
    _isSyncingPending = true;
    notifyListeners();

    var syncedCount = 0;

    try {
      final pendingRows = await SqfliteConfig.instance.getPendingTripTickets();
      if (pendingRows.isEmpty) {
        return 0;
      }

      for (final row in pendingRows) {
        final localId = int.tryParse(row['id']?.toString() ?? '');
        final rawPayload = row['payload_json']?.toString() ?? '';

        if (localId == null || rawPayload.trim().isEmpty) {
          continue;
        }

        final payload = SqfliteConfig.instance.decodePendingPayload(rawPayload);
        if (payload.isEmpty) {
          continue;
        }

        try {
          final response = await http.post(
            ApiConfig.dailyTripTicketsUri(),
            headers: await _buildHeaders(),
            body: jsonEncode(payload),
          );

          if (response.statusCode >= 200 && response.statusCode < 300) {
            await SqfliteConfig.instance.removePendingTripTicket(localId);
            syncedCount++;
          }
        } catch (_) {
          // Keep failed payload for next sync attempt.
        }
      }
    } finally {
      _isSyncingPending = false;
      notifyListeners();
    }

    return syncedCount;
  }

  Future<void> _refreshConnectivityStatus() async {
    final result = await _connectivity.checkConnectivity();
    _isOnline = _hasConnection(result);
  }

  Future<void> _loadKnownTicketKeysFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final storedKeys =
        prefs.getStringList(_knownTicketKeysStorageKey) ?? const <String>[];

    _knownTicketKeys
      ..clear()
      ..addAll(storedKeys.where((key) => key.trim().isNotEmpty));
  }

  Future<void> _persistKnownTicketKeysToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _knownTicketKeysStorageKey,
      _knownTicketKeys.toList(growable: false),
    );
  }

  Future<void> _clearKnownTicketKeysFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_knownTicketKeysStorageKey);
  }

  bool _hasConnection(List<ConnectivityResult> result) {
    return result.any((status) => status != ConnectivityResult.none);
  }

  Future<Map<String, String>> _buildHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? '';

    final headers = <String, String>{'Accept': 'application/json'};
    if (token.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${token.trim()}';
    }

    return headers;
  }

  List<Map<String, dynamic>> _extractTicketList(dynamic payload) {
    if (payload is! Map<String, dynamic>) {
      return [];
    }

    final data = payload['data'];
    if (data is! List) {
      return [];
    }

    return data
        .whereType<Map>()
        .map((item) => item.map((key, value) => MapEntry('$key', value)))
        .toList();
  }

  String _extractMessage(dynamic payload, {required String fallback}) {
    if (payload is! Map<String, dynamic>) {
      return fallback;
    }

    final message = payload['message'];
    if (message is String && message.trim().isNotEmpty) {
      return message.trim();
    }

    return fallback;
  }

  String _ticketKey(Map<String, dynamic> ticket) {
    final trfId = ticket['transportation_request_form_id']?.toString();
    if (trfId != null && trfId.trim().isNotEmpty) {
      return 'trf-$trfId';
    }

    final id = ticket['id']?.toString();
    if (id != null && id.trim().isNotEmpty) {
      return 'dtt-$id';
    }

    final requestFormData = _asStringDynamicMap(ticket['request_form_data']);
    final requestId = requestFormData['id']?.toString();
    if (requestId != null && requestId.trim().isNotEmpty) {
      return 'req-$requestId';
    }

    final destination = requestFormData['destination']?.toString().trim() ?? '';
    final requestor =
        requestFormData['requestor_name']?.toString().trim() ?? '';
    final createdAt = ticket['created_at']?.toString().trim() ?? '';
    final fallbackSignature = '$destination|$requestor|$createdAt';
    if (fallbackSignature.replaceAll('|', '').isNotEmpty) {
      return 'sig-$fallbackSignature';
    }

    return '';
  }

  Map<String, dynamic> _asStringDynamicMap(dynamic rawValue) {
    if (rawValue is Map<String, dynamic>) {
      return rawValue;
    }

    if (rawValue is Map) {
      return rawValue.map((key, value) => MapEntry('$key', value));
    }

    return const <String, dynamic>{};
  }

  Future<void> _handleNewTicketNotifications(
    List<Map<String, dynamic>> fetchedTickets,
  ) async {
    final incomingKeys =
        fetchedTickets.map(_ticketKey).where((key) => key.isNotEmpty).toSet();

    final newKeys = incomingKeys.difference(_knownTicketKeys);
    if (newKeys.isEmpty) {
      _knownTicketKeys
        ..clear()
        ..addAll(incomingKeys);
      await _persistKnownTicketKeysToStorage();
      return;
    }

    final newTicketDetails = <Map<String, String>>[];

    for (final ticket in fetchedTickets) {
      final key = _ticketKey(ticket);
      if (!newKeys.contains(key)) {
        continue;
      }

      final requestFormData = _asStringDynamicMap(ticket['request_form_data']);
      final destination =
          requestFormData['destination']?.toString().trim().isNotEmpty == true
              ? requestFormData['destination'].toString().trim()
              : 'Unknown destination';
      final requestor =
          requestFormData['requestor_name']?.toString().trim().isNotEmpty ==
                  true
              ? requestFormData['requestor_name'].toString().trim()
              : 'Unknown requestor';
      final trfId = ticket['transportation_request_form_id']?.toString() ?? '-';

      newTicketDetails.add({
        'title': 'New Transportation Request',
        'body': 'TRF ID $trfId - $destination ($requestor)',
      });

      _notificationFeed.insert(0, {
        'title': 'New Transportation Request',
        'body': 'TRF ID $trfId - $destination ($requestor)',
        'created_at': DateTime.now().toIso8601String(),
      });
    }

    if (newTicketDetails.isEmpty) {
      _knownTicketKeys
        ..clear()
        ..addAll(incomingKeys);
      await _persistKnownTicketKeysToStorage();
      return;
    }

    _unreadNotifications += newTicketDetails.length;

    if (newTicketDetails.length == 1) {
      await AppNotificationService.showNewTransportationRequest(
        title: newTicketDetails.first['title']!,
        body: newTicketDetails.first['body']!,
      );
    } else {
      await AppNotificationService.showNewTransportationRequest(
        title: 'New Transportation Requests',
        body: '${newTicketDetails.length} new requests are available.',
      );
    }

    _knownTicketKeys
      ..clear()
      ..addAll(incomingKeys);

    await _persistKnownTicketKeysToStorage();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
