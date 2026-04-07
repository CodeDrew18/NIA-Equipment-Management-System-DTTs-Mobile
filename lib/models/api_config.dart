class ApiConfig {
  ApiConfig._();

  static const String apiBaseUrl = 'http://192.168.1.41:8000/api';
  static const String _dailyTripTicketsPath = '/daily-trip-tickets';
  static const String _loginPath = '/login';

  static Uri loginUri() {
    return Uri.parse('$apiBaseUrl$_loginPath');
  }

  static Uri dailyTripTicketsUri() {
    return Uri.parse('$apiBaseUrl$_dailyTripTicketsPath');
  }

  static Uri dailyTripTicketByIdUri(int id) {
    return Uri.parse('$apiBaseUrl$_dailyTripTicketsPath/$id');
  }
}
