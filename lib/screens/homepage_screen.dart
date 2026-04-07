import 'package:ems/auth/login_page_screen.dart';
import 'package:ems/providers/dtt_provider.dart';
import 'package:ems/screens/dtts.dart';
import 'package:ems/services/app_notification_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quickalert/quickalert.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await AppNotificationService.ensurePermission();
      if (!mounted) {
        return;
      }

      await context.read<DttProvider>().start();
      await _loadDriverName();
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
    if (!mounted || name.isEmpty) {
      return;
    }

    setState(() {
      _driverName = name;
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
      type: QuickAlertType.confirm,
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
        final filteredTickets = _filteredTickets(provider.tickets);
        final visibleTickets = _visibleTickets(filteredTickets);
        final hasMore = visibleTickets.length < filteredTickets.length;

        return Scaffold(
          backgroundColor: const Color(0xFFF4F8FC),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0B395D),
            foregroundColor: Colors.white,
            elevation: 0,
            title: const Text(
              'Driver Dashboard',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            actions: [
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
          ),
          drawer: Drawer(
            child: SafeArea(
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF0D4C73), Color(0xFF1F6F9E)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
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
                  ListTile(
                    leading: const Icon(Icons.home_outlined),
                    title: const Text('Home'),
                    onTap: () => Navigator.of(context).pop(),
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
          body: Container(
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
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
                              value: provider.tickets.length.toString(),
                            ),
                            const SizedBox(width: 10),
                            _metricChip(
                              label: 'Filtered',
                              value: filteredTickets.length.toString(),
                            ),
                            const SizedBox(width: 10),
                            _metricChip(
                              label:
                                  provider.isSyncingPending
                                      ? 'Syncing'
                                      : 'Pending',
                              value:
                                  provider.isSyncingPending ? '...' : 'Ready',
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
                    filteredTickets: filteredTickets,
                    visibleTickets: visibleTickets,
                    hasMore: hasMore,
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
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
          ),
        );
      },
    );
  }

  Widget _buildTicketSection({
    required DttProvider provider,
    required List<Map<String, dynamic>> filteredTickets,
    required List<Map<String, dynamic>> visibleTickets,
    required bool hasMore,
  }) {
    if (provider.isBusy && provider.tickets.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.errorMessage != null && provider.tickets.isEmpty) {
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

    if (provider.tickets.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'No daily trip tickets found for your account yet.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w600),
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
