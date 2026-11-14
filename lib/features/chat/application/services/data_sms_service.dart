import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../crypto/chat_crypto_service.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_thread.dart';
import '../../domain/entities/chat_user.dart';
import '../../domain/repositories/message_cache_repository.dart';
import 'android_data_sms.dart';
import 'data_sms_protocol.dart';

export 'data_sms_protocol.dart' show DataSmsEstimate;

class SmsLocalThread {
  const SmsLocalThread(this.thread, this.user);
  final ChatThread thread;
  final ChatUser user;
}

class DataSmsService {
  DataSmsService({
    required this.native,
    required this.crypto,
    required this.cache,
    required this.currentUid,
    required this.isUnlocked,
    this.onIncoming,
    FlutterSecureStorage? storage,
  }) : storage = storage ?? const FlutterSecureStorage();

  final AndroidDataSms native;
  final ChatCryptoService crypto;
  final MessageCacheRepository cache;
  final FlutterSecureStorage storage;
  final String? Function() currentUid;
  final bool Function() isUnlocked;
  final Future<void> Function(ChatThread)? onIncoming;
  final _changes = StreamController<ChatMessage>.broadcast();
  Stream<ChatMessage> get changes => _changes.stream;
  Timer? _timer;
  bool _polling = false;
  bool _disposed = false;
  bool _recoverInterrupted = true;
  final _rejected = <String>{};

  String _requireUid() {
    final uid = currentUid();
    if (uid == null || !isUnlocked()) {
      throw StateError('Unlock the signed-in chat account to use data SMS.');
    }
    return uid;
  }

  void _checkAccount(String uid) {
    if (_requireUid() != uid) {
      throw StateError('Chat account changed during data SMS processing.');
    }
  }

  String _contactsKey(String uid) => 'data_sms_contacts_$uid';

  Future<Map<String, dynamic>> _contacts(String uid) async {
    final raw = await storage.read(key: _contactsKey(uid));
    if (raw == null) return {};
    return (jsonDecode(raw) as Map).cast<String, dynamic>();
  }

  Future<void> remember(ChatThread thread, ChatUser other) async {
    final uid = _requireUid();
    if (thread.threadId != ChatThread.buildId(uid, other.uid)) {
      throw const FormatException('Invalid SMS conversation identity.');
    }
    final records = await _contacts(uid);
    final previous = (records[thread.threadId] as Map?)
        ?.cast<String, dynamic>();
    records[thread.threadId] = {
      'thread': thread.toFirestore(),
      'user': other.toFirestore(),
      if (previous?['phone'] != null) 'phone': previous!['phone'],
    };
    _checkAccount(uid);
    await storage.write(key: _contactsKey(uid), value: jsonEncode(records));
  }

  Future<String?> phone(String threadId) async {
    final records = await _contacts(_requireUid());
    return (records[threadId] as Map?)?['phone'] as String?;
  }

  Future<void> setPhone(String threadId, String? value) async {
    final uid = _requireUid();
    final normalized = value?.replaceAll(RegExp(r'[\s().-]'), '');
    if (normalized != null &&
        normalized.isNotEmpty &&
        !RegExp(r'^\+[1-9][0-9]{6,14}$').hasMatch(normalized)) {
      throw const FormatException(
        'Use an international phone number, for example +919876543210.',
      );
    }
    final records = await _contacts(uid);
    final record = (records[threadId] as Map?)?.cast<String, dynamic>();
    if (record == null) throw StateError('Open this conversation first.');
    if (normalized == null || normalized.isEmpty) {
      record.remove('phone');
    } else {
      record['phone'] = normalized;
    }
    records[threadId] = record;
    _checkAccount(uid);
    await storage.write(key: _contactsKey(uid), value: jsonEncode(records));
  }

  Future<void> enable() async {
    final uid = _requireUid();
    if (!await native.isSupported()) {
      throw StateError('This device does not support data SMS.');
    }
    await native.requestPermission();
    _checkAccount(uid);
    start();
  }

