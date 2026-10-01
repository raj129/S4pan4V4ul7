import '../../application/services/chat_auth_service.dart';
import '../../application/services/chat_backup_service.dart';
import '../../application/services/chat_identity_service.dart';
import '../../application/services/chat_notification_service.dart';
import '../../application/services/contact_discovery_service.dart';
import '../../application/services/presence_service.dart';
import '../../application/services/profile_service.dart';
import '../../application/services/push_notification_service.dart';
import '../../application/services/vault_session.dart';
import '../../crypto/services/chat_crypto_service.dart';
import '../../data/repositories_impl/drift_chat_search_index_repository.dart';
import '../../data/repositories_impl/drift_message_cache_repository.dart';
import '../../data/repositories_impl/drift_outbox_repository.dart';
import '../../data/repositories_impl/firebase_avatar_storage.dart';
import '../../data/repositories_impl/firestore_push_token_repository.dart';
import '../../data/repositories_impl/google_drive_chat_backup_store.dart';
import '../../data/repositories_impl/local_chat_backup_store.dart';
import '../../data/repositories_impl/firestore_message_repository.dart';
import '../../data/repositories_impl/firestore_presence_repository.dart';
import '../../data/repositories_impl/firestore_thread_repository.dart';
import '../../data/repositories_impl/firestore_typing_repository.dart';
import '../../data/repositories_impl/firestore_user_repository.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/chat_search_index_repository.dart';
import '../../domain/repositories/message_cache_repository.dart';
import '../../domain/repositories/outbox_repository.dart';
import '../../domain/repositories/message_repository.dart';
import '../../domain/repositories/presence_repository.dart';
import '../../domain/repositories/push_token_repository.dart';
import '../../domain/repositories/thread_repository.dart';
import '../../domain/repositories/typing_repository.dart';
import '../../domain/repositories/user_repository.dart';
import '../../presentation/widgets/chat/chat_media_preview.dart';
import '../../storage/local_db/vault_database.dart';

/// Composition root for the chat feature.
///
/// Kept separate from [AppDependencies] and created lazily, because every
/// member touches Firebase and must not be constructed in tests that run with
/// `persistentState: false`.
///
/// These were previously built inside `ChatApp`'s state, which meant a new
/// [ChatCryptoService] — and therefore an empty decryption cache — on every
/// rebuild of the chat route.
class ChatDependencies {
  ChatDependencies({
    required AuthRepository authRepository,
    required VaultSession vaultSession,
    VaultDatabase? database,
    UserRepository? userRepository,
    ThreadRepository? threadRepository,
    MessageRepository? messageRepository,
    MediaRepository? mediaRepository,
    PresenceRepository? presenceRepository,
    TypingRepository? typingRepository,
    ChatCryptoService? cryptoService,
    PushTokenRepository? pushTokenRepository,
  }) : _authRepository = authRepository,
       _vaultSession = vaultSession,
       _database = database {
    if (pushTokenRepository != null) {
      this.pushTokenRepository = pushTokenRepository;
    }
    if (userRepository != null) this.userRepository = userRepository;
    if (threadRepository != null) this.threadRepository = threadRepository;
    if (messageRepository != null) this.messageRepository = messageRepository;
    if (mediaRepository != null) this.mediaRepository = mediaRepository;
    if (presenceRepository != null)
      this.presenceRepository = presenceRepository;
    if (typingRepository != null) this.typingRepository = typingRepository;
    if (cryptoService != null) this.cryptoService = cryptoService;
    _vaultSession.addListener(_onVaultSessionChanged);
  }

  /// Drop in-memory chat keys as soon as the vault locks.
  void _onVaultSessionChanged() {
    if (!_vaultSession.isUnlocked) cryptoService.clearKeyCache();
  }

  final AuthRepository _authRepository;

  /// Exposed so the session can authorize Google Drive once up front.
  AuthRepository get authRepository => _authRepository;
  final VaultSession _vaultSession;

  /// Shared local database, or null in the in-memory test configuration.
  final VaultDatabase? _database;

