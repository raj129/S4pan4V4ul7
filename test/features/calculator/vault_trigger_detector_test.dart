import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/calculator/domain/models/secret_entry_config.dart';
import 'package:photo_vault/features/calculator/presentation/widgets/keypad_layouts.dart';
import 'package:photo_vault/features/calculator/presentation/widgets/vault_trigger_detector.dart';

void main() {
  group('SecretEntryConfig', () {
    test('round-trips through JSON for all methods', () {
      for (final method in SecretEntryMethod.values) {
        final original = SecretEntryConfig.defaultsFor(method).copyWith(
          secretExpression: '1337',
          tapCount: 4,
          requireClearedDisplay: true,
        );
        final decoded = SecretEntryConfig.fromJson(original.toJson());
        expect(decoded, original);
      }
    });

    test('falls back safely on invalid JSON', () {
      final decoded = SecretEntryConfig.fromJson(<String, dynamic>{
        'method': 'unknown',
        'primaryKeyId': 'nonexistent',
        'tapCount': 99,
      });
      expect(decoded.oneHandedEnabled, isFalse);
      expect(decoded.method, SecretEntryMethod.holdPinConfirm);
      expect(decoded.primaryKeyId, kEqualsKeyId);
      expect(decoded.tapCount, 6);
    });
  });

  group('VaultTriggerDetector', () {
    test('default simultaneousHold triggers on 7 + =', () async {
      var triggered = 0;
      final detector = VaultTriggerDetector(
        onTriggered: () => triggered++,
        holdDuration: const Duration(milliseconds: 50),
      );

      detector.handlePressStart(kSevenKeyId);
      detector.handlePressStart(kEqualsKeyId);
      expect(detector.isArmed, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(triggered, 1);
      detector.dispose();
    });

    test('holdPinConfirm (Method 99) arms on hold, captures PIN, and confirms on MR', () async {
      String? submittedPin;
      final detector = VaultTriggerDetector(
        onTriggered: () {},
        onPinSubmitted: (pin) async {
          submittedPin = pin;
          return true;
        },
        config: SecretEntryConfig.defaultsFor(SecretEntryMethod.holdPinConfirm),
        holdDuration: const Duration(milliseconds: 40),
        cooldown: const Duration(milliseconds: 20),
      );

      detector.handlePressStart(kEqualsKeyId);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      detector.handlePressEnd(kEqualsKeyId);
      expect(detector.isArmed, isTrue);

      for (final key in ['digit-1', 'digit-9', 'digit-5', 'digit-9', 'backspace', 'digit-8']) {
        detector.handleKeyTap(key);
      }
      detector.handleKeyTap(kMemoryRecallKeyId);
      await Future<void>.delayed(Duration.zero);

      expect(submittedPin, '1958');
      expect(detector.isArmed, isFalse);
      detector.dispose();
    });

    test('sequentialHold (Method 1) triggers on Hold A -> Release -> Tap B', () async {
      var triggered = 0;
      final detector = VaultTriggerDetector(
        onTriggered: () => triggered++,
        config: SecretEntryConfig.defaultsFor(
          SecretEntryMethod.sequentialHold,
        ).copyWith(requireClearedDisplay: true),
        holdDuration: const Duration(milliseconds: 40),
        sequentialWindow: const Duration(milliseconds: 200),
      );

      // Blocked when display is not cleared.
      detector.handlePressStart(
        kEqualsKeyId,
        currentExpression: '12+3',
        isDisplayCleared: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      detector.handlePressEnd(kEqualsKeyId);
      detector.handleKeyTap(kSevenKeyId);
      expect(triggered, 0);

      // Succeeds when display is cleared.
      detector.handlePressStart(
        kEqualsKeyId,
        currentExpression: '',
        isDisplayCleared: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      detector.handlePressEnd(kEqualsKeyId);
      expect(detector.isArmed, isTrue);
      detector.handleKeyTap(kSevenKeyId);
      expect(triggered, 1);
      detector.dispose();
    });

    test('secretExpressionHold (Method 2) triggers only when expression matches', () async {
      var triggered = 0;
      final detector = VaultTriggerDetector(
        onTriggered: () => triggered++,
        config: SecretEntryConfig.defaultsFor(
          SecretEntryMethod.secretExpressionHold,
        ).copyWith(secretExpression: '1337'),
        holdDuration: const Duration(milliseconds: 40),
      );

      detector.handlePressStart(kEqualsKeyId, currentExpression: '1234');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      detector.handlePressEnd(kEqualsKeyId);
      expect(triggered, 0);

      detector.handlePressStart(kEqualsKeyId, currentExpression: '1337');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(triggered, 1);
      detector.dispose();
    });

    test('multiTapHold (Method 3) triggers after N quick taps then hold', () async {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      var triggered = 0;
      final detector = VaultTriggerDetector(
        onTriggered: () => triggered++,
        config: SecretEntryConfig.defaultsFor(
          SecretEntryMethod.multiTapHold,
        ).copyWith(primaryKeyId: 'clear', tapCount: 3),
        holdDuration: const Duration(milliseconds: 40),
        multiTapWindow: const Duration(milliseconds: 500),
        now: () => now,
      );

      for (var i = 0; i < 3; i++) {
        detector.handlePressStart('clear');
        detector.handlePressEnd('clear');
        detector.handleKeyTap('clear');
        now = now.add(const Duration(milliseconds: 100));
      }

      detector.handlePressStart('clear');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(triggered, 1);
      detector.dispose();
    });

    test('secretMathEquation (Method 4) extracts trailing 4 digits on hold', () async {
      String? submittedPin;
      final detector = VaultTriggerDetector(
        onTriggered: () {},
        onPinSubmitted: (pin) async {
          submittedPin = pin;
          return true;
        },
        config: SecretEntryConfig.defaultsFor(
          SecretEntryMethod.secretMathEquation,
        ),
        holdDuration: const Duration(milliseconds: 40),
      );

      detector.handlePressStart(kEqualsKeyId, currentExpression: '42+1958');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(submittedPin, '1958');
      detector.dispose();
    });

    test('default 7 + = simultaneous hold still triggers when one-handed mode is enabled', () async {
      var triggered = 0;
      final detector = VaultTriggerDetector(
        onTriggered: () => triggered++,
        config: SecretEntryConfig.defaultsFor(
          SecretEntryMethod.holdPinConfirm,
          oneHandedEnabled: true,
        ),
        holdDuration: const Duration(milliseconds: 50),
      );

      detector.handlePressStart(kSevenKeyId);
      detector.handlePressStart(kEqualsKeyId);
      expect(detector.isArmed, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(triggered, 1);
      detector.dispose();
    });

    test('custom default hold keys work alongside one-handed mode', () async {
      var triggered = 0;
      final detector = VaultTriggerDetector(
        onTriggered: () => triggered++,
        config: SecretEntryConfig.defaultsFor(
          SecretEntryMethod.holdPinConfirm,
          oneHandedEnabled: true,
          defaultPrimaryKeyId: 'digit-1',
          defaultSecondaryKeyId: 'add',
        ),
        holdDuration: const Duration(milliseconds: 50),
      );

      detector.handlePressStart('digit-1');
      detector.handlePressStart('add');
      expect(detector.isArmed, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(triggered, 1);
      detector.dispose();
    });
  });
}
