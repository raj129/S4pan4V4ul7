import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/services/chat_auth_service.dart';
import '../../application/services/presence_service.dart';
import '../../crypto/services/chat_crypto_service.dart';
import '../../data/repositories_impl/firebase_auth_repository.dart';
import '../../data/repositories_impl/firestore_message_repository.dart';
import '../../data/repositories_impl/firestore_thread_repository.dart';
import '../../data/repositories_impl/firestore_user_repository.dart';
import '../screens/chat_screens/chat_list_screen.dart';
import '../screens/chat_screens/chat_sign_in_screen.dart';
import '../state/chat/chat_auth_cubit.dart';
import '../state/chat/thread_list_cubit.dart';
import '../state/chat/user_lookup_cubit.dart';
import '../state/chat/active_thread_cubit.dart';

/// Stand-alone chat app widget. Can be used as a tab inside the existing
/// vault app or as the root of its own entry-point.
///
/// Dependency wiring lives here so that screens stay free of DI details.
class ChatApp extends StatefulWidget {
  const ChatApp({super.key});

  @override
  State<ChatApp> createState() => _ChatAppState();
}

class _ChatAppState extends State<ChatApp> with WidgetsBindingObserver {
  late final _userRepository = FirestoreUserRepository();
  late final _threadRepository = FirestoreThreadRepository();
  late final _messageRepository = FirestoreMessageRepository();
  late final _mediaRepository = FirebaseMediaRepository();
  late final _cryptoService = ChatCryptoService();
  late final _authRepository = FirebaseAuthRepository();

  late final _presenceService = PresenceService(userRepository: _userRepository);
  late final _chatAuthService = ChatAuthService(
    authRepository: _authRepository,
    userRepository: _userRepository,
    cryptoService: _cryptoService,
  );

  late final _chatAuthCubit = ChatAuthCubit(
    authService: _chatAuthService,
    presenceService: _presenceService,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chatAuthCubit.checkSession();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      _presenceService.deactivate();
    } else if (state == AppLifecycleState.resumed) {
      _presenceService.activate();
    }
  }

  @override
  void dispose() {
    _chatAuthCubit.close();
    _presenceService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _chatAuthCubit,
      child: BlocBuilder<ChatAuthCubit, ChatAuthState>(
        builder: (context, authState) {
          if (authState is ChatAuthInitial || authState is ChatAuthLoading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (authState is! ChatAuthAuthenticated) {
            return const ChatSignInScreen();
          }

          final currentUser = authState.user;

          return MultiBlocProvider(
            providers: [
              BlocProvider(
                create: (_) => ThreadListCubit(
                  threadRepository: _threadRepository,
                  userRepository: _userRepository,
                  messageRepository: _messageRepository,
                  mediaRepository: _mediaRepository,
                  myUid: currentUser.uid,
                ),
              ),
              BlocProvider(
                create: (_) => UserLookupCubit(
                  userRepository: _userRepository,
                  threadRepository: _threadRepository,
                  myUid: currentUser.uid,
                ),
              ),
              BlocProvider(
                create: (_) => ActiveThreadCubit(
                  messageRepository: _messageRepository,
                  threadRepository: _threadRepository,
                  userRepository: _userRepository,
                  mediaRepository: _mediaRepository,
                  cryptoService: _cryptoService,
                  myUid: currentUser.uid,
                ),
              ),
            ],
            child: ChatListScreen(myUid: currentUser.uid),
          );
        },
      ),
    );
  }
}
