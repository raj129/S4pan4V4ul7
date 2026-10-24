import 'dart:async';
import 'dart:io';

import '../../application/media/chat_share_inbox.dart';
import '../../application/media/chat_camera_recovery.dart';
import '../../application/services/chat_privacy_maintenance.dart';
import '../../application/services/chat_backup_scheduler.dart';
import '../../application/media/android_chat_secure_media_service.dart';
import 'package:photo_vault/core/app/external_activity_guard.dart';
import 'package:file_picker/file_picker.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../application/services/live_location_service.dart';
import '../../application/services/chat_notification_service.dart';
import 'package:photo_vault/core/integrations/chat_vault_bridge.dart';
import '../../application/media/image_compressor.dart';
import '../../application/services/profile_service.dart';
import '../../data/repositories/local_sticker_pack_repository.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/message_metadata.dart';
import '../../domain/entities/chat_thread.dart';
import '../../domain/entities/chat_user.dart';
import '../../domain/entities/live_location.dart';
import '../../domain/repositories/live_location_repository.dart';
import 'package:photo_vault/features/vault/domain/repositories/settings_repository.dart';
import 'package:photo_vault/core/widgets/app_state_views.dart';
import '../state/active_thread_cubit.dart';
import '../state/thread_list_cubit.dart';
import 'package:photo_vault/core/presentation/theme/app_colors.dart';
import 'package:photo_vault/core/presentation/theme/app_spacing.dart';
import '../widgets/chat_day_divider.dart';
import '../widgets/chat_media_preview.dart';
import '../widgets/chat_scrollbar.dart';
import '../widgets/chat_wallpaper.dart';
import '../widgets/image_quality_sheet.dart';
import '../widgets/video_quality_sheet.dart';
import '../widgets/contact_info_sheet.dart';
import '../widgets/message_bubble.dart';
import '../widgets/user_avatar.dart';
import '../widgets/typing_indicator.dart';
import '../widgets/vault_picker_sheet.dart';
import '../widgets/chat_audio_recorder.dart';
import '../widgets/chat_media_picker.dart';
import 'chat_saved_attachments_screen.dart';

/// Arguments needed to build [ThreadScreen].
class ChatThreadArgs {
  const ChatThreadArgs({
    required this.thread,
    required this.otherUser,
    this.activeThreadCubit,
    this.threadListCubit,
  });

  final ChatThread thread;
  final ChatUser otherUser;
  final ActiveThreadCubit? activeThreadCubit;

  /// The `/chat/thread` route sits outside ChatApp's providers, so the list
  /// cubit (needed by Clear / Delete) is handed over explicitly.
  final ThreadListCubit? threadListCubit;
}

/// Push the thread screen via declarative routing.
Future<void> openThreadScreen(
  BuildContext context, {
  required ChatThread thread,
  required ChatUser otherUser,
  bool replace = false,
}) {
  ActiveThreadCubit? activeThread;
  try {
    activeThread = context.read<ActiveThreadCubit>();
  } catch (_) {}
  ThreadListCubit? threadList;
  try {
    threadList = context.read<ThreadListCubit>();
  } catch (_) {}
  final args = ChatThreadArgs(
    thread: thread,
    otherUser: otherUser,
    activeThreadCubit: activeThread,
    threadListCubit: threadList,
  );
  if (replace) {
    context.pushReplacement('/chat/thread', extra: args);
    return Future<void>.value();
  } else {
    return context.push('/chat/thread', extra: args);
  }
}

/// The 1:1 chat thread screen.
class ThreadScreen extends StatefulWidget {
  const ThreadScreen({
    super.key,
    required this.thread,
    required this.otherUser,
    required this.mediaLoader,
    required this.vaultBridge,
    required this.onLock,
    this.notificationService,
    this.settingsRepository,
    this.profileService,
    this.liveLocationRepository,
    this.liveLocationService,
  });

  final ChatThread thread;
  final ChatUser otherUser;

  /// Resolves the contact's nickname; without it the real name is shown.
  final ProfileService? profileService;

  /// Passed explicitly rather than read from context: this screen is pushed
  /// onto the root navigator, so it sits outside the chat providers.
  final ChatMediaLoader mediaLoader;

  /// Bridge to the photo vault, for attaching and saving media.
  final ChatVaultBridge vaultBridge;
  final VoidCallback onLock;

  /// Told which thread is on screen so it does not notify about it.
  final ChatNotificationService? notificationService;

  /// Remembers the last attachment quality the user chose.
  final SettingsRepository? settingsRepository;
  final LiveLocationRepository? liveLocationRepository;
  final LiveLocationService? liveLocationService;

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  final _textCtrl = TextEditingController();
  final _itemScrollCtrl = ItemScrollController();
  final _itemPositions = ItemPositionsListener.create();
  final _picker = ImagePicker();
  final _secureMedia = const AndroidChatSecureMediaService();
  final _uuid = const Uuid();
  final _inputFocus = FocusNode();

  bool _showEmojiPicker = false;
  bool _searching = false;
  final _searchCtrl = TextEditingController();
  ChatMessage? _editingMessage;
  bool _privacyReady = false;
  Object? _privacyError;
  final Set<String> _receiveScheduled = {};
  final Set<String> _moveRecoveryChecked = {};
  ChatCameraRecovery? _cameraRecovery;
  bool _recoveringCamera = false;
  bool _capturingCamera = false;
  final Set<String> _cameraShown = {};
  String? _stickerPackUserId;
  LocalStickerPackRepository? _stickerPackRepository;

  bool get _isEditing => _editingMessage != null;

  /// Message flashed after jumping to it from a quote.
  String? _highlightedId;

  /// Rows most recently rendered, so a message id can be mapped to an index.
  List<_ThreadItem> _items = const [];

  /// Drives the send button's reveal without rebuilding the whole composer on
  /// every keystroke.
  final _hasText = ValueNotifier<bool>(false);

  /// Viewport position in the whole cached history (0 first .. 1 latest).
  final _historyPosition = ValueNotifier<double?>(null);
  final _scrollbarVisible = ValueNotifier<bool>(false);
  final _showJumpToLatest = ValueNotifier<bool>(false);
  Timer? _scrollbarHide;
  Timer? _positionThrottle;
  StreamSubscription<Object>? _liveLocationErrorSubscription;

  /// Whether the rows in [_items] were built from a detached window.
  bool _renderedDetached = false;

