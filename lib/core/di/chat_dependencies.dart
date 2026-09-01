import '../../application/services/chat_auth_service.dart';
import '../../application/services/chat_identity_service.dart';
import '../../application/services/chat_notification_service.dart';
import '../../application/services/contact_discovery_service.dart';
import '../../application/services/presence_service.dart';
import '../../application/services/vault_session.dart';
import '../../crypto/services/chat_crypto_service.dart';
import '../../data/repositories_impl/drift_message_cache_repository.dart';
import '../../data/repositories_impl/drift_outbox_repository.dart';
import '../../data/repositories_impl/firestore_message_repository.dart';
import '../../data/repositories_impl/firestore_presence_repository.dart';
import '../../data/repositories_impl/firestore_thread_repository.dart';
import '../../data/repositories_impl/firestore_typing_repository.dart';
import '../../data/repositories_impl/firestore_user_repository.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/message_cache_repository.dart';
import '../../domain/repositories/outbox_repository.dart';
import '../../domain/repositories/message_repository.dart';
import '../../domain/repositories/presence_repository.dart';
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
  }) : _authRepository = authRepository,
       _vaultSession = vaultSession,
       _database = database;

  final AuthRepository _authRepository;
  final VaultSession _vaultSession;

  /// Shared local database, or null in the in-memory test configuration.
  final VaultDatabase? _database;

  late final UserRepository userRepository = FirestoreUserRepository();
  late final ThreadRepository threadRepository = FirestoreThreadRepository();
  late final MessageRepository messageRepository =
      FirestoreMessageRepository();
  late final MediaRepository mediaRepository = FirebaseMediaRepository();
  late final ChatCryptoService cryptoService = ChatCryptoService();

  /// Swap point for presence: replacing these two bindings with Realtime
  /// Database implementations is the whole cost of that migration.
  late final PresenceRepository presenceRepository =
      FirestorePresenceRepository();
  late final TypingRepository typingRepository = FirestoreTypingRepository();

  /// Offline message cache. Falls back to a no-op when no local database is
  /// available, so the chat still works (online-only) in tests.
  late final MessageCacheRepository messageCache = switch (_database) {
    final VaultDatabase db => DriftMessageCacheRepository(db),
    _ => const NoopMessageCacheRepository(),
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
      ChatNotificationService(
        threadRepository: threadRepository,
        userRepository: userRepository,
      );

  late final PresenceService presenceService = PresenceService(
    presenceRepository: presenceRepository,
  );

  late final ChatIdentityService identityService = ChatIdentityService(
    userRepository: userRepository,
    cryptoService: cryptoService,
  );

  late final ChatAuthService authService = ChatAuthService(
    authRepository: _authRepository,
    userRepository: userRepository,
    presenceRepository: presenceRepository,
    cryptoService: cryptoService,
    identityService: identityService,
    readPin: () => _vaultSession.pin,
  );

  void dispose() {
    presenceService.dispose();
    notificationService.dispose();
    mediaLoader.clear();
  }
}
