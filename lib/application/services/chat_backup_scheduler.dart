import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:workmanager/workmanager.dart';

import '../../crypto/services/chat_crypto_service.dart';
import '../../data/repositories_impl/drift_outbox_repository.dart';
import '../../data/repositories_impl/drift_message_cache_repository.dart';
import '../../data/repositories_impl/firebase_auth_repository.dart';
import '../../data/repositories_impl/firestore_message_repository.dart';
import '../../data/repositories_impl/firestore_thread_repository.dart';
import '../../data/repositories_impl/google_drive_chat_backup_store.dart';
import '../../data/repositories_impl/local_chat_backup_store.dart';
import '../../domain/repositories/outbox_repository.dart';
import '../../firebase_options.dart';
import '../../storage/local_db/vault_database.dart';
import 'chat_attachment_staging.dart';
import 'chat_backup_service.dart';
import 'chat_outbox_delivery.dart';

/// OAuth web client id used by Google Sign-In (shared with `main.dart`).
const googleServerClientId =
    '209716874258-p9n2n9jmu87oqqu84703hf9kvuodokdn.apps.googleusercontent.com';

const _nightlyTaskName = 'photo_vault.chat_backup.nightly';
const _mediaUploadTaskName = 'photo_vault.chat_media.upload';

/// Target local time of the nightly backup.
const _backupHour = 2;

/// Background isolate entry point for workmanager.
@pragma('vm:entry-point')
void chatBackupCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == _mediaUploadTaskName) {
      final messageId = inputData?['messageId'];
      if (messageId is! String || messageId.isEmpty) return true;
      return runBackgroundChatMediaUpload(messageId);
    }
    if (task == _nightlyTaskName) {
      try {
        await runBackgroundChatBackup();
      } catch (e) {
        debugPrint('Nightly chat backup failed: $e');
      }
      // A failed backup is retried the next night and on the next app open.
      return true;
    }
    return true;
  });
}

Future<void>? _workmanagerInitialization;

Future<void> _ensureWorkmanagerInitialized() => _workmanagerInitialization ??=
    Workmanager().initialize(chatBackupCallbackDispatcher);

/// Schedules one network-constrained attempt for a durable queued attachment.
Future<void> scheduleChatAttachmentUpload(String messageId) async {
  if (kIsWeb || !Platform.isAndroid) return;
  await _ensureWorkmanagerInitialized();
  await Workmanager().registerOneOffTask(
    'chat-media-$messageId',
    _mediaUploadTaskName,
    inputData: {'messageId': messageId},
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingWorkPolicy.keep,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(seconds: 30),
  );
}

/// Uploads and delivers one staged attachment without needing plaintext keys.
Future<bool> runBackgroundChatMediaUpload(String messageId) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return true;

  final db = VaultDatabase();
  final outbox = DriftOutboxRepository(db);
  try {
    OutboxItem? item;
    for (final queued in await outbox.pending()) {
      if (queued.messageId == messageId) {
        item = queued;
        break;
      }
    }
    if (item == null || item.senderId != uid) return true;

    final delivery = ChatOutboxDeliveryService(
      outbox: outbox,
      mediaRepository: FirebaseMediaRepository(),
      messageRepository: FirestoreMessageRepository(),
      threadRepository: FirestoreThreadRepository(),
      stagingStore: FileAttachmentStagingStore(),
    );
    try {
      final result = await delivery.deliver(item: item, uid: uid);
      return result != null;
    } on StagedAttachmentMissingException catch (e) {
      await outbox.markFailed(messageId, e.toString());
      return true;
    } catch (e) {
      await outbox.markFailed(messageId, e.toString());
      debugPrint('Background attachment delivery failed: $e');
      return false;
    }
  } finally {
    await db.close();
  }
}

/// Performs one backup outside the UI (own Firebase + database instances).
Future<void> runBackgroundChatBackup() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  try {
    await GoogleSignIn.instance
        .initialize(serverClientId: googleServerClientId)
        .timeout(const Duration(seconds: 10));
  } catch (_) {
    // Drive is then skipped and retried when the app is next opened.
  }

  final db = VaultDatabase();
  try {
    final service = ChatBackupService(
      cache: DriftMessageCacheRepository(db),
      crypto: ChatCryptoService(),
      stores: [
        LocalChatBackupStore(),
        GoogleDriveChatBackupStore(authRepository: FirebaseAuthRepository()),
      ],
      currentUid: () => uid,
    );
    // Slightly under a day so a periodic run that fires a little early is
    // not skipped.
    await service.backupIfDue(minAge: const Duration(hours: 20));
  } finally {
    await db.close();
  }
}

/// Schedules the nightly backup (Android only; desktop backs up on open).
Future<void> scheduleNightlyChatBackup() async {
  if (kIsWeb || !Platform.isAndroid) return;
  await _ensureWorkmanagerInitialized();
  await Workmanager().registerPeriodicTask(
    _nightlyTaskName,
    _nightlyTaskName,
    frequency: const Duration(hours: 24),
    initialDelay: delayUntilNextBackup(DateTime.now()),
    constraints: Constraints(
      networkType: NetworkType.notRequired,
      requiresBatteryNotLow: true,
    ),
    // Keep the existing schedule so every app launch does not push the next
    // run a day further out.
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}

/// Time from [now] until the next [_backupHour]:00 local time.
@visibleForTesting
Duration delayUntilNextBackup(DateTime now) {
  var next = DateTime(now.year, now.month, now.day, _backupHour);
  if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
  return next.difference(now);
}
