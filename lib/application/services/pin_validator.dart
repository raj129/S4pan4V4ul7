/// Pure-logic PIN validator. No platform dependencies.
///
/// Security rule: never log the PIN value passed to these methods.
class PinValidator {
  static const int requiredLength = 6;

  // PINs rejected for being trivially guessable.
  static const Set<String> _weakPins = {
    '000000',
    '111111',
    '222222',
    '333333',
    '444444',
    '555555',
    '666666',
    '777777',
    '888888',
    '999999',
    '123456',
    '654321',
    '012345',
    '543210',
    '111222',
    '112233',
  };

  /// Returns null when the PIN is acceptable, or an error message otherwise.
  String? validate(String pin) {
    if (pin.length != requiredLength) {
      return 'PIN must be exactly $requiredLength digits.';
    }
    if (!RegExp(r'^\d+$').hasMatch(pin)) {
      return 'PIN must contain digits only.';
    }
    if (_weakPins.contains(pin)) {
      return 'PIN is too easy to guess. Choose a different PIN.';
    }
    return null;
  }

  /// Returns true when [pin] and [confirmPin] are identical.
  bool matches(String pin, String confirmPin) => pin == confirmPin;
}
