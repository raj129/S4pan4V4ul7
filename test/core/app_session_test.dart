import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/core/app/app_session.dart';
import 'package:photo_vault/domain/entities/user_mode.dart';

void main() {
  group('AppSessionState', () {
    test('starts locked with localOnly mode by default', () {
      final session = AppSessionState();
      expect(session.isUnlocked, isFalse);
      expect(session.mode, UserMode.localOnly);
      expect(session.calculatorOnboardingCompleted, isFalse);
      expect(session.photoSyncEnabled, isFalse);
    });

    test('unlock() flips isUnlocked and notifies listeners once', () {
      final session = AppSessionState();
      var notifications = 0;
      session.addListener(() => notifications++);

      session.unlock();

      expect(session.isUnlocked, isTrue);
      expect(notifications, 1);
    });

    test('unlock() is a no-op (no extra notification) when already unlocked', () {
      final session = AppSessionState()..unlock();
      var notifications = 0;
      session.addListener(() => notifications++);

      session.unlock();

      expect(notifications, 0);
    });

    test('lock() flips isUnlocked back and notifies listeners', () {
      final session = AppSessionState()..unlock();
      var notifications = 0;
      session.addListener(() => notifications++);

      session.lock();

      expect(session.isUnlocked, isFalse);
      expect(notifications, 1);
    });

    test('mode setter only notifies when the mode actually changes', () {
      final session = AppSessionState();
      var notifications = 0;
      session.addListener(() => notifications++);

      session.mode = UserMode.localOnly; // same value, no notification
      expect(notifications, 0);

      session.mode = UserMode.googleEnabled;
      expect(session.mode, UserMode.googleEnabled);
      expect(notifications, 1);
    });

    test(
      'calculatorOnboardingCompleted setter only notifies when the value changes',
      () {
        final session = AppSessionState();
        var notifications = 0;
        session.addListener(() => notifications++);

        session.calculatorOnboardingCompleted = false;
        expect(notifications, 0);

        session.calculatorOnboardingCompleted = true;
        expect(session.calculatorOnboardingCompleted, isTrue);
        expect(notifications, 1);
      },
    );
  });
}