  late UserRepository userRepository = FirestoreUserRepository();
  late ThreadRepository threadRepository = FirestoreThreadRepository();
  late MessageRepository messageRepository = FirestoreMessageRepository();
  late MediaRepository mediaRepository = FirebaseMediaRepository();
  late ChatCryptoService cryptoService = ChatCryptoService();

  /// Swap point for presence: replacing these two bindings with Realtime
  /// Database implementations is the whole cost of that migration.
  late PresenceRepository presenceRepository = FirestorePresenceRepository();
  late TypingRepository typingRepository = FirestoreTypingRepository();

  /// Offline message cache. Falls back to a no-op when no local database is
  /// available, so the chat still works (online-only) in tests.
  late final MessageCacheRepository messageCache = switch (_database) {
    final VaultDatabase db => DriftMessageCacheRepository(db),
    _ => const NoopMessageCacheRepository(),
  };

  /// Keyed local search index over the message cache.
  late final ChatSearchIndexRepository searchIndex = switch (_database) {
    final VaultDatabase db => DriftChatSearchIndexRepository(db),
    _ => const NoopChatSearchIndexRepository(),
  };

  /// Durable send queue. Falls back to a no-op when no local database is
  /// available, so sends behave as online-only in tests.
  late final OutboxRepository outbox = switch (_database) {
    final VaultDatabase db => DriftOutboxRepository(db),
    _ => const NoopOutboxRepository(),
  };

  /// Shared decrypt-and-cache pipeline for attachments.
  ///
  /// Held here, not in the widget tree, so its cache survives navigation
  /// between threads instead of re-downloading on every rebuild.
  late final ChatMediaLoader mediaLoader = ChatMediaLoader(
    mediaRepository: mediaRepository,
    cryptoService: cryptoService,
  );

  late final ContactDiscoveryService contactDiscoveryService =
      ContactDiscoveryService(userRepository: userRepository);

  /// Serverless new-message notifications, driven by the thread listener.
  late final ChatNotificationService notificationService =
      ChatNotificationService(threadRepository: threadRepository);

  late PushTokenRepository pushTokenRepository = FirestorePushTokenRepository();

  /// FCM registration, fed by the `onChatMessageCreated` Cloud Function.
  /// Built on first use so tests without Firebase never touch it.
  PushNotificationService? _pushService;
  PushNotificationService get pushService =>
      _pushService ??= PushNotificationService(
        tokenRepository: pushTokenRepository,
        notificationService: notificationService,
        messageRepository: messageRepository,
      );

  late final PresenceService presenceService = PresenceService(
    presenceRepository: presenceRepository,
  );

  late final ChatIdentityService identityService = ChatIdentityService(
    userRepository: userRepository,
    cryptoService: cryptoService,
  );

  /// Own name/avatar and contact aliases, kept locally and in the backup.
  late final ProfileService profileService = ProfileService(
    store: messageCache,
    userRepository: userRepository,
    avatarStorage: FirebaseAvatarStorage(),
  );

  late final ChatAuthService authService = ChatAuthService(
    profileService: profileService,
    authRepository: _authRepository,
    userRepository: userRepository,
    presenceRepository: presenceRepository,
    cryptoService: cryptoService,
    identityService: identityService,
    readPin: () => _vaultSession.pin,
    beforeSignOut: () async {
      await _pushService?.stop();
      await mediaLoader.clearAll();
    },
  );

  /// Nightly / manual chat backup to this device and Google Drive.
  late final ChatBackupService backupService = ChatBackupService(
    cache: messageCache,
    crypto: cryptoService,
    stores: [
      LocalChatBackupStore(),
      GoogleDriveChatBackupStore(authRepository: _authRepository),
    ],
    currentUid: () => authService.currentUid,
    profile: profileService,
  );

  void dispose() {
    _vaultSession.removeListener(_onVaultSessionChanged);
    presenceService.dispose();
    _pushService?.dispose();
    notificationService.dispose();
    mediaLoader.clear();
  }
}
