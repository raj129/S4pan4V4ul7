/// Availability of biometric / device-credential unlock on this device.
enum BiometricAvailability {
  /// Hardware present and enrolled credentials available.
  available,

  /// Hardware present but no enrolled biometrics.
  notEnrolled,

  /// No biometric hardware or not supported on this platform.
  unavailable,
}

/// Abstracts platform biometric operations.
///
/// Security rule: biometric is a convenience unlock only.
/// It must never be the only path to unlock the vault.
abstract class BiometricService {
  /// Returns the availability status on the current device.
  Future<BiometricAvailability> checkAvailability();

  /// Prompts the user for biometric or device-credential authentication.
  /// Returns true if authenticated, false if cancelled or failed.
  Future<bool> authenticate({required String reason});
}