  Future<void> forget(String threadId) async {
    final uid = _requireUid();
    final records = await _contacts(uid);
    records.remove(threadId);
    _checkAccount(uid);
    await storage.write(key: _contactsKey(uid), value: jsonEncode(records));
  }

  Future<void> hideMessage(ChatMessage message) async {
    final uid = _requireUid();
    if (!message.isDataSms) {
      throw StateError('Expected a data SMS message.');
    }
    await _save(
      message.copyWith(deletedFor: {...message.deletedFor, uid}.toList()),
    );
  }

  Future<void> markRead(String threadId) async {
    final uid = _requireUid();
    final key = 'sms_read_${uid}_$threadId';
    final previous = int.tryParse(await cache.readSetting(key) ?? '') ?? 0;
    final recent =
        (await cache.loadAll(
            threadId,
          )).where((m) => m.isDataSms && m.senderId != uid).toList()
          ..sort((a, b) => b.sentAt.compareTo(a.sentAt));
    if (recent.isEmpty ||
        recent.first.sentAt.millisecondsSinceEpoch <= previous) {
      return;
    }
    _checkAccount(uid);
    await cache.writeSetting(
      key,
      DateTime.now().toUtc().millisecondsSinceEpoch.toString(),
    );
    if (!_disposed) _changes.add(recent.first);
  }

  Future<List<SmsLocalThread>> localThreads() async {
    final uid = _requireUid();
    final records = await _contacts(uid);
    final result = <SmsLocalThread>[];
    for (final entry in records.entries) {
      final record = (entry.value as Map).cast<String, dynamic>();
      var thread = ChatThread.fromFirestore(
        (record['thread'] as Map).cast<String, dynamic>(),
      );
      final user = ChatUser.fromFirestore(
        (record['user'] as Map).cast<String, dynamic>(),
      );
      final messages = await cache.loadAll(entry.key);
      final cleared = await cache.getClearedBefore(entry.key);
      final visible =
          messages
              .where(
                (m) =>
                    !m.isDeletedFor(uid) &&
                    (cleared == null || m.sentAt.isAfter(cleared)),
              )
              .toList()
            ..sort((a, b) => b.sentAt.compareTo(a.sentAt));
      final last = visible.firstOrNull;
      final readAt =
          int.tryParse(
            await cache.readSetting('sms_read_${uid}_${entry.key}') ?? '',
          ) ??
          0;
      final unread = visible
          .where(
            (m) =>
                m.isDataSms &&
                m.senderId != uid &&
                m.sentAt.millisecondsSinceEpoch > readAt,
          )
          .length;
      if (last != null && last.sentAt.isAfter(thread.lastMessageAt)) {
        thread = thread.copyWith(
          lastMessage: last.isDataSms ? 'Data SMS' : 'Encrypted message',
          lastMessageAt: last.sentAt,
        );
      }
      result.add(
        SmsLocalThread(thread.copyWith(unreadCounts: {uid: unread}), user),
      );
    }
    _checkAccount(uid);
    return result;
  }