  @override
  void initState() {
    super.initState();
    _inputFocus.addListener(_onInputFocusChanged);
    widget.profileService?.addListener(_onProfileChanged);
    widget.vaultBridge.vaultSessionChanges.addListener(_recoverOnVaultUnlock);
    _textCtrl.addListener(_onTextControllerChanged);
    _prepareChat();
    _itemPositions.itemPositions.addListener(_onScroll);
    widget.notificationService?.setActiveThread(widget.thread.threadId);
    _liveLocationErrorSubscription = widget.liveLocationService?.errors.listen((
      error,
    ) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Live location update failed: $error')),
      );
    });
  }

  Future<void> _prepareChat() async {
    try {
      await ChatPrivacyMaintenance.ensureClean();
      if (!mounted) return;
      context.read<ActiveThreadCubit>().openThread(
        thread: widget.thread,
        otherUser: widget.otherUser,
      );
      setState(() {
        _privacyReady = true;
        _privacyError = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<ActiveThreadCubit>().markVisibleAsRead();
        _sendSharedFiles();
      });
    } on FileSystemException catch (error) {
      if (mounted) setState(() => _privacyError = error);
    } on PlatformException catch (error) {
      if (mounted) setState(() => _privacyError = error);
    }
  }

  Future<void> _scheduleReceivedMedia(ActiveThreadLoaded state) async {
    if (!Platform.isAndroid) return;
    unawaited(_recoverCameraResults());
    unawaited(_recoverCommittedMoves(state));
    final uid = context.read<ActiveThreadCubit>().myUid;
    for (final message in state.messages) {
      if (message.senderId == uid ||
          message.isDeletedFor(uid) ||
          message.mediaRef == null ||
          (message.mediaType != MessageType.image &&
              message.mediaType != MessageType.video) ||
          !_receiveScheduled.add(message.messageId)) {
        continue;
      }

      try {
        await scheduleChatReceive(
          uid: uid,
          threadId: message.threadId,
          messageId: message.messageId,
        );
      } on PlatformException {
        _receiveScheduled.remove(message.messageId);
        debugPrint(
          'Received attachment background download could not be scheduled.',
        );
      }
    }
  }

  void _recoverOnVaultUnlock() {
    if (!mounted || !widget.vaultBridge.isUnlocked) return;
    _moveRecoveryChecked.clear();
    _cameraShown.clear();
    unawaited(_recoverCameraResults());
    final state = context.read<ActiveThreadCubit>().state;
    if (state is ActiveThreadLoaded) unawaited(_recoverCommittedMoves(state));
  }

  Future<void> _recoverCommittedMoves(ActiveThreadLoaded state) async {
    if (!Platform.isAndroid || !widget.vaultBridge.isUnlocked) return;
    final uid = context.read<ActiveThreadCubit>().myUid;
    for (final message in state.messages) {
      final ref = message.mediaRef;
      if (!mounted || !widget.vaultBridge.isUnlocked) return;
      if (ref == null ||
          message.senderId == uid ||
          !_moveRecoveryChecked.add(ref)) {
        continue;
      }
      final key = '$uid:$ref';
      void checkOwner() {
        if (!mounted || widget.mediaLoader.accountId != uid) {
          throw StateError('Chat account changed during move recovery.');
        }
      }

      try {
        // Resume only a previously recorded, user-requested move. This never
        // creates a new vault import or downloads attachment bytes.
        final result = await widget.vaultBridge.resumeMove(
          sourceId: '$uid:${message.threadId}:$ref',
          onMarkMoved: () async {
            checkOwner();
            await widget.mediaLoader.diskCache.markMoved(key);
          },
          onSourceCleanup: () async {
            checkOwner();
            await widget.mediaLoader.removeAfterVaultMove(ref);
          },
        );
        if (result?.cleanupPending == true) {
          throw StateError('Committed attachment cleanup remains pending.');
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Previous vault move needs attention. Tap Move to vault to retry.',
              ),
            ),
          );
        }
      }
    }
  }

  static const _videoExtensions = {
    'mp4',
    'mov',
    'mkv',
    'webm',
    '3gp',
    'avi',
    'm4v',
  };

  /// Sends files shared into the app from another app, once the user has
  /// picked this conversation as the destination.
  Future<void> _sendSharedFiles() async {
    final shared = ChatShareInbox.instance.take();
    if (shared.isEmpty) return;
    final cubit = context.read<ActiveThreadCubit>();
    final messenger = ScaffoldMessenger.of(context);
    bool isVideo(XFile f) {
      final dot = f.path.lastIndexOf('.');
      return dot >= 0 &&
          _videoExtensions.contains(f.path.substring(dot + 1).toLowerCase());
    }

    final images = shared.where((f) => !isVideo(f)).toList();
    final videos = shared.where(isVideo).toList();
    if (images.isNotEmpty) await _sendImages(cubit, images, messenger);
    for (final video in videos) {
      if (!mounted) return;
      if (await video.length() > ActiveThreadCubit.maxAttachmentBytes) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Attachments must be smaller than 64 MB.'),
          ),
        );
        continue;
      }
      final bytes = Uint8List.fromList(await video.readAsBytes());
      try {
        if (!mounted) return;
        await cubit.sendMedia(
          messageId: _uuid.v4(),
          rawBytes: bytes,
          type: MessageType.video,
          sourceUri: _originalSourceUri(video),
        );
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    }
  }

  void _onTextControllerChanged() {
    _hasText.value = _textCtrl.text.trim().isNotEmpty;
  }

  void _onScroll() {
    final positions = _itemPositions.itemPositions.value;
    if (positions.isEmpty) return;
    final cubit = context.read<ActiveThreadCubit>();
    final indexes = positions.map((p) => p.index);
    final furthest = indexes.reduce((a, b) => a > b ? a : b);
    final nearest = indexes.reduce((a, b) => a < b ? a : b);
    // The list is reversed, so the highest index is the oldest row on screen.
    if (furthest >= _items.length - 3) {
      cubit.loadOlderMessages();
    }
    final state = cubit.state;
    final detached = state is ActiveThreadLoaded && state.isDetached;
    // A detached window pages newer history in as the bottom is approached.
    if (detached && nearest <= 3) cubit.loadNewerMessages();
    _showJumpToLatest.value = detached || nearest > 12;
    _scrollbarVisible.value = true;
    _scrollbarHide?.cancel();
    _scrollbarHide = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) _scrollbarVisible.value = false;
    });
    _scheduleHistoryPosition((nearest + furthest) ~/ 2);
    // Scrolling reveals older messages, which are now read too.
    cubit.markVisibleAsRead();
  }

  /// Refresh the scrollbar thumb from the message around [index], throttled
  /// because it is a (cheap, indexed) database count.
  void _scheduleHistoryPosition(int index) {
    if (_positionThrottle?.isActive ?? false) return;
    _positionThrottle = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted || _items.isEmpty) return;
      ChatMessage? msg;
      for (var i = index.clamp(0, _items.length - 1); i < _items.length; i++) {
        msg = _items[i].message;
        if (msg != null) break;
      }
      if (msg == null) return;
      final pos = await context.read<ActiveThreadCubit>().positionOf(msg);
      if (mounted && pos != null) _historyPosition.value = pos;
    });
  }

  void _onProfileChanged() {
    if (mounted) setState(() {});
  }

  /// The contact's name as this user has chosen to see it.
  String _nameOf(ChatUser user) =>
      widget.profileService?.nameFor(user) ?? user.displayName;

  void _onInputFocusChanged() {
    if (_inputFocus.hasFocus && _showEmojiPicker && mounted) {
      setState(() => _showEmojiPicker = false);
    }
  }

  @override
  void dispose() {
    _inputFocus.removeListener(_onInputFocusChanged);
    widget.profileService?.removeListener(_onProfileChanged);
    widget.vaultBridge.vaultSessionChanges.removeListener(
      _recoverOnVaultUnlock,
    );
    widget.notificationService?.setActiveThread(null);
    _textCtrl.removeListener(_onTextControllerChanged);
    _itemPositions.itemPositions.removeListener(_onScroll);
    _scrollbarHide?.cancel();
    _positionThrottle?.cancel();
    unawaited(_liveLocationErrorSubscription?.cancel());
    _historyPosition.dispose();
    _scrollbarVisible.dispose();
    _showJumpToLatest.dispose();
    _hasText.dispose();
    _textCtrl.dispose();
    _searchCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_privacyReady) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: Center(
          child: _privacyError == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Could not remove old unencrypted chat copies.'),
                    TextButton(
                      onPressed: _prepareChat,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
        ),
      );
    }
    return MultiBlocListener(
      listeners: [
        BlocListener<ActiveThreadCubit, ActiveThreadState>(
          listener: (context, state) {
            if (state is ActiveThreadLoaded) {
              unawaited(_scheduleReceivedMedia(state));
            }
          },
        ),
        BlocListener<ActiveThreadCubit, ActiveThreadState>(
          listenWhen: (prev, next) {
            final prevErr = prev is ActiveThreadLoaded
                ? prev.actionError
                : null;
            final nextErr = next is ActiveThreadLoaded
                ? next.actionError
                : null;
            return nextErr != null && nextErr != prevErr;
          },
          listener: (context, state) {
            final message = (state as ActiveThreadLoaded).actionError!;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(message)));
            context.read<ActiveThreadCubit>().clearActionError();
          },
        ),
        BlocListener<ActiveThreadCubit, ActiveThreadState>(
          listenWhen: (prev, next) =>
              next is ActiveThreadLoaded &&
              next.scrollRequest != null &&
              (prev is! ActiveThreadLoaded ||
                  prev.scrollRequest != next.scrollRequest),
          listener: (context, state) {
            final request = (state as ActiveThreadLoaded).scrollRequest!;
            // Wait for the list to rebuild with the window the cubit loaded,
            // otherwise the target row would not exist yet.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _performScroll(request);
            });
          },
        ),
        BlocListener<ActiveThreadCubit, ActiveThreadState>(
          listenWhen: (prev, next) =>
              prev is ActiveThreadLoaded &&
              next is ActiveThreadLoaded &&
              !identical(prev.messages, next.messages) &&
              prev.scrollRequest == next.scrollRequest,
          listener: (context, state) => _keepAnchor(),
        ),
      ],
      child: Scaffold(
        appBar: _buildAppBar(context),
        body: Column(
          children: [
            Expanded(
              child: ChatWallpaper(
                child: Column(
                  children: [
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned.fill(child: _buildMessageList()),
                          Positioned(
                            top: AppSpacing.sm,
                            bottom: AppSpacing.sm,
                            right: 0,
                            width: 200,
                            child: ChatScrollbar(
                              position: _historyPosition,
                              visible: _scrollbarVisible,
                              dateAt: context
                                  .read<ActiveThreadCubit>()
                                  .dateAtFraction,
                              onJump: context
                                  .read<ActiveThreadCubit>()
                                  .jumpToFraction,
                            ),
                          ),
                          _buildLoadingNewer(),
                          _buildJumpToLatest(),
                        ],
                      ),
                    ),
                    _buildTypingBanner(),
                  ],
                ),
              ),
            ),
            _buildOfflineBanner(),
            _buildComposerSurface(context),
            _buildEmojiPicker(),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineBanner() {
    return BlocBuilder<ActiveThreadCubit, ActiveThreadState>(
      buildWhen: (previous, current) =>
          previous is ActiveThreadLoaded &&
          current is ActiveThreadLoaded &&
          previous.isOffline != current.isOffline,
      builder: (context, state) {
        final isOffline = state is ActiveThreadLoaded ? state.isOffline : false;
        return AnimatedSize(
          duration: AppDuration.normal,
          curve: Curves.easeOut,
          child: isOffline
              ? Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'You are offline. Messages will send when connected.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    if (_searching) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _stopSearch,
        ),
        title: TextField(
          controller: _searchCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search this chat',
            border: InputBorder.none,
          ),
          onChanged: (v) => context.read<ActiveThreadCubit>().setSearchQuery(v),
        ),
        actions: [
          BlocBuilder<ActiveThreadCubit, ActiveThreadState>(
            buildWhen: (prev, next) =>
                prev is! ActiveThreadLoaded ||
                next is! ActiveThreadLoaded ||
                prev.searchMatchIds != next.searchMatchIds ||
                prev.currentMatchId != next.currentMatchId ||
                prev.searchInProgress != next.searchInProgress ||
                prev.indexingProgress != next.indexingProgress ||
                prev.searchQuery != next.searchQuery,
            builder: (context, state) {
              if (state is! ActiveThreadLoaded || !state.isSearching) {
                return const SizedBox.shrink();
              }
              final cubit = context.read<ActiveThreadCubit>();
              final total = state.searchMatchIds.length;
              final index = state.currentMatchIndex;
              final String label;
              if (state.searchInProgress && index < 0) {
                label = '…';
              } else if (total == 0) {
                label = 'No results';
              } else {
                label = '${index + 1} of $total';
              }
              final indexing = state.indexingProgress;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (indexing != null) ...[
                    Tooltip(
                      message: 'Indexing older messages…',
                      child: SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: indexing,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
                  IconButton(
                    tooltip: 'Older match',
                    icon: const Icon(Icons.keyboard_arrow_up_rounded),
                    onPressed: index >= 0 && index < total - 1
                        ? cubit.nextMatch
                        : null,
                  ),
                  IconButton(
                    tooltip: 'Newer match',
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    onPressed: index > 0 ? cubit.previousMatch : null,
                  ),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              _searchCtrl.clear();
              context.read<ActiveThreadCubit>().clearSearch();
            },
          ),
        ],
      );
    }
    return AppBar(
      leadingWidth: 40,
      actions: [
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'search') {
              setState(() => _searching = true);
            } else if (value == 'date') {
              _pickJumpDate();
            } else if (value == 'clear') {
              _confirmClearMessages(context);
            } else if (value == 'delete') {
              _confirmDeleteThread(context);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'search', child: Text('Search this chat')),
            PopupMenuItem(value: 'date', child: Text('Jump to date')),
            PopupMenuItem(value: 'clear', child: Text('Clear messages')),
            PopupMenuItem(value: 'delete', child: Text('Delete thread')),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.lock_outline_rounded),
          tooltip: 'Lock vault',
          onPressed: widget.onLock,
        ),
      ],
      title: BlocBuilder<ActiveThreadCubit, ActiveThreadState>(
        builder: (context, state) {
          final online = state is ActiveThreadLoaded
              ? state.otherIsOnline
              : false;
          final theme = Theme.of(context);
          final semantic = context.semantic;
          final presence = online ? semantic.online : semantic.offline;
          final header = Row(
            children: [
              _PresenceAvatar(
                user: widget.otherUser,
                name: _nameOf(widget.otherUser),
                online: online,
                ringColor: presence,
              ),
              const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _nameOf(widget.otherUser),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    AnimatedDefaultTextStyle(
                      duration: AppDuration.normal,
                      style:
                          theme.textTheme.labelSmall?.copyWith(
                            color: presence,
                            fontWeight: FontWeight.w500,
                          ) ??
                          TextStyle(color: presence),
                      child: Text(online ? 'Online' : 'Offline'),
                    ),
                  ],
                ),
              ),
            ],
          );
          final service = widget.profileService;
          if (service == null) return header;
          return InkWell(
            onTap: () => showContactInfoSheet(
              context,
              profileService: service,
              user: widget.otherUser,
            ),
            child: header,
          );
        },
      ),
    );
  }

  void _stopSearch() {
    _searchCtrl.clear();
    context.read<ActiveThreadCubit>().clearSearch();
    setState(() => _searching = false);
  }

  void _cancelEdit() {
    if (!_isEditing) return;
    setState(() {
      _editingMessage = null;
      _textCtrl.clear();
      _hasText.value = false;
      _showEmojiPicker = false;
      _inputFocus.unfocus();
    });
  }

  Future<void> _commitEdit() async {
    final msg = _editingMessage;
    if (msg == null || !_isEditing) return;
    final edited = _textCtrl.text.trim();
    if (edited.isEmpty) {
      _cancelEdit();
      return;
    }
    final cubit = context.read<ActiveThreadCubit>();
    await cubit.editMessage(msg, edited);
    if (!mounted) return;
    _cancelEdit();
  }

  Widget _buildMessageList() {
    return BlocBuilder<ActiveThreadCubit, ActiveThreadState>(
      // Typing, presence, composer and indexing emissions do not change any
      // row, so skip rebuilding (and re-grouping) the whole list for them.
      buildWhen: (prev, next) {
        if (prev is! ActiveThreadLoaded || next is! ActiveThreadLoaded) {
          return true;
        }
        return !identical(prev.messages, next.messages) ||
            prev.isOffline != next.isOffline ||
            prev.uploadProgress != next.uploadProgress ||
            prev.currentMatchId != next.currentMatchId ||
            prev.searchQuery != next.searchQuery ||
            !identical(prev.searchMatchIds, next.searchMatchIds) ||
            prev.hasMore != next.hasMore ||
            prev.isDetached != next.isDetached;
      },
      builder: (context, state) {
        if (state is ActiveThreadLoading) {
          return const LoadingView(message: 'Decrypting messages…');
        }
        if (state is ActiveThreadError) {
          return ErrorView(message: state.message);
        }
        if (state is! ActiveThreadLoaded) return const SizedBox.shrink();

        final msgs = state.visibleMessages;
        if (msgs.isEmpty) {
          _items = const [];
          return EmptyView(
            icon: Icons.waving_hand_outlined,
            title: 'No messages yet',
            subtitle:
                'Say hello to ${_nameOf(widget.otherUser)} — everything you '
                'send is end-to-end encrypted.',
          );
        }

        final cubit = context.read<ActiveThreadCubit>();
        final myUid = cubit.myUid;

        final showPagingSpinner = state.hasMore;
        final items = _buildThreadItems(msgs, withDayDividers: true);
        _items = items;
        _renderedDetached = state.isDetached;
        final matchIds = state.searchMatchIds.toSet();

        return ScrollablePositionedList.builder(
          itemScrollController: _itemScrollCtrl,
          itemPositionsListener: _itemPositions,
          reverse: true,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          itemCount: items.length + (showPagingSpinner ? 1 : 0),
          itemBuilder: (context, i) {
            if (i == items.length) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }

            final item = items[i];
            if (item.divider != null) {
              return ChatDayDivider(date: item.divider!);
            }

            final msg = item.message!;
            final isMine = msg.senderId == myUid;
            return MessageBubble(
              key: ValueKey(msg.messageId),
              message: msg,
              isMine: isMine,
              myUid: myUid,
              otherUid: widget.otherUser.uid,
              isOffline: state.isOffline,
              mediaLoader: widget.mediaLoader,
              liveLocationRepository: widget.liveLocationRepository,
              onStopLiveLocation: _stopLiveLocation,
              sendStatus: state.uploadProgress[msg.messageId],
              onPauseUpload: () => cubit.pauseUpload(msg.messageId),
              onResumeUpload: () => cubit.resumeUpload(msg.messageId),
              onCancelUpload: state.uploadProgress[msg.messageId] == null
                  ? null
                  : () async {
                      HapticFeedback.selectionClick();
                      await cubit.cancelUpload(msg.messageId);
                    },
              isHighlighted:
                  _highlightedId == msg.messageId ||
                  state.currentMatchId == msg.messageId,
              highlightQuery: matchIds.contains(msg.messageId)
                  ? state.searchQuery
                  : '',
              isFirstInGroup: item.isFirstInGroup,
              isLastInGroup: item.isLastInGroup,
              onReply: () {
                cubit.setReplyTarget(msg);
                _inputFocus.requestFocus();
              },
              onReact: (emoji) => cubit.toggleReaction(msg, emoji),
              // Always wired up for own, non-media messages — eligibility
              // (30-minute / edited-before-read rule) is checked once,
              // centrally, inside `_promptEdit`, so both the long-press menu
              // entry and the Signal-style double-tap give the same
              // accept/reject behaviour instead of silently disappearing.
              onEdit:
                  isMine &&
                      !msg.isMedia &&
                      msg.mediaType != MessageType.liveLocation &&
                      cubit.canEditMessage(msg)
                  ? () => _promptEdit(msg)
                  : null,
              onCopy: msg.localDecryptedText?.trim().isNotEmpty == true
                  ? () => _copyMessage(msg.localDecryptedText!)
                  : null,
              canReplyFromLeftToRight: true,
              onTapQuote: _jumpToMessage,
              onSaveToVault: msg.isMedia && msg.senderId != cubit.myUid
                  ? () => _saveToVault(msg)
                  : null,
              onSaveAsSticker:
                  msg.mediaRef != null &&
                      state.uploadProgress[msg.messageId] == null &&
                      const {
                        MessageType.image,
                        MessageType.gif,
                        MessageType.sticker,
                      }.contains(msg.mediaType)
                  ? () => unawaited(_saveAsSticker(msg, cubit))
                  : null,
              onForward: msg.mediaType == MessageType.liveLocation
                  ? null
                  : () => _promptForward(msg),
              onRetry: msg.status == MessageStatus.failed
                  ? () => cubit.retryMessage(msg.messageId)
                  : null,
              onDiscard: msg.status == MessageStatus.failed
                  ? () => cubit.discardMessage(msg.messageId)
                  : null,
              onDeleteForMe: () => _confirmDeleteForMe(msg),
              onDeleteForEveryone: isMine
                  ? () => _confirmDeleteForEveryone(msg)
                  : null,
            );
          },
        );
      },
    );
  }

  /// Longest gap between two messages from the same sender that still reads as
  /// one continuous run.
  static const _groupWindow = Duration(minutes: 5);

  /// Flatten [msgs] into renderable rows, newest first to match `reverse: true`.
  ///
  /// Because the list is reversed, `index + 1` is the *older* neighbour and
  /// `index - 1` is the *newer* one — grouping and day dividers both read in
  /// that direction.
  List<_ThreadItem> _buildThreadItems(
    List<ChatMessage> msgs, {
    required bool withDayDividers,
  }) {
    final items = <_ThreadItem>[];

    for (var i = 0; i < msgs.length; i++) {
      final msg = msgs[i];
      final older = i + 1 < msgs.length ? msgs[i + 1] : null;
      final newer = i > 0 ? msgs[i - 1] : null;

      final startsDay = older == null || !_sameDay(older.sentAt, msg.sentAt);

      items.add(
        _ThreadItem.message(
          msg,
          // A day divider always breaks a run.
          isFirstInGroup: startsDay || !_sameRun(older, msg),
          isLastInGroup: !_sameRun(msg, newer),
        ),
      );

      // Appended *after* the message so the reversed list draws it above.
      if (withDayDividers && startsDay) {
        items.add(_ThreadItem.divider(msg.sentAt));
      }
    }

    return items;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Whether [earlier] and [later] belong to the same visual run.
  static bool _sameRun(ChatMessage? earlier, ChatMessage? later) {
    if (earlier == null || later == null) return false;
    if (earlier.senderId != later.senderId) return false;
    if (!_sameDay(earlier.sentAt, later.sentAt)) return false;
    return later.sentAt.difference(earlier.sentAt).abs() <= _groupWindow;
  }

  /// Scroll to a quoted message and flash it, loading it (with its
  /// surrounding conversation) from local history if it is not on screen.
  Future<void> _jumpToMessage(String messageId) async {
    final found = await context.read<ActiveThreadCubit>().jumpToMessage(
      messageId,
    );
    if (!mounted) return;
    if (!found) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Original message is not on this device.'),
        ),
      );
      return;
    }
    setState(() => _highlightedId = messageId);
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && _highlightedId == messageId) {
        setState(() => _highlightedId = null);
      }
    });
  }

  /// Honour a scroll request from the cubit (search match, quote, date,
  /// scrollbar or jump-to-latest).
  void _performScroll(ChatScrollRequest request) {
    if (!_itemScrollCtrl.isAttached) return;
    final id = request.messageId;
    if (id == null) {
      _itemScrollCtrl.jumpTo(index: 0);
      _showJumpToLatest.value = false;
      return;
    }
    final index = _items.indexWhere((i) => i.message?.messageId == id);
    if (index < 0) return;
    final positions = _itemPositions.itemPositions.value;
    final near = positions.any((p) => (p.index - index).abs() < 30);
    if (near) {
      _itemScrollCtrl.scrollTo(
        index: index,
        alignment: 0.4,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      // Animating across a freshly loaded window would flash every message
      // in between; land on the target directly instead.
      _itemScrollCtrl.jumpTo(index: index, alignment: 0.4);
    }
  }

  /// Keep the message under the viewport still when rows are inserted or
  /// dropped below it (newer paging, trimming, arrivals while scrolled up).
  void _keepAnchor() {
    if (!_itemScrollCtrl.isAttached) return;
    final positions = _itemPositions.itemPositions.value.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    if (positions.isEmpty) return;
    // Pinned to the latest message: let new messages scroll into view.
    if (positions.first.index == 0 && !_renderedDetached) return;
    ItemPosition? anchor;
    String? anchorId;
    for (final p in positions) {
      if (p.index < _items.length && _items[p.index].message != null) {
        anchor = p;
        anchorId = _items[p.index].message!.messageId;
        break;
      }
    }
    if (anchor == null || anchorId == null) return;
    final oldIndex = anchor.index;
    final leadingEdge = anchor.itemLeadingEdge;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_itemScrollCtrl.isAttached) return;
      final newIndex = _items.indexWhere(
        (i) => i.message?.messageId == anchorId,
      );
      if (newIndex < 0 || newIndex == oldIndex) return;
      _itemScrollCtrl.jumpTo(index: newIndex, alignment: leadingEdge);
    });
  }

  Future<void> _pickJumpDate() async {
    final cubit = context.read<ActiveThreadCubit>();
    final bounds = await cubit.historyBounds();
    if (!mounted) return;
    if (bounds == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No messages saved on this device yet.')),
      );
      return;
    }
    final first = bounds.$1.toLocal();
    final last = bounds.$2.toLocal();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(first.year, first.month, first.day),
      lastDate: DateTime(last.year, last.month, last.day),
      initialDate: DateTime(last.year, last.month, last.day),
      helpText: 'Jump to date',
    );
    if (picked == null || !mounted) return;
    final found = await cubit.jumpToDate(picked);
    if (!found && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No messages around that date.')),
      );
    }
  }

  /// Spinner shown while a detached window pages newer messages in.
  Widget _buildLoadingNewer() {
    // Always positioned: a non-positioned Stack child would size the Stack.
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: BlocBuilder<ActiveThreadCubit, ActiveThreadState>(
        buildWhen: (prev, next) =>
            prev is! ActiveThreadLoaded ||
            next is! ActiveThreadLoaded ||
            prev.loadingNewer != next.loadingNewer,
        builder: (context, state) {
          final loading = state is ActiveThreadLoaded && state.loadingNewer;
          if (!loading) return const SizedBox.shrink();
          return const LinearProgressIndicator(minHeight: 2);
        },
      ),
    );
  }

  /// WhatsApp-style "scroll to latest" button with a badge for messages
  /// that arrived while viewing older history.
  Widget _buildJumpToLatest() {
    return Positioned(
      right: AppSpacing.md,
      bottom: AppSpacing.md,
      child: BlocBuilder<ActiveThreadCubit, ActiveThreadState>(
        buildWhen: (prev, next) =>
            prev is! ActiveThreadLoaded ||
            next is! ActiveThreadLoaded ||
            prev.isDetached != next.isDetached ||
            prev.newWhileDetached != next.newWhileDetached,
        builder: (context, state) {
          final loaded = state is ActiveThreadLoaded ? state : null;
          return ValueListenableBuilder<bool>(
            valueListenable: _showJumpToLatest,
            builder: (context, show, _) {
              final visible = (loaded?.isDetached ?? false) || show;
              final count = loaded?.newWhileDetached ?? 0;
              return AnimatedScale(
                scale: visible ? 1 : 0,
                duration: AppDuration.normal,
                child: Badge(
                  isLabelVisible: count > 0,
                  label: Text('$count'),
                  child: FloatingActionButton.small(
                    heroTag: null,
                    tooltip: 'Scroll to latest',
                    onPressed: visible
                        ? context.read<ActiveThreadCubit>().jumpToLatest
                        : null,
                    child: const Icon(Icons.keyboard_double_arrow_down_rounded),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmClearMessages(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear messages'),
        content: const Text(
          'Remove every message from your view of this chat? '
          'The other person will not be affected and can still see them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (_searching) _stopSearch();
    final threadList = this.context.read<ThreadListCubit>();
    final activeThread = this.context.read<ActiveThreadCubit>();
    await threadList.clearThread(widget.thread.threadId);
    if (!mounted) return;
    await activeThread.openThread(
      thread: widget.thread,
      otherUser: widget.otherUser,
    );
  }

  Future<void> _confirmDeleteThread(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete thread'),
        content: const Text(
          'Delete this conversation and all its messages? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final threadList = this.context.read<ThreadListCubit>();
    final navigator = Navigator.of(this.context);
    await threadList.deleteThread(widget.thread.threadId);
    if (!mounted) return;
    navigator.pop();
  }

  Future<void> _promptEdit(ChatMessage msg) async {
    final cubit = context.read<ActiveThreadCubit>();
    final messenger = ScaffoldMessenger.of(context);
    if (!cubit.canEditMessage(msg)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('This message can no longer be edited.')),
      );
      return;
    }
    final text = msg.localDecryptedText ?? '';
    context.read<ActiveThreadCubit>().clearReplyTarget();
    setState(() {
      _editingMessage = msg;
      _textCtrl.text = text;
      _textCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _textCtrl.text.length),
      );
      _showEmojiPicker = false;
      _hasText.value = _textCtrl.text.trim().isNotEmpty;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocus.requestFocus();
    });
  }

  /// "Delete for me" only ever needs a lightweight confirmation since it is
  /// non-destructive to the other participant, but it still goes through the
  /// screen's own stable [context] (never a per-row context) for the same
  /// reason `_promptEdit` does — a `showDialog` awaiting a per-row context
  /// can outlive that context if the list rebuilds mid-dialog.
  Future<void> _confirmDeleteForMe(ChatMessage msg) async {
    final cubit = context.read<ActiveThreadCubit>();
    final state = cubit.state;
    final pending =
        state is ActiveThreadLoaded &&
        state.uploadProgress.containsKey(msg.messageId);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete message'),
        content: Text(
          pending
              ? 'Cancel this upload and delete the pending message and its temporary files?'
              : 'Remove this message from your copy of the chat? '
                    'The other person will still see it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _stopOwnLiveLocationBeforeDelete(msg, cubit);
      await cubit.deleteMessageForMe(msg);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete message: $error')),
        );
      }
    }
  }

  /// "Delete for everyone" is destructive and irreversible, so it gets a
  /// distinct, more explicit confirmation (mirroring Signal/WhatsApp), again
  /// routed through the screen's stable [context].
  Future<void> _confirmDeleteForEveryone(ChatMessage msg) async {
    final cubit = context.read<ActiveThreadCubit>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete for everyone'),
        content: const Text(
          'This message will be deleted for everyone in this chat. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete for everyone'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _stopOwnLiveLocationBeforeDelete(msg, cubit);
      await cubit.deleteMessageForEveryone(msg);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete message: $error')),
        );
      }
    }
  }

  Future<void> _stopOwnLiveLocationBeforeDelete(
    ChatMessage message,
    ActiveThreadCubit cubit,
  ) async {
    final sessionId = message.liveLocationSessionId;
    if (message.mediaType != MessageType.liveLocation ||
        message.senderId != cubit.myUid ||
        sessionId == null) {
      return;
    }
    await _stopLiveLocation(message.threadId, message.senderId, sessionId);
  }

  /// Pick a conversation and re-send the message into it.
  Future<void> _promptForward(ChatMessage message) async {
    final cubit = context.read<ActiveThreadCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final targets = await cubit.loadForwardTargets();
    if (!mounted) return;
    if (targets.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No other conversations to forward to.')),
      );
      return;
    }

    final chosen = await showModalBottomSheet<ForwardTarget>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'Forward to',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            for (final target in targets)
              ListTile(
                leading: UserAvatar(
                  avatar: target.user.avatar,
                  name: _nameOf(target.user),
                ),
                title: Text(_nameOf(target.user)),
                onTap: () => Navigator.pop(sheetContext, target),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;

    await cubit.forwardMessage(
      message,
      targetThreadId: chosen.thread.threadId,
      targetRecipientUid: chosen.user.uid,
    );
    messenger.showSnackBar(
      SnackBar(content: Text('Forwarded to ${_nameOf(chosen.user)}.')),
    );
  }

  Widget _buildTypingBanner() {
    return BlocBuilder<ActiveThreadCubit, ActiveThreadState>(
      buildWhen: (prev, next) {
        final prevTyping = prev is ActiveThreadLoaded
            ? prev.otherIsTyping
            : false;
        final nextTyping = next is ActiveThreadLoaded
            ? next.otherIsTyping
            : false;
        return prevTyping != nextTyping;
      },
      builder: (context, state) {
        final typing = state is ActiveThreadLoaded
            ? state.otherIsTyping
            : false;
        return TypingIndicator(visible: typing);
      },
    );
  }

  /// Quote strip shown above the composer while a reply is staged.
  Widget _buildReplyPreview() {
    return BlocBuilder<ActiveThreadCubit, ActiveThreadState>(
      buildWhen: (prev, next) {
        final prevTarget = prev is ActiveThreadLoaded ? prev.replyTarget : null;
        final nextTarget = next is ActiveThreadLoaded ? next.replyTarget : null;
        return prevTarget != nextTarget;
      },
      builder: (context, state) {
        final target = state is ActiveThreadLoaded ? state.replyTarget : null;
        if (target == null) return const SizedBox.shrink();

        final cs = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        final myUid = context.read<ActiveThreadCubit>().myUid;
        final preview = target.isMedia
            ? target.mediaPreview
            : (target.localDecryptedText ?? '');

        return Container(
          margin: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.sm,
            0,
          ),
          padding: const EdgeInsets.only(left: AppSpacing.sm),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: AppRadius.all(AppRadius.md),
            border: Border(left: BorderSide(color: cs.primary, width: 3)),
          ),
          child: Row(
            children: [
              Icon(Icons.reply_rounded, size: 18, color: cs.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        target.senderId == myUid
                            ? 'Replying to yourself'
                            : 'Replying to ${_nameOf(widget.otherUser)}',
                        style: textTheme.labelSmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'Cancel reply',
                onPressed: () =>
                    context.read<ActiveThreadCubit>().clearReplyTarget(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEditHeader() {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Text(
            'Edit message',
            style: textTheme.titleSmall?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Cancel edit',
            onPressed: _cancelEdit,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  /// The composer surface: reply strip + edit header + input bar sharing one
  /// elevated plane.
  Widget _buildComposerSurface(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isEditing) _buildEditHeader(),
          if (!_isEditing) _buildReplyPreview(),
          _buildInputBar(context),
        ],
      ),
    );
  }

  Widget _buildInputBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      // The picker supplies its own bottom inset when open.
      bottom: !_showEmojiPicker,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Emoji, attach and the field share one pill so the composer reads
            // as a single control rather than three loose widgets.
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: AppRadius.all(AppRadius.pill),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _ComposerAction(
                      icon: _showEmojiPicker
                          ? Icons.keyboard_outlined
                          : Icons.emoji_emotions_outlined,
                      tooltip: _showEmojiPicker
                          ? 'Keyboard'
                          : 'Emoji, stickers, and GIFs',
                      onPressed: _toggleEmojiPicker,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _textCtrl,
                        focusNode: _inputFocus,
                        maxLines: 5,
                        minLines: 1,
                        textCapitalization: TextCapitalization.sentences,
                        style: Theme.of(context).textTheme.bodyLarge,
                        onTap: () {
                          if (_showEmojiPicker) {
                            setState(() => _showEmojiPicker = false);
                          }
                        },
                        decoration: InputDecoration(
                          hintText: _isEditing ? 'Edit message' : 'Message',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.md,
                          ),
                          hintStyle: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        onChanged: (v) {
                          if (_isEditing) {
                            _hasText.value = v.trim().isNotEmpty;
                            return;
                          }
                          context.read<ActiveThreadCubit>().onTextChanged(v);
                        },
                      ),
                    ),
                    _ComposerAction(
                      icon: Icons.attach_file_rounded,
                      tooltip: 'Attach',
                      onPressed: () => _pickMedia(context),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _SendButton(
              hasText: _hasText,
              onSend: _isEditing ? _commitEdit : _send,
              icon: _isEditing ? Icons.check_rounded : Icons.send_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyMessage(String text) async {
    await Clipboard.setData(ClipboardData(text: text.trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Message copied')));
  }

  ChatCameraRecovery _cameraService(ActiveThreadCubit cubit) =>
      _cameraRecovery ??= ChatCameraRecovery(
        crypto: cubit.cryptoService,
        currentUid: () => widget.mediaLoader.accountId,
      );

  Future<void> _saveAsSticker(
    ChatMessage message,
    ActiveThreadCubit cubit,
  ) async {
    final storagePath = message.mediaRef;
    if (storagePath == null) return;
    Uint8List? bytes;
    try {
      bytes = await widget.mediaLoader.fetchUncached(
        threadId: message.threadId,
        storagePath: storagePath,
        senderId: message.senderId,
      );
      final extension = _stickerExtension(bytes);
      await _stickerPackFor(
        cubit.myUid,
      ).addSticker(bytes: bytes, extension: extension, label: 'Chat sticker');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Added to My stickers')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save sticker: $error')),
        );
      }
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
    }
  }

  String _stickerExtension(Uint8List bytes) {
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return 'gif';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'webp';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'jpg';
    }
    throw const FormatException(
      'Only GIF, WebP, PNG, or JPEG images can be saved as stickers.',
    );
  }

  Future<void> _deleteOwnedCameraCopy(XFile source) async {
    final file = File(source.path);
    if (!await file.exists()) return;
    final root = await (await getTemporaryDirectory()).resolveSymbolicLinks();
    final resolved = await file.resolveSymbolicLinks();
    if (p.isWithin(root, resolved)) await file.delete();
  }

  Future<void> _persistCameraResult(
    ChatCameraRecovery recovery,
    String uid,
    String thread,
    String id,
    XFile file,
  ) async {
    Uint8List? bytes;
    try {
      if (await file.length() > ActiveThreadCubit.maxAttachmentBytes) {
        throw StateError('Captured photo is larger than 64 MB.');
      }
      bytes = await file.readAsBytes();
      await recovery.save(uid, thread, id, bytes);
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      await _deleteOwnedCameraCopy(file);
    }
  }

  Future<void> _captureExternalCamera(ActiveThreadCubit cubit) async {
    final recovery = _cameraService(cubit);
    final uid = cubit.myUid;
    final thread = widget.thread.threadId;
    final id = _uuid.v4();
    final messenger = ScaffoldMessenger.of(context);
    _capturingCamera = true;
    try {
      await recovery.begin(uid, thread, id);
      final file = await ExternalActivityGuard.run(
        () => _picker.pickImage(source: ImageSource.camera),
      );
      if (file == null) {
        await recovery.endIntent(uid, thread);
      } else {
        // Persist before checking mounted: locking may have disposed this route.
        await _persistCameraResult(recovery, uid, thread, id, file);
      }
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not recover captured photo: $error')),
        );
      } else {
        debugPrint('Chat camera capture recovery failed.');
      }
    } finally {
      _capturingCamera = false;
    }
    if (mounted) await _recoverCameraResults();
  }

  Future<void> _recoverCameraResults() async {
    if (!mounted ||
        !Platform.isAndroid ||
        _recoveringCamera ||
        _capturingCamera ||
        !widget.vaultBridge.isUnlocked) {
      return;
    }
    final cubit = context.read<ActiveThreadCubit>();
    if (cubit.state is! ActiveThreadLoaded) return;
    final recovery = _cameraService(cubit);
    final uid = cubit.myUid;
    final thread = widget.thread.threadId;
    _recoveringCamera = true;
    try {
      final intent = await recovery.intent(uid, thread);
      if (intent != null) {
        final lost = await _picker.retrieveLostData();
        if (lost.exception != null) throw lost.exception!;
        final files = lost.files;
        if (files != null && files.isNotEmpty) {
          await _persistCameraResult(
            recovery,
            uid,
            thread,
            intent,
            files.first,
          );
        } else {
          await recovery.endIntent(uid, thread);
        }
      }
      for (final id in await recovery.pending(uid, thread)) {
        if (!mounted || !widget.vaultBridge.isUnlocked) return;
        final state = cubit.state;
        if ((state is ActiveThreadLoaded &&
                state.messages.any(
                  (message) =>
                      message.messageId == id &&
                      message.status != MessageStatus.sending &&
                      message.status != MessageStatus.failed,
                )) ||
            cubit.androidUploads?.jobs.any(
                  (job) => job.message.messageId == id,
                ) ==
                true) {
          await recovery.remove(uid, thread, id);
          continue;
        }
        if (!_cameraShown.add(id)) continue;
        final bytes = await recovery.read(uid, thread, id);
        try {
          if (!mounted || !widget.vaultBridge.isUnlocked) return;
          final attach = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Captured photo'),
              content: AnimatedBuilder(
                animation: widget.vaultBridge.vaultSessionChanges,
                builder: (_, _) => widget.vaultBridge.isUnlocked
                    ? Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Text(
                          'Captured photo is corrupt or unsupported. Discard it and take another photo.',
                        ),
                      )
                    : const Text('Unlock to view the captured photo.'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Discard'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Attach'),
                ),
              ],
            ),
          );
          if (!mounted || !widget.vaultBridge.isUnlocked) return;
          if (attach == false) {
            await recovery.remove(uid, thread, id);
          } else if (attach == true) {
            final quality = await _askImageQuality(
              bytes.length,
              imageBytes: bytes,
            );
            if (quality == null || !mounted || !widget.vaultBridge.isUnlocked) {
              continue;
            }
            await cubit.sendMedia(
              messageId: id,
              rawBytes: bytes,
              type: MessageType.image,
              quality: quality,
              propagateFailure: true,
            );
            await recovery.remove(uid, thread, id);
          }
        } finally {
          await MemoryImage(bytes).evict();
          bytes.fillRange(0, bytes.length, 0);
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Captured photo recovery needs attention: $error'),
          ),
        );
      }
    } finally {
      _recoveringCamera = false;
    }
  }

  void _send() {
    final text = _textCtrl.text;
    if (text.trim().isEmpty) return;
    _textCtrl.clear();
    context.read<ActiveThreadCubit>().sendText(text);
  }

  void _toggleEmojiPicker() {
    if (_showEmojiPicker) {
      setState(() => _showEmojiPicker = false);
      _inputFocus.requestFocus();
      return;
    }
    // Drop the keyboard first, otherwise both compete for the same space.
    _inputFocus.unfocus();
    setState(() => _showEmojiPicker = true);
  }

  Widget _buildEmojiPicker() {
    if (!_showEmojiPicker) return const SizedBox.shrink();
    final cubit = context.read<ActiveThreadCubit>();
    return ChatMediaPickerPanel(
      stickerPack: _stickerPackFor(cubit.myUid),
      buildEmojiPicker: (height) => ThemedEmojiPicker(
        textEditingController: _textCtrl,
        height: height,
        searchHeight: height * 0.7,
        showSearchButton: false,
        showBackspace: false,
        columns: 9,
        onEmojiSelected: (category, emoji) {
          context.read<ActiveThreadCubit>().onTextChanged(_textCtrl.text);
        },
      ),
      onSend: (bytes, type, fileName) => cubit.sendMedia(
        messageId: _uuid.v4(),
        rawBytes: bytes,
        type: type,
        filename: fileName,
        propagateFailure: true,
      ),
      onInsertEmoji: _insertEmoji,
      onBackspace: _backspaceComposerText,
      onClose: _toggleEmojiPicker,
    );
  }

  void _insertEmoji(String emoji) {
    final current = _textCtrl.value;
    final text = current.text;
    final selection = current.selection;
    final start = selection.isValid && selection.start <= text.length
        ? selection.start
        : text.length;
    final end = selection.isValid && selection.end <= text.length
        ? selection.end
        : start;
    final updated = text.replaceRange(start, end, emoji);
    _textCtrl.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: start + emoji.length),
      composing: TextRange.empty,
    );
    context.read<ActiveThreadCubit>().onTextChanged(updated);
  }

  void _backspaceComposerText() {
    final current = _textCtrl.value;
    final text = current.text;
    final selection = current.selection;
    late final String updated;
    late final int cursor;
    if (selection.isValid && selection.start != selection.end) {
      updated = text.replaceRange(selection.start, selection.end, '');
      cursor = selection.start;
    } else {
      final offset = selection.isValid ? selection.extentOffset : text.length;
      if (offset <= 0 || offset > text.length) return;
      final before = text
          .substring(0, offset)
          .characters
          .skipLast(1)
          .toString();
      updated = before + text.substring(offset);
      cursor = before.length;
    }
    _textCtrl.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: cursor),
      composing: TextRange.empty,
    );
    context.read<ActiveThreadCubit>().onTextChanged(updated);
  }

  LocalStickerPackRepository _stickerPackFor(String userId) {
    if (_stickerPackUserId != userId) {
      _stickerPackUserId = userId;
      _stickerPackRepository = LocalStickerPackRepository(userId: userId);
    }
    return _stickerPackRepository!;
  }

  Future<void> _pickMedia(BuildContext context) async {
    // Capture before any await to satisfy use_build_context_synchronously.
    final cubit = context.read<ActiveThreadCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.spaceEvenly,
            children: [
              _AttachmentOption(
                icon: Icons.photo_library_rounded,
                label: 'Gallery',
                color: const Color(0xFF7C4DFF),
                onTap: () => Navigator.pop(sheetContext, 'photo'),
              ),
              _AttachmentOption(
                icon: Icons.camera_alt_rounded,
                label: 'Camera',
                color: const Color(0xFFE91E63),
                onTap: () => Navigator.pop(sheetContext, 'camera'),
              ),
              _AttachmentOption(
                icon: Icons.lock_rounded,
                label: 'From Vault',
                color: const Color(0xFFFF9800),
                onTap: () => Navigator.pop(sheetContext, 'vault'),
              ),
              _AttachmentOption(
                icon: Icons.videocam_rounded,
                label: 'Video',
                color: const Color(0xFF2196F3),
                onTap: () => Navigator.pop(sheetContext, 'video'),
              ),
              _AttachmentOption(
                icon: Icons.insert_drive_file_rounded,
                label: 'Document',
                color: const Color(0xFF009688),
                onTap: () => Navigator.pop(sheetContext, 'document'),
              ),
              _AttachmentOption(
                icon: Icons.mic_rounded,
                label: 'Audio',
                color: const Color(0xFFFF5722),
                onTap: () => Navigator.pop(sheetContext, 'audio'),
              ),
              _AttachmentOption(
                icon: Icons.folder_special_rounded,
                label: 'Saved Files',
                color: const Color(0xFF673AB7),
                onTap: () => Navigator.pop(sheetContext, 'saved'),
              ),
              if (Platform.isAndroid)
                _AttachmentOption(
                  icon: Icons.location_on_rounded,
                  label: 'Live Location',
                  color: const Color(0xFF4CAF50),
                  onTap: () => Navigator.pop(sheetContext, 'liveLocation'),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted || !context.mounted) return;
    if (choice == 'liveLocation') {
      await _shareLiveLocation(cubit);
      return;
    }
    if (choice == 'saved') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatSavedAttachmentsScreen(
            bridge: widget.vaultBridge,
            onPreview: (item, bytes) async {
              if (item.mimeType.startsWith('video/')) {
                await _secureMedia.showVideo(bytes);
              } else if (item.mimeType.startsWith('audio/')) {
                await _secureMedia.showAudio(bytes);
              } else if (item.mimeType == 'application/pdf') {
                await _secureMedia.showPdf(bytes);
              } else {
                if (!mounted) return;
                await showDialog<void>(
                  context: this.context,
                  builder: (_) => AlertDialog(
                    title: Text(item.originalFilename),
                    content: AnimatedBuilder(
                      animation: widget.vaultBridge.vaultSessionChanges,
                      builder: (_, _) => !widget.vaultBridge.isUnlocked
                          ? const Text('Vault locked.')
                          : item.mimeType.startsWith('image/')
                          ? Image.memory(bytes)
                          : const Text(
                              'In-app preview unavailable for this format.',
                            ),
                    ),
                  ),
                );
              }
            },
          ),
        ),
      );
      return;
    }
    if (choice == 'audio') {
      await showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: ChatAudioRecorder(
            onDismiss: () {
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            },
            onError: (error) =>
                messenger.showSnackBar(SnackBar(content: Text(error))),
            onRecorded: (attachment) async {
              await cubit.sendMedia(
                messageId: _uuid.v4(),
                rawBytes: attachment.bytes,
                type: MessageType.audio,
                filename: attachment.fileName,
                propagateFailure: true,
              );
            },
          ),
        ),
      );
      return;
    }
    if (choice == 'camera' && Platform.isAndroid) {
      await _captureExternalCamera(cubit);
      return;
    }
    if (Platform.isAndroid && choice != 'vault') {
      try {
        final selected = choice == 'camera'
            ? [?await _secureMedia.capturePhoto()]
            : await ExternalActivityGuard.run(
                () => _secureMedia.pickAttachments(
                  mimeTypes: [
                    switch (choice) {
                      'photo' => 'image/*',
                      'video' => 'video/*',
                      _ => '*/*',
                    },
                  ],
                ),
              );
        if (selected.isEmpty || !mounted || !context.mounted) return;

        if (choice == 'photo') {
          var photos = selected;
          if (photos.length > _maxPhotosPerSend) {
            photos = photos.sublist(0, _maxPhotosPerSend);
            messenger.showSnackBar(
              SnackBar(
                content: Text('Sending the first $_maxPhotosPerSend photos.'),
              ),
            );
          }
          final quality = await _askImageQuality(
            photos.first.bytes.length,
            imageBytes: photos.first.bytes,
          );
          if (quality == null || !mounted) return;

          final items = photos
              .map(
                (att) => OutgoingImageItem(
                  messageId: _uuid.v4(),
                  bytes: att.bytes,
                  sourceUri: att.sourceUri,
                  sourceFlags: att.sourceFlags,
                  filename: att.fileName,
                ),
              )
              .toList(growable: false);

          await cubit.sendMultipleImages(items: items, quality: quality);
          return;
        }

        if (choice == 'camera') {
          final attachment = selected.first;
          await _sendImageWithQuality(
            cubit,
            attachment.bytes,
            sourceUri: attachment.sourceUri,
            sourceFlags: attachment.sourceFlags,
          );
          return;
        }

        if (choice == 'video') {
          final selectedQuality = await VideoQualitySheet.show(
            context,
            originalBytes: selected.first.bytes.length,
            selected: VideoQuality.high,
            videoBytes: selected.length == 1 ? selected.first.bytes : null,
            showEstimates: selected.length == 1,
          );
          if (selectedQuality == null || !mounted || !context.mounted) return;
          await cubit.sendMultipleVideos(
            items: selected
                .map(
                  (attachment) => OutgoingVideoItem(
                    messageId: _uuid.v4(),
                    bytes: attachment.bytes,
                    filename: attachment.fileName,
                    sourceUri: attachment.sourceUri,
                    sourceFlags: attachment.sourceFlags,
                  ),
                )
                .toList(growable: false),
            quality: selectedQuality,
          );
          return;
        }

        for (final attachment in selected) {
          if (!mounted) return;
          await cubit.sendMedia(
            messageId: _uuid.v4(),
            rawBytes: attachment.bytes,
            type: MessageType.file,
            filename: attachment.fileName,
            sourceUri: attachment.sourceUri,
            sourceFlags: attachment.sourceFlags,
          );
        }
      } on PlatformException catch (error) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(error.message ?? 'Could not acquire attachment.'),
          ),
        );
      } catch (error) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not attach file: $error')),
        );
      }
      return;
    }

    if (choice == 'vault') {
      await _sendFromVault(cubit);
      return;
    }
    if (choice == 'document') {
      await _sendDocument(cubit);
      return;
    }

    // Gallery photos are multi-select; the camera and video pickers are not.
    if (choice == 'photo') {
      final files = await ExternalActivityGuard.run(_picker.pickMultiImage);
      if (files.isEmpty || !mounted) return;
      await _sendImages(cubit, files, messenger);
      return;
    }

    XFile? file;
    MessageType? type;

    if (choice == 'camera') {
      file = await ExternalActivityGuard.run(
        () => _picker.pickImage(source: ImageSource.camera),
      );
      type = MessageType.image;
    } else if (choice == 'video') {
      file = await ExternalActivityGuard.run(
        () => _picker.pickVideo(source: ImageSource.gallery),
      );
      type = MessageType.video;
    }

    if (file == null || type == null || !mounted || !context.mounted) return;

    if (type == MessageType.image) {
      await _sendImages(
        cubit,
        [file],
        messenger,
        retainSource: choice != 'camera',
      );
      return;
    }

    if (type == MessageType.video) {
      final bytes = Uint8List.fromList(await file.readAsBytes());
      try {
        if (!mounted || !context.mounted) return;
        final quality = await VideoQualitySheet.show(
          context,
          originalBytes: bytes.length,
          selected: VideoQuality.high,
          videoBytes: bytes,
        );
        if (quality == null || !mounted || !context.mounted) return;
        await cubit.sendMedia(
          messageId: _uuid.v4(),
          rawBytes: bytes,
          type: MessageType.video,
          videoQuality: quality,
          sourceUri: _originalSourceUri(file),
        );
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
      return;
    }

    final length = await file.length();
    if (!mounted) return;
    if (length > ActiveThreadCubit.maxAttachmentBytes) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Attachments must be smaller than 64 MB.'),
        ),
      );
      return;
    }
    final bytes = Uint8List.fromList(await file.readAsBytes());
    try {
      if (!mounted) return;
      await cubit.sendMedia(
        messageId: _uuid.v4(),
        rawBytes: bytes,
        type: type,
        sourceUri: _originalSourceUri(file),
      );
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<void> _shareLiveLocation(ActiveThreadCubit cubit) async {
    final service = widget.liveLocationService;
    final repository = widget.liveLocationRepository;
    if (!Platform.isAndroid || service == null || repository == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Live location sharing is unavailable on this device.'),
        ),
      );
      return;
    }

    if (service.isSharing && service.activeThreadId != widget.thread.threadId) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Live location already shared'),
          content: const Text(
            'Starting a new session will stop sharing in the other chat.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }

    final duration = await showModalBottomSheet<Duration>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Share live location',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'Your encrypted location is visible only in this chat.',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('For 15 minutes'),
              onTap: () =>
                  Navigator.pop(sheetContext, const Duration(minutes: 15)),
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('For 1 hour'),
              onTap: () =>
                  Navigator.pop(sheetContext, const Duration(hours: 1)),
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('For 8 hours'),
              onTap: () =>
                  Navigator.pop(sheetContext, const Duration(hours: 8)),
            ),
          ],
        ),
      ),
    );
    if (duration == null || !mounted) return;

    try {
      await _requestLiveLocationPermissions();
      if (!mounted) return;
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError(
          'Turn on device location services, then try sharing again.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      final point = LiveLocationPoint(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        heading: position.heading,
        speed: position.speed,
        timestamp: position.timestamp.toUtc(),
      );

      final sessionId = await service.startSharing(
        threadId: widget.thread.threadId,
        userId: cubit.myUid,
        duration: duration,
        initialPoint: point,
      );
      if (!await cubit.sendLiveLocationMessage(sessionId: sessionId)) {
        await service.stopSharing();
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Live location shared for ${_durationLabel(duration)}.',
          ),
        ),
      );
    } catch (error) {
      if (service.isSharing &&
          service.activeThreadId == widget.thread.threadId) {
        try {
          await service.stopSharing();
        } catch (stopError) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Could not stop the failed session: $stopError'),
              ),
            );
          }
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share live location: $error')),
        );
      }
    }
  }

  Future<void> _requestLiveLocationPermissions() async {
    final foregroundPermission = await Permission.locationWhenInUse.request();
    if (!mounted) throw StateError('The chat closed before sharing started.');
    if (!foregroundPermission.isGranted) {
      throw StateError(
        'Allow location access while using the app to share your location.',
      );
    }

    var backgroundPermission = await Permission.locationAlways.status;
    if (!backgroundPermission.isGranted) {
      backgroundPermission = await Permission.locationAlways.request();
    }
    if (!backgroundPermission.isGranted) {
      if (!mounted) {
        throw StateError('The chat closed before sharing started.');
      }
      final openSettings = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Allow background location'),
          content: const Text(
            'Choose “Allow all the time” in app settings so sharing can '
            'continue while the app is in the background.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Open settings'),
            ),
          ],
        ),
      );
      if (openSettings != true) {
        throw StateError('Background location permission is required.');
      }
      await openAppSettings();
      if (!mounted) throw StateError('The chat closed before sharing started.');
      backgroundPermission = await Permission.locationAlways.status;
      if (!backgroundPermission.isGranted) {
        throw StateError('Background location permission is required.');
      }
    }

    final notificationPermission = await Permission.notification.request();
    if (!notificationPermission.isGranted) {
      throw StateError(
        'Allow notifications so Android can show the active sharing notice.',
      );
    }
  }

  String _durationLabel(Duration duration) {
    if (duration.inHours > 0) return '${duration.inHours} hour(s)';
    return '${duration.inMinutes} minutes';
  }

  Future<void> _stopLiveLocation(
    String threadId,
    String userId,
    String sessionId,
  ) async {
    final service = widget.liveLocationService;
    if (service != null &&
        service.activeThreadId == threadId &&
        service.activeSessionId == sessionId &&
        userId == context.read<ActiveThreadCubit>().myUid) {
      await service.stopSharing();
      return;
    }
    await widget.liveLocationRepository?.stopSession(
      sessionId: sessionId,
      threadId: threadId,
      userId: userId,
    );
  }

  String _originalSourceUri(XFile file) => file.path.startsWith('content:')
      ? file.path
      : File(file.path).uri.toString();

  /// Most photos anyone sends at once; beyond this the batch is trimmed rather
  /// than queueing an unbounded amount of compression work.
  static const _maxPhotosPerSend = 10;

  /// Asks for a quality once, then sends every picked photo.
  Future<void> _sendImages(
    ActiveThreadCubit cubit,
    List<XFile> files,
    ScaffoldMessengerState messenger, {
    bool retainSource = true,
  }) async {
    var picked = files;
    if (picked.length > _maxPhotosPerSend) {
      picked = picked.sublist(0, _maxPhotosPerSend);
      messenger.showSnackBar(
        SnackBar(content: Text('Sending the first $_maxPhotosPerSend photos.')),
      );
    }

    // The sheet is sized from the first photo and applies to the whole batch,
    // so picking ten photos is still one decision.
    final firstBytes = Uint8List.fromList(await picked.first.readAsBytes());
    if (!mounted) return;
    final quality = await _askImageQuality(
      firstBytes.length,
      imageBytes: firstBytes,
    );
    if (quality == null || !mounted) return;

    final items = <OutgoingImageItem>[];
    for (var i = 0; i < picked.length; i++) {
      final bytes = i == 0
          ? firstBytes
          : Uint8List.fromList(await picked[i].readAsBytes());
      items.add(
        OutgoingImageItem(
          messageId: _uuid.v4(),
          bytes: bytes,
          sourceUri: retainSource ? _originalSourceUri(picked[i]) : null,
          filename: picked[i].name,
        ),
      );
    }

    await cubit.sendMultipleImages(items: items, quality: quality);
  }

  /// Shows the quality sheet, seeded with the last choice and remembering a
  /// new one. Returns null if the sheet was dismissed.
  Future<ImageQuality?> _askImageQuality(
    int originalBytes, {
    Uint8List? imageBytes,
  }) async {
    final settings = widget.settingsRepository;
    final remembered = ImageQualityX.parse(
      await settings?.getChatImageQuality(),
    );
    if (!mounted) return null;
    final chosen = await ImageQualitySheet.show(
      context,
      originalBytes: originalBytes,
      selected: remembered,
      imageBytes: imageBytes,
    );
    if (chosen == null) return null;
    if (chosen != remembered) {
      await settings?.setChatImageQuality(chosen.name);
    }
    return chosen;
  }

  /// Asks which quality to send a single photo at, then sends it.
  Future<void> _sendImageWithQuality(
    ActiveThreadCubit cubit,
    Uint8List bytes, {
    String? sourceUri,
    int sourceFlags = 0,
  }) async {
    final quality = await _askImageQuality(bytes.length, imageBytes: bytes);
    if (quality == null || !mounted) return;
    await cubit.sendMedia(
      messageId: _uuid.v4(),
      rawBytes: bytes,
      type: MessageType.image,
      quality: quality,
      sourceUri: sourceUri,
      sourceFlags: sourceFlags,
    );
  }

  /// Attach any file (PDF, Office document, archive…) as an encrypted blob.
  Future<void> _sendDocument(ActiveThreadCubit cubit) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await ExternalActivityGuard.run(FilePicker.pickFile);
      if (picked == null || !mounted) return;
      final length = await picked.length();
      if (length != null && length > ActiveThreadCubit.maxAttachmentBytes) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Attachments must be smaller than 64 MB.'),
          ),
        );
        return;
      }
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      await cubit.sendMedia(
        messageId: _uuid.v4(),
        rawBytes: bytes,
        type: MessageType.file,
        filename: picked.name,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not attach file: $e')),
      );
    }
  }

  /// Attach a photo that already lives in the encrypted vault.
  ///
  /// The vault and the chat use different keys, so the photo is decrypted with
  /// the vault key and re-encrypted with the thread key. It is never written to
  /// disk in the clear along the way.
  Future<void> _sendFromVault(ActiveThreadCubit cubit) async {
    final photo = await VaultPickerSheet.show(
      context,
      bridge: widget.vaultBridge,
    );
    if (photo == null || !mounted) return;
    Uint8List? bytes;
    try {
      bytes = Uint8List.fromList(
        await widget.vaultBridge.readVaultPhoto(photo),
      );
      if (!mounted) return;
      await _sendImageWithQuality(cubit, bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not read vault photo: $e')));
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
    }
  }

  /// Copy received media into the vault.
  Future<void> _saveToVault(ChatMessage message) async {
    final messenger = ScaffoldMessenger.of(context);
    final ref = message.mediaRef;
    if (ref == null) return;
    if (!widget.vaultBridge.isUnlocked) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Unlock the vault before moving this attachment.'),
        ),
      );
      return;
    }
    final uid = context.read<ActiveThreadCubit>().myUid;
    widget.mediaLoader.setAccount(uid);
    final key = widget.mediaLoader.diskKey(ref);
    final sourceId = '$uid:${message.threadId}:$ref';
    widget.mediaLoader.diskCache.pin(key);
    Uint8List? bytes;
    void checkAccount() {
      if (widget.mediaLoader.accountId != uid) {
        throw StateError('Chat account changed during vault move.');
      }
    }

    Future<void> mark() async {
      checkAccount();
      await widget.mediaLoader.diskCache.markMoved(key);
    }

    Future<void> cleanup() async {
      checkAccount();
      await widget.mediaLoader.removeAfterVaultMove(ref);
    }

    try {
      var result = await widget.vaultBridge.resumeMove(
        sourceId: sourceId,
        onMarkMoved: mark,
        onSourceCleanup: cleanup,
      );
      if (result == null) {
        bytes = await widget.mediaLoader.fetchUncached(
          threadId: message.threadId,
          storagePath: ref,
          senderId: message.senderId,
        );
        checkAccount();
        final extension = switch (message.mediaType) {
          MessageType.video => 'mp4',
          MessageType.audio => 'wav',
          _ => 'jpg',
        };
        result = await widget.vaultBridge.moveToVault(
          bytes: bytes,
          filename: message.documentName ?? '${message.messageId}.$extension',
          sourceId: sourceId,
          mediaType: message.mediaType?.name,
          onMarkMoved: mark,
          onSourceCleanup: cleanup,
        );
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.cleanupPending
                ? 'Stored in vault; local cleanup pending. Tap Move to vault to retry.'
                : 'Moved to vault.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not move to vault: $e')),
      );
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      widget.mediaLoader.diskCache.unpin(key);
    }
  }
}

