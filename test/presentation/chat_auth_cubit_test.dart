import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/application/services/chat_auth_service.dart';
import 'package:photo_vault/application/services/chat_identity_service.dart';
import 'package:photo_vault/application/services/presence_service.dart';
import 'package:photo_vault/domain/entities/chat_user.dart';
import 'package:photo_vault/presentation/state/chat/chat_auth_cubit.dart';

final _user = ChatUser(
  uid: 'me',
  email: 'me@example.com',
  displayName: 'Me',
  publicKey: 'pk',
  createdAt: DateTime.utc(2024),
);

/// Auth service whose server calls behave like a device with no network.
class _OfflineAuthService implements ChatAuthService {
  ChatUser? localUser = _user;

  /// Controls each [syncWithServer] call; defaults to never completing, which
  /// is exactly what an unacknowledged Firestore write looks like offline.
  Future<IdentitySyncResult> Function() onSync = () =>
      Completer<IdentitySyncResult>().future;

  int syncCalls = 0;

  @override
  IdentitySyncResult? lastIdentitySync;

  @override
  Future<ChatUser?> restoreLocalSession() async => localUser;

  @override
  Future<IdentitySyncResult> syncWithServer(ChatUser user) {
    syncCalls++;
    return onSync();
  }

  @override
  Future<ChatUser> ensureSignedIn({required bool allowInteractiveSignIn}) =>
      Completer<ChatUser>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not needed');
}

class _HangingPresence implements PresenceService {
  @override
  Future<void> activate() => Completer<void>().future;

  @override
  Future<void> deactivate() => Completer<void>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not needed');
}

void main() {
  late _OfflineAuthService auth;
  late StreamController<List<ConnectivityResult>> connectivity;
  late ChatAuthCubit cubit;

  setUp(() {
    auth = _OfflineAuthService();
    connectivity = StreamController<List<ConnectivityResult>>.broadcast();
    cubit = ChatAuthCubit(
      authService: auth,
      presenceService: _HangingPresence(),
      connectivityStream: connectivity.stream,
    );
  });

  tearDown(() async {
    await cubit.close();
    await connectivity.close();
  });

  test(
    'a returning user is authenticated while the server never answers',
    () async {
      await cubit.checkSession().timeout(const Duration(seconds: 1));

      final state = cubit.state;
      expect(state, isA<ChatAuthAuthenticated>());
      expect((state as ChatAuthAuthenticated).user.uid, 'me');
      expect(auth.syncCalls, 1);
    },
  );

  test(
    'a failed background sync is retried when the device reconnects',
    () async {
      auth.onSync = () async => throw StateError('unavailable');
      await cubit.checkSession();
      await Future<void>.delayed(Duration.zero);

      auth.onSync = () async => IdentitySyncResult.upToDate;
      connectivity.add(const [ConnectivityResult.wifi]);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(auth.syncCalls, 2);
      final state = cubit.state as ChatAuthAuthenticated;
      expect(state.identitySync, IdentitySyncResult.upToDate);
    },
  );

  test('no retry is attempted while the device stays offline', () async {
    auth.onSync = () async => throw StateError('unavailable');
    await cubit.checkSession();
    await Future<void>.delayed(Duration.zero);

    connectivity.add(const [ConnectivityResult.none]);
    await Future<void>.delayed(Duration.zero);

    expect(auth.syncCalls, 1);
    expect(cubit.state, isA<ChatAuthAuthenticated>());
  });
}
