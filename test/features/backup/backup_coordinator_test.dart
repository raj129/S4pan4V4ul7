import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/backup/application/backup_coordinator.dart';

void main() {
  test('operations run one at a time, in the order they were queued', () async {
    final coordinator = BackupCoordinator.inProcess();
    final log = <String>[];
    final gate = Completer<void>();

    final first = coordinator.run(() async {
      log.add('first start');
      await gate.future;
      log.add('first end');
      return 1;
    });
    final second = coordinator.run(() async {
      log.add('second start');
      return 2;
    });

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(log, ['first start']);

    gate.complete();
    expect(await first, 1);
    expect(await second, 2);
    expect(log, ['first start', 'first end', 'second start']);
  });

  test(
    'a failing operation returns its error and does not block later ones',
    () async {
      final coordinator = BackupCoordinator.inProcess();

      final failing = coordinator.run<int>(
        () async => throw StateError('boom'),
      );
      final after = coordinator.run(() async => 7);

      await expectLater(failing, throwsA(isA<StateError>()));
      expect(await after, 7);
    },
  );

  test(
    'the file lock is released after each operation, including failures',
    () async {
      final dir = await Directory.systemTemp.createTemp('backup_lock_test');
      addTearDown(() => dir.delete(recursive: true));
      final lock = File('${dir.path}/backup.lock');
      final coordinator = BackupCoordinator(lockFile: () async => lock);

      await expectLater(
        coordinator.run<void>(() async => throw StateError('boom')),
        throwsA(isA<StateError>()),
      );
      // If the lock had leaked, this second acquisition would hang.
      final value = await coordinator
          .run(() async => 'ok')
          .timeout(const Duration(seconds: 5));
      expect(value, 'ok');
      expect(await lock.exists(), isTrue);
    },
  );
}
