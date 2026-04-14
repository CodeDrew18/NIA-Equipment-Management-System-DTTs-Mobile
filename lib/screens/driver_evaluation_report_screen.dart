import 'dart:convert';

import 'package:ems/models/api_config.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class DriverEvaluationReportScreen extends StatefulWidget {
  const DriverEvaluationReportScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<DriverEvaluationReportScreen> createState() =>
      _DriverEvaluationReportScreenState();
}

class _DriverEvaluationReportScreenState
    extends State<DriverEvaluationReportScreen> {
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isLoadingDetail = false;
  String? _errorMessage;
  String _driverName = 'Driver';
  List<Map<String, dynamic>> _evaluations = [];

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeScreen() async {
    await _loadDriverNameFromPrefs();
    await _fetchEvaluations();
  }

  Future<void> _loadDriverNameFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('driver_name')?.trim() ?? '';
    if (!mounted || name.isEmpty) {
      return;
    }

    setState(() {
      _driverName = name;
    });
  }

  Map<String, dynamic> _asStringMap(dynamic rawValue) {
    if (rawValue is Map<String, dynamic>) {
      return rawValue;
    }

    if (rawValue is Map) {
      return rawValue.map((key, value) => MapEntry(key.toString(), value));
    }

    return const <String, dynamic>{};
  }

  List<Map<String, dynamic>> _asListOfMap(dynamic rawValue) {
    if (rawValue is! List) {
      return [];
    }

    return rawValue
        .whereType<Map>()
        .map((entry) => entry.map((key, value) => MapEntry('$key', value)))
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

  Future<Map<String, String>> _buildHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token')?.trim() ?? '';

    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };

    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  }

  Future<void> _fetchEvaluations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(
        ApiConfig.driverPerformanceEvaluationsUri(),
        headers: await _buildHeaders(),
      );

      dynamic payload;
      if (response.body.trim().isNotEmpty) {
        payload = jsonDecode(response.body);
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = _asListOfMap(_asStringMap(payload)['data']);
        final driverMap = _asStringMap(_asStringMap(payload)['driver']);
        final fetchedName = driverMap['name']?.toString().trim() ?? '';

        if (!mounted) {
          return;
        }

        setState(() {
          _evaluations = data;
          if (fetchedName.isNotEmpty) {
            _driverName = fetchedName;
          }
        });
      } else {
        final message = _extractMessage(
          payload,
          fallback: 'Failed to load driver evaluations.',
        );

        if (!mounted) {
          return;
        }

        setState(() {
          _errorMessage = message;
        });
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Unable to connect to server. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value;
    }

    final raw = value.toString().trim();
    if (raw.isEmpty) {
      return null;
    }

    final normalized = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
    return DateTime.tryParse(normalized);
  }

  String _formatDateTime(dynamic value) {
    final date = _parseDate(value);
    if (date == null) {
      return '—';
    }

    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '${date.year}-$month-$day $hour:$minute';
  }

  String _formatScore(dynamic value) {
    if (value == null) {
      return '—';
    }

    final parsed = num.tryParse(value.toString());
    if (parsed == null) {
      return '—';
    }

    return parsed.toStringAsFixed(1);
  }

  Color _statusBackground(String status) {
    final lower = status.toLowerCase();
    if (lower.contains('approved') ||
        lower.contains('completed') ||
        lower.contains('submitted')) {
      return const Color(0xFFEAF7EF);
    }
    if (lower.contains('pending') || lower.contains('review')) {
      return const Color(0xFFFFF4DF);
    }
    if (lower.contains('reject') || lower.contains('declin')) {
      return const Color(0xFFFDE8E8);
    }
    return const Color(0xFFE8F2F9);
  }

  Color _statusForeground(String status) {
    final lower = status.toLowerCase();
    if (lower.contains('approved') ||
        lower.contains('completed') ||
        lower.contains('submitted')) {
      return const Color(0xFF257041);
    }
    if (lower.contains('pending') || lower.contains('review')) {
      return const Color(0xFF8B6200);
    }
    if (lower.contains('reject') || lower.contains('declin')) {
      return const Color(0xFF8F2323);
    }
    return const Color(0xFF0D4C73);
  }

  List<Map<String, dynamic>> _filteredEvaluations() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _evaluations;
    }

    return _evaluations.where((evaluation) {
      final request = _asStringMap(evaluation['request']);
      final values = [
        evaluation['id']?.toString() ?? '',
        evaluation['evaluator_name']?.toString() ?? '',
        request['destination']?.toString() ?? '',
        request['vehicle_id']?.toString() ?? '',
        evaluation['status']?.toString() ?? '',
      ];

      return values.any((value) => value.toLowerCase().contains(query));
    }).toList();
  }

  Future<void> _openEvaluationDetail(Map<String, dynamic> summary) async {
    final id = int.tryParse(summary['id']?.toString() ?? '');
    if (id == null || _isLoadingDetail) {
      return;
    }

    setState(() {
      _isLoadingDetail = true;
    });

    try {
      final response = await http.get(
        ApiConfig.driverPerformanceEvaluationByIdUri(id),
        headers: await _buildHeaders(),
      );

      dynamic payload;
      if (response.body.trim().isNotEmpty) {
        payload = jsonDecode(response.body);
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (!mounted) {
          return;
        }

        final message = _extractMessage(
          payload,
          fallback: 'Failed to load evaluation details.',
        );

        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
        return;
      }

      final detail = _asStringMap(_asStringMap(payload)['data']);

      if (!mounted) {
        return;
      }

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        showDragHandle: true,
        builder: (_) => _EvaluationDetailSheet(data: detail),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Unable to load evaluation details.')),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingDetail = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredEvaluations();

    final content = Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: [Color(0xFF0B395D), Color(0xFF1F6F9E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _driverName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${filtered.length} evaluation(s) found',
                style: const TextStyle(
                  color: Color(0xFFCDE6F7),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Search by destination, evaluator, vehicle',
              prefixIcon: const Icon(Icons.search),
              suffixIcon:
                  _searchController.text.isEmpty
                      ? null
                      : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
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
        Expanded(child: _buildBody(filtered)),
      ],
    );

    if (widget.embedded) {
      return Container(color: const Color(0xFFF4F8FC), child: content);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B395D),
        foregroundColor: Colors.white,
        title: const Text('Driver Evaluation Report'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _fetchEvaluations,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: content,
    );
  }

  Widget _buildBody(List<Map<String, dynamic>> filtered) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    if (_evaluations.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'No submitted driver performance evaluations available yet.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    if (filtered.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'No evaluations matched your search.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchEvaluations,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
        itemCount: filtered.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, index) {
          final item = filtered[index];
          final request = _asStringMap(item['request']);
          final status = item['status']?.toString() ?? '—';
          final destination = request['destination']?.toString() ?? '—';
          final evaluatedAt = _formatDateTime(item['evaluated_at']);
          final overall = _formatScore(item['overall_rating']);
          final badgeColor = _statusBackground(status);
          final badgeTextColor = _statusForeground(status);

          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openEvaluationDetail(item),
            child: Ink(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD8E5EF)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x120D4C73),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Evaluation #${item['id'] ?? '-'}',
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
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: badgeTextColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Destination: $destination',
                    style: const TextStyle(
                      color: Color(0xFF2A3E4F),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Evaluator: ${item['evaluator_name']?.toString() ?? '—'}',
                    style: const TextStyle(color: Color(0xFF4B5F6F)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Evaluated At: $evaluatedAt',
                    style: const TextStyle(color: Color(0xFF4B5F6F)),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F2F9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Overall Rating: $overall',
                          style: const TextStyle(
                            color: Color(0xFF0D4C73),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (_isLoadingDetail)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        const Icon(
                          Icons.chevron_right,
                          color: Color(0xFF7C8F9D),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Tap to view full evaluation details',
                    style: TextStyle(
                      color: Color(0xFF6A7B89),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EvaluationDetailSheet extends StatelessWidget {
  const _EvaluationDetailSheet({required this.data});

  final Map<String, dynamic> data;

  Map<String, dynamic> _asStringMap(dynamic rawValue) {
    if (rawValue is Map<String, dynamic>) {
      return rawValue;
    }

    if (rawValue is Map) {
      return rawValue.map((key, value) => MapEntry(key.toString(), value));
    }

    return const <String, dynamic>{};
  }

  String _score(dynamic value) {
    if (value == null) {
      return '—';
    }

    final parsed = num.tryParse(value.toString());
    if (parsed == null) {
      return '—';
    }

    return parsed.toStringAsFixed(1);
  }

  double _scorePercent(dynamic value) {
    final parsed = num.tryParse(value?.toString() ?? '');
    if (parsed == null) {
      return 0;
    }

    final normalized = parsed / 5;
    if (normalized < 0) {
      return 0;
    }
    if (normalized > 1) {
      return 1;
    }
    return normalized.toDouble();
  }

  Color _statusBackground(String status) {
    final lower = status.toLowerCase();
    if (lower.contains('approved') ||
        lower.contains('completed') ||
        lower.contains('submitted')) {
      return const Color(0xFFEAF7EF);
    }
    if (lower.contains('pending') || lower.contains('review')) {
      return const Color(0xFFFFF4DF);
    }
    if (lower.contains('reject') || lower.contains('declin')) {
      return const Color(0xFFFDE8E8);
    }
    return const Color(0xFFE8F2F9);
  }

  Color _statusForeground(String status) {
    final lower = status.toLowerCase();
    if (lower.contains('approved') ||
        lower.contains('completed') ||
        lower.contains('submitted')) {
      return const Color(0xFF257041);
    }
    if (lower.contains('pending') || lower.contains('review')) {
      return const Color(0xFF8B6200);
    }
    if (lower.contains('reject') || lower.contains('declin')) {
      return const Color(0xFF8F2323);
    }
    return const Color(0xFF0D4C73);
  }

  String _valueText(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '—' : text;
  }

  String _formatDateTime(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) {
      return '—';
    }

    final normalized = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null) {
      return raw;
    }

    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '${parsed.year}-$month-$day $hour:$minute';
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
    );
  }

  Widget _metaChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8E5EF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF0D4C73)),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF5B6C7A),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0D4C73),
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

  Widget _scoreLine(String label, dynamic value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2A3E4F),
                ),
              ),
            ),
            Text(
              _score(value),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF0D4C73),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: _scorePercent(value),
            minHeight: 8,
            color: const Color(0xFF0D4C73),
            backgroundColor: const Color(0xFFDDE8F1),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final request = _asStringMap(data['request']);
    final status = _valueText(data['status']);
    final statusBackground = _statusBackground(status);
    final statusForeground = _statusForeground(status);

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (context, controller) {
          return ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0B395D), Color(0xFF1F6F9E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Evaluation #${_valueText(data['id'])}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: statusBackground,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              color: statusForeground,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _valueText(request['destination']),
                      style: const TextStyle(
                        color: Color(0xFFD3E8F8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _metaChip(
                    icon: Icons.star_rounded,
                    label: 'Overall Rating',
                    value: _score(data['overall_rating']),
                  ),
                  _metaChip(
                    icon: Icons.person_outline,
                    label: 'Evaluator',
                    value: _valueText(data['evaluator_name']),
                  ),
                  _metaChip(
                    icon: Icons.schedule,
                    label: 'Evaluated At',
                    value: _formatDateTime(data['evaluated_at']),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F8FC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD8E5EF)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle(context, 'Performance Scores'),
                    const SizedBox(height: 10),
                    _scoreLine('Timeliness Score', data['timeliness_score']),
                    const SizedBox(height: 10),
                    _scoreLine('Safety Score', data['safety_score']),
                    const SizedBox(height: 10),
                    _scoreLine('Compliance Score', data['compliance_score']),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _sectionTitle(context, 'Comments'),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FBFE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD8E5EF)),
                ),
                child: Text(
                  _valueText(data['comments']),
                  style: const TextStyle(
                    color: Color(0xFF304555),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _sectionTitle(context, 'Request Information'),
              const SizedBox(height: 8),
              _KeyValueTable(
                rows: [
                  ('Destination', _valueText(request['destination'])),
                  ('Vehicle ID', _valueText(request['vehicle_id'])),
                  ('Vehicle Type', _valueText(request['vehicle_type'])),
                  ('Request Date', _valueText(request['request_date'])),
                  ('Status', _valueText(request['status'])),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _KeyValueTable extends StatelessWidget {
  const _KeyValueTable({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD8E5EF)),
      ),
      child: Column(
        children: List.generate(rows.length, (index) {
          final row = rows[index];
          final isLast = index == rows.length - 1;

          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: index.isEven ? Colors.white : const Color(0xFFF8FBFE),
              border:
                  isLast
                      ? null
                      : const Border(
                        bottom: BorderSide(color: Color(0xFFDDE8F1)),
                      ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    row.$1,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF4B5F6F),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    row.$2,
                    style: const TextStyle(
                      color: Color(0xFF1D2A34),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
