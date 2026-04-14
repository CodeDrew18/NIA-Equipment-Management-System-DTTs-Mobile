import 'dart:math' as math;

import 'package:ems/auth/login_page_screen.dart';
import 'package:ems/providers/dtt_provider.dart';
import 'package:ems/screens/driver_evaluation_report_screen.dart';
import 'package:ems/screens/dtts.dart';
import 'package:ems/screens/monthly_official_travel_report_screen.dart';
import 'package:ems/services/app_notification_service.dart';
import 'package:ems/services/fcm_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quickalert/quickalert.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _DrawerSection {
  dashboard,
  dailyTripTicket,
  monthlyReport,
  driverEvaluation,
}

class HomepageScreen extends StatefulWidget {
  const HomepageScreen({super.key});

  @override
  State<HomepageScreen> createState() => _HomepageScreenState();
}

class _HomepageScreenState extends State<HomepageScreen> {
  static const int _pageSize = 10;

  final TextEditingController _searchController = TextEditingController();

  bool _isLoadingAlertVisible = false;
  int _currentPage = 1;
  String _driverName = 'Driver';
  bool _hasResolvedDriverName = false;
  _DrawerSection _selectedSection = _DrawerSection.dashboard;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<DttProvider>();

      await AppNotificationService.ensurePermission();
      if (!mounted) {
        return;
      }

      await _loadDriverName();
      if (!mounted) {
        return;
      }

      await FcmService.instance.syncTokenWithBackend();
      await provider.start();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDriverName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('driver_name')?.trim() ?? '';
    if (!mounted) {
      return;
    }

