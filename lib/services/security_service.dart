import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Quản lý khóa ứng dụng bằng sinh trắc học (Face ID, Touch ID, vân tay Android).
class SecurityService {
  static const String _prefBiometricLockKey = 'biometric_lock_enabled';
  final LocalAuthentication _localAuth = LocalAuthentication();

  Future<bool> isBiometricLockEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefBiometricLockKey) ?? false;
  }

  Future<void> setBiometricLockEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefBiometricLockKey, enabled);
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

