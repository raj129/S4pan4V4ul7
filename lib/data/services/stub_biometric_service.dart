import '../../application/services/biometric_service.dart';

/// Stub biometric service used on platforms without biometric hardware,
/// or during development/testing without a physical device.
///
/// Always reports [BiometricAvailability.unavailable] so the biometric
/// setup screen is gracefully skipped during desktop testing.
class StubBiometricService implements BiometricService {
  const StubBiometricService();

  @override
  Future<BiometricAvailability> checkAvailability() async =>
      BiometricAvailability.unavailable;

  @override
  Future<bool> authenticate({required String reason}) async => false;
}
