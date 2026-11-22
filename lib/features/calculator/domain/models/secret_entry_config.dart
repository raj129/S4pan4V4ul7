import 'package:flutter/foundation.dart';

import '../../presentation/widgets/keypad_layouts.dart';

/// Available calculator secret-entry gestures for opening the vault.
enum SecretEntryMethod {
  /// Default two-key simultaneous hold (`7` + `=` by default).
  simultaneousHold,

  /// Hold a trigger key, type the PIN, and press a confirm key (e.g. `MR`)
  /// to jump straight to chat without showing the lock screen.
  holdPinConfirm,

  /// Hold Key A (~800ms), release, then tap Key B within 1.5s.
  sequentialHold,

  /// Enter a secret number/expression and long-press a trigger key.
  secretExpressionHold,

  /// Rapidly tap one key N times, then hold on the (N+1)th press.
  multiTapHold,

  /// Type `<PIN>` (or `<expr><PIN>`) and long-press a trigger key to unlock
  /// directly to chat, or evaluate normally if invalid.
  secretMathEquation,
}

extension SecretEntryMethodX on SecretEntryMethod {
  String get id => name;

  String get title => switch (this) {
    SecretEntryMethod.simultaneousHold => 'Simultaneous Two-Key Hold (Default)',
    SecretEntryMethod.holdPinConfirm => 'Hold + PIN + Confirm Key (Direct Chat)',
    SecretEntryMethod.sequentialHold => 'Sequential Hold (Hold A, then Tap B)',
    SecretEntryMethod.secretExpressionHold => 'Secret Expression + Hold Key',
    SecretEntryMethod.multiTapHold => 'Multi-Tap + Long-Press Combo',
    SecretEntryMethod.secretMathEquation =>
      'Secret Math Equation (Direct Chat)',
  };

  String get shortSummary => switch (this) {
    SecretEntryMethod.simultaneousHold => 'Hold two keys together',
    SecretEntryMethod.holdPinConfirm => 'Hold key, type PIN, press confirm key',
    SecretEntryMethod.sequentialHold => 'Hold first key, release, tap second',
    SecretEntryMethod.secretExpressionHold => 'Type secret code, then hold key',
    SecretEntryMethod.multiTapHold => 'Tap key repeatedly, then hold',
    SecretEntryMethod.secretMathEquation =>
      'Type PIN in calculation, then hold key',
  };

  bool get isDirectChatUnlock =>
      this == SecretEntryMethod.holdPinConfirm ||
      this == SecretEntryMethod.secretMathEquation;

  static const List<SecretEntryMethod> oneHandedMethods = <SecretEntryMethod>[
    SecretEntryMethod.holdPinConfirm,
    SecretEntryMethod.sequentialHold,
    SecretEntryMethod.secretExpressionHold,
    SecretEntryMethod.multiTapHold,
    SecretEntryMethod.secretMathEquation,
  ];

  static SecretEntryMethod fromId(String? raw) {
    for (final value in SecretEntryMethod.values) {
      if (value.id == raw) return value;
    }
    return SecretEntryMethod.holdPinConfirm;
  }
}

/// Configurable descriptor for a selectable calculator key.
class CalcKeyOption {
  const CalcKeyOption({
    required this.id,
    required this.label,
    required this.category,
  });

  final String id;
  final String label;
  final String category;
}

