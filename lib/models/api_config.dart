class ApiConfig {
  ApiConfig._();

  static const String apiBaseUrl = 'http://192.168.1.210:8000/api';
  static const String _dailyTripTicketsPath = '/daily-trip-tickets';
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

  static Uri fcmTokenUri() {
    return Uri.parse('$apiBaseUrl$_fcmTokenPath');
  }

  static Uri logoutUri() {
    return Uri.parse('$apiBaseUrl$_logoutPath');
  }
}
