import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as hashing;
import 'package:cryptography/cryptography.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:workmanager/workmanager.dart';

import '../../crypto/services/chat_crypto_service.dart';
import '../../data/repositories_impl/drift_message_cache_repository.dart';
import '../../data/repositories_impl/firebase_auth_repository.dart';
import '../../data/repositories_impl/firestore_message_repository.dart';
import '../../data/repositories_impl/google_drive_chat_backup_store.dart';
import '../../data/repositories_impl/local_chat_backup_store.dart';
import '../../firebase_options.dart';
import '../../storage/local_db/vault_database.dart';
import 'chat_backup_service.dart';
import 'chat_media_cache.dart';
import 'chat_receive_service.dart';

/// OAuth web client id used by Google Sign-In (shared with `main.dart`).
const googleServerClientId =
    '209716874258-p9n2n9jmu87oqqu84703hf9kvuodokdn.apps.googleusercontent.com';

const _nightlyTaskName = 'photo_vault.chat_backup.nightly';
const _receiveTaskName = 'photo_vault.chat_receive';

/// Target local time of the nightly backup.
const _backupHour = 2;

/// Background isolate entry point for workmanager.
@pragma('vm:entry-point')
void chatBackupCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == _receiveTaskName) {
      final uid = inputData?['uid'];
      final thread = inputData?['threadId'];
      final message = inputData?['messageId'];
      if (uid is! String || thread is! String || message is! String) {
        return true;
      }
      return runBackgroundChatReceive(uid, thread, message);
    }
    if (task != _nightlyTaskName) return true;
    try {
      await runBackgroundChatBackup();
    } catch (e) {
      debugPrint('Nightly chat backup failed: $e');
    }
    // Always report success: a failed run is simply retried the next night,
    // and the app backs up on open when a run was missed.
    return true;
  });
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
  final crypto = ChatCryptoService();
  try {
    await crypto.requireAccount(uid);
    final service = ChatBackupService(
      cache: DriftMessageCacheRepository(db),
      crypto: crypto,
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
    crypto.clearKeyCache();
    await db.close();
  }
}

/// Schedules the nightly backup (Android only; desktop backs up on open).
Future<void> scheduleNightlyChatBackup() async {
  if (!Platform.isAndroid) return;
  await Workmanager().initialize(chatBackupCallbackDispatcher);
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

/// WorkManager owns the durable offline queue; input contains IDs, not content.
Future<void> scheduleChatReceive({
  required String uid,
  required String threadId,
  required String messageId,
}) async {
  if (!Platform.isAndroid) return;
  if (uid.isEmpty || messageId.isEmpty || !threadId.split('_').contains(uid)) {
    throw const FormatException('Invalid chat receive job.');
  }
  await Workmanager().initialize(chatBackupCallbackDispatcher);
  final identity = hashing.sha256
      .convert(utf8.encode('$uid:$threadId:$messageId'))
      .toString();
  await Workmanager().registerOneOffTask(
    '$_receiveTaskName.$identity',
    _receiveTaskName,
    existingWorkPolicy: ExistingWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.connected),
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(seconds: 30),
    inputData: {'uid': uid, 'threadId': threadId, 'messageId': messageId},
  );
}

Future<bool> runBackgroundChatReceive(
  String uid,
  String threadId,
  String messageId,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  if (FirebaseAuth.instance.currentUser?.uid != uid) return true;
  final db = VaultDatabase();
  final cache = DriftMessageCacheRepository(db);
  final identity = hashing.sha256
      .convert(utf8.encode('$uid:$threadId:$messageId'))
      .toString();
  final attemptKey = 'chat_receive_attempts_$identity';
  final statusKey = 'chat_receive_status_$identity';
  final crypto = ChatCryptoService();
  try {
    final attempts =
        int.tryParse(await cache.readSetting(attemptKey) ?? '') ?? 0;
    await cache.writeSetting(attemptKey, '${attempts + 1}');
    await crypto.requireAccount(uid);
    await cache.writeSetting(statusKey, 'downloading');
    await ChatReceiveService(
      messages: FirestoreMessageRepository(),
      messageCache: cache,
      media: FirebaseMediaRepository(),
      crypto: crypto,
      cache: ChatMediaCache(),
      currentUid: () => FirebaseAuth.instance.currentUser?.uid,
    ).process(uid: uid, threadId: threadId, messageId: messageId);
    await cache.writeSetting(statusKey, 'cached');
    await cache.writeSetting(attemptKey, null);
    return true;
  } on ChatReceiveAccountChanged {
    return true;
  } on FormatException {
    await cache.writeSetting(statusKey, 'corrupted');
    return true;
  } on RangeError {
    await cache.writeSetting(statusKey, 'corrupted');
    return true;
  } on SecretBoxAuthenticationError {
    await cache.writeSetting(statusKey, 'authentication_failed');
    return true;
  } on ChatCacheCapacityException {
    await cache.writeSetting(statusKey, 'storage_full');
    return true;
  } on FileSystemException {
    await cache.writeSetting(statusKey, 'storage_unavailable');
    return true;
  } on FirebaseException catch (error) {
    final permanent = {
      'permission-denied',
      'unauthorized',
      'object-not-found',
      'invalid-argument',
    }.contains(error.code);
    final attempts =
        int.tryParse(await cache.readSetting(attemptKey) ?? '') ?? 1;
    await cache.writeSetting(
      statusKey,
      permanent || attempts >= 8 ? 'failed' : 'retrying',
    );
    debugPrint('Background chat receive: ${error.code}.');
    return permanent || attempts >= 8;
  } on TimeoutException {
    final attempts =
        int.tryParse(await cache.readSetting(attemptKey) ?? '') ?? 1;
    await cache.writeSetting(statusKey, attempts >= 8 ? 'failed' : 'retrying');
    return attempts >= 8;
  } on StateError {
    // The thread key may arrive on a later foreground key exchange.
    final attempts =
        int.tryParse(await cache.readSetting(attemptKey) ?? '') ?? 1;
    await cache.writeSetting(statusKey, 'key_unavailable');
    return attempts >= 8;
  } on PlatformException catch (error) {
    // Keystore/storage access may be temporarily unavailable after boot or
    // while Android restricts a headless worker. Never retry without a bound.
    final attempts =
        int.tryParse(await cache.readSetting(attemptKey) ?? '') ?? 1;
    await cache.writeSetting(
      statusKey,
      attempts >= 8 ? 'failed' : 'key_unavailable',
    );
    debugPrint('Background chat secure storage: ${error.code}.');
    return attempts >= 8;
  } finally {
    crypto.clearKeyCache();
    await db.close();
  }
}

/// Time from [now] until the next [_backupHour]:00 local time.
@visibleForTesting
Duration delayUntilNextBackup(DateTime now) {
  var next = DateTime(now.year, now.month, now.day, _backupHour);
  if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
  return next.difference(now);
}