/// All calculator keys (basic keypad + memory bar) that can be assigned to
/// secret-entry roles.
const List<CalcKeyOption> selectableCalculatorKeys = <CalcKeyOption>[
  CalcKeyOption(id: kMemoryClearKeyId, label: 'MC', category: 'Memory'),
  CalcKeyOption(id: kMemoryRecallKeyId, label: 'MR', category: 'Memory'),
  CalcKeyOption(id: kMemoryAddKeyId, label: 'M+', category: 'Memory'),
  CalcKeyOption(id: kMemorySubtractKeyId, label: 'M−', category: 'Memory'),
  CalcKeyOption(id: 'clear', label: 'AC', category: 'Function'),
  CalcKeyOption(id: 'percent', label: '%', category: 'Function'),
  CalcKeyOption(id: 'paren', label: '( )', category: 'Function'),
  CalcKeyOption(id: 'divide', label: '÷', category: 'Operator'),
  CalcKeyOption(id: 'digit-7', label: '7', category: 'Digit'),
  CalcKeyOption(id: 'digit-8', label: '8', category: 'Digit'),
  CalcKeyOption(id: 'digit-9', label: '9', category: 'Digit'),
  CalcKeyOption(id: 'multiply', label: '×', category: 'Operator'),
  CalcKeyOption(id: 'digit-4', label: '4', category: 'Digit'),
  CalcKeyOption(id: 'digit-5', label: '5', category: 'Digit'),
  CalcKeyOption(id: 'digit-6', label: '6', category: 'Digit'),
  CalcKeyOption(id: 'subtract', label: '−', category: 'Operator'),
  CalcKeyOption(id: 'digit-1', label: '1', category: 'Digit'),
  CalcKeyOption(id: 'digit-2', label: '2', category: 'Digit'),
  CalcKeyOption(id: 'digit-3', label: '3', category: 'Digit'),
  CalcKeyOption(id: 'add', label: '+', category: 'Operator'),
  CalcKeyOption(id: 'decimal', label: '.', category: 'Digit'),
  CalcKeyOption(id: 'digit-0', label: '0', category: 'Digit'),
  CalcKeyOption(id: 'backspace', label: '⌫', category: 'Function'),
  CalcKeyOption(id: kEqualsKeyId, label: '=', category: 'Operator'),
];

String labelForCalcKeyId(String keyId) {
  for (final option in selectableCalculatorKeys) {
    if (option.id == keyId) return option.label;
  }
  return keyId;
}

@immutable
class SecretEntryConfig {
  const SecretEntryConfig({
    this.defaultPrimaryKeyId = kSevenKeyId,
    this.defaultSecondaryKeyId = kEqualsKeyId,
    this.oneHandedEnabled = false,
    this.method = SecretEntryMethod.holdPinConfirm,
    this.primaryKeyId = kEqualsKeyId,
    this.secondaryKeyId = kSevenKeyId,
    this.confirmKeyId = kMemoryRecallKeyId,
    this.secretExpression = '77',
    this.tapCount = 3,
    this.requireClearedDisplay = false,
  });

  factory SecretEntryConfig.defaultsFor(
    SecretEntryMethod method, {
    bool oneHandedEnabled = true,
    String defaultPrimaryKeyId = kSevenKeyId,
    String defaultSecondaryKeyId = kEqualsKeyId,
  }) {
    return switch (method) {
      SecretEntryMethod.simultaneousHold => SecretEntryConfig(
        defaultPrimaryKeyId: defaultPrimaryKeyId,
        defaultSecondaryKeyId: defaultSecondaryKeyId,
        oneHandedEnabled: false,
        method: SecretEntryMethod.holdPinConfirm,
      ),
      SecretEntryMethod.holdPinConfirm => SecretEntryConfig(
        defaultPrimaryKeyId: defaultPrimaryKeyId,
        defaultSecondaryKeyId: defaultSecondaryKeyId,
        oneHandedEnabled: oneHandedEnabled,
        method: SecretEntryMethod.holdPinConfirm,
        primaryKeyId: kEqualsKeyId,
        confirmKeyId: kMemoryRecallKeyId,
      ),
      SecretEntryMethod.sequentialHold => SecretEntryConfig(
        defaultPrimaryKeyId: defaultPrimaryKeyId,
        defaultSecondaryKeyId: defaultSecondaryKeyId,
        oneHandedEnabled: oneHandedEnabled,
        method: SecretEntryMethod.sequentialHold,
        primaryKeyId: kEqualsKeyId,
        secondaryKeyId: kSevenKeyId,
      ),
      SecretEntryMethod.secretExpressionHold => SecretEntryConfig(
        defaultPrimaryKeyId: defaultPrimaryKeyId,
        defaultSecondaryKeyId: defaultSecondaryKeyId,
        oneHandedEnabled: oneHandedEnabled,
        method: SecretEntryMethod.secretExpressionHold,
        primaryKeyId: kEqualsKeyId,
        secretExpression: '77',
      ),
      SecretEntryMethod.multiTapHold => SecretEntryConfig(
        defaultPrimaryKeyId: defaultPrimaryKeyId,
        defaultSecondaryKeyId: defaultSecondaryKeyId,
        oneHandedEnabled: oneHandedEnabled,
        method: SecretEntryMethod.multiTapHold,
        primaryKeyId: kEqualsKeyId,
        tapCount: 3,
      ),
      SecretEntryMethod.secretMathEquation => SecretEntryConfig(
        defaultPrimaryKeyId: defaultPrimaryKeyId,
        defaultSecondaryKeyId: defaultSecondaryKeyId,
        oneHandedEnabled: oneHandedEnabled,
        method: SecretEntryMethod.secretMathEquation,
        primaryKeyId: kEqualsKeyId,
      ),
    };
  }