  Future<ChatMessage> send({
    required ChatThread thread,
    required ChatUser recipient,
    required String text,
  }) async {
    final uid = _requireUid();
    await crypto.requireAccount(uid);
    if (thread.threadId != ChatThread.buildId(uid, recipient.uid) ||
        !await crypto.hasThreadKey(thread.threadId)) {
      throw StateError('Set up this encrypted conversation online first.');
    }
    final destination = await phone(thread.threadId);
    if (destination == null) {
      throw StateError('Set a recipient phone number first.');
    }
    if (!await native.isSupported()) {
      throw StateError('This device does not support data SMS.');
    }
    final plain = text.trim();
    if (plain.isEmpty) throw const FormatException('Enter a text message.');
    await native.requestPermission();
    _checkAccount(uid);
    final id = const Uuid().v4();
    final at = DateTime.now().toUtc();
    final encryptedEnvelope = await crypto.encryptMessage(
      threadId: thread.threadId,
      plaintext: DataSmsProtocol.body(
        id: id,
        threadId: thread.threadId,
        senderId: uid,
        recipientId: recipient.uid,
        sentAt: at.millisecondsSinceEpoch,
        text: plain,
      ),
    );
    final payload = DataSmsProtocol.pack(thread.threadId, encryptedEnvelope);
    var message = ChatMessage(
      messageId: id,
      threadId: thread.threadId,
      senderId: uid,
      encryptedText: await crypto.encryptMessage(
        threadId: thread.threadId,
        plaintext: plain,
      ),
      sentAt: at,
      deletedFor: const [],
      transport: MessageTransport.dataSms,
      smsSegments: DataSmsProtocol.segmentCount(payload.length),
      smsDeliveryState: 'submitting',
    );
    _checkAccount(uid);
    await _save(message);
    await cache.writeSetting('sms_outgoing_${uid}_$id', '1');
    _checkAccount(uid);
    try {
      final status = await native.send(
        messageId: id,
        payload: payload,
        phone: destination,
      );
      message = message.copyWith(
        smsDeliveryState: status.state,
        smsError: status.error,
        clearSmsError: status.error == null,
      );
    } on PlatformException {
      // Submission may have reached the modem. Never retry automatically.
      message = message.copyWith(
        smsDeliveryState: 'unconfirmed',
        smsError:
            'Submission could not be confirmed. Check before sending again; charges may apply.',
      );
    }
    _checkAccount(uid);
    await _save(message);
    return message.withDecryptedText(plain);
  }

  Future<void> _save(ChatMessage message) async {
    await cache.save([message]);
    if (!_disposed) _changes.add(message);
  }

  void start() {
    if (_disposed || !isUnlocked() || currentUid() == null) return;
    _timer ??= Timer.periodic(
      const Duration(seconds: 3),
      (_) => _refreshLogged(),
    );
    unawaited(_refreshLogged());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _rejected.clear();
    _recoverInterrupted = true;
  }

  Future<void> _refreshLogged() async {
    try {
      await refresh();
    } catch (error) {
      debugPrint('Data SMS processing unavailable: ${error.runtimeType}');
      if (!_disposed) {
        _changes.addError(
          StateError(
            'Data SMS processing unavailable. Reopen chat to try again.',
          ),
        );
      }
    }
  }

