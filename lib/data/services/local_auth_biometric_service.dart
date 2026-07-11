import 'package:local_auth/local_auth.dart';

import '../../application/services/biometric_service.dart';

class LocalAuthBiometricService implements BiometricService {
  LocalAuthBiometricService({LocalAuthentication? localAuth})
    : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;

  @override
  Future<BiometricAvailability> checkAvailability() async {
    final supported = await _localAuth.isDeviceSupported();
    if (!supported) return BiometricAvailability.unavailable;
    final canCheck = await _localAuth.canCheckBiometrics;
    if (!canCheck) return BiometricAvailability.notEnrolled;
    return BiometricAvailability.available;
  }

  @override
  Future<bool> authenticate({required String reason}) async {
    return _localAuth.authenticate(
      localizedReason: reason,
      options: const AuthenticationOptions(
        biometricOnly: false,
        stickyAuth: true,
      ),
    );
  }
}
