import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/application/services/last_seen_privacy_presence_repository.dart';
import 'package:photo_vault/features/chat/application/services/presence_service.dart';
import 'package:photo_vault/features/chat/domain/entities/user_presence.dart';
import 'package:photo_vault/features/chat/domain/repositories/presence_repository.dart';
import 'package:photo_vault/features/chat/presentation/formatting/last_seen_formatter.dart';

class _RecordingPresence implements PresenceRepository {
  final calls = <String>[];
  // ignore: close_sinks - test fake lives for the whole test.
  final updates = StreamController<Map<String, UserPresence>>.broadcast();

  @override
  Future<void> setOnline(String uid, {bool shareLastSeen = true}) async =>
      calls.add('online:$uid:$shareLastSeen');

  @override
  Future<void> setOffline(String uid, {bool shareLastSeen = true}) async =>
      calls.add('offline:$uid:$shareLastSeen');

  @override
  Stream<UserPresence> watch(String uid) => throw UnimplementedError();

  @override
  Stream<Map<String, UserPresence>> watchMany(List<String> uids) =>
      updates.stream;

  @override
  void dispose() {}
}

void main() {
  group('formatLastSeen', () {
    final now = DateTime(2026, 11, 1, 18, 0);
    // intl separates AM/PM with a narrow no-break space.
    String fmt(DateTime t) =>
        formatLastSeen(t, now: now).replaceAll('\u202f', ' ');

    test('today', () {
      expect(fmt(DateTime(2026, 11, 1, 14, 5)), 'last seen today at 2:05 PM');
    });

    test('yesterday', () {
      expect(
        fmt(DateTime(2026, 10, 31, 9, 30)),
        'last seen yesterday at 9:30 AM',
      );
    });

    test('within a week shows the weekday', () {
      expect(fmt(DateTime(2026, 10, 28, 9, 30)), 'last seen Wed at 9:30 AM');
    });

    test('earlier this year shows the date', () {
      expect(fmt(DateTime(2026, 3, 12, 9, 30)), 'last seen 12 Mar');
    });

    test('previous years include the year', () {
      expect(fmt(DateTime(2025, 3, 12, 9, 30)), 'last seen 12 Mar 2025');
    });
  });

  group('LastSeenPrivacyPresenceRepository', () {
    final seen = DateTime.utc(2026, 11, 1, 10);

    test('passes last seen through while sharing is on, '
        'and hides it reciprocally when turned off', () async {
      final inner = _RecordingPresence();
      final share = ValueNotifier<bool>(true);
      final repo = LastSeenPrivacyPresenceRepository(
        inner: inner,
        shareLastSeen: share,
      );
      final got = <UserPresence>[];
      final sub = repo.watchMany(['bob']).listen((m) => got.add(m['bob']!));

      inner.updates.add({'bob': UserPresence(isOnline: false, lastSeen: seen)});
      await pumpEventQueue();
      expect(got.last.lastSeen, seen);

      share.value = false;
      await pumpEventQueue();
      expect(got.last.lastSeen, isNull, reason: 're-emitted without it');
      expect(got.last.isOnline, isFalse);

      share.value = true;
      await pumpEventQueue();
      expect(got.last.lastSeen, seen);

      await sub.cancel();
      share.dispose();
    });

    test('online state is never hidden', () async {
      final inner = _RecordingPresence();
      final share = ValueNotifier<bool>(false);
      final repo = LastSeenPrivacyPresenceRepository(
        inner: inner,
        shareLastSeen: share,
      );
      final got = <UserPresence>[];
      final sub = repo.watchMany(['bob']).listen((m) => got.add(m['bob']!));
      inner.updates.add({'bob': UserPresence(isOnline: true, lastSeen: seen)});
      await pumpEventQueue();
      expect(got.single.isOnline, isTrue);
      expect(got.single.lastSeen, isNull);
      await sub.cancel();
      share.dispose();
    });
  });

  group('PresenceService.setShareLastSeen', () {
    test('republishes offline presence when changed while inactive', () async {
      final repo = _RecordingPresence();
      final service = PresenceService(
        presenceRepository: repo,
        currentUid: () => 'me',
      );
      await service.setShareLastSeen(false);
      expect(repo.calls, ['offline:me:false']);
      await service.activate();
      expect(repo.calls.last, 'online:me:false');
      service.dispose();
    });

    test('republishes online presence when changed while active', () async {
      final repo = _RecordingPresence();
      final service = PresenceService(
        presenceRepository: repo,
        currentUid: () => 'me',
      );
      await service.activate();
      await service.setShareLastSeen(false);
      expect(repo.calls, ['online:me:true', 'online:me:false']);
      await service.deactivate();
      expect(repo.calls.last, 'offline:me:false');
      service.dispose();
    });

    test('no-op when unchanged or signed out', () async {
      final repo = _RecordingPresence();
      final service = PresenceService(
        presenceRepository: repo,
        currentUid: () => null,
      );
      await service.setShareLastSeen(true);
      await service.setShareLastSeen(false);
      expect(repo.calls, isEmpty);
      expect(service.shareLastSeen.value, isFalse);
      service.dispose();
    });
  });
}