  Future<void> refresh() async {
    if (_polling || _disposed || !isUnlocked() || currentUid() == null) return;
    _polling = true;
    try {
      final uid = _requireUid();
      await crypto.requireAccount(uid);
      final snapshot = await native.snapshot();
      final records = await _contacts(uid);
      for (final incoming in snapshot.incoming) {
        final rejectionId = '$uid:${incoming.phone}:${incoming.id}';
        if (_rejected.contains(rejectionId)) continue;
        try {
          final wire = DataSmsProtocol.unpack(incoming.payload);
          final contact = records[wire.threadId] as Map?;
          if (contact == null || !await crypto.hasThreadKey(wire.threadId)) {
            continue;
          }
          final envelope = jsonDecode(
            await crypto.decryptMessage(
              threadId: wire.threadId,
              encryptedB64: wire.ciphertext,
            ),
          );
          if (envelope is! Map ||
              envelope['v'] != 1 ||
              envelope['id'] != incoming.id ||
              envelope['t'] != wire.threadId ||
              envelope['r'] != uid ||
              envelope['s'] != (contact['user'] as Map)['uid'] ||
              wire.threadId !=
                  ChatThread.buildId(uid, envelope['s'] as String) ||
              envelope['at'] is! int ||
              (envelope['at'] as int) < 0 ||
              (envelope['at'] as int) > 8640000000000000 ||
              envelope['text'] is! String ||
              (envelope['text'] as String).trim().isEmpty) {
            throw const FormatException(
              'Invalid authenticated data SMS identity.',
            );
          }
          _checkAccount(uid);
          final existing = await cache.loadById(incoming.id);
          final seenKey = 'sms_seen_${uid}_${incoming.id}';
          final seen = await cache.readSetting(seenKey) != null;
          final at = DateTime.fromMillisecondsSinceEpoch(
            envelope['at'] as int,
            isUtc: true,
          );
          final cleared = await cache.getClearedBefore(wire.threadId);
          final horizon = await cache.getHistoryHorizon();
          if (!seen &&
              existing == null &&
              (cleared == null || at.isAfter(cleared)) &&
              (horizon == null || at.isAfter(horizon))) {
            final message = ChatMessage(
              messageId: incoming.id,
              threadId: wire.threadId,
              senderId: envelope['s'] as String,
              encryptedText: await crypto.encryptMessage(
                threadId: wire.threadId,
                plaintext: envelope['text'] as String,
              ),
              sentAt: at,
              deletedFor: const [],
              transport: MessageTransport.dataSms,
              smsSegments: DataSmsProtocol.segmentCount(
                incoming.payload.length,
              ),
              smsDeliveryState: 'received',
            );
            _checkAccount(uid);
            await _save(message);
            await onIncoming?.call(
              ChatThread.fromFirestore(
                (contact['thread'] as Map).cast<String, dynamic>(),
              ),
            );
          }
          _checkAccount(uid);
          await cache.writeSetting(seenKey, '1');
          await native.acknowledge(
            messageId: incoming.id,
            source: incoming.phone,
          );
        } on FormatException {
          _reject(rejectionId);
        } on SecretBoxAuthenticationError {
          _reject(rejectionId);
        }
      }
      for (final status in snapshot.outgoing) {
        _checkAccount(uid);
        final message = await cache.loadById(status.id);
        if (message == null) {
          if (status.state == 'delivered' &&
              await cache.readSetting('sms_outgoing_${uid}_${status.id}') !=
                  null) {
            _checkAccount(uid);
            await native.acknowledgeOutgoing(messageId: status.id);
            await cache.writeSetting('sms_outgoing_${uid}_${status.id}', null);
          }
          continue;
        }
        if (!message.isDataSms || message.senderId != uid) {
          continue;
        }
        if (message.smsDeliveryState != status.state ||
            message.smsError != status.error) {
          await _save(
            message.copyWith(
              smsDeliveryState: status.state,
              smsError: status.error,
              clearSmsError: status.error == null,
            ),
          );
        }
        if (status.state == 'delivered') {
          _checkAccount(uid);
          await native.acknowledgeOutgoing(messageId: status.id);
          await cache.writeSetting('sms_outgoing_${uid}_${status.id}', null);
        }
      }
      final knownOutgoing = snapshot.outgoing
          .map((status) => status.id)
          .toSet();
      if (_recoverInterrupted) {
        _recoverInterrupted = false;
        for (final threadId in records.keys) {
          for (final message in await cache.loadAll(threadId)) {
            if (message.isDataSms &&
                message.senderId == uid &&
                message.smsDeliveryState == 'submitting' &&
                !knownOutgoing.contains(message.messageId)) {
              if (DateTime.now().toUtc().difference(message.sentAt) <=
                  const Duration(seconds: 30)) {
                _recoverInterrupted = true;
                continue;
              }
              _checkAccount(uid);
              await _save(
                message.copyWith(
                  smsDeliveryState: 'unconfirmed',
                  smsError:
                      'Submission interrupted. Check before sending again; charges may apply.',
                ),
              );
            }
          }
        }
      }
    } finally {
      _polling = false;
    }
  }

  void _reject(String id) {
    _rejected.add(id);
    debugPrint('Rejected invalid or unauthenticated data SMS.');
    if (!_disposed) {
      _changes.addError(
        const FormatException('An invalid data SMS was rejected.'),
      );
    }
  }

  void dispose() {
    stop();
    _disposed = true;
    unawaited(_changes.close());
  }
}