  factory SecretEntryConfig.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return const SecretEntryConfig();
    final rawMethod = raw['method'] as String?;
    final parsedMethod = SecretEntryMethodX.fromId(rawMethod);
    final isKnownOneHanded = SecretEntryMethodX.oneHandedMethods.any(
      (m) => m.id == rawMethod,
    );
    final oneHandedEnabled =
        raw['oneHandedEnabled'] as bool? ?? isKnownOneHanded;
    final method = parsedMethod == SecretEntryMethod.simultaneousHold
        ? SecretEntryMethod.holdPinConfirm
        : parsedMethod;
    final defaults = SecretEntryConfig.defaultsFor(
      method,
      oneHandedEnabled: oneHandedEnabled,
    );
    final rawTapCount = raw['tapCount'];
    final tapCount = rawTapCount is int
        ? rawTapCount.clamp(2, 6)
        : defaults.tapCount;
    final rawExpr = raw['secretExpression'];
    final secretExpression = rawExpr is String && rawExpr.trim().isNotEmpty
        ? rawExpr.trim()
        : defaults.secretExpression;
    return SecretEntryConfig(
      defaultPrimaryKeyId: _validKeyOrDefault(
        raw['defaultPrimaryKeyId'] as String?,
        defaults.defaultPrimaryKeyId,
      ),
      defaultSecondaryKeyId: _validKeyOrDefault(
        raw['defaultSecondaryKeyId'] as String?,
        defaults.defaultSecondaryKeyId,
      ),
      oneHandedEnabled: oneHandedEnabled,
      method: method,
      primaryKeyId: _validKeyOrDefault(
        raw['primaryKeyId'] as String?,
        defaults.primaryKeyId,
      ),
      secondaryKeyId: _validKeyOrDefault(
        raw['secondaryKeyId'] as String?,
        defaults.secondaryKeyId,
      ),
      confirmKeyId: _validKeyOrDefault(
        raw['confirmKeyId'] as String?,
        defaults.confirmKeyId,
      ),
      secretExpression: secretExpression,
      tapCount: tapCount,
      requireClearedDisplay:
          raw['requireClearedDisplay'] as bool? ??
          defaults.requireClearedDisplay,
    );
  }

  static String _validKeyOrDefault(String? keyId, String fallback) {
    if (keyId == null || keyId.isEmpty) return fallback;
    for (final option in selectableCalculatorKeys) {
      if (option.id == keyId) return keyId;
    }
    return fallback;
  }

  /// Always-on simultaneous two-key hold keys (default `7` & `=`).
  final String defaultPrimaryKeyId;
  final String defaultSecondaryKeyId;

  /// Whether the configured one-handed / stealth method is active alongside
  /// the always-on default simultaneous hold.
  final bool oneHandedEnabled;

  final SecretEntryMethod method;

  /// Primary hold/tap key:
  /// - `simultaneousHold`: first key (default `7`)
  /// - `holdPinConfirm`: hold key to arm PIN entry (default `=`)
  /// - `sequentialHold`: key to hold first (default `=`)
  /// - `secretExpressionHold`: key to long-press after expression (default `=`)
  /// - `multiTapHold`: key to tap N times and hold (default `=`)
  /// - `secretMathEquation`: key to long-press after equation (default `=`)
  final String primaryKeyId;

  /// Secondary key:
  /// - `simultaneousHold`: second simultaneous key (default `=`)
  /// - `sequentialHold`: key to tap after releasing [primaryKeyId] (default `7`)
  final String secondaryKeyId;

  /// Confirm key for [SecretEntryMethod.holdPinConfirm] (default `MR`).
  final String confirmKeyId;

  /// Expected expression for [SecretEntryMethod.secretExpressionHold].
  final String secretExpression;

  /// Number of quick taps before the hold press in [SecretEntryMethod.multiTapHold].
  final int tapCount;

  /// Whether [SecretEntryMethod.sequentialHold] requires an empty/cleared display.
  final bool requireClearedDisplay;

  SecretEntryConfig copyWith({
    String? defaultPrimaryKeyId,
    String? defaultSecondaryKeyId,
    bool? oneHandedEnabled,
    SecretEntryMethod? method,
    String? primaryKeyId,
    String? secondaryKeyId,
    String? confirmKeyId,
    String? secretExpression,
    int? tapCount,
    bool? requireClearedDisplay,
  }) {
    return SecretEntryConfig(
      defaultPrimaryKeyId: defaultPrimaryKeyId ?? this.defaultPrimaryKeyId,
      defaultSecondaryKeyId:
          defaultSecondaryKeyId ?? this.defaultSecondaryKeyId,
      oneHandedEnabled: oneHandedEnabled ?? this.oneHandedEnabled,
      method: method ?? this.method,
      primaryKeyId: primaryKeyId ?? this.primaryKeyId,
      secondaryKeyId: secondaryKeyId ?? this.secondaryKeyId,
      confirmKeyId: confirmKeyId ?? this.confirmKeyId,
      secretExpression: secretExpression ?? this.secretExpression,
      tapCount: tapCount ?? this.tapCount,
      requireClearedDisplay:
          requireClearedDisplay ?? this.requireClearedDisplay,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'defaultPrimaryKeyId': defaultPrimaryKeyId,
    'defaultSecondaryKeyId': defaultSecondaryKeyId,
    'oneHandedEnabled': oneHandedEnabled,
    'method': method.id,
    'primaryKeyId': primaryKeyId,
    'secondaryKeyId': secondaryKeyId,
    'confirmKeyId': confirmKeyId,
    'secretExpression': secretExpression,
    'tapCount': tapCount,
    'requireClearedDisplay': requireClearedDisplay,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SecretEntryConfig &&
          runtimeType == other.runtimeType &&
          defaultPrimaryKeyId == other.defaultPrimaryKeyId &&
          defaultSecondaryKeyId == other.defaultSecondaryKeyId &&
          oneHandedEnabled == other.oneHandedEnabled &&
          method == other.method &&
          primaryKeyId == other.primaryKeyId &&
          secondaryKeyId == other.secondaryKeyId &&
          confirmKeyId == other.confirmKeyId &&
          secretExpression == other.secretExpression &&
          tapCount == other.tapCount &&
          requireClearedDisplay == other.requireClearedDisplay;

  @override
  int get hashCode => Object.hash(
    defaultPrimaryKeyId,
    defaultSecondaryKeyId,
    oneHandedEnabled,
    method,
    primaryKeyId,
    secondaryKeyId,
    confirmKeyId,
    secretExpression,
    tapCount,
    requireClearedDisplay,
  );
}
