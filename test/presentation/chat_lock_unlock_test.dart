import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/core/app/app_session.dart';
import 'package:photo_vault/core/di/app_dependencies.dart';
import 'package:photo_vault/core/di/chat_dependencies.dart';
import 'package:photo_vault/core/routing/app_router.dart';
import 'package:photo_vault/crypto/services/chat_crypto_service.dart';
import 'package:photo_vault/domain/entities/chat_message.dart';
import 'package:photo_vault/domain/entities/chat_thread.dart';
import 'package:photo_vault/domain/entities/chat_user.dart';
import 'package:photo_vault/domain/entities/user_mode.dart';
import 'package:photo_vault/domain/entities/user_presence.dart';
import 'package:photo_vault/domain/entities/vault_settings.dart';
import 'package:photo_vault/domain/repositories/message_repository.dart';
import 'package:photo_vault/domain/repositories/presence_repository.dart';
import 'package:photo_vault/domain/repositories/thread_repository.dart';
import 'package:photo_vault/domain/repositories/typing_repository.dart';
import 'package:photo_vault/domain/repositories/user_repository.dart';
import 'package:photo_vault/presentation/app/main_scaffold.dart';
import 'package:photo_vault/presentation/screens/chat_screens/thread_screen.dart';
import 'package:photo_vault/presentation/screens/lock/lock_screen.dart';
import 'package:photo_vault/presentation/state/onboarding/onboarding_cubit.dart';

class _FakeMessageRepo implements MessageRepository {
  @override
  Stream<List<ChatMessage>> watchMessages(String threadId, {int limit = 30}) =>
      const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeThreadRepo implements ThreadRepository {
  @override
  Stream<List<ChatThread>> watchThreadsForUser(String uid) =>
      const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUserRepo implements UserRepository {
  @override
  Future<ChatUser?> getUserById(String uid) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePresenceRepo implements PresenceRepository {
  @override
  Stream<UserPresence> watch(String uid) => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTypingRepo implements TypingRepository {
  @override
  Stream<bool> watchTyping({required String threadId, required String otherUid}) =>
      const Stream.empty();

  @override
  Future<void> setTyping({
    required String threadId,
    required String uid,
    required bool isTyping,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMediaRepo implements MediaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCryptoService implements ChatCryptoService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Auto-lock and unlock while chat thread is open does not throw duplicate GlobalKey error',
      (WidgetTester tester) async {
    final deps = AppDependencies(persistentState: false);
    deps.chatOverride = ChatDependencies(
      authRepository: deps.authRepository,
      vaultSession: deps.vaultSession,
      userRepository: _FakeUserRepo(),
      threadRepository: _FakeThreadRepo(),
      messageRepository: _FakeMessageRepo(),
      mediaRepository: _FakeMediaRepo(),
      presenceRepository: _FakePresenceRepo(),
      typingRepository: _FakeTypingRepo(),
      cryptoService: _FakeCryptoService(),
    );

    await deps.initialize();
    await deps.vaultRepository.initializeVault(
      vaultId: 'v1',
      settings: VaultSettings.defaults(mode: UserMode.localOnly),
    );

    final session = AppSessionState(initialMode: UserMode.localOnly);
    session.unlock();

    final onboardingCubit = OnboardingCubit(
      authRepository: deps.authRepository,
      createVaultUseCase: deps.createVaultUseCase,
      pinValidator: deps.pinValidator,
      restoreFlowService: deps.restoreFlowService,
    );

    final router = buildAppRouter(
      deps: deps,
      session: session,
      onboardingCubit: onboardingCubit,
      onSettingsChanged: () async {},
    );

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Navigate to /chat
    router.go('/chat');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Open a thread via openThreadScreen
    final now = DateTime.now();
    final thread = ChatThread(
      threadId: 'test_thread_1',
      participantIds: const ['me', 'other'],
      lastMessage: 'Hello',
      lastMessageAt: now,
      unreadCounts: const {'me': 0, 'other': 0},
      createdAt: now,
    );
    final otherUser = ChatUser(
      uid: 'other',
      email: 'other@example.com',
      displayName: 'Other User',
      publicKey: 'dGVzdF9wdWJsaWNfa2V5',
      createdAt: now,
    );

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final scaffoldContext = tester.element(find.byType(Scaffold).first);
    openThreadScreen(
      scaffoldContext,
      thread: thread,
      otherUser: otherUser,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ThreadScreen), findsOneWidget);

    // Simulate auto-lock
    session.lock();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(LockScreen), findsOneWidget);

    // Simulate unlock
    session.unlock();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify no crash, LockScreen is gone, and MainScaffold is safely displayed
    expect(find.byType(LockScreen), findsNothing);
    expect(find.byType(MainScaffold), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 10));
  });
}
