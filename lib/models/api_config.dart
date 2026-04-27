class ApiConfig {
  ApiConfig._();

  static const String apiBaseUrl = 'http://192.168.1.210:8000/api';
  static const String _dailyTripTicketsPath = '/daily-trip-tickets';
  static const String _driverPerformanceEvaluationsPath =
      '/driver-performance-evaluations';
  static const String _monthlyOfficialTravelReportDownloadPath =
      '/monthly-official-travel-report/download';
  static const String _loginPath = '/login';
  static const String _fcmTokenPath = '/fcm-token';
  static const String _logoutPath = '/logout';

  static Uri loginUri() {
    return Uri.parse('$apiBaseUrl$_loginPath');
  }

  static Uri dailyTripTicketsUri() {
    return Uri.parse('$apiBaseUrl$_dailyTripTicketsPath');
  }

  static Uri dailyTripTicketByIdUri(int id) {
    return Uri.parse('$apiBaseUrl$_dailyTripTicketsPath/$id');
  }

  static Uri driverPerformanceEvaluationsUri() {
    return Uri.parse('$apiBaseUrl$_driverPerformanceEvaluationsPath');
  }

  static Uri driverPerformanceEvaluationByIdUri(int id) {
    return Uri.parse('$apiBaseUrl$_driverPerformanceEvaluationsPath/$id');
  }

  static Uri monthlyOfficialTravelReportDownloadUri({
    required String month,
    String format = 'xlsx',
    String? copy,
  }) {
    final queryParameters = <String, String>{'month': month, 'format': format};

    final normalizedCopy = copy?.trim() ?? '';
    if (normalizedCopy.isNotEmpty) {
      queryParameters['copy'] = normalizedCopy;
    }

    return Uri.parse(
      '$apiBaseUrl$_monthlyOfficialTravelReportDownloadPath',
    ).replace(queryParameters: queryParameters);
  }

  static Uri fcmTokenUri() {
    return Uri.parse('$apiBaseUrl$_fcmTokenPath');
  }

  static Uri logoutUri() {
    return Uri.parse('$apiBaseUrl$_logoutPath');
  }
}
