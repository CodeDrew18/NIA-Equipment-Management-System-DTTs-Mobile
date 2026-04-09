import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:ems/models/api_config.dart';
import 'package:ems/screens/homepage_screen.dart';
import 'package:ems/services/fcm_service.dart';
import 'package:quickalert/quickalert.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginPageScreen extends StatefulWidget {
  const LoginPageScreen({super.key});

  @override
  State<LoginPageScreen> createState() => _LoginPageScreenState();
}

class _LoginPageScreenState extends State<LoginPageScreen> {
  final _formKey = GlobalKey<FormState>();
  final userIdController = TextEditingController();
  final passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isLoadingAlertVisible = false;

  @override
  void dispose() {
    userIdController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        const Text(
                          'EMS',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF0D4C73),
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Equipment Management System',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF24516B),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 28),
                        _buildInputField(
                          controller: userIdController,
                          label: 'UserId',
                          hintText: 'Enter your account userId',
                          icon: Icons.person_outline,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          validator: (value) {
                            final userId = value?.trim() ?? '';
                            if (userId.isEmpty) {
                              return 'UserId is required';
                            }
                            if (userId.length != 6) {
                              return 'UserId must be 6 digits';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        _buildInputField(
                          controller: passwordController,
                          label: 'Password',
                          hintText: 'Enter your password',
                          icon: Icons.lock_outline,
                          obscureText: true,
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Password is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              foregroundColor: Colors.white,
                              backgroundColor: const Color(0xFF0D4C73),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Login',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_isLoading)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.25),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Fetching data...',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
    });
    _showLoadingAlert('Validating account...');

    final url = ApiConfig.loginUri();
    final fcmToken = await FcmService.instance.getCurrentToken();

    final requestPayload = <String, dynamic>{
      'userId': userIdController.text,
      'password': passwordController.text,
      'device_name': 'flutter-mobile',
    };
    if (fcmToken.isNotEmpty) {
      requestPayload['fcm_token'] = fcmToken;
    }

    try {
      final response = await http.post(
        url,
        body: jsonEncode(requestPayload),
        headers: {'Content-Type': 'application/json'},
      );

      dynamic data;
      if (response.body.isNotEmpty) {
        data = jsonDecode(response.body);
      }

      if (!mounted) {
        return;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_logged_in', true);

        final authToken = _extractAuthToken(data);
        if (authToken.isNotEmpty) {
          await prefs.setString('auth_token', authToken);
        } else {
          await prefs.remove('auth_token');
        }

        final driverName = _extractDriverName(data);
        if (driverName.isNotEmpty) {
          await prefs.setString('driver_name', driverName);
        }

        await FcmService.instance.syncTokenWithBackend();

        if (!mounted) {
          return;
        }

        _hideLoadingAlert();

        await QuickAlert.show(
          context: context,
          type: QuickAlertType.success,
          title: 'Login Successful',
          text: 'Redirecting to homepage...',
          confirmBtnText: 'OK',
        );

        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!mounted) {
          return;
        }

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomepageScreen()),
        );
      } else {
        _hideLoadingAlert();

        final serverMessage =
            data is Map<String, dynamic>
                ? (data['message']?.toString() ?? 'Login failed.')
                : 'Login failed.';
        await QuickAlert.show(
          context: context,
          type: QuickAlertType.error,
          title: 'Login Failed',
          text: serverMessage,
          confirmBtnText: 'OK',
        );
      }
    } catch (e) {
      _hideLoadingAlert();

      if (!mounted) {
        return;
      }
      await QuickAlert.show(
        context: context,
        type: QuickAlertType.error,
        title: 'Network Error',
        text: 'Unable to connect to server. Please try again.',
        confirmBtnText: 'OK',
      );
    } finally {
      _hideLoadingAlert();
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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

  void _hideLoadingAlert() {
    if (!mounted || !_isLoadingAlertVisible) {
      return;
    }

    _isLoadingAlertVisible = false;
    try {
      Navigator.of(context, rootNavigator: true).pop();
    } catch (_) {
      // Ignore in case dialog is already dismissed.
    }
  }

  String _extractAuthToken(dynamic data) {
    if (data is! Map<String, dynamic>) {
      return '';
    }

    final directToken = data['token'] ?? data['access_token'];
    if (directToken is String && directToken.trim().isNotEmpty) {
      return directToken.trim();
    }

    final payload = data['data'];
    if (payload is Map<String, dynamic>) {
      final nestedToken = payload['token'] ?? payload['access_token'];
      if (nestedToken is String && nestedToken.trim().isNotEmpty) {
        return nestedToken.trim();
      }
    }

    return '';
  }

  String _extractDriverName(dynamic data) {
    if (data is! Map<String, dynamic>) {
      return '';
    }

    final user = data['user'];
    if (user is Map<String, dynamic>) {
      final name = user['name'];
      if (name is String && name.trim().isNotEmpty) {
        return name.trim();
      }
    }

    final payload = data['data'];
    if (payload is Map<String, dynamic>) {
      final nestedUser = payload['user'];
      if (nestedUser is Map<String, dynamic>) {
        final nestedName = nestedUser['name'];
        if (nestedName is String && nestedName.trim().isNotEmpty) {
          return nestedName.trim();
        }
      }

      final directName = payload['name'];
      if (directName is String && directName.trim().isNotEmpty) {
        return directName.trim();
      }
    }

    return '';
  }

  Widget _buildInputField({
    required String label,
    required String hintText,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    TextEditingController? controller,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      style: const TextStyle(
        color: Color(0xFF15314B),
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        hintStyle: const TextStyle(color: Color(0xFF8CA2B2)),
        filled: true,
        fillColor: const Color(0xFFF6FAFC),
        prefixIcon: Icon(icon, color: const Color(0xFF0D4C73)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD5E2EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD5E2EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF0D4C73), width: 1.4),
        ),
      ),
    );
  }
}
