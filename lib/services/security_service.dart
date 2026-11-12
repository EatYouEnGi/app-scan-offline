import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Quản lý khóa ứng dụng bằng sinh trắc học (Face ID, Touch ID, vân tay Android)
/// và cấu hình người dùng (ngôn ngữ VI/EN, trạng thái Onboarding).
class SecurityService {
  static const String _prefBiometricLockKey = 'biometric_lock_enabled';
  static const String _prefLanguageCodeKey = 'app_language_code';
  static const String _prefOnboardingSeenKey = 'app_onboarding_completed';
  final LocalAuthentication _localAuth = LocalAuthentication();

  Future<bool> isBiometricLockEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefBiometricLockKey) ?? false;
  }

  Future<void> setBiometricLockEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefBiometricLockKey, enabled);
  }

  Future<String> getLanguageCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefLanguageCodeKey) ?? 'vi';
  }

  Future<void> setLanguageCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefLanguageCodeKey, code);
  }

  Future<bool> hasCompletedOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefOnboardingSeenKey) ?? false;
  }

  Future<void> setCompletedOnboarding(bool completed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefOnboardingSeenKey, completed);
  }

  Future<bool> canCheckBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateUser({
    String reason = 'Xác thực sinh trắc học để mở kho tài liệu scan cá nhân',
  }) async {
    try {
      final supported = await canCheckBiometrics();
      if (!supported) return true;

      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
