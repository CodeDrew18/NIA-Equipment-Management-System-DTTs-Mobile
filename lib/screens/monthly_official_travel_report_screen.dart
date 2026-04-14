import 'package:calendar_date_picker2/calendar_date_picker2.dart';
import 'package:flutter/material.dart';

class MonthlyOfficialTravelReportScreen extends StatefulWidget {
  const MonthlyOfficialTravelReportScreen({
    super.key,
    required this.tickets,
    required this.assignedDriver,
    this.embedded = false,
  });

  final List<Map<String, dynamic>> tickets;
  final String assignedDriver;
  final bool embedded;

  @override
  State<MonthlyOfficialTravelReportScreen> createState() =>
      _MonthlyOfficialTravelReportScreenState();
}

class _MonthlyOfficialTravelReportScreenState
    extends State<MonthlyOfficialTravelReportScreen> {
  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  late DateTime _selectedMonth;
  DateTime? _selectedCalendarDate;

  @override
  void initState() {
    super.initState();
    _selectedMonth = _initialMonthFromTickets() ?? DateTime.now();
    _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month);
    _selectedCalendarDate = null;
  }

  DateTime? _initialMonthFromTickets() {
    for (final ticket in widget.tickets) {
      final date = _ticketDate(ticket);
      if (date != null) {
        return date;
      }
    }
    return null;
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Select report month',
      initialDatePickerMode: DatePickerMode.year,
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _selectedMonth = DateTime(picked.year, picked.month);
      _selectedCalendarDate = null;
    });
  }

  void _showPrintHint() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Print is available in web. Mobile print integration can be added next.',
          ),
        ),
      );
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value;
    }

    if (value is int) {
      if (value > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      if (value > 1000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value * 1000);
      }
    }

    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return null;
      }

      final normalized =
          trimmed.contains('T') ? trimmed : trimmed.replaceFirst(' ', 'T');
      return DateTime.tryParse(normalized);
    }

    return null;
  }

  DateTime? _ticketDate(Map<String, dynamic> ticket) {
    final keys = [
      'departure_time',
      'arrival_time_office',
      'created_at',
      'updated_at',
    ];

    for (final key in keys) {
      final parsed = _parseDate(ticket[key]);
      if (parsed != null) {
        return parsed;
      }
    }

    return null;
  }

  bool _isSameMonth(DateTime date) {
    return date.year == _selectedMonth.year &&
        date.month == _selectedMonth.month;
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

  String? _firstNonEmptyText(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  num? _toNumber(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value;
    }

    return num.tryParse(value.toString().trim());
  }

  num? _firstNumber(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final parsed = _toNumber(source[key]);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  List<String> _splitPlateValues(dynamic rawValue) {
    final text = rawValue?.toString().trim() ?? '';
    if (text.isEmpty) {
      return const [];
    }

    final parts =
        text
            .split(RegExp(r'[,;/|\n]+'))
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty)
            .toList();

    if (parts.isEmpty) {
      return [text];
    }

    return parts;
  }

  String _normalizePlate(String value) {
    return value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  List<String> _plateCandidatesFromTicket(Map<String, dynamic> ticket) {
    final requestFormData = _asStringMap(ticket['request_form_data']);

    final sources = [
      requestFormData['vehicle_plate_no'],
      requestFormData['vehicle_plate'],
      requestFormData['plate_no'],
      ticket['vehicle_plate_no'],
      ticket['vehicle_plate'],
      ticket['plate_no'],
      requestFormData['vehicle_id'],
      ticket['vehicle_id'],
    ];

    final candidates = <String>[];
    for (final source in sources) {
      candidates.addAll(_splitPlateValues(source));
    }
    return candidates;
  }

  String? _primaryVehiclePlate(List<Map<String, dynamic>> tickets) {
    final counts = <String, int>{};
    final displayByNormalized = <String, String>{};

    for (final ticket in tickets) {
      for (final candidate in _plateCandidatesFromTicket(ticket)) {
        final normalized = _normalizePlate(candidate);
        if (normalized.isEmpty) {
          continue;
        }
        counts[normalized] = (counts[normalized] ?? 0) + 1;
        displayByNormalized.putIfAbsent(normalized, () => candidate);
      }
    }

    if (counts.isEmpty) {
      return null;
    }

    final sortedEntries =
        counts.entries.toList()..sort((a, b) {
          final countCompare = b.value.compareTo(a.value);
          if (countCompare != 0) {
            return countCompare;
          }
          return a.key.compareTo(b.key);
        });

    final selectedNormalized = sortedEntries.first.key;
    return displayByNormalized[selectedNormalized];
  }

  bool _ticketMatchesPlate(
    Map<String, dynamic> ticket,
    String normalizedPlate,
  ) {
    if (normalizedPlate.isEmpty) {
      return true;
    }

    for (final candidate in _plateCandidatesFromTicket(ticket)) {
      if (_normalizePlate(candidate) == normalizedPlate) {
        return true;
      }
    }

    return false;
  }

  String _formatMonth(DateTime month) {
    return '${_monthNames[month.month - 1]} ${month.year}';
  }

  String _formatNumber(num? value, {int fractionDigits = 1}) {
    if (value == null) {
      return '—';
    }
    return value.toStringAsFixed(fractionDigits);
  }

  String _dayLabel(DateTime date) {
    return date.day.toString().padLeft(2, '0');
  }

  int _daysInSelectedMonth() {
    return DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day;
  }

  List<Map<String, dynamic>> _ticketsForSelectedMonth() {
    return widget.tickets.where((ticket) {
      final date = _ticketDate(ticket);
      return date != null && _isSameMonth(date);
    }).toList();
  }

  String _normalizeReportText(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty || text == '—') {
      return '';
    }
    return text;
  }

  String _mergeReportText(Set<String> values) {
    if (values.isEmpty) {
      return '—';
    }
    return values.join(', ');
  }

  List<_ReportRow> _buildRows(List<Map<String, dynamic>> filteredTickets) {
    final groupedByDay = <int, _ReportDayAggregate>{};

    for (final ticket in filteredTickets) {
      final date = _ticketDate(ticket);
      if (date == null) {
        continue;
      }

      final requestFormData = _asStringMap(ticket['request_form_data']);

      final aggregate = groupedByDay.putIfAbsent(
        date.day,
        () => _ReportDayAggregate(),
      );

      aggregate.add(
        distance: _firstNumber(ticket, ['distance_travelled']),
        diesel: _firstNumber(ticket, ['diesel_liters', 'diesel', 'fuel_used']),
        gasoline: _firstNumber(ticket, ['gasoline_liters', 'gasoline']),
        engineOil: _firstNumber(ticket, ['engine_oil_liters']),
        gearOil: _firstNumber(ticket, ['gear_oil_liters']),
        fuelBalanceBefore: _firstNumber(ticket, [
          'fuel_balance_before',
          'bf',
          'brake_fluid_liters',
          'brake_fluid',
        ]),
        grease: _firstNumber(ticket, ['grease_kgs']),
        purchasedIssued: _normalizeReportText(
          _firstNonEmptyText([
            ticket['purchased_issued'],
            requestFormData['purchased_issued'],
            requestFormData['status'],
          ]),
        ),
        passenger: _normalizeReportText(
          _firstNonEmptyText([
            requestFormData['passenger'],
            requestFormData['requestor_name'],
          ]),
        ),
        destination: _normalizeReportText(
          _firstNonEmptyText([
            requestFormData['destination'],
            requestFormData['destination_place'],
          ]),
        ),
      );
    }

    final rows = <_ReportRow>[];
    final daysInMonth = _daysInSelectedMonth();

    for (var day = 1; day <= daysInMonth; day++) {
      final dayDate = DateTime(_selectedMonth.year, _selectedMonth.month, day);
      final aggregate = groupedByDay[day];

      if (aggregate == null) {
        rows.add(
          _ReportRow(
            date: dayDate,
            distance: null,
            diesel: null,
            gasoline: null,
            engineOil: null,
            gearOil: null,
            fuelBalanceBefore: null,
            grease: null,
            purchasedIssued: '—',
            passenger: '—',
            destination: '—',
          ),
        );
        continue;
      }

      rows.add(
        _ReportRow(
          date: dayDate,
          distance: aggregate.distance,
          diesel: aggregate.diesel,
          gasoline: aggregate.gasoline,
          engineOil: aggregate.engineOil,
          gearOil: aggregate.gearOil,
          fuelBalanceBefore: aggregate.fuelBalanceBefore,
          grease: aggregate.grease,
          purchasedIssued: _mergeReportText(aggregate.purchasedIssuedValues),
          passenger: _mergeReportText(aggregate.passengerValues),
          destination: _mergeReportText(aggregate.destinationValues),
        ),
      );
    }

    return rows;
  }

  num _sumBy(List<_ReportRow> rows, num? Function(_ReportRow row) selector) {
    return rows.fold<num>(0, (sum, row) => sum + (selector(row) ?? 0));
  }

  Widget _metaCard({
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCE4ED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF737781),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF191C1E),
                  ),
                ),
              ),
              if (onTap != null)
                const Icon(Icons.calendar_month, color: Color(0xFF003466)),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) {
      return card;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: card,
    );
  }

  bool _hasTripData(_ReportRow row) {
    return row.distance != null ||
        row.diesel != null ||
        row.gasoline != null ||
        row.engineOil != null ||
        row.gearOil != null ||
        row.fuelBalanceBefore != null ||
        row.grease != null ||
        row.purchasedIssued != '—' ||
        row.passenger != '—' ||
        row.destination != '—';
  }

  bool _dayHasData(DateTime date, Map<int, _ReportRow> dataByDay) {
    return date.year == _selectedMonth.year &&
        date.month == _selectedMonth.month &&
        dataByDay.containsKey(date.day);
  }

  String _fullDateText(DateTime date) {
    return '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';
  }

  Widget _summaryMetricTile({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return SizedBox(
      width: 158,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F8FC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFD8E5EF)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: const Color(0xFF0D4C73)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF5B6C7A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0D4C73),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dailyMetricChip({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8E5EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF5B6C7A),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0D4C73),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailLine({required String label, required String value}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 118,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF5B6C7A),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1D2A34),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dayRecordCard(_ReportRow row) {
    final hasTrip = _hasTripData(row);
    final destinationText =
        row.destination == '—' ? 'No destination recorded' : row.destination;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasTrip ? Colors.white : const Color(0xFFFAFCFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasTrip ? const Color(0xFFD6E4EF) : const Color(0xFFE0E9F1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      hasTrip
                          ? const Color(0xFFE8F2F9)
                          : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _dayLabel(row.date),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0D4C73),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Day ${_dayLabel(row.date)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0D4C73),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      destinationText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF4A5E6E),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color:
                      hasTrip
                          ? const Color(0xFFEAF7EF)
                          : const Color(0xFFF2F4F7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  hasTrip ? 'Recorded' : 'No Trip',
                  style: TextStyle(
                    color:
                        hasTrip
                            ? const Color(0xFF257041)
                            : const Color(0xFF687987),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _dailyMetricChip(
                label: 'Distance',
                value: _formatNumber(row.distance),
              ),
              _dailyMetricChip(
                label: 'Diesel',
                value: _formatNumber(row.diesel),
              ),
              _dailyMetricChip(
                label: 'Gasoline',
                value: _formatNumber(row.gasoline),
              ),
              _dailyMetricChip(
                label: 'Engine Oil',
                value: _formatNumber(row.engineOil),
              ),
              _dailyMetricChip(
                label: 'Gear Oil',
                value: _formatNumber(row.gearOil),
              ),
              _dailyMetricChip(
                label: 'Fuel Balance Before',
                value: _formatNumber(row.fuelBalanceBefore),
              ),
              _dailyMetricChip(
                label: 'Grease',
                value: _formatNumber(row.grease),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _detailLine(label: 'Passenger', value: row.passenger),
          const SizedBox(height: 6),
          _detailLine(label: 'Purchased / Issued', value: row.purchasedIssued),
        ],
      ),
    );
  }

  Widget _buildCalendarBreakdownSection({
    required List<_ReportRow> rows,
    required num totalDistance,
    required num totalDiesel,
    required num totalGasoline,
    required num totalEngineOil,
    required num totalGearOil,
    required num totalFuelBalanceBefore,
    required num totalGrease,
  }) {
    final rowsWithData = rows.where(_hasTripData).toList();
    final dataByDay = {for (final row in rowsWithData) row.date.day: row};

    final selectedDate = _selectedCalendarDate;
    final selectedDayRow =
        selectedDate != null &&
                selectedDate.year == _selectedMonth.year &&
                selectedDate.month == _selectedMonth.month
            ? dataByDay[selectedDate.day]
            : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCE4ED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Trip Calendar',
            style: TextStyle(
              color: Color(0xFF0D4C73),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${rowsWithData.length} of ${rows.length} day(s) have trip records.',
            style: const TextStyle(
              color: Color(0xFF5A6B79),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          CalendarDatePicker2(
            config: CalendarDatePicker2Config(
              calendarType: CalendarDatePicker2Type.single,
              firstDate: DateTime(2000, 1, 1),
              lastDate: DateTime(2100, 12, 31),
              currentDate: DateTime.now(),
              firstDayOfWeek: 1,
              selectedDayHighlightColor: const Color(0xFF0D4C73),
              selectedDayTextStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
              controlsTextStyle: const TextStyle(
                color: Color(0xFF0D4C73),
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
              weekdayLabelTextStyle: const TextStyle(
                color: Color(0xFF5B6C7A),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
              dayTextStyle: const TextStyle(
                color: Color(0xFF1D2A34),
                fontWeight: FontWeight.w600,
              ),
              dayBuilder: ({
                required date,
                textStyle,
                decoration,
                isSelected,
                isDisabled,
                isToday,
              }) {
                final hasData = _dayHasData(date, dataByDay);
                if (!hasData) {
                  return null;
                }

                final dayText = MaterialLocalizations.of(
                  context,
                ).formatDecimal(date.day);
                final isSelectedDay = isSelected == true;

                return Container(
                  decoration:
                      isSelectedDay
                          ? decoration
                          : BoxDecoration(
                            color: const Color(0xFFEAF7EF),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xFFCAE9D5)),
                          ),
                  child: Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          dayText,
                          style: textStyle?.copyWith(
                            color:
                                isSelectedDay
                                    ? Colors.white
                                    : const Color(0xFF257041),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        // Positioned(
                        //   bottom: 5,
                        //   child: Container(
                        //     width: 6,
                        //     height: 6,
                        //     decoration: BoxDecoration(
                        //       shape: BoxShape.circle,
                        //       color:
                        //           isSelectedDay
                        //               ? Colors.white
                        //               : const Color(0xFF2A8248),
                        //     ),
                        //   ),
                        // ),
                      ],
                    ),
                  ),
                );
              },
            ),
            displayedMonthDate: _selectedMonth,
            value:
                _selectedCalendarDate == null
                    ? []
                    : [DateUtils.dateOnly(_selectedCalendarDate!)],
            onDisplayedMonthChanged: (monthDate) {
              setState(() {
                _selectedMonth = DateTime(monthDate.year, monthDate.month);
                if (_selectedCalendarDate != null &&
                    (_selectedCalendarDate!.year != _selectedMonth.year ||
                        _selectedCalendarDate!.month != _selectedMonth.month)) {
                  _selectedCalendarDate = null;
                }
              });
            },
            onValueChanged: (selectedDates) {
              setState(() {
                _selectedCalendarDate =
                    selectedDates.isEmpty
                        ? null
                        : DateUtils.dateOnly(selectedDates.first);
              });
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _summaryMetricTile(
                label: 'Distance',
                value: _formatNumber(totalDistance),
                icon: Icons.route_outlined,
              ),
              _summaryMetricTile(
                label: 'Diesel',
                value: _formatNumber(totalDiesel),
                icon: Icons.local_gas_station_outlined,
              ),
              _summaryMetricTile(
                label: 'Gasoline',
                value: _formatNumber(totalGasoline),
                icon: Icons.opacity_outlined,
              ),
              _summaryMetricTile(
                label: 'Engine Oil',
                value: _formatNumber(totalEngineOil),
                icon: Icons.oil_barrel_outlined,
              ),
              _summaryMetricTile(
                label: 'Gear Oil',
                value: _formatNumber(totalGearOil),
                icon: Icons.build_circle_outlined,
              ),
              _summaryMetricTile(
                label: 'Fuel Balance Before',
                value: _formatNumber(totalFuelBalanceBefore),
                icon: Icons.settings_input_component_outlined,
              ),
              _summaryMetricTile(
                label: 'Grease',
                value: _formatNumber(totalGrease),
                icon: Icons.grain_outlined,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (selectedDate == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF7FAFD),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE0E9F1)),
              ),
              child: const Text(
                'Tap a date in the calendar to view the trip data.',
                style: TextStyle(
                  color: Color(0xFF5A6B79),
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else if (selectedDayRow == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF7FAFD),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE0E9F1)),
              ),
              child: Text(
                'No trip data for ${_fullDateText(selectedDate)}.',
                style: const TextStyle(
                  color: Color(0xFF5A6B79),
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else ...[
            Text(
              'Selected Day: ${_fullDateText(selectedDate)}',
              style: const TextStyle(
                color: Color(0xFF0D4C73),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            _dayRecordCard(selectedDayRow),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthTickets = _ticketsForSelectedMonth();
    final resolvedVehiclePlate = _primaryVehiclePlate(monthTickets);
    final normalizedResolvedPlate = _normalizePlate(resolvedVehiclePlate ?? '');
    final monthVehicleTickets =
        normalizedResolvedPlate.isEmpty
            ? monthTickets
            : monthTickets
                .where(
                  (ticket) =>
                      _ticketMatchesPlate(ticket, normalizedResolvedPlate),
                )
                .toList();
    final rows = _buildRows(monthVehicleTickets);

    final metadataTicket =
        monthVehicleTickets.isNotEmpty
            ? monthVehicleTickets.first
            : (monthTickets.isNotEmpty
                ? monthTickets.first
                : (widget.tickets.isNotEmpty
                    ? widget.tickets.first
                    : const <String, dynamic>{}));

    final requestData = _asStringMap(metadataTicket['request_form_data']);

    final fallbackVehiclePlate =
        _firstNonEmptyText([
          requestData['vehicle_plate_no'],
          requestData['vehicle_plate'],
          requestData['plate_no'],
          requestData['vehicle_id'],
          metadataTicket['vehicle_id'],
          metadataTicket['vehicle_plate_no'],
        ]) ??
        '—';

    final vehiclePlate = resolvedVehiclePlate ?? fallbackVehiclePlate;

    final assignedDriver =
        _firstNonEmptyText([
          widget.assignedDriver,
          requestData['driver_name'],
        ]) ??
        '—';

    final propertyNumber =
        _firstNonEmptyText([
          requestData['property_number'],
          requestData['property_no'],
        ]) ??
        '—';

    final totalDistance = _sumBy(rows, (row) => row.distance);
    final totalDiesel = _sumBy(rows, (row) => row.diesel);
    final totalGasoline = _sumBy(rows, (row) => row.gasoline);
    final totalEngineOil = _sumBy(rows, (row) => row.engineOil);
    final totalGearOil = _sumBy(rows, (row) => row.gearOil);
    final totalFuelBalanceBefore = _sumBy(rows, (row) => row.fuelBalanceBefore);
    final totalGrease = _sumBy(rows, (row) => row.grease);

    final content = SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;

                final titleSection = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'MONTHLY OFFICIAL TRAVEL REPORT',
                      style: TextStyle(
                        color: Color(0xFF003466),
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Official Institutional Form for Each Motor Vehicle',
                      style: TextStyle(
                        color: Color(0xFF3A6843),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                );

                final printButton = ElevatedButton.icon(
                  onPressed: _showPrintHint,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF003466),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Print Report'),
                );

                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      titleSection,
                      const SizedBox(height: 12),
                      printButton,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [Expanded(child: titleSection), printButton],
                );
              },
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth =
                    constraints.maxWidth < 920
                        ? (constraints.maxWidth - 12) / 2
                        : (constraints.maxWidth - 36) / 4;

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: cardWidth,
                      child: _metaCard(
                        label: 'MONTH OF REPORT',
                        value: _formatMonth(_selectedMonth),
                        onTap: _pickMonth,
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _metaCard(
                        label: 'VEHICLE PLATE NO.',
                        value: vehiclePlate,
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _metaCard(
                        label: 'ASSIGNED DRIVER',
                        value: assignedDriver,
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _metaCard(
                        label: 'PROPERTY NUMBER',
                        value: propertyNumber,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            _buildCalendarBreakdownSection(
              rows: rows,
              totalDistance: totalDistance,
              totalDiesel: totalDiesel,
              totalGasoline: totalGasoline,
              totalEngineOil: totalEngineOil,
              totalGearOil: totalGearOil,
              totalFuelBalanceBefore: totalFuelBalanceBefore,
              totalGrease: totalGrease,
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F4F7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDCE4ED)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        left: BorderSide(color: Color(0xFF003466), width: 3),
                      ),
                    ),
                    padding: const EdgeInsets.only(left: 10),
                    child: const Text(
                      '"I hereby certify to the correctness of the above statement and that motor vehicle was used strictly official business only."',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 860;
                      final entries = [
                        _signatureBlock(
                          title: 'Approved By (Division Manager, EOD)',
                          value: 'DIVISION MANAGER',
                        ),
                        _signatureBlock(
                          title: 'Name of the Driver',
                          value: assignedDriver,
                        ),
                        _signatureBlock(
                          title: 'Signature of the Driver',
                          value: '',
                        ),
                      ];

                      if (compact) {
                        return Column(
                          children: [
                            entries[0],
                            const SizedBox(height: 20),
                            entries[1],
                            const SizedBox(height: 20),
                            entries[2],
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: entries[0]),
                          const SizedBox(width: 18),
                          Expanded(child: entries[1]),
                          const SizedBox(width: 18),
                          Expanded(child: entries[2]),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECF5EE),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFC8DBCC)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NOTE & INSTRUCTIONS',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF3A6843),
                            letterSpacing: 0.7,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'This report should be accomplished in trip-ticket. The original copy, with supporting original driver records of travels, should be submitted through the Administrative Officer or equivalent to the concerned auditor.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF424750),
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Equipment Management Section, Urdaneta City, Pangasinan',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF003466),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B395D),
        foregroundColor: Colors.white,
        title: const Text('Monthly Official Travel Report'),
      ),
      body: content,
    );
  }

  Widget _signatureBlock({required String title, required String value}) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          height: 40,
          alignment: Alignment.bottomCenter,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF191C1E))),
          ),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0xFF737781),
          ),
        ),
      ],
    );
  }
}

