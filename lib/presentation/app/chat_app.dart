import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/chat_dependencies.dart';
import '../../application/services/chat_notification_service.dart';
import '../../application/services/chat_vault_bridge.dart';
import '../../domain/entities/user_mode.dart';
import '../screens/chat_screens/chat_list_screen.dart';
import '../screens/chat_screens/chat_sign_in_screen.dart';
import '../widgets/chat/chat_media_preview.dart';
import '../state/chat/chat_auth_cubit.dart';
import '../state/chat/contact_discovery_cubit.dart';
import '../state/chat/thread_list_cubit.dart';
import '../state/chat/user_lookup_cubit.dart';
import '../state/chat/active_thread_cubit.dart';

/// Stand-alone chat app widget. Can be used as a tab inside the existing
/// vault app or as the root of its own entry-point.
class ChatApp extends StatefulWidget {
  const ChatApp({
    required this.dependencies,
    required this.vaultBridge,
    required this.userMode,
    super.key,
  });

  final ChatDependencies dependencies;

  /// Bridge to the photo vault, for attaching and saving media.
  final ChatVaultBridge vaultBridge;
  final UserMode userMode;

  @override
  State<ChatApp> createState() => _ChatAppState();
}

class _ChatAppState extends State<ChatApp> with WidgetsBindingObserver {
  ChatDependencies get _deps => widget.dependencies;

  late final _chatAuthCubit = ChatAuthCubit(
    authService: _deps.authService,
    presenceService: _deps.presenceService,
  );
  bool _didShowLocalModePrompt = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.userMode == UserMode.localOnly) {
      _chatAuthCubit.markUnauthenticated();
    } else {
      _chatAuthCubit.checkSession();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      _deps.presenceService.deactivate();
    } else if (state == AppLifecycleState.resumed) {
      _deps.presenceService.activate();
    }
  }

  @override
  void dispose() {
    _chatAuthCubit.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _chatAuthCubit,
      child: BlocListener<ChatAuthCubit, ChatAuthState>(
        listenWhen: (prev, next) => prev.runtimeType != next.runtimeType,
        listener: (context, authState) {
          // Notifications follow the signed-in session, not the widget tree, so
          // they keep working while the user is on another tab.
          if (authState is ChatAuthAuthenticated) {
            _deps.notificationService.start(authState.user.uid);
          } else {
            _deps.notificationService.stop();
          }
          if (widget.userMode != UserMode.localOnly) return;
          if (authState is ChatAuthAuthenticated) {
            _didShowLocalModePrompt = false;
            return;
          }
          if (_didShowLocalModePrompt) return;
          _didShowLocalModePrompt = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            await showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Sign in required for chat'),
                content: const Text(
                  'You are in local mode. Sign in with Google to use encrypted chat.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Not now'),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      context.read<ChatAuthCubit>().signIn();
                    },
                    child: const Text('Sign in'),
                  ),
                ],
              ),
            );
          });
        },
        child: BlocBuilder<ChatAuthCubit, ChatAuthState>(
          builder: (context, authState) {
            if (authState is ChatAuthInitial || authState is ChatAuthLoading) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (authState is! ChatAuthAuthenticated) {
              return ChatSignInScreen(isLocalMode: widget.userMode == UserMode.localOnly);
            }

            final currentUser = authState.user;

            return MultiRepositoryProvider(
              providers: [
                RepositoryProvider<ChatMediaLoader>.value(
                  value: _deps.mediaLoader,
                ),
                RepositoryProvider<ChatVaultBridge>.value(
                  value: widget.vaultBridge,
                ),
                RepositoryProvider<ChatNotificationService>.value(
                  value: _deps.notificationService,
                ),
              ],
              child: MultiBlocProvider(
                providers: [
                  BlocProvider(
                    create: (_) => ThreadListCubit(
                      threadRepository: _deps.threadRepository,
                      userRepository: _deps.userRepository,
                      messageRepository: _deps.messageRepository,
                      mediaRepository: _deps.mediaRepository,
                      presenceRepository: _deps.presenceRepository,
                      messageCache: _deps.messageCache,
                      myUid: currentUser.uid,
                    ),
                  ),
                  BlocProvider(
                    create: (_) => UserLookupCubit(
                      userRepository: _deps.userRepository,
                      threadRepository: _deps.threadRepository,
                      myUid: currentUser.uid,
                    ),
                  ),
                  BlocProvider(
                    create: (_) => ContactDiscoveryCubit(
                      service: _deps.contactDiscoveryService,
                      myUid: currentUser.uid,
                    ),
                  ),
                  BlocProvider(
                    create: (_) => ActiveThreadCubit(
                      messageRepository: _deps.messageRepository,
                      threadRepository: _deps.threadRepository,
                      userRepository: _deps.userRepository,
                      typingRepository: _deps.typingRepository,
                      presenceRepository: _deps.presenceRepository,
                      mediaRepository: _deps.mediaRepository,
                      messageCache: _deps.messageCache,
                      outbox: _deps.outbox,
                      cryptoService: _deps.cryptoService,
                      myUid: currentUser.uid,
                    ),
                  ),
                ],
                child: ChatListScreen(myUid: currentUser.uid),
              ),
            );
          },
        ),
      ),
    );
  }
}
