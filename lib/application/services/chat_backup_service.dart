import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart' as hash;

import '../../crypto/services/chat_crypto_service.dart';
import '../../domain/repositories/chat_backup_store.dart';
import '../../domain/repositories/message_cache_repository.dart';

/// A decrypted chat backup found in one of the stores.
class ChatBackupSnapshot {
  const ChatBackupSnapshot({
    required this.backupAt,
    required this.source,
    required this.messages,
    required this.clearedBefore,
  });

  final DateTime backupAt;
  final String source;
  final List<CachedMessageRecord> messages;
  final Map<String, DateTime> clearedBefore;

  int get messageCount => messages.length;
}

/// Outcome of a backup run.
class ChatBackupResult {
  const ChatBackupResult({
    required this.backupAt,
    required this.messageCount,
    required this.savedTo,
    required this.skipped,
  });

  final DateTime backupAt;
  final int messageCount;
  final List<String> savedTo;

  /// Store label → reason it was not written.
  final Map<String, String> skipped;
}

/// WhatsApp-style chat backup and restore.
///
/// A backup is this device's *local* view of every chat — the cached
/// ciphertext plus each thread's "clear chat" watermark — encrypted under a
/// key derived from the identity key. After a reinstall or cleared data, only
/// a restore brings history back: older server messages stay hidden behind a
/// history horizon, so a cleared chat is never resurrected from Firestore.
class ChatBackupService {
  ChatBackupService({
    required MessageCacheRepository cache,
    required ChatCryptoService crypto,
    required List<ChatBackupStore> stores,
    required String? Function() currentUid,
    Future<List<ConnectivityResult>> Function()? checkConnectivity,
    DateTime Function()? clock,
  }) : _cache = cache,
       _crypto = crypto,
       _stores = stores,
       _currentUid = currentUid,
       _checkConnectivity =
           checkConnectivity ?? (() => Connectivity().checkConnectivity()),
       _clock = clock ?? DateTime.now;

  final MessageCacheRepository _cache;
  final ChatCryptoService _crypto;
  final List<ChatBackupStore> _stores;
  final String? Function() _currentUid;
  final Future<List<ConnectivityResult>> Function() _checkConnectivity;
  final DateTime Function() _clock;

  static const _formatVersion = 1;
  static const _initialisedKey = 'chat_backup_initialised';
  static const _restorePendingKey = 'chat_restore_pending';
  static const _lastBackupKey = 'chat_last_backup_at';
  static const _cloudPendingKey = 'chat_backup_cloud_pending';
  static const _wifiOnlyKey = 'chat_backup_wifi_only';

  /// How often an automatic backup is due.
  static const backupInterval = Duration(hours: 24);

  /// Stable, non-reversible file key for the signed-in account.
  String? _accountId() {
    final uid = _currentUid();
    if (uid == null || uid.isEmpty) return null;
    return hash.sha256.convert(utf8.encode(uid)).toString().substring(0, 20);
  }

  // ---------------------------------------------------------------------------
  // Fresh-install detection
  // ---------------------------------------------------------------------------

  /// Runs once per install. With an empty cache this is a fresh install or
  /// cleared data: server history is hidden behind a horizon of "now" until
  /// the user restores a backup. Returns true if a restore should be offered.
  Future<bool> prepareForSession() async {
    if (await _cache.readSetting(_initialisedKey) == null) {
      final hasLocalHistory = (await _cache.exportAll()).isNotEmpty;
      if (!hasLocalHistory) {
        await _cache.setHistoryHorizon(_clock().toUtc());
        await _cache.writeSetting(_restorePendingKey, '1');
      }
      await _cache.writeSetting(_initialisedKey, '1');
    }
    return await _cache.readSetting(_restorePendingKey) != null;
  }

  Future<void> dismissRestoreOffer() =>
      _cache.writeSetting(_restorePendingKey, null);

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  Future<bool> isWifiOnly() async =>
      await _cache.readSetting(_wifiOnlyKey) != '0';

  Future<void> setWifiOnly(bool value) =>
      _cache.writeSetting(_wifiOnlyKey, value ? '1' : '0');

  Future<DateTime?> lastBackupAt() async {
    final ms = int.tryParse(await _cache.readSetting(_lastBackupKey) ?? '');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<bool> _networkAllowed() async {
    final results = await _checkConnectivity();
    if (await isWifiOnly()) {
      return results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet);
    }
    return results.any((r) => r != ConnectivityResult.none);
  }

  // ---------------------------------------------------------------------------
  // Backup
  // ---------------------------------------------------------------------------

