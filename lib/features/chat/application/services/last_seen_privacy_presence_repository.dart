import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/entities/user_presence.dart';
import '../../domain/repositories/presence_repository.dart';

/// Applies the reciprocal "Show last seen" rule to everything read through it:
/// when the local user hides their own last seen, they cannot see anyone
/// else's either (WhatsApp semantics). Online state is never affected.
///
/// A decorator so the rule lives in one place and every consumer (thread
/// header, chat list, ...) gets it without knowing about the setting.
class LastSeenPrivacyPresenceRepository implements PresenceRepository {
  LastSeenPrivacyPresenceRepository({
    required PresenceRepository inner,
    required ValueListenable<bool> shareLastSeen,
  }) : _inner = inner,
       _shareLastSeen = shareLastSeen;

  final PresenceRepository _inner;
  final ValueListenable<bool> _shareLastSeen;

  @override
  Future<void> setOnline(String uid, {bool shareLastSeen = true}) =>
      _inner.setOnline(uid, shareLastSeen: shareLastSeen);

  @override
  Future<void> setOffline(String uid, {bool shareLastSeen = true}) =>
      _inner.setOffline(uid, shareLastSeen: shareLastSeen);

  @override
  Stream<UserPresence> watch(String uid) => _withPrivacy(
    _inner.watch(uid),
    (p) => _shareLastSeen.value ? p : p.withoutLastSeen(),
  );

  @override
  Stream<Map<String, UserPresence>> watchMany(List<String> uids) =>
      _withPrivacy(
        _inner.watchMany(uids),
        (byUid) => _shareLastSeen.value
            ? byUid
            : byUid.map((uid, p) => MapEntry(uid, p.withoutLastSeen())),
      );

  /// Maps [source] through [apply], re-emitting the latest value whenever the
  /// local setting changes so open screens update immediately.
  Stream<T> _withPrivacy<T>(Stream<T> source, T Function(T) apply) {
    late T latest;
    var hasLatest = false;
    StreamSubscription<T>? sub;
    // ignore: close_sinks - returned as the stream; torn down in onCancel.
    late StreamController<T> controller;

    void emit() {
      if (!hasLatest || controller.isClosed) return;
      controller.add(apply(latest));
    }

    controller = StreamController<T>(
      onListen: () {
        _shareLastSeen.addListener(emit);
        sub = source.listen(
          (value) {
            latest = value;
            hasLatest = true;
            emit();
          },
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onPause: () => sub?.pause(),
      onResume: () => sub?.resume(),
      onCancel: () async {
        _shareLastSeen.removeListener(emit);
        await sub?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  void dispose() => _inner.dispose();
}
