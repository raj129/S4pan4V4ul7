import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/application/services/chat_backup_scheduler.dart';
import 'package:photo_vault/application/services/chat_backup_service.dart';
import 'package:photo_vault/crypto/services/chat_crypto_service.dart';
import 'package:photo_vault/domain/entities/chat_message.dart';
import 'package:photo_vault/domain/repositories/chat_backup_store.dart';

import '../helpers/memory_message_cache.dart';

/// Reversible stand-in for backup encryption.
class _FakeCrypto implements ChatCryptoService {
  @override
  Future<Uint8List> encryptBackup(List<int> plain) async =>
      Uint8List.fromList([7, ...plain.map((b) => b ^ 0x5a)]);

  @override
  Future<Uint8List> decryptBackup(List<int> encrypted) async {
    if (encrypted.isEmpty || encrypted.first != 7) {
      throw const FormatException('bad key');
    }
    return Uint8List.fromList(encrypted.skip(1).map((b) => b ^ 0x5a).toList());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _MemoryStore implements ChatBackupStore {
  _MemoryStore(this.label, {this.requiresNetwork = false});

  @override
  final String label;
  @override
  final bool requiresNetwork;

  final Map<String, Uint8List> blobs = {};
  int writes = 0;

  @override
  Future<void> write(
    String accountId,
    Uint8List blob, {
    bool interactive = false,
  }) async {
    writes++;
    blobs[accountId] = blob;
  }

  @override
  Future<Uint8List?> read(String accountId, {bool interactive = false}) async =>
      blobs[accountId];
}

ChatMessage _msg(String id, DateTime at, {String thread = 't1'}) =>
    ChatMessage(
      messageId: id,
      threadId: thread,
      senderId: 'me',
      encryptedText: 'cipher-$id',
      sentAt: at,
      deletedFor: const [],
    );

void main() {
  late MemoryMessageCache cache;
  late _MemoryStore local;
  late _MemoryStore drive;
  late List<ConnectivityResult> connectivity;
  late DateTime now;

  ChatBackupService build({MemoryMessageCache? on}) => ChatBackupService(
    cache: on ?? cache,
    crypto: _FakeCrypto(),
    stores: [local, drive],
    currentUid: () => 'uid-1',
    checkConnectivity: () async => connectivity,
    clock: () => now,
  );

  setUp(() {
    cache = MemoryMessageCache();
    local = _MemoryStore('This device');
    drive = _MemoryStore('Google Drive', requiresNetwork: true);
    connectivity = [ConnectivityResult.wifi];
    now = DateTime.utc(2024, 3, 10, 2);
  });

  test('clear, chat, back up, wipe, restore shows only post-clear messages',
      () async {
    final clearedAt = DateTime.utc(2024, 3, 9, 12);
    await cache.setClearedBefore('t1', clearedAt);
    await cache.save([_msg('after-clear', DateTime.utc(2024, 3, 9, 18))]);
    await build().backupNow();

    // "Clear app data": a brand-new cache.
    final fresh = MemoryMessageCache();
    now = DateTime.utc(2024, 3, 10, 9);
    final service = build(on: fresh);
    expect(await service.prepareForSession(), isTrue);
    expect(fresh.horizon, now);

    final snapshot = await service.findLatestBackup();
    expect(snapshot, isNotNull);
    await service.restore(snapshot!);

    expect(fresh.rows.keys, ['after-clear']);
    expect(fresh.cleared['t1'], clearedAt);
    // Messages that reached the server after the backup are visible again.
    expect(fresh.horizon, DateTime.utc(2024, 3, 10, 2));
    expect(await service.prepareForSession(), isFalse);
  });

  test('an existing install with history is not given a horizon', () async {
    await cache.save([_msg('a', DateTime.utc(2024, 3, 1))]);

    expect(await build().prepareForSession(), isFalse);
    expect(cache.horizon, isNull);
  });

  test('Wi-Fi only skips Drive on mobile data and retries later', () async {
    await cache.save([_msg('a', DateTime.utc(2024, 3, 1))]);
    connectivity = [ConnectivityResult.mobile];

    final result = await build().backupNow();

    expect(result.savedTo, ['This device']);
    expect(result.skipped.keys, ['Google Drive']);
    expect(drive.writes, 0);

    // Not overdue, but the missed cloud upload makes it due.
    connectivity = [ConnectivityResult.wifi];
    now = now.add(const Duration(hours: 1));
    await build().backupIfDue();
    expect(drive.writes, 1);
  });

  test('backupIfDue waits for a day and never runs before a restore decision',
      () async {
    final service = build();
    await service.prepareForSession(); // empty cache → restore pending
    expect(await service.backupIfDue(), isNull);

    await service.dismissRestoreOffer();
    expect(await service.backupIfDue(), isNotNull);
    now = now.add(const Duration(hours: 5));
    expect(await service.backupIfDue(), isNull);
    now = now.add(const Duration(hours: 20));
    expect(await service.backupIfDue(), isNotNull);
  });

  test('picks the newest readable backup across stores', () async {
    await cache.save([_msg('old', DateTime.utc(2024, 3, 1))]);
    connectivity = [ConnectivityResult.none];
    await build().backupNow(); // local only
    now = now.add(const Duration(days: 1));
    await cache.save([_msg('new', DateTime.utc(2024, 3, 11))]);
    connectivity = [ConnectivityResult.wifi];
    await build().backupNow();
    local.blobs.updateAll((_, _) => Uint8List.fromList([1, 2, 3]));

    final snapshot = await build().findLatestBackup();

    expect(snapshot!.source, 'Google Drive');
    expect(snapshot.messageCount, 2);
  });

  test('next backup is scheduled for 2 AM local time', () {
    expect(
      delayUntilNextBackup(DateTime(2024, 3, 10, 23)),
      const Duration(hours: 3),
    );
    expect(
      delayUntilNextBackup(DateTime(2024, 3, 10, 1, 30)),
      const Duration(minutes: 30),
    );
  });
}