/// One renderable row in the thread list: either a message or a day divider.
class _ThreadItem {
  const _ThreadItem.message(
    ChatMessage this.message, {
    required this.isFirstInGroup,
    required this.isLastInGroup,
  }) : divider = null;

  const _ThreadItem.divider(DateTime this.divider)
    : message = null,
      isFirstInGroup = false,
      isLastInGroup = false;

  final ChatMessage? message;
  final DateTime? divider;
  final bool isFirstInGroup;
  final bool isLastInGroup;
}

/// App-bar avatar with a presence ring, so status reads at a glance.
class _PresenceAvatar extends StatelessWidget {
  const _PresenceAvatar({
    required this.user,
    required this.name,
    required this.online,
    required this.ringColor,
  });

  final ChatUser user;
  final String name;
  final bool online;
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        children: [
          AnimatedContainer(
            duration: AppDuration.normal,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: online ? ringColor : Colors.transparent,
                width: 2,
              ),
            ),
            child: UserAvatar(avatar: user.avatar, name: name, radius: 18),
          ),
        ],
      ),
    );
  }
}

/// Compact icon button sized to sit inside the composer pill.
class _ComposerAction extends StatelessWidget {
  const _ComposerAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 22),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      onPressed: onPressed,
    );
  }
}

/// Send/update button that grows into view only once there is something to
/// send or update.
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.hasText,
    required this.onSend,
    this.icon = Icons.send_rounded,
  });

  final ValueListenable<bool> hasText;
  final VoidCallback onSend;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<bool>(
      valueListenable: hasText,
      builder: (context, enabled, child) {
        return AnimatedScale(
          duration: AppDuration.fast,
          curve: Curves.easeOutBack,
          scale: enabled ? 1 : 0.85,
          child: AnimatedOpacity(
            duration: AppDuration.fast,
            opacity: enabled ? 1 : 0.45,
            child: Material(
              color: enabled ? cs.primary : cs.surfaceContainerHighest,
              shape: const CircleBorder(),
              elevation: enabled ? 2 : 0,
              shadowColor: cs.primary.withValues(alpha: 0.4),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: enabled ? onSend : null,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Icon(
                    icon,
                    size: 20,
                    color: enabled ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AttachmentOption extends StatelessWidget {
  const _AttachmentOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 78,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.withValues(alpha: 0.32),
                  width: 1.5,
                ),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
