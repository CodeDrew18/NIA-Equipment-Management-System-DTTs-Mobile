import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:ems/models/api_config.dart';
import 'package:ems/models/sqflite_config.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:quickalert/quickalert.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DailyDriversTripTicketScreen extends StatefulWidget {
  const DailyDriversTripTicketScreen({super.key, required this.ticketData});

  final Map<String, dynamic> ticketData;

  @override
  State<DailyDriversTripTicketScreen> createState() =>
      _DailyDriversTripTicketScreenState();
}

class _DailyDriversTripTicketScreenState
    extends State<DailyDriversTripTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final Connectivity _connectivity = Connectivity();

  late Map<String, dynamic> _ticketData;

  late final TextEditingController _departureTimeController;
  late final TextEditingController _arrivalDestinationController;
  late final TextEditingController _departureDestinationController;
  late final TextEditingController _arrivalOfficeController;

  late final TextEditingController _odometerStartController;
  late final TextEditingController _odometerEndController;
  late final TextEditingController _distanceTravelledController;

  late final TextEditingController _fuelBalanceBeforeController;
  late final TextEditingController _fuelIssuedRegionalController;
  late final TextEditingController _fuelPurchasedTripController;
  late final TextEditingController _fuelIssuedNiaController;
  late final TextEditingController _fuelTotalController;
  late final TextEditingController _fuelUsedController;
  late final TextEditingController _fuelBalanceAfterController;

  late final TextEditingController _gearOilController;
  late final TextEditingController _engineOilController;
  late final TextEditingController _greaseController;
  late final TextEditingController _remarksController;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isOnline = true;
  bool _isSaving = false;
  bool _isFetchingDetails = false;
  bool _isLoadingAlertVisible = false;

  @override
  void initState() {
    super.initState();
    _ticketData = Map<String, dynamic>.from(widget.ticketData);
    _initializeControllers();
    _observeConnectivity();
    _checkCurrentConnectivity();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTicketDetails();
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();

    _departureTimeController.dispose();
    _arrivalDestinationController.dispose();
    _departureDestinationController.dispose();
    _arrivalOfficeController.dispose();
    _odometerStartController.dispose();
    _odometerEndController.dispose();
    _distanceTravelledController.dispose();
    _fuelBalanceBeforeController.dispose();
    _fuelIssuedRegionalController.dispose();
    _fuelPurchasedTripController.dispose();
    _fuelIssuedNiaController.dispose();
    _fuelTotalController.dispose();
    _fuelUsedController.dispose();
    _fuelBalanceAfterController.dispose();
    _gearOilController.dispose();
    _engineOilController.dispose();
    _greaseController.dispose();
    _remarksController.dispose();

    super.dispose();
  }

  void _initializeControllers() {
    _departureTimeController = TextEditingController(
      text: _valueAsString(_ticketData['departure_time']),
    );
    _arrivalDestinationController = TextEditingController(
      text: _valueAsString(_ticketData['arrival_time_destination']),
    );
    _departureDestinationController = TextEditingController(
      text: _valueAsString(_ticketData['departure_time_destination']),
    );
    _arrivalOfficeController = TextEditingController(
      text: _valueAsString(_ticketData['arrival_time_office']),
    );

    _odometerStartController = TextEditingController(
      text: _valueAsString(_ticketData['odometer_start']),
    );
    _odometerEndController = TextEditingController(
      text: _valueAsString(_ticketData['odometer_end']),
    );
    _distanceTravelledController = TextEditingController(
      text: _valueAsString(_ticketData['distance_travelled']),
    );

    _fuelBalanceBeforeController = TextEditingController(
      text: _valueAsString(_ticketData['fuel_balance_before']),
    );
    _fuelIssuedRegionalController = TextEditingController(
      text: _valueAsString(_ticketData['fuel_issued_regional']),
    );
    _fuelPurchasedTripController = TextEditingController(
      text: _valueAsString(_ticketData['fuel_purchased_trip']),
    );
    _fuelIssuedNiaController = TextEditingController(
      text: _valueAsString(_ticketData['fuel_issued_nia']),
    );
    _fuelTotalController = TextEditingController(
      text: _valueAsString(_ticketData['fuel_total']),
    );
    _fuelUsedController = TextEditingController(
      text: _valueAsString(_ticketData['fuel_used']),
    );
    _fuelBalanceAfterController = TextEditingController(
      text: _valueAsString(_ticketData['fuel_balance_after']),
    );

    _gearOilController = TextEditingController(
      text: _valueAsString(_ticketData['gear_oil_liters']),
    );
    _engineOilController = TextEditingController(
      text: _valueAsString(_ticketData['engine_oil_liters']),
    );
    _greaseController = TextEditingController(
      text: _valueAsString(_ticketData['grease_kgs']),
    );
    _remarksController = TextEditingController(
      text: _valueAsString(_ticketData['remarks']),
    );
  }

  void _observeConnectivity() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      result,
    ) {
      final online = _hasConnection(result);
      if (!mounted) {
        return;
      }
      setState(() {
        _isOnline = online;
      });
    });
  }

  Future<void> _checkCurrentConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    if (!mounted) {
      return;
    }
    setState(() {
      _isOnline = _hasConnection(result);
    });
  }

  bool _hasConnection(List<ConnectivityResult> result) {
    return result.any((status) => status != ConnectivityResult.none);
  }

  Future<void> _loadTicketDetails() async {
    if (_isFetchingDetails) {
      return;
    }

    final ticketId = int.tryParse(_ticketData['id']?.toString() ?? '');
    if (ticketId == null) {
      return;
    }

    final result = await _connectivity.checkConnectivity();
    if (!_hasConnection(result)) {
      if (mounted) {
        setState(() {
          _isOnline = false;
        });
      }
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isFetchingDetails = true;
      _isOnline = true;
    });

    try {
      final response = await http.get(
        ApiConfig.dailyTripTicketByIdUri(ticketId),
        headers: await _buildHeaders(),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return;
      }

      if (response.body.trim().isEmpty) {
        return;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final data = decoded['data'];
      if (data is! Map) {
        return;
      }

      final fetched = data.map((key, value) => MapEntry(key.toString(), value));
      final merged = <String, dynamic>{..._ticketData, ...fetched};
      merged['request_form_data'] = _asStringDynamicMap(
        merged['request_form_data'],
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _ticketData = merged;
        _departureTimeController.text = _valueAsString(
          _ticketData['departure_time'],
        );
        _arrivalDestinationController.text = _valueAsString(
          _ticketData['arrival_time_destination'],
        );
        _departureDestinationController.text = _valueAsString(
          _ticketData['departure_time_destination'],
        );
        _arrivalOfficeController.text = _valueAsString(
          _ticketData['arrival_time_office'],
        );
        _odometerStartController.text = _valueAsString(
          _ticketData['odometer_start'],
        );
        _odometerEndController.text = _valueAsString(
          _ticketData['odometer_end'],
        );
        _distanceTravelledController.text = _valueAsString(
          _ticketData['distance_travelled'],
        );
        _fuelBalanceBeforeController.text = _valueAsString(
          _ticketData['fuel_balance_before'],
        );
        _fuelIssuedRegionalController.text = _valueAsString(
          _ticketData['fuel_issued_regional'],
        );
        _fuelPurchasedTripController.text = _valueAsString(
          _ticketData['fuel_purchased_trip'],
        );
        _fuelIssuedNiaController.text = _valueAsString(
          _ticketData['fuel_issued_nia'],
        );
        _fuelTotalController.text = _valueAsString(_ticketData['fuel_total']);
        _fuelUsedController.text = _valueAsString(_ticketData['fuel_used']);
        _fuelBalanceAfterController.text = _valueAsString(
          _ticketData['fuel_balance_after'],
        );
        _gearOilController.text = _valueAsString(
          _ticketData['gear_oil_liters'],
        );
        _engineOilController.text = _valueAsString(
          _ticketData['engine_oil_liters'],
        );
        _greaseController.text = _valueAsString(_ticketData['grease_kgs']);
        _remarksController.text = _valueAsString(_ticketData['remarks']);
      });
    } catch (_) {
      // Keep existing values when show endpoint fails.
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingDetails = false;
        });
      }
    }
  }

  String _valueAsString(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString();
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

  String _emptyToNull(String value) {
    return value.trim();
  }

  String _twoDigits(int value) {
    return value.toString().padLeft(2, '0');
  }

  DateTime _parseDateTimeOrNow(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return DateTime.now();
    }

    final normalized =
        trimmed.contains('T') ? trimmed : trimmed.replaceFirst(' ', 'T');
    return DateTime.tryParse(normalized) ?? DateTime.now();
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${_twoDigits(dateTime.month)}-${_twoDigits(dateTime.day)} ${_twoDigits(dateTime.hour)}:${_twoDigits(dateTime.minute)}:00';
  }

  Future<void> _pickDateTime(TextEditingController controller) async {
    final initialDateTime = _parseDateTimeOrNow(controller.text);
    final date = await showDatePicker(
      context: context,
      initialDate: initialDateTime,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (date == null || !mounted) {
      return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDateTime),
    );

    if (time == null || !mounted) {
      return;
    }

    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    setState(() {
      controller.text = _formatDateTime(selected);
    });
  }

  num? _parseNumber(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return num.tryParse(trimmed);
  }

  String? _validateNumber(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    if (num.tryParse(raw) == null) {
      return 'Enter a valid number.';
    }
    return null;
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
      // Ignore in case the loading dialog was already dismissed.
    }
  }

  Future<Map<String, String>> _buildHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? '';

    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };

    if (token.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${token.trim()}';
    }

    return headers;
  }

  Future<void> _saveTicket() async {
    if (_isSaving) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      await QuickAlert.show(
        context: context,
        type: QuickAlertType.warning,
        title: 'Invalid Form',
        text: 'Please fix the invalid numeric fields before submitting.',
        confirmBtnText: 'OK',
      );
      return;
    }

    final tripRequestId = int.tryParse(
      _ticketData['transportation_request_form_id']?.toString() ?? '',
    );

    if (tripRequestId == null) {
      await QuickAlert.show(
        context: context,
        type: QuickAlertType.error,
        title: 'Missing ID',
        text:
            'Transportation Request Form ID is missing for this DTT. Please refresh and try again.',
        confirmBtnText: 'OK',
      );
      return;
    }

    final payload = <String, dynamic>{
      'transportation_request_form_id': tripRequestId,
      'request_form_data': _asStringDynamicMap(
        _ticketData['request_form_data'],
      ),
    };

    void putDateField(String key, TextEditingController controller) {
      final value = _emptyToNull(controller.text);
      if (value.isNotEmpty) {
        payload[key] = value;
      }
    }

    void putNumberField(String key, TextEditingController controller) {
      final parsed = _parseNumber(controller.text);
      if (parsed != null) {
        payload[key] = parsed;
      }
    }

    putDateField('departure_time', _departureTimeController);
    putDateField('arrival_time_destination', _arrivalDestinationController);
    putDateField('departure_time_destination', _departureDestinationController);
    putDateField('arrival_time_office', _arrivalOfficeController);

    putNumberField('odometer_start', _odometerStartController);
    putNumberField('odometer_end', _odometerEndController);
    putNumberField('distance_travelled', _distanceTravelledController);
    putNumberField('fuel_balance_before', _fuelBalanceBeforeController);
    putNumberField('fuel_issued_regional', _fuelIssuedRegionalController);
    putNumberField('fuel_purchased_trip', _fuelPurchasedTripController);
    putNumberField('fuel_issued_nia', _fuelIssuedNiaController);
    putNumberField('fuel_total', _fuelTotalController);
    putNumberField('fuel_used', _fuelUsedController);
    putNumberField('fuel_balance_after', _fuelBalanceAfterController);
    putNumberField('gear_oil_liters', _gearOilController);
    putNumberField('engine_oil_liters', _engineOilController);
    putNumberField('grease_kgs', _greaseController);

    final remarks = _emptyToNull(_remarksController.text);
    if (remarks.isNotEmpty) {
      payload['remarks'] = remarks;
    }

    final connectivity = await _connectivity.checkConnectivity();
    if (!_hasConnection(connectivity)) {
      if (mounted) {
        setState(() {
          _isOnline = false;
        });
      }

      await SqfliteConfig.instance.queuePendingTripTicket(
        transportationRequestFormId: tripRequestId,
        payload: payload,
      );

      if (!mounted) {
        return;
      }

      await QuickAlert.show(
        context: context,
        type: QuickAlertType.success,
        title: 'Saved Offline',
        text:
            'No internet connection. This ticket is temporarily saved and will sync automatically when online.',
        confirmBtnText: 'OK',
      );

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
      return;
    }

    if (!mounted) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSaving = true;
      _isOnline = true;
    });
    _showLoadingAlert('Saving trip ticket...');

    try {
      final response = await http.post(
        ApiConfig.dailyTripTicketsUri(),
        headers: await _buildHeaders(),
        body: jsonEncode(payload),
      );

      dynamic data;
      if (response.body.isNotEmpty) {
        data = jsonDecode(response.body);
      }

      _closeLoadingAlert();

      if (!mounted) {
        return;
      }

      final message =
          data is Map<String, dynamic> && data['message'] is String
              ? (data['message'] as String)
              : 'Trip ticket saved successfully.';

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await QuickAlert.show(
          context: context,
          type: QuickAlertType.success,
          title: 'Saved',
          text: message,
          confirmBtnText: 'OK',
        );

        if (!mounted) {
          return;
        }
        Navigator.of(context).pop(true);
      } else {
        await QuickAlert.show(
          context: context,
          type: QuickAlertType.error,
          title: 'Save Failed',
          text: message,
          confirmBtnText: 'OK',
        );
      }
    } catch (_) {
      _closeLoadingAlert();
      if (!mounted) {
        return;
      }

      await SqfliteConfig.instance.queuePendingTripTicket(
        transportationRequestFormId: tripRequestId,
        payload: payload,
      );

      if (!mounted) {
        return;
      }

      await QuickAlert.show(
        context: context,
        type: QuickAlertType.success,
        title: 'Saved Offline',
        text:
            'Network issue detected. This ticket was stored locally and will sync automatically when online.',
        confirmBtnText: 'OK',
      );

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final requestFormData = _asStringDynamicMap(
      _ticketData['request_form_data'],
    );
    final trfId =
        _ticketData['transportation_request_form_id']?.toString() ?? '-';
    final destination =
        requestFormData['destination']?.toString() ??
        'No destination available';
    final requestor =
        requestFormData['requestor_name']?.toString() ?? 'Unknown';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D4C73),
        foregroundColor: Colors.white,
        title: const Text('Daily Drivers Trip Ticket'),
      ),
      body: Column(
        children: [
          if (!_isOnline)
            Container(
              width: double.infinity,
              color: const Color(0xFFFCE8D3),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: const Text(
                'Offline mode: save will be queued locally and synced automatically when online.',
                style: TextStyle(
                  color: Color(0xFF8A5B00),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 120),
                children: [
                  Card(
                    elevation: 1.2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TRF ID: $trfId',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text('Destination: $destination'),
                          const SizedBox(height: 4),
                          Text('Requestor: $requestor'),
                          if (_isFetchingDetails)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text('Refreshing ticket details...'),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Time Details',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  _buildDateTimeField(
                    controller: _departureTimeController,
                    label: 'Departure Time',
                    hint: 'YYYY-MM-DD HH:MM:SS',
                    icon: Icons.schedule,
                  ),
                  _buildDateTimeField(
                    controller: _arrivalDestinationController,
                    label: 'Arrival Time (Destination)',
                    hint: 'YYYY-MM-DD HH:MM:SS',
                    icon: Icons.schedule,
                  ),
                  _buildDateTimeField(
                    controller: _departureDestinationController,
                    label: 'Departure Time (Destination)',
                    hint: 'YYYY-MM-DD HH:MM:SS',
                    icon: Icons.schedule,
                  ),
                  _buildDateTimeField(
                    controller: _arrivalOfficeController,
                    label: 'Arrival Time (Office)',
                    hint: 'YYYY-MM-DD HH:MM:SS',
                    icon: Icons.schedule,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Trip & Fuel Details',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  _buildNumberField(
                    controller: _odometerStartController,
                    label: 'Odometer Start',
                    icon: Icons.speed,
                  ),
                  _buildNumberField(
                    controller: _odometerEndController,
                    label: 'Odometer End',
                    icon: Icons.speed,
                  ),
                  _buildNumberField(
                    controller: _distanceTravelledController,
                    label: 'Distance Travelled',
                    icon: Icons.route,
                  ),
                  _buildNumberField(
                    controller: _fuelBalanceBeforeController,
                    label: 'Fuel Balance Before',
                    icon: Icons.local_gas_station,
                  ),
                  _buildNumberField(
                    controller: _fuelIssuedRegionalController,
                    label: 'Fuel Issued Regional',
                    icon: Icons.local_gas_station,
                  ),
                  _buildNumberField(
                    controller: _fuelPurchasedTripController,
                    label: 'Fuel Purchased During Trip',
                    icon: Icons.local_gas_station,
                  ),
                  _buildNumberField(
                    controller: _fuelIssuedNiaController,
                    label: 'Fuel Issued NIA',
                    icon: Icons.local_gas_station,
                  ),
                  _buildNumberField(
                    controller: _fuelTotalController,
                    label: 'Fuel Total',
                    icon: Icons.local_gas_station,
                  ),
                  _buildNumberField(
                    controller: _fuelUsedController,
                    label: 'Fuel Used',
                    icon: Icons.local_gas_station,
                  ),
                  _buildNumberField(
                    controller: _fuelBalanceAfterController,
                    label: 'Fuel Balance After',
                    icon: Icons.local_gas_station,
                  ),
                  _buildNumberField(
                    controller: _gearOilController,
                    label: 'Gear Oil (Liters)',
                    icon: Icons.oil_barrel_outlined,
                  ),
                  _buildNumberField(
                    controller: _engineOilController,
                    label: 'Engine Oil (Liters)',
                    icon: Icons.oil_barrel,
                  ),
                  _buildNumberField(
                    controller: _greaseController,
                    label: 'Grease (Kgs)',
                    icon: Icons.scale_outlined,
                  ),
                  _buildTextField(
                    controller: _remarksController,
                    label: 'Remarks',
                    hint: 'Add remarks here...',
                    icon: Icons.notes,
                    maxLines: 4,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSaving ? null : _saveTicket,
        backgroundColor: const Color(0xFF0D4C73),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.save),
        label: const Text('Save DTT'),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildDateTimeField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        readOnly: true,
        onTap: _isSaving ? null : () => _pickDateTime(controller),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon),
          suffixIcon: IconButton(
            onPressed: _isSaving ? null : () => _pickDateTime(controller),
            icon: const Icon(Icons.calendar_today_outlined),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildNumberField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: _validateNumber,
        decoration: InputDecoration(
          labelText: label,
          hintText: 'Enter numeric value',
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