  Future<ChatBackupResult> backupNow({bool interactive = false}) async {
    final accountId = _accountId();
    if (accountId == null) throw StateError('Not signed in to chat.');

    final backupAt = _clock().toUtc();
    final records = await _cache.exportAll();
    final cleared = await _cache.getAllClearedBefore();
    final payload = {
      'v': _formatVersion,
      'backupAt': backupAt.millisecondsSinceEpoch,
      'cleared': {
        for (final e in cleared.entries) e.key: e.value.millisecondsSinceEpoch,
      },
      'messages': [for (final r in records) r.toJson()],
    };
    final blob = await _crypto.encryptBackup(
      gzip.encode(utf8.encode(jsonEncode(payload))),
    );

    final savedTo = <String>[];
    final skipped = <String, String>{};
    final networkOk = await _networkAllowed();
    var cloudPending = false;
    for (final store in _stores) {
      if (store.requiresNetwork && !networkOk) {
        skipped[store.label] = (await isWifiOnly())
            ? 'Waiting for Wi-Fi'
            : 'Offline';
        cloudPending = true;
        continue;
      }
      try {
        await store.write(accountId, blob, interactive: interactive);
        savedTo.add(store.label);
      } catch (e) {
        skipped[store.label] = e.toString();
        if (store.requiresNetwork) cloudPending = true;
      }
    }
    if (savedTo.isEmpty) {
      throw StateError('Backup failed: ${skipped.values.join('; ')}');
    }
    await _cache.writeSetting(
      _lastBackupKey,
      backupAt.millisecondsSinceEpoch.toString(),
    );
    await _cache.writeSetting(_cloudPendingKey, cloudPending ? '1' : null);
    return ChatBackupResult(
      backupAt: backupAt,
      messageCount: records.length,
      savedTo: savedTo,
      skipped: skipped,
    );
  }

  /// Backs up when the daily backup is overdue, or a cloud upload was missed.
  /// Called on app open so desktop (no background scheduler) is covered too.
  Future<ChatBackupResult?> backupIfDue({
    Duration minAge = backupInterval,
  }) async {
    if (_accountId() == null) return null;
    // Never back up an un-restored fresh install over a good backup.
    if (await _cache.readSetting(_restorePendingKey) != null) return null;
    final last = await lastBackupAt();
    final cloudPending = await _cache.readSetting(_cloudPendingKey) != null;
    final overdue = last == null || _clock().difference(last) >= minAge;
    if (!overdue && !cloudPending) return null;
    return backupNow();
  }

  // ---------------------------------------------------------------------------
  // Restore
  // ---------------------------------------------------------------------------

  /// The newest readable backup across all stores, or null if there is none.
  Future<ChatBackupSnapshot?> findLatestBackup({
    bool interactive = false,
  }) async {
    final accountId = _accountId();
    if (accountId == null) return null;
    ChatBackupSnapshot? best;
    for (final store in _stores) {
      try {
        final blob = await store.read(accountId, interactive: interactive);
        if (blob == null) continue;
        final snapshot = await _decode(blob, store.label);
        if (best == null || snapshot.backupAt.isAfter(best.backupAt)) {
          best = snapshot;
        }
      } catch (_) {
        // Unreachable store or unreadable blob: try the next one.
      }
    }
    return best;
  }

  Future<ChatBackupSnapshot> _decode(Uint8List blob, String source) async {
    final plain = await _crypto.decryptBackup(blob);
    final map = jsonDecode(utf8.decode(gzip.decode(plain)));
    if (map is! Map || map['v'] != _formatVersion) {
      throw const FormatException('Unsupported chat backup.');
    }
    final cleared = <String, DateTime>{};
    final rawCleared = map['cleared'];
    if (rawCleared is Map) {
      for (final e in rawCleared.entries) {
        if (e.key is String && e.value is int) {
          cleared[e.key as String] = DateTime.fromMillisecondsSinceEpoch(
            e.value as int,
            isUtc: true,
          );
        }
      }
    }
    final messages = <CachedMessageRecord>[];
    final rawMessages = map['messages'];
    if (rawMessages is List) {
      for (final m in rawMessages) {
        final record = CachedMessageRecord.fromJson(m);
        if (record != null) messages.add(record);
      }
    }
    return ChatBackupSnapshot(
      backupAt: DateTime.fromMillisecondsSinceEpoch(
        map['backupAt'] as int,
        isUtc: true,
      ),
      source: source,
      messages: messages,
      clearedBefore: cleared,
    );
  }

  /// Loads [snapshot] into the local cache.
  ///
  /// Clear watermarks are restored (keeping the later one if this device has
  /// its own), and on a fresh install the history horizon moves back to the
  /// backup time, so messages that arrived after the backup still appear.
  Future<void> restore(ChatBackupSnapshot snapshot) async {
    for (final e in snapshot.clearedBefore.entries) {
      final existing = await _cache.getClearedBefore(e.key);
      if (existing == null || e.value.isAfter(existing)) {
        await _cache.setClearedBefore(e.key, e.value);
      }
    }
    final visible = snapshot.messages.where((m) {
      final cleared = snapshot.clearedBefore[m.threadId];
      return cleared == null || m.sentAtMs > cleared.millisecondsSinceEpoch;
    }).toList();
    await _cache.importAll(visible);

    final horizon = await _cache.getHistoryHorizon();
    if (horizon != null && snapshot.backupAt.isBefore(horizon)) {
      await _cache.setHistoryHorizon(snapshot.backupAt);
    }
    await dismissRestoreOffer();
  }
}
