import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../di/chat_dependencies.dart';
import '../../application/services/chat_backup_service.dart';
import '../../application/services/chat_notification_service.dart';
import 'package:photo_vault/core/integrations/chat_vault_bridge.dart';
import 'package:photo_vault/features/vault/domain/entities/user_mode.dart';
import '../screens/chat_list_screen.dart';
import '../screens/chat_sign_in_screen.dart';
import '../widgets/chat_media_preview.dart';
import '../state/chat_auth_cubit.dart';
import '../state/thread_list_cubit.dart';
import '../state/user_lookup_cubit.dart';
import '../state/active_thread_cubit.dart';

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

  /// On-screen chat restore state (replaces the old modal popup).
  ChatBackupSnapshot? _pendingRestoreSnapshot;
  bool _restoringChat = false;
  ChatRestoreProgress? _chatRestoreProgress;

  Future<void> _ensurePrepared() async {
    if (_sessionPrepared || _preparing) return;
    _preparing = true;
    try {
      // Only run the local fresh-install check before showing chat; Drive
      // authorization is a network call and must never block opening chat
      // offline or on slow internet.
      await _deps.backupService.prepareForSession();
    } catch (_) {
      // A failed check must never lock the user out of chat.
    }
    if (!mounted) return;
    setState(() => _sessionPrepared = true);
    _preparing = false;
    unawaited(
      _deps.authRepository.warmUpDriveAuthorization().catchError((_) {}),
    );
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
      try {
        await _deps.authRepository
            .warmUpDriveAuthorization()
            .timeout(const Duration(seconds: 10));
      } catch (_) {}
      final snapshot = await backup.findLatestBackup();
      if (snapshot == null) {
        // Identity synced and still nothing readable: there is no backup.
        if (auth.identitySync != null) await backup.dismissRestoreOffer();
        return;
      }
      if (!mounted) return;
      setState(() => _pendingRestoreSnapshot = snapshot);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              'Chat backup could not be restored: '
              '${_briefBackupError(error)}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
    } finally {
      _restoreOfferInFlight = false;
    }
  }

  Future<void> _startOnScreenRestore() async {
    final snapshot = _pendingRestoreSnapshot;
    if (snapshot == null || _restoringChat) return;
    setState(() {
      _restoringChat = true;
      _chatRestoreProgress = ChatRestoreProgress(
        stage: ChatRestoreStage.restoringMessages,
        source: snapshot.source,
        done: 0,
        total: snapshot.messageCount,
      );
    });
    try {
      final restored = await _deps.backupService.restore(
        snapshot,
        onProgress: (p) {
          if (mounted) setState(() => _chatRestoreProgress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _pendingRestoreSnapshot = null;
        _restoringChat = false;
        _chatRestoreProgress = null;
        _restoreGeneration++;
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            restored == 0
                ? 'Chat backup found, but no messages needed restoring.'
                : 'Restored ${restored == 1 ? '1 chat message' : '$restored chat messages'} '
                      'from ${snapshot.source}.',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _restoringChat = false;
        _chatRestoreProgress = null;
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            'Chat backup could not be restored: '
            '${_briefBackupError(error)}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
  }

  Future<void> _skipOnScreenRestore() async {
    if (_restoringChat) return;
    await _deps.backupService.dismissRestoreOffer();
    if (!mounted) return;
    setState(() => _pendingRestoreSnapshot = null);
  }

  static String _briefBackupError(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
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
    unawaited(_deps.arrivalAlertService?.refreshArrivals());
    unawaited(_deps.savedPlacesService?.purgeExpired());
    unawaited(_deps.liveLocationService?.restore());
    if (widget.userMode == UserMode.localOnly) {
      _chatAuthCubit.markUnauthenticated();
    } else {
      _chatAuthCubit.checkSession();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Not awaited: presence writes are only acknowledged once online.
    // `inactive` is deliberately ignored: it fires for the notification shade,
    // permission dialogs and the app switcher, and treating those as leaving
    // made presence flicker offline/online and restart the heartbeat.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _deps.dataSms?.stop();
      unawaited(_deps.presenceService.deactivate().catchError(_logPresence));
    } else if (state == AppLifecycleState.resumed) {
      _deps.dataSms?.start();
      unawaited(_deps.presenceService.activate().catchError(_logPresence));
      // Delivers arrival messages queued by geofences while the app was closed.
      unawaited(_deps.arrivalAlertService?.refreshArrivals());
    }
  }

  static void _logPresence(Object error) =>
      debugPrint('Presence update failed (will retry on next change): $error');

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
          _deps.mediaLoader.setAccount(authState.user.uid);
          _deps.uploads?.start(authState.user.uid);
          _deps.dataSms?.start();
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
              try {
                unawaited(_deps.pushService.start(authState.user.uid));
              } catch (_) {
                // Firebase unavailable (tests); local notifications still work.
              }
            } else if (authState is ChatAuthUnauthenticated ||
                authState is ChatAuthError) {
              // Loading/Initial are transient: tearing down here would cancel
              // every visible attachment each time the session is re-checked.
              _deps.uploads?.stop();
              _deps.dataSms?.stop();
              _deps.mediaLoader.setAccount('');
              _deps.notificationService.stop();
              final locationService = _deps.liveLocationService;
              if (locationService?.isSharing == true) {
                unawaited(
                  locationService!.stopSharing().catchError((Object error) {
                    debugPrint(
                      'Could not stop live location on sign-out: $error',
                    );
                  }),
                );
              }
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
              if (authState is ChatAuthInitial ||
                  authState is ChatAuthLoading) {
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

              final pendingSnapshot = _pendingRestoreSnapshot;
              if (pendingSnapshot != null) {
                return _OnScreenChatRestoreView(
                  snapshot: pendingSnapshot,
                  formattedTime: _formatBackupTime(pendingSnapshot.backupAt),
                  restoring: _restoringChat,
                  progress: _chatRestoreProgress,
                  onRestore: _startOnScreenRestore,
                  onSkip: _skipOnScreenRestore,
                );
              }

              return MultiRepositoryProvider(
                key: ValueKey(_restoreGeneration),
                providers: [
                  ChangeNotifierProvider<ChatMediaLoader>.value(
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
                        dataSms: _deps.dataSms,
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
                        androidUploads: _deps.uploads,
                        dataSms: _deps.dataSms,
                        localMedia: _deps.localMedia,
                        mediaLoader: _deps.mediaLoader,
                        messageRepository: _deps.messageRepository,
                        threadRepository: _deps.threadRepository,
                        userRepository: _deps.userRepository,
                        typingRepository: _deps.typingRepository,
                        presenceRepository: _deps.presenceRepository,
                        mediaRepository: _deps.mediaRepository,
                        messageCache: _deps.messageCache,
                        searchIndex: _deps.searchIndex,
                        outbox: _deps.outbox,
                        cryptoService: _deps.cryptoService,
                        myUid: currentUser.uid,
                        connectivityStream:
                            Connectivity().onConnectivityChanged,
                        onMediaReady: _deps.mediaLoader.seed,
                      ),
                    ),
                  ],
                  child: ChatListScreen(
                    myUid: currentUser.uid,
                    profileService: _deps.profileService,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OnScreenChatRestoreView extends StatelessWidget {
  const _OnScreenChatRestoreView({
    required this.snapshot,
    required this.formattedTime,
    required this.restoring,
    required this.progress,
    required this.onRestore,
    required this.onSkip,
  });

  final ChatBackupSnapshot snapshot;
  final String formattedTime;
  final bool restoring;
  final ChatRestoreProgress? progress;
  final VoidCallback onRestore;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Restore Chats')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cs.primaryContainer,
                      ),
                      child: Icon(
                        Icons.restore_rounded,
                        size: 44,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    restoring ? 'Restoring chat history…' : 'Chat backup found',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    restoring
                        ? (progress?.message ?? 'Restoring messages…')
                        : 'A backup from $formattedTime was found on '
                              '${snapshot.source} with ${snapshot.messageCount} '
                              'messages.\n\n'
                              'If you skip, earlier messages stay hidden and '
                              'the next backup replaces this one.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (restoring) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress?.fraction,
                        minHeight: 8,
                      ),
                    ),
                  ] else ...[
                    FilledButton.icon(
                      onPressed: onRestore,
                      icon: const Icon(Icons.restore_rounded),
                      label: const Text('Restore chats'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: onSkip,
                      child: const Text('Skip'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
