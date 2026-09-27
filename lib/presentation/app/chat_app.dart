import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../core/di/chat_dependencies.dart';
import '../../application/services/chat_notification_service.dart';
import '../../application/services/chat_vault_bridge.dart';
import '../../domain/entities/user_mode.dart';
import '../screens/chat_screens/chat_list_screen.dart';
import '../screens/chat_screens/chat_sign_in_screen.dart';
import '../widgets/chat/chat_media_preview.dart';
import '../state/chat/chat_auth_cubit.dart';
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
    connectivityStream: Connectivity().onConnectivityChanged,
  );
  bool _didShowLocalModePrompt = false;

  /// True once the fresh-install check has run for this session; the chat
  /// list waits for it so no server history is cached before the horizon.
  bool _sessionPrepared = false;
  bool _preparing = false;
  bool _restoreOfferInFlight = false;

  /// Bumped after a restore so the chat cubits are rebuilt from the cache.
  int _restoreGeneration = 0;

  Future<void> _ensurePrepared() async {
    if (_sessionPrepared || _preparing) return;
    _preparing = true;
    try {
      await _deps.backupService.prepareForSession();
    } catch (_) {
      // A failed check must never lock the user out of chat.
    }
    if (!mounted) return;
    setState(() => _sessionPrepared = true);
    _preparing = false;
    final state = _chatAuthCubit.state;
    if (state is ChatAuthAuthenticated) unawaited(_maybeOfferRestore(state));
  }

  /// Offers to restore a backup after a fresh install, once the identity key
  /// (needed to decrypt the backup) has been synced.
  Future<void> _maybeOfferRestore(ChatAuthAuthenticated auth) async {
    if (!_sessionPrepared || _restoreOfferInFlight) return;
    _restoreOfferInFlight = true;
    try {
      final backup = _deps.backupService;
      final pending = await backup.prepareForSession();
      if (!pending) {
        unawaited(backup.backupIfDue().then((_) {}, onError: (_) {}));
        return;
      }
      if (auth.historyLocked) return;
      final snapshot = await backup.findLatestBackup();
      if (snapshot == null) {
        // Identity synced and still nothing readable: there is no backup.
        if (auth.identitySync != null) await backup.dismissRestoreOffer();
        return;
      }
      if (!mounted) return;
      final restore = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.restore_rounded),
          title: const Text('Restore chat backup?'),
          content: Text(
            'A backup from ${_formatBackupTime(snapshot.backupAt)} was found '
            'on ${snapshot.source} with ${snapshot.messageCount} messages.\n\n'
            'If you skip, earlier messages stay hidden and the next backup '
            'replaces this one.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (restore == true) {
        await backup.restore(snapshot);
        if (!mounted) return;
        setState(() => _restoreGeneration++);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('Restored ${snapshot.messageCount} messages.')),
        );
      } else if (restore == false) {
        await backup.dismissRestoreOffer();
      }
    } catch (_) {
      // Restore is best-effort; chat keeps working without it.
    } finally {
      _restoreOfferInFlight = false;
    }
  }

  static String _formatBackupTime(DateTime at) {
    final l = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

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
    // Not awaited: presence writes are only acknowledged once online.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      unawaited(_deps.presenceService.deactivate().catchError((_) {}));
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_deps.presenceService.activate().catchError((_) {}));
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
        listenWhen: (prev, next) =>
            next is ChatAuthAuthenticated &&
            (prev is! ChatAuthAuthenticated ||
                prev.identitySync != next.identitySync),
        listener: (context, authState) {
          if (authState is! ChatAuthAuthenticated) return;
          if (_sessionPrepared) {
            unawaited(_maybeOfferRestore(authState));
          } else {
            unawaited(_ensurePrepared());
          }
        },
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
              return ChatSignInScreen(
                isLocalMode: widget.userMode == UserMode.localOnly,
              );
            }

            final currentUser = authState.user;

            if (!_sessionPrepared) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => unawaited(_ensurePrepared()),
              );
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            return MultiRepositoryProvider(
              key: ValueKey(_restoreGeneration),
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
                      connectivityStream: Connectivity().onConnectivityChanged,
                    ),
                  ),
                ],
                child: ChatListScreen(myUid: currentUser.uid),
              ),
            );
          },
        ),
      ),
      ),
    );
  }
}
