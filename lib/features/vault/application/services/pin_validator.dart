/// Pure-logic PIN validator. No platform dependencies.
///
/// Security rule: never log the PIN value passed to these methods.
class PinValidator {
  static const int requiredLength = 4;

  // PINs rejected for being trivially guessable.
  static const Set<String> _weakPins = {
    '0000',
    '1111',
    '2222',
    '3333',
    '4444',
    '5555',
    '6666',
    '7777',
    '8888',
    '9999',
    '1234',
    '4321',
    '0123',
    '3210',
    '1122',
    '1212',
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
