import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_vault/core/app/app_session.dart';
import 'package:photo_vault/core/di/app_dependencies.dart';
import 'package:photo_vault/core/routing/app_router.dart';
import 'package:photo_vault/features/chat/application/crypto/chat_crypto_service.dart';
import 'package:photo_vault/features/chat/application/media/chat_media_loader.dart';
import 'package:photo_vault/features/chat/application/media/chat_media_manager_service.dart';
import 'package:photo_vault/features/chat/application/services/chat_auth_service.dart';
import 'package:photo_vault/features/chat/application/services/chat_notification_service.dart';
import 'package:photo_vault/features/chat/application/services/data_sms_service.dart';
import 'package:photo_vault/features/chat/application/services/profile_service.dart';
import 'package:photo_vault/features/chat/di/chat_dependencies.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_message.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_thread.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_user.dart';
import 'package:photo_vault/features/chat/domain/repositories/chat_draft_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/chat_search_index_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/message_cache_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/message_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/notes_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/outbox_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/presence_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/thread_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/typing_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/user_repository.dart';
import 'package:photo_vault/features/chat/presentation/screens/new_chat_screen.dart';
import 'package:photo_vault/features/chat/presentation/screens/thread_screen.dart';
import 'package:photo_vault/features/chat/presentation/state/active_thread_cubit.dart';
import 'package:photo_vault/features/chat/presentation/state/thread_list_cubit.dart';
import 'package:photo_vault/features/chat/presentation/state/user_lookup_cubit.dart';
import 'package:photo_vault/features/vault/presentation/state/onboarding_cubit.dart';

class _Sms implements DataSmsService {
  @override
  Stream<ChatMessage> get changes => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repositories
    implements
        MessageRepository,
        ThreadRepository,
        UserRepository,
        TypingRepository,
        PresenceRepository,
        MediaRepository,
        NotesRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements ChatAuthService {
  @override
  String get currentUid => 'me';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Media implements ChatMediaLoader {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MediaManager implements ChatMediaManagerService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Notifications implements ChatNotificationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Profile implements ProfileService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Onboarding implements OnboardingCubit {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ChatDeps implements ChatDependencies {
  _ChatDeps(this.sms);
  final DataSmsService sms;
  final repositories = _Repositories();
  late final values = <Symbol, Object?>{
    #dataSms: sms,
    #messageRepository: repositories,
    #threadRepository: repositories,
    #userRepository: repositories,
    #typingRepository: repositories,
    #presenceRepository: repositories,
    #mediaRepository: repositories,
    #notesRepository: repositories,
    #messageCache: const NoopMessageCacheRepository(),
    #searchIndex: const NoopChatSearchIndexRepository(),
    #outbox: const NoopOutboxRepository(),
    #draftRepository: const NoopChatDraftRepository(),
    #cryptoService: ChatCryptoService(),
    #authService: _Auth(),
    #mediaLoader: _Media(),
    #mediaManagerService: _MediaManager(),
    #notificationService: _Notifications(),
    #profileService: _Profile(),
    #uploads: null,
    #localMedia: null,
  };
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter && values.containsKey(invocation.memberName)) {
      return values[invocation.memberName];
    }
    return super.noSuchMethod(invocation);
  }
}

class _RouteState implements GoRouterState {
  _RouteState(this.extra);
  @override
  final Object? extra;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProvidedActive extends Cubit<ActiveThreadState>
    implements ActiveThreadCubit {
  _ProvidedActive() : super(const ActiveThreadLoading());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProvidedList extends Cubit<ThreadListState> implements ThreadListCubit {
  _ProvidedList() : super(const ThreadListLoading());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProvidedLookup extends Cubit<UserLookupState>
    implements UserLookupCubit {
  _ProvidedLookup() : super(const UserLookupIdle());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Iterable<RouteBase> _descendants(List<RouteBase> routes) sync* {
  for (final route in routes) {
    yield route;
    yield* _descendants(route.routes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GoRouter router;
  late AppSessionState session;
  late _Sms sms;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
          (_) async => null,
        );
    sms = _Sms();
    session = AppSessionState();
    final deps = AppDependencies(persistentState: false)
      ..chatOverride = _ChatDeps(sms);
    router = buildAppRouter(
      deps: deps,
      session: session,
      onboardingCubit: _Onboarding(),
      onSettingsChanged: () async {},
    );
  });
  tearDown(() {
    router.dispose();
    session.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
          null,
        );
  });

  GoRoute route(String path) => _descendants(
    router.configuration.routes,
  ).whereType<GoRoute>().singleWhere((route) => route.path == path);

  final threadArgs = ChatThreadArgs(
    thread: ChatThread(
      threadId: 'me_other',
      participantIds: const ['me', 'other'],
      lastMessage: '',
      lastMessageAt: DateTime.utc(2026),
      createdAt: DateTime.utc(2026),
      unreadCounts: const {},
    ),
    otherUser: ChatUser(
      uid: 'other',
      email: 'other@example.com',
      displayName: 'Other',
      publicKey: '',
      createdAt: DateTime.utc(2026),
    ),
  );

  testWidgets('new-chat fallback controller receives shared SMS service', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final lookup =
                route('new').builder!(context, _RouteState(null))
                    as BlocProvider<UserLookupCubit>;
            final active = lookup.child! as BlocProvider<ActiveThreadCubit>;
            return active.buildWithChild(
              context,
              Builder(
                builder: (context) {
                  expect(context.read<ActiveThreadCubit>().dataSms, same(sms));
                  return const SizedBox();
                },
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('direct-thread fallback controllers receive shared SMS service', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final list =
                route('thread').builder!(context, _RouteState(threadArgs))
                    as BlocProvider<ThreadListCubit>;
            final active = list.child! as BlocProvider<ActiveThreadCubit>;
            return list.buildWithChild(
              context,
              active.buildWithChild(
                context,
                Builder(
                  builder: (context) {
                    expect(
                      context.read<ActiveThreadCubit>().dataSms,
                      same(sms),
                    );
                    expect(context.read<ThreadListCubit>().dataSms, same(sms));
                    return const SizedBox();
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('routes retain explicitly provided controllers', (tester) async {
    final active = _ProvidedActive();
    final list = _ProvidedList();
    final lookup = _ProvidedLookup();
    final args = ChatThreadArgs(
      thread: threadArgs.thread,
      otherUser: threadArgs.otherUser,
      activeThreadCubit: active,
      threadListCubit: list,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final providedList =
                route('thread').builder!(context, _RouteState(args))
                    as BlocProvider<ThreadListCubit>;
            final providedActive =
                providedList.child! as BlocProvider<ActiveThreadCubit>;
            final providedLookup =
                route('new').builder!(
                      context,
                      _RouteState(
                        NewChatArgs(
                          activeThreadCubit: active,
                          userLookupCubit: lookup,
                        ),
                      ),
                    )
                    as BlocProvider<UserLookupCubit>;
            final newActive =
                providedLookup.child! as BlocProvider<ActiveThreadCubit>;
            return providedList.buildWithChild(
              context,
              providedActive.buildWithChild(
                context,
                providedLookup.buildWithChild(
                  context,
                  newActive.buildWithChild(
                    context,
                    Builder(
                      builder: (context) {
                        expect(context.read<ActiveThreadCubit>(), same(active));
                        expect(context.read<ThreadListCubit>(), same(list));
                        expect(context.read<UserLookupCubit>(), same(lookup));
                        return const SizedBox();
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(active.isClosed, isFalse);
    expect(list.isClosed, isFalse);
    expect(lookup.isClosed, isFalse);
    await active.close();
    await list.close();
    await lookup.close();
  });
}