class _ReportRow {
  _ReportRow({
    required this.date,
    required this.distance,
    required this.diesel,
    required this.gasoline,
    required this.engineOil,
    required this.gearOil,
    required this.fuelBalanceBefore,
    required this.grease,
    required this.purchasedIssued,
    required this.passenger,
    required this.destination,
  });

  final DateTime date;
  final num? distance;
  final num? diesel;
  final num? gasoline;
  final num? engineOil;
  final num? gearOil;
  final num? fuelBalanceBefore;
  final num? grease;
  final String purchasedIssued;
  final String passenger;
  final String destination;
}

class _ReportDayAggregate {
  num? distance;
  num? diesel;
  num? gasoline;
  num? engineOil;
  num? gearOil;
  num? fuelBalanceBefore;
  num? grease;

  final Set<String> purchasedIssuedValues = <String>{};
  final Set<String> passengerValues = <String>{};
  final Set<String> destinationValues = <String>{};

  void add({
    required num? distance,
    required num? diesel,
    required num? gasoline,
    required num? engineOil,
    required num? gearOil,
    required num? fuelBalanceBefore,
    required num? grease,
    required String purchasedIssued,
    required String passenger,
    required String destination,
  }) {
    this.distance = _sumNullable(this.distance, distance);
    this.diesel = _sumNullable(this.diesel, diesel);
    this.gasoline = _sumNullable(this.gasoline, gasoline);
    this.engineOil = _sumNullable(this.engineOil, engineOil);
    this.gearOil = _sumNullable(this.gearOil, gearOil);
    this.fuelBalanceBefore = _sumNullable(
      this.fuelBalanceBefore,
      fuelBalanceBefore,
    );
    this.grease = _sumNullable(this.grease, grease);

    if (purchasedIssued.isNotEmpty) {
      purchasedIssuedValues.add(purchasedIssued);
    }
    if (passenger.isNotEmpty) {
      passengerValues.add(passenger);
    }
    if (destination.isNotEmpty) {
      destinationValues.add(destination);
    }
  }

  num? _sumNullable(num? current, num? incoming) {
    if (incoming == null) {
      return current;
    }
    return (current ?? 0) + incoming;
  }
}