    setState(() {
      if (name.isNotEmpty) {
        _driverName = name;
      }
      _hasResolvedDriverName = true;
    });
  }

  String _driverInitials(String rawName) {
    final parts =
        rawName
            .trim()
            .split(RegExp(r'\s+'))
            .where((part) => part.isNotEmpty)
            .toList();

    if (parts.isEmpty) {
      return 'DR';
    }

    final first = parts.first.substring(0, 1).toUpperCase();
    final last =
        parts.length > 1 ? parts.last.substring(0, 1).toUpperCase() : first;

    return '$first$last';
  }

  String _normalizeSearch(String value) {
    return value.trim().toLowerCase();
  }

  String _normalizeNameForMatch(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<String> _splitDriverCandidates(String rawValue) {
    final value = rawValue.trim();
    if (value.isEmpty) {
      return const <String>[];
    }

    final parts =
        value
            .split(RegExp(r'[,;/|\n]+'))
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty)
            .toList();

    if (parts.isEmpty) {
      return <String>[value];
    }

    return parts;
  }

  String _ticketIdentityKey(Map<String, dynamic> ticket) {
    final trfId =
        ticket['transportation_request_form_id']?.toString().trim() ?? '';
    if (trfId.isNotEmpty) {
      return 'trf-$trfId';
    }

    final dttId = ticket['id']?.toString().trim() ?? '';
    if (dttId.isNotEmpty) {
      return 'dtt-$dttId';
    }

    final requestFormData = _asStringDynamicMap(ticket['request_form_data']);
    final requestId = requestFormData['id']?.toString().trim() ?? '';
    if (requestId.isNotEmpty) {
      return 'req-$requestId';
    }

    return '';
  }

  bool _matchesAssignedDriverName(String candidate, String normalizedDriver) {
    final normalizedCandidate = _normalizeNameForMatch(candidate);
    if (normalizedCandidate.isEmpty) {
      return false;
    }

    if (normalizedCandidate == normalizedDriver) {
      return true;
    }

    final splitCandidates = _splitDriverCandidates(candidate);
    if (splitCandidates.length <= 1) {
      return false;
    }

    return splitCandidates.any(
      (name) => _normalizeNameForMatch(name) == normalizedDriver,
    );
  }

  List<Map<String, dynamic>> _ticketsForLoggedInDriver(
    List<Map<String, dynamic>> tickets,
  ) {
    if (!_hasResolvedDriverName) {
      return const <Map<String, dynamic>>[];
    }

    final normalizedDriver = _normalizeNameForMatch(_driverName);
    if (normalizedDriver.isEmpty || normalizedDriver == 'driver') {
      return const <Map<String, dynamic>>[];
    }

    final matchedTickets =
        tickets.where((ticket) {
          final requestFormData = _asStringDynamicMap(
            ticket['request_form_data'],
          );
          final nameCandidates = <String>[
            requestFormData['driver_name']?.toString() ?? '',
            requestFormData['assigned_driver']?.toString() ?? '',
            requestFormData['driver']?.toString() ?? '',
            requestFormData['drivers']?.toString() ?? '',
            ticket['driver_name']?.toString() ?? '',
            ticket['assigned_driver']?.toString() ?? '',
            ticket['driver']?.toString() ?? '',
          ];

          return nameCandidates.any(
            (candidate) =>
                _matchesAssignedDriverName(candidate, normalizedDriver),
          );
        }).toList();

    final seenKeys = <String>{};
    final uniqueTickets = <Map<String, dynamic>>[];

    for (final ticket in matchedTickets) {
      final key = _ticketIdentityKey(ticket);
      if (key.isEmpty || seenKeys.add(key)) {
        uniqueTickets.add(ticket);
      }
    }

    return uniqueTickets;
  }

  Map<String, dynamic> _asStringDynamicMap(dynamic rawValue) {
    if (rawValue is Map<String, dynamic>) {
      return rawValue;
    }

    if (rawValue is Map) {
      return rawValue.map((key, value) => MapEntry(key.toString(), value));
    }

    return const <String, dynamic>{};
  }

  List<Map<String, dynamic>> _filteredTickets(
    List<Map<String, dynamic>> tickets,
  ) {
    final query = _normalizeSearch(_searchController.text);
    if (query.isEmpty) {
      return tickets;
    }

    return tickets.where((ticket) {
      final requestFormData = _asStringDynamicMap(ticket['request_form_data']);
      final values = [
        ticket['id']?.toString() ?? '',
        ticket['transportation_request_form_id']?.toString() ?? '',
        requestFormData['destination']?.toString() ?? '',
        requestFormData['requestor_name']?.toString() ?? '',
        requestFormData['driver_name']?.toString() ?? '',
      ];

      return values.any((value) => value.toLowerCase().contains(query));
    }).toList();
  }

  List<Map<String, dynamic>> _visibleTickets(
    List<Map<String, dynamic>> source,
  ) {
    final maxItems = _currentPage * _pageSize;
    final end = maxItems > source.length ? source.length : maxItems;
    return source.sublist(0, end);
  }

  void _loadMoreTickets(List<Map<String, dynamic>> source) {
    final visibleCount = _visibleTickets(source).length;
    if (visibleCount >= source.length) {
      return;
    }

    setState(() {
      _currentPage += 1;
    });
  }

  void _selectSection(_DrawerSection section) {
    Navigator.of(context).pop();
    if (_selectedSection == section) {
      return;
    }

    setState(() {
      _selectedSection = section;
      if (section == _DrawerSection.dailyTripTicket) {
        _currentPage = 1;
      }
    });
  }

  void _showLoadingAlert(String text) {
    if (!mounted || _isLoadingAlertVisible) {
      return;
    }

    _isLoadingAlertVisible = true;
    QuickAlert.show(
      context: context,
      type: QuickAlertType.loading,
      title: 'Please wait',
      text: text,
      barrierDismissible: false,
    );
  }

  void _closeLoadingAlert() {
    if (!mounted || !_isLoadingAlertVisible) {
      return;
    }

    _isLoadingAlertVisible = false;
    try {
      Navigator.of(context, rootNavigator: true).pop();
    } catch (_) {
      // Ignore if dialog has already been dismissed.
    }
  }

  Future<void> _handleLogout() async {
    var shouldLogout = false;

    await QuickAlert.show(
      context: context,
      type: QuickAlertType.info,
      title: 'Logout',
      text: 'Are you sure you want to logout?',
      confirmBtnText: 'Logout',
      cancelBtnText: 'Cancel',
      showCancelBtn: true,
      onConfirmBtnTap: () {
        shouldLogout = true;
        Navigator.of(context, rootNavigator: true).pop();
      },
      onCancelBtnTap: () {
        Navigator.of(context, rootNavigator: true).pop();
      },
    );

    if (!shouldLogout || !mounted) {
      return;
    }

    _showLoadingAlert('Logging out...');

    final provider = context.read<DttProvider>();
    await provider.stop();
    await provider.reset(clearPersistedKeys: true);
    await FcmService.instance.clearTokenFromBackend();
    await FcmService.instance.logoutFromBackend();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_logged_in', false);
    await prefs.remove('auth_token');
    await prefs.remove('driver_name');

    _closeLoadingAlert();

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPageScreen()),
      (route) => false,
    );
  }

  Future<void> _openTicket(Map<String, dynamic> ticket) async {
    final wasUpdated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DailyDriversTripTicketScreen(ticketData: ticket),
      ),
    );

    if (wasUpdated == true && mounted) {
      await context.read<DttProvider>().onTicketUpdated();
    }
  }

  Future<void> _showNotificationCenter(DttProvider provider) async {
    await provider.markNotificationsRead();
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        final items = provider.notificationFeed;

        if (items.isEmpty) {
          return const SizedBox(
            height: 220,
            child: Center(
              child: Text(
                'No notifications yet.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final item = items[index];
            final title = item['title']?.toString() ?? 'Notification';
            final body = item['body']?.toString() ?? '';

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD7E4EF)),
                color: const Color(0xFFF8FBFE),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.notifications_active_outlined,
                    color: Color(0xFF0D4C73),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(body),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DttProvider>(
      builder: (context, provider, _) {
        final driverTickets = _ticketsForLoggedInDriver(provider.tickets);
        final filteredTickets = _filteredTickets(driverTickets);
        final visibleTickets = filteredTickets;
        final hasMore = false;
        final showNotificationAction =
            _selectedSection == _DrawerSection.dashboard ||
            _selectedSection == _DrawerSection.dailyTripTicket;
        final showRefreshFab =
            _selectedSection == _DrawerSection.dashboard ||
            _selectedSection == _DrawerSection.dailyTripTicket;
        final appBarTitle = switch (_selectedSection) {
          _DrawerSection.dashboard => 'Driver Dashboard',
          _DrawerSection.dailyTripTicket => 'Daily Driver\'s Trip Ticket',
          _DrawerSection.monthlyReport => 'Monthly Official Travel Report',
          _DrawerSection.driverEvaluation => 'Driver Evaluation Report',
        };

        return Scaffold(
          backgroundColor: const Color(0xFFF4F8FC),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0B395D),
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text(
              appBarTitle,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            actions: [
              if (showNotificationAction) ...[
                IconButton(
                  onPressed: () => _showNotificationCenter(provider),
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.notifications_none_rounded, size: 28),
                      if (provider.unreadNotifications > 0)
                        Positioned(
                          right: -5,
                          top: -5,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            constraints: const BoxConstraints(minWidth: 18),
                            child: Text(
                              provider.unreadNotifications > 99
                                  ? '99+'
                                  : provider.unreadNotifications.toString(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
          drawer: Drawer(
            child: SafeArea(
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                    color: const Color(0xFF0B395D),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 27,
                          backgroundColor: Colors.white,
                          child: Text(
                            _driverInitials(_driverName),
                            style: const TextStyle(
                              color: Color(0xFF0D4C73),
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Logged In Driver',
                                style: TextStyle(
                                  color: Color(0xFFCDE6F7),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _driverName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: Icon(
                        Icons.home_outlined,
                        color:
                            _selectedSection == _DrawerSection.dashboard
                                ? Colors.white
                                : Colors.black,
                      ),
                      title: Text(
                        'Dashboard',
                        style: TextStyle(
                          color:
                              _selectedSection == _DrawerSection.dashboard
                                  ? Colors.white
                                  : Colors.black,
                        ),
                      ),
                      selected: _selectedSection == _DrawerSection.dashboard,
                      selectedTileColor: const Color(0xFF0B395D),
                      selectedColor: const Color(0xFF0B395D),
                      onTap: () => _selectSection(_DrawerSection.dashboard),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: Icon(
                        Icons.local_shipping_outlined,
                        color:
                            _selectedSection == _DrawerSection.dailyTripTicket
                                ? Colors.white
                                : Colors.black,
                      ),
                      title: Text(
                        'Daily Driver\'s Trip Ticket',
                        style: TextStyle(
                          color:
                              _selectedSection == _DrawerSection.dailyTripTicket
                                  ? Colors.white
                                  : Colors.black,
                        ),
                      ),
                      selected:
                          _selectedSection == _DrawerSection.dailyTripTicket,
                      selectedTileColor: const Color(0xFF0B395D),
                      selectedColor: const Color(0xFF0B395D),
                      onTap:
                          () => _selectSection(_DrawerSection.dailyTripTicket),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),

                      leading: Icon(
                        Icons.assignment_outlined,
                        color:
                            _selectedSection == _DrawerSection.monthlyReport
                                ? Colors.white
                                : Colors.black,
                      ),
                      title: Text(
                        'Monthly Travel Report',
                        style: TextStyle(
                          color:
                              _selectedSection == _DrawerSection.monthlyReport
                                  ? Colors.white
                                  : Colors.black,
                        ),
                      ),
                      selected:
                          _selectedSection == _DrawerSection.monthlyReport,
                      selectedTileColor: const Color(0xFF0B395D),
                      selectedColor: const Color(0xFF0B395D),
                      onTap: () => _selectSection(_DrawerSection.monthlyReport),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: Icon(
                        Icons.assessment_outlined,
                        color:
                            _selectedSection == _DrawerSection.driverEvaluation
                                ? Colors.white
                                : Colors.black,
                      ),
                      title: Text(
                        'Driver Evaluation Report',
                        style: TextStyle(
                          color:
                              _selectedSection ==
                                      _DrawerSection.driverEvaluation
                                  ? Colors.white
                                  : Colors.black,
                        ),
                      ),
                      selected:
                          _selectedSection == _DrawerSection.driverEvaluation,
                      selectedTileColor: const Color(0xFF0B395D),
                      selectedColor: const Color(0xFF0B395D),
                      onTap:
                          () => _selectSection(_DrawerSection.driverEvaluation),
                    ),
                  ),
                  const Spacer(),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.redAccent),
                    title: const Text(
                      'Logout',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                    onTap: () async {
                      Navigator.of(context).pop();
                      await _handleLogout();
                    },
                  ),
                ],
              ),
            ),
          ),
          body: _buildSelectedSectionBody(
            provider: provider,
            driverTickets: driverTickets,
            filteredTickets: filteredTickets,
            visibleTickets: visibleTickets,
            hasMore: hasMore,
          ),
          floatingActionButton:
              showRefreshFab
                  ? FloatingActionButton.extended(
                    onPressed:
                        provider.isBusy
                            ? null
                            : () async {
                              await context.read<DttProvider>().manualRefresh();
                            },
                    backgroundColor: const Color(0xFF0D4C73),
                    foregroundColor: Colors.white,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  )
                  : null,
        );
      },
    );
  }

  Widget _buildSelectedSectionBody({
    required DttProvider provider,
    required List<Map<String, dynamic>> driverTickets,
    required List<Map<String, dynamic>> filteredTickets,
    required List<Map<String, dynamic>> visibleTickets,
    required bool hasMore,
  }) {
    switch (_selectedSection) {
      case _DrawerSection.dashboard:
        return _buildDashboardSummaryBody(
          provider: provider,
          driverTickets: driverTickets,
        );
      case _DrawerSection.dailyTripTicket:
        return _buildHomeDashboardBody(
          provider: provider,
          driverTickets: driverTickets,
          filteredTickets: filteredTickets,
          visibleTickets: visibleTickets,
          hasMore: hasMore,
        );
      case _DrawerSection.monthlyReport:
        return Container(
          color: const Color(0xFFF7F9FC),
          child: MonthlyOfficialTravelReportScreen(
            tickets: driverTickets,
            assignedDriver: _driverName,
            embedded: true,
          ),
        );
      case _DrawerSection.driverEvaluation:
        return const DriverEvaluationReportScreen(embedded: true);
    }
  }

  DateTime? _parseTicketDate(dynamic rawValue) {
    final value = rawValue?.toString().trim() ?? '';
    if (value.isEmpty) {
      return null;
    }

    return DateTime.tryParse(value);
  }

  DateTime? _ticketDate(Map<String, dynamic> ticket) {
    final requestFormData = _asStringDynamicMap(ticket['request_form_data']);
    final candidates = [
      ticket['departure_time'],
      ticket['arrival_time_destination'],
      ticket['arrival_time_office'],
      ticket['created_at'],
      requestFormData['departure_time'],
      requestFormData['date_of_travel'],
      requestFormData['travel_date'],
      requestFormData['created_at'],
    ];

    for (final candidate in candidates) {
      final parsed = _parseTicketDate(candidate);
      if (parsed != null) {
        return parsed;
      }
    }

    return null;
  }

  String _ticketStatusBucket(Map<String, dynamic> ticket) {
    final requestFormData = _asStringDynamicMap(ticket['request_form_data']);
    final rawStatus =
        requestFormData['status']?.toString() ??
        ticket['status']?.toString() ??
        '';
    final status = rawStatus.trim().toLowerCase();

    if (status.contains('complete') ||
        status.contains('approved') ||
        status.contains('done')) {
      return 'Completed';
    }

    if (status.contains('cancel') || status.contains('reject')) {
      return 'Cancelled';
    }

    if (status.contains('transit') ||
        status.contains('travel') ||
        status.contains('ongoing')) {
      return 'In Transit';
    }

    return 'Pending';
  }

  int _todayTicketCount(List<Map<String, dynamic>> tickets) {
    final now = DateTime.now();
    return tickets.where((ticket) {
      final date = _ticketDate(ticket);
      if (date == null) {
        return false;
      }

      return date.year == now.year &&
          date.month == now.month &&
          date.day == now.day;
    }).length;
  }

  Map<String, int> _statusDistribution(List<Map<String, dynamic>> tickets) {
    final counts = <String, int>{
      'Completed': 0,
      'Pending': 0,
      'In Transit': 0,
      'Cancelled': 0,
    };

    for (final ticket in tickets) {
      final bucket = _ticketStatusBucket(ticket);
      counts[bucket] = (counts[bucket] ?? 0) + 1;
    }

    return counts;
  }

  List<_MonthlyPoint> _monthlyPoints(
    List<Map<String, dynamic>> tickets, {
    int months = 6,
  }) {
    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final now = DateTime.now();
    final monthStarts = List<DateTime>.generate(months, (index) {
      final date = DateTime(now.year, now.month - (months - 1 - index), 1);
      return DateTime(date.year, date.month, 1);
    });

    final counts = <String, int>{};
    for (final monthStart in monthStarts) {
      counts['${monthStart.year}-${monthStart.month}'] = 0;
    }

    for (final ticket in tickets) {
      final date = _ticketDate(ticket);
      if (date == null) {
        continue;
      }

      final key = '${date.year}-${date.month}';
      if (counts.containsKey(key)) {
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }

    return monthStarts.map((monthStart) {
      final key = '${monthStart.year}-${monthStart.month}';
      final shortYear = monthStart.year.toString().substring(2);
      final label = '${monthNames[monthStart.month - 1]} $shortYear';
      return _MonthlyPoint(label: label, count: counts[key] ?? 0);
    }).toList();
  }

  List<MapEntry<String, int>> _topDestinationCounts(
    List<Map<String, dynamic>> tickets, {
    int limit = 5,
  }) {
    final counts = <String, int>{};

    for (final ticket in tickets) {
      final requestFormData = _asStringDynamicMap(ticket['request_form_data']);
      final destination =
          requestFormData['destination']?.toString().trim() ?? '';
      if (destination.isEmpty) {
        continue;
      }

      counts[destination] = (counts[destination] ?? 0) + 1;
    }

    final sortedEntries =
        counts.entries.toList()..sort((a, b) {
          final byCount = b.value.compareTo(a.value);
          if (byCount != 0) {
            return byCount;
          }
          return a.key.compareTo(b.key);
        });

    if (sortedEntries.length <= limit) {
      return sortedEntries;
    }

    return sortedEntries.sublist(0, limit);
  }

  Widget _buildDashboardSummaryBody({
    required DttProvider provider,
    required List<Map<String, dynamic>> driverTickets,
  }) {
    if (!_hasResolvedDriverName) {
      return const Center(child: CircularProgressIndicator());
    }

    final statusCounts = _statusDistribution(driverTickets);
    final completed = statusCounts['Completed'] ?? 0;
    final pending = statusCounts['Pending'] ?? 0;
    final inTransit = statusCounts['In Transit'] ?? 0;
    final cancelled = statusCounts['Cancelled'] ?? 0;
    final todayCount = _todayTicketCount(driverTickets);
    final monthlyPoints = _monthlyPoints(driverTickets);
    final topDestinations = _topDestinationCounts(driverTickets);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF7FBFF), Color(0xFFEAF3FB)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
        children: [
          if (!provider.isOnline)
            Container(
              width: double.infinity,
              color: const Color(0xFFFCE8D3),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: const Text(
                'Offline mode: summaries may not include newly submitted server records yet.',
                style: TextStyle(
                  color: Color(0xFF8A5B00),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [Color(0xFF0B395D), Color(0xFF1F6F9E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dashboard Overview',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Driver: $_driverName',
                  style: const TextStyle(
                    color: Color(0xFFD0E7F8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _dashboardMetricTile(
                label: 'Total DTTs',
                value: '${driverTickets.length}',
                icon: Icons.assignment_outlined,
                color: const Color(0xFF0B395D),
              ),
              _dashboardMetricTile(
                label: 'Today Trips',
                value: '$todayCount',
                icon: Icons.today_outlined,
                color: const Color(0xFF1E6EA0),
              ),
              _dashboardMetricTile(
                label: 'Completed',
                value: '$completed',
                icon: Icons.check_circle_outline,
                color: const Color(0xFF257041),
              ),
              _dashboardMetricTile(
                label: 'Pending',
                value: '$pending',
                icon: Icons.pending_outlined,
                color: const Color(0xFFB26A00),
              ),
              _dashboardMetricTile(
                label: 'In Transit',
                value: '$inTransit',
                icon: Icons.local_shipping_outlined,
                color: const Color(0xFF4B5F6F),
              ),
              _dashboardMetricTile(
                label: 'Cancelled',
                value: '$cancelled',
                icon: Icons.cancel_outlined,
                color: const Color(0xFF9C2D2D),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _dashboardSectionCard(
            title: 'Trip Status Chart',
            subtitle: 'Status distribution of your daily trip tickets.',
            child: _statusChart(statusCounts),
          ),
          const SizedBox(height: 12),
          _dashboardSectionCard(
            title: 'Monthly Ticket Graph',
            subtitle: 'Trip ticket volume for the last 6 months.',
            child: _MonthlyTrendGraph(points: monthlyPoints),
          ),
          const SizedBox(height: 12),
          _dashboardSectionCard(
            title: 'Top Destinations Graph',
            subtitle: 'Most frequent destinations based on your DTT records.',
            child: _topDestinationGraph(topDestinations),
          ),
        ],
      ),
    );
  }

  Widget _dashboardMetricTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD6E3EC)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF5A6D7D),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF0F2E47),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardSectionCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD6E3EC)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF0F2E47),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF5A6D7D),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _statusChart(Map<String, int> statusCounts) {
    const order = ['Completed', 'Pending', 'In Transit', 'Cancelled'];
    const colors = {
      'Completed': Color(0xFF257041),
      'Pending': Color(0xFFB26A00),
      'In Transit': Color(0xFF1E6EA0),
      'Cancelled': Color(0xFF9C2D2D),
    };

    final total = statusCounts.values.fold<int>(0, (sum, count) => sum + count);

    return Column(
      children:
          order.map((status) {
            final count = statusCounts[status] ?? 0;
            final ratio = total == 0 ? 0.0 : count / total;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 88,
                    child: Text(
                      status,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF3D5365),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 12,
                        value: ratio,
                        backgroundColor: const Color(0xFFE7EEF4),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          colors[status]!,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 26,
                    child: Text(
                      '$count',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Color(0xFF0F2E47),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
    );
  }

  Widget _topDestinationGraph(List<MapEntry<String, int>> destinations) {
    if (destinations.isEmpty) {
      return const Text(
        'No destination data available yet.',
        style: TextStyle(color: Color(0xFF5A6D7D), fontWeight: FontWeight.w600),
      );
    }

    final maxCount = destinations
        .map((entry) => entry.value)
        .fold<int>(0, (maxValue, value) => math.max(maxValue, value));
    final safeMaxCount = maxCount == 0 ? 1 : maxCount;

    return Column(
      children:
          destinations.map((entry) {
            final widthFactor = entry.value / safeMaxCount;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      entry.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF3D5365),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: Stack(
                        children: [
                          Container(height: 12, color: const Color(0xFFE7EEF4)),
                          FractionallySizedBox(
                            widthFactor: widthFactor,
                            child: Container(
                              height: 12,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF0B395D),
                                    Color(0xFF1F6F9E),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${entry.value}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Color(0xFF0F2E47),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
    );
  }

  Widget _buildHomeDashboardBody({
    required DttProvider provider,
    required List<Map<String, dynamic>> driverTickets,
    required List<Map<String, dynamic>> filteredTickets,
    required List<Map<String, dynamic>> visibleTickets,
    required bool hasMore,
  }) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF7FBFF), Color(0xFFEAF3FB)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          if (!provider.isOnline)
            Container(
              width: double.infinity,
              color: const Color(0xFFFCE8D3),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: const Text(
                'Offline mode: you can still open records and save offline entries.',
                style: TextStyle(
                  color: Color(0xFF8A5B00),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0B395D), Color(0xFF1F6F9E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Daily Trip Ticket Overview',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _metricChip(
                        label: 'Total',
                        value: driverTickets.length.toString(),
                      ),
                      const SizedBox(width: 10),
                      _metricChip(
                        label: 'Filtered',
                        value: filteredTickets.length.toString(),
                      ),
                      const SizedBox(width: 10),
                      _metricChip(
                        label:
                            provider.isSyncingPending ? 'Syncing' : 'Pending',
                        value: provider.isSyncingPending ? '...' : 'Ready',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (_) {
                setState(() {
                  _currentPage = 1;
                });
              },
              decoration: InputDecoration(
                labelText: 'Search by TRF, destination, requestor',
                prefixIcon: const Icon(Icons.search),
                suffixIcon:
                    _searchController.text.isEmpty
                        ? null
                        : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _currentPage = 1;
                            });
                          },
                          icon: const Icon(Icons.close),
                        ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Showing ${visibleTickets.length} of ${filteredTickets.length}',
                  style: const TextStyle(
                    color: Color(0xFF3A4E5C),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (provider.isSyncingPending)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _buildTicketSection(
              provider: provider,
              driverTickets: driverTickets,
              filteredTickets: filteredTickets,
              visibleTickets: visibleTickets,
              hasMore: hasMore,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketSection({
    required DttProvider provider,
    required List<Map<String, dynamic>> driverTickets,
    required List<Map<String, dynamic>> filteredTickets,
    required List<Map<String, dynamic>> visibleTickets,
    required bool hasMore,
  }) {
    if (!_hasResolvedDriverName) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.isBusy && driverTickets.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.errorMessage != null && driverTickets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            provider.errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    if (driverTickets.isEmpty) {
      final nameLabel = _driverName.trim();
      final message =
          nameLabel.isNotEmpty && nameLabel.toLowerCase() != 'driver'
              ? 'No daily trip tickets found for $nameLabel yet.'
              : 'No daily trip tickets found for your account yet.';

      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    if (filteredTickets.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'No trip tickets matched your search.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<DttProvider>().manualRefresh(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 90),
        itemCount: visibleTickets.length + (hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index >= visibleTickets.length) {
            final remaining = filteredTickets.length - visibleTickets.length;
            return OutlinedButton.icon(
              onPressed: () => _loadMoreTickets(filteredTickets),
              icon: const Icon(Icons.expand_more),
              label: Text('Load more ($remaining remaining)'),
            );
          }

          final ticket = visibleTickets[index];
          final requestFormData = _asStringDynamicMap(
            ticket['request_form_data'],
          );

          final trfId =
              ticket['transportation_request_form_id']?.toString() ?? '-';
          final destination =
              requestFormData['destination']?.toString().trim().isNotEmpty ==
                      true
                  ? requestFormData['destination'].toString()
                  : 'No destination';
          final requestor =
              requestFormData['requestor_name']?.toString().trim().isNotEmpty ==
                      true
                  ? requestFormData['requestor_name'].toString()
                  : 'Unknown requestor';
          final status =
              requestFormData['status']?.toString().trim().isNotEmpty == true
                  ? requestFormData['status'].toString()
                  : 'Pending';

          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openTicket(ticket),
            child: Ink(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD8E5EF)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F2F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Color(0xFF0D4C73),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'TRF ID: $trfId',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF7EF),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  status,
                                  style: const TextStyle(
                                    color: Color(0xFF257041),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Destination: $destination',
                            style: const TextStyle(color: Color(0xFF4B5F6F)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Requestor: $requestor',
                            style: const TextStyle(color: Color(0xFF4B5F6F)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right, color: Color(0xFF7C8F9D)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _metricChip({required String label, required String value}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFCDE6F7),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthlyPoint {
  const _MonthlyPoint({required this.label, required this.count});

  final String label;
  final int count;
}

class _MonthlyTrendGraph extends StatelessWidget {
  const _MonthlyTrendGraph({required this.points});

  final List<_MonthlyPoint> points;

  @override
  Widget build(BuildContext context) {
    final values = points.map((point) => point.count).toList(growable: false);

    return Column(
      children: [
        SizedBox(
          height: 190,
          child: CustomPaint(
            painter: _MonthlyTrendPainter(values: values),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children:
              points.map((point) {
                return Expanded(
                  child: Column(
                    children: [
                      Text(
                        point.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF5A6D7D),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${point.count}',
                        style: const TextStyle(
                          color: Color(0xFF0F2E47),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
        ),
      ],
    );
  }
}

class _MonthlyTrendPainter extends CustomPainter {
  _MonthlyTrendPainter({required this.values});

  final List<int> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) {
      return;
    }

    final gridPaint =
        Paint()
          ..color = const Color(0xFFE5EDF3)
          ..strokeWidth = 1;

    for (var i = 0; i < 4; i++) {
      final y = (size.height / 3) * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final maxValue = values.fold<int>(
      0,
      (currentMax, value) => math.max(currentMax, value),
    );
    final safeMaxValue = maxValue == 0 ? 1 : maxValue;
    final stepX = values.length == 1 ? 0.0 : size.width / (values.length - 1);

    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final normalized = values[i] / safeMaxValue;
      final y = size.height - (normalized * (size.height - 18)) - 9;
      points.add(Offset(i * stepX, y));
    }

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }

    final areaPath =
        Path.from(linePath)
          ..lineTo(points.last.dx, size.height)
          ..lineTo(points.first.dx, size.height)
          ..close();

    final areaPaint =
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0x70226A9B), Color(0x10226A9B)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
          ..style = PaintingStyle.fill;

    canvas.drawPath(areaPath, areaPaint);

    final linePaint =
        Paint()
          ..color = const Color(0xFF1F6F9E)
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

    canvas.drawPath(linePath, linePaint);

    final dotFill = Paint()..color = const Color(0xFF1F6F9E);
    final dotBorder = Paint()..color = Colors.white;

    for (final point in points) {
      canvas.drawCircle(point, 5, dotBorder);
      canvas.drawCircle(point, 3.2, dotFill);
    }
  }

  @override
  bool shouldRepaint(covariant _MonthlyTrendPainter oldDelegate) {
    return true;
  }
}
