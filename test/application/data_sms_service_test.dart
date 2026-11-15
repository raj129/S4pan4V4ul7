import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/application/crypto/chat_crypto_service.dart';
import 'package:photo_vault/features/chat/application/services/android_data_sms.dart';
import 'package:photo_vault/features/chat/application/services/data_sms_protocol.dart';
import 'package:photo_vault/features/chat/application/services/data_sms_service.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_thread.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_user.dart';

import '../helpers/memory_message_cache.dart';

class _Native implements AndroidDataSms {
  int submissions = 0;
  Uint8List? payload;
  String? destination;
  bool permitted = true;
  final incoming = <NativeSmsIncoming>[];
  final outgoing = <NativeSmsStatus>[];
  final acknowledged = <String>[];
  final outgoingAcknowledged = <String>[];
  void Function()? duringSnapshot;

  @override
  Future<NativeSmsSnapshot> snapshot() async {
    duringSnapshot?.call();
    return NativeSmsSnapshot(incoming: [...incoming], outgoing: [...outgoing]);
  }

  @override
  Future<void> acknowledgeOutgoing({required String messageId}) async {
    outgoingAcknowledged.add(messageId);
    outgoing.removeWhere(
      (status) => status.id == messageId && status.state == 'delivered',
    );
  }

  @override
  Future<void> acknowledge({
    required String messageId,
    required String source,
  }) async {
    acknowledged.add(messageId);
    incoming.removeWhere(
      (message) => message.id == messageId && message.phone == source,
    );
  }

  @override
  Future<bool> isSupported() async => true;
  @override
  Future<void> requestPermission() async {
    if (!permitted) throw PlatformException(code: 'permission_denied');
  }

  @override
  Future<NativeSmsStatus> send({
    required String messageId,
    required Uint8List payload,
    required String phone,
  }) async {
    submissions++;
    this.payload = payload;
    destination = phone;
    throw PlatformException(code: 'ambiguous_submission');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final thread = ChatThread(
    threadId: 'alice_bob',
    participantIds: const ['alice', 'bob'],
    lastMessage: '',
    lastMessageAt: DateTime.utc(2026),
    createdAt: DateTime.utc(2026),
    unreadCounts: const {},
  );
  final bob = ChatUser(
    uid: 'bob',
    email: 'bob@example.com',
    displayName: 'Bob',
    publicKey: '',
    createdAt: DateTime.utc(2026),
  );
  late _Native native;
  late DataSmsService service;
  late MemoryMessageCache cache;
  late ChatCryptoService crypto;
  bool unlocked = true;
  String? uid = 'alice';

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({
      'chat_key_account': 'alice',
      'chat_thread_key_alice_bob': base64Encode(List<int>.filled(32, 7)),
    });
    uid = 'alice';
    unlocked = true;
    native = _Native();
    crypto = ChatCryptoService();
    cache = MemoryMessageCache();
    service = DataSmsService(
      native: native,
      crypto: crypto,
      cache: cache,
      currentUid: () => uid,
      isUnlocked: () => unlocked,
    );
    await service.remember(thread, bob);
    await service.setPhone(thread.threadId, '+91 (98765) 43210');
  });
  tearDown(() => service.dispose());

  Future<void> send(String text) =>
      service.send(thread: thread, recipient: bob, text: text);

  Future<NativeSmsIncoming> received({
    String id = '12345678-1234-4234-8234-123456789012',
    String? recipient,
    String text = 'offline hello',
  }) async => NativeSmsIncoming(
    id: id,
    phone: '+12345678901',
    payload: DataSmsProtocol.pack(
      thread.threadId,
      await crypto.encryptMessage(
        threadId: thread.threadId,
        plaintext: DataSmsProtocol.body(
          id: id,
          threadId: thread.threadId,
          senderId: 'bob',
          recipientId: recipient ?? 'alice',
          sentAt: DateTime.now().toUtc().millisecondsSinceEpoch,
          text: text,
        ),
      ),
    ),
  );

  Future<NativeSmsIncoming> receivedV2({
    String id = '12345678-1234-4234-8234-123456789012',
    String phone = '+919876543210',
    String text = 'offline hello',
  }) async {
    final sentAtMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    return NativeSmsIncoming(
      id: id,
      phone: phone,
      payload: DataSmsProtocol.packV2(
        sentAtMs: sentAtMs,
        encryptedBytes: await crypto.encryptDataSms(
          threadId: thread.threadId,
          sentAtMs: sentAtMs,
          plaintext: text,
        ),
      ),
    );
  }

  test(
    'manual number normalizes but is not published to message storage',
    () async {
      expect(await service.phone(thread.threadId), '+919876543210');
      await expectLater(
        service.setPhone(thread.threadId, '9876543210'),
        throwsFormatException,
      );
      expect(cache.rows, isEmpty);
      await service.setPhone(thread.threadId, null);
      await expectLater(send('hello'), throwsStateError);
      expect(native.submissions, 0);
    },
  );

  test(
    'ambiguous submission persists encrypted local state without automatic retries',
    () async {
      final message = await service.send(
        thread: thread,
        recipient: bob,
        text: 'hello',
      );
      expect(native.submissions, 1);
      expect(message.isDataSms, isTrue);
      expect(message.smsDeliveryState, 'unconfirmed');
      expect(message.localDecryptedText, 'hello');
      final stored = await cache.loadById(message.messageId);
      expect(stored!.localDecryptedText, isNull);
      expect(cache.rows.values.single.payloadJson, isNot(contains('hello')));
      final packet = DataSmsProtocol.unpack(native.payload!);
      expect(packet.version, 2);
      expect(packet.sentAtMs, message.sentAt.millisecondsSinceEpoch);
      expect(
        await crypto.decryptDataSms(
          threadId: thread.threadId,
          sentAtMs: packet.sentAtMs!,
          encryptedBytes: packet.encryptedBytes!,
        ),
        'hello',
      );
      expect(
        message.smsSegments,
        DataSmsProtocol.segmentCount(native.payload!.length),
      );
      expect(message.smsSegments, 1);
      expect(native.destination, '+919876543210');
      await Future<void>.delayed(Duration.zero);
      expect(native.submissions, 1);
    },
  );

  test(
    'permission denial and oversized messages never reach native send',
    () async {
      native.permitted = false;
      await expectLater(send('hello'), throwsA(isA<PlatformException>()));
      expect(cache.rows, isEmpty);
      native.permitted = true;
      await expectLater(
        send(List.filled(2000, 'x').join()),
        throwsFormatException,
      );
      expect(native.submissions, 0);
      expect(cache.rows, isEmpty);
    },
  );

  test('locked, wrong account and absent keys block sends', () async {
    unlocked = false;
    await expectLater(send('hello'), throwsStateError);
    unlocked = true;
    uid = 'bob';
    await expectLater(send('hello'), throwsStateError);
    uid = 'alice';
    await const FlutterSecureStorage().delete(key: 'chat_thread_key_alice_bob');
    await expectLater(send('hello'), throwsStateError);
    expect(native.submissions, 0);
  });

  test(
    'known conversation and phone mapping survive service restart',
    () async {
      await service.send(thread: thread, recipient: bob, text: 'hello');
      service.dispose();
      service = DataSmsService(
        native: native,
        crypto: crypto,
        cache: cache,
        currentUid: () => uid,
        isUnlocked: () => unlocked,
      );
      expect(await service.phone(thread.threadId), '+919876543210');
      final local = await service.localThreads();
      expect(local.single.thread.threadId, thread.threadId);
      expect(local.single.thread.lastMessage, 'Data SMS');
      expect(local.single.user.uid, 'bob');
    },
  );

  test(
    'authenticated offline receipt saves before acknowledgement and deduplicates replay',
    () async {
      final incoming = await received();
      native.incoming.add(incoming);
      await service.refresh();
      expect(native.acknowledged, [incoming.id]);
      final stored = await cache.loadById(incoming.id);
      expect(stored!.isDataSms, isTrue);
      expect(stored.localDecryptedText, isNull);
      expect(
        await crypto.decryptMessage(
          threadId: thread.threadId,
          encryptedB64: stored.encryptedText,
        ),
        'offline hello',
      );
      expect(
        (await service.localThreads()).single.thread.unreadCountFor('alice'),
        1,
      );
      await service.markRead(thread.threadId);
      expect(
        (await service.localThreads()).single.thread.unreadCountFor('alice'),
        0,
      );
      await cache.remove(incoming.id);
      native.incoming.add(incoming);
      await service.refresh();
      expect(await cache.loadById(incoming.id), isNull);
      expect(native.acknowledged, hasLength(2));
    },
  );

  test(
    'compact V2 routes by sender phone to the linked encrypted thread',
    () async {
      final incoming = await receivedV2(text: 'V2 from phone');
      native.incoming.add(incoming);
      await service.refresh();

      expect(native.acknowledged, [incoming.id]);
      final stored = await cache.loadById(incoming.id);
      expect(stored?.threadId, thread.threadId);
      expect(stored?.senderId, 'bob');
      expect(stored?.smsSegments, 1);
      expect(
        await crypto.decryptMessage(
          threadId: thread.threadId,
          encryptedB64: stored!.encryptedText,
        ),
        'V2 from phone',
      );
    },
  );

  test(
    'compact V2 from an unlinked phone is not routed or acknowledged',
    () async {
      native.incoming.add(
        await receivedV2(phone: '+12025550123', text: 'unlinked'),
      );
      await service.refresh();
      expect(cache.rows, isEmpty);
      expect(native.acknowledged, isEmpty);
    },
  );

  test('ambiguous phone mappings do not guess a destination thread', () async {
    final otherThread = ChatThread(
      threadId: 'alice_carol',
      participantIds: const ['alice', 'carol'],
      lastMessage: '',
      lastMessageAt: DateTime.utc(2026),
      createdAt: DateTime.utc(2026),
      unreadCounts: const {},
    );
    final carol = ChatUser(
      uid: 'carol',
      email: 'carol@example.com',
      displayName: 'Carol',
      publicKey: '',
      createdAt: DateTime.utc(2026),
    );
    await service.remember(otherThread, carol);
    await service.setPhone(otherThread.threadId, '+919876543210');
    final incoming = await receivedV2(text: 'ambiguous phone');
    native.incoming.add(incoming);

    await service.refresh();

    expect(cache.rows, isEmpty);
    expect(native.acknowledged, isEmpty);
  });

  test(
    'wrong recipient and tampered ciphertext are never imported or acknowledged',
    () async {
      native.incoming.add(await received(recipient: 'eve'));
      final valid = await received(id: '22345678-1234-4234-8234-123456789012');
      final corrupted = Uint8List.fromList(valid.payload);
      corrupted[corrupted.length - 1] ^= 1;
      native.incoming.add(
        NativeSmsIncoming(id: valid.id, phone: valid.phone, payload: corrupted),
      );
      await service.refresh();
      expect(cache.rows, isEmpty);
      expect(native.acknowledged, isEmpty);
    },
  );

  test(
    'locked receipt waits, then clears and account changes cannot import stale messages',
    () async {
      native.incoming.add(await received());
      unlocked = false;
      await service.refresh();
      expect(cache.rows, isEmpty);
      expect(native.acknowledged, isEmpty);
      unlocked = true;
      cache.cleared[thread.threadId] = DateTime.now().toUtc().add(
        const Duration(minutes: 1),
      );
      await service.refresh();
      expect(cache.rows, isEmpty);
      expect(native.acknowledged, hasLength(1));
      native.incoming.add(
        await received(id: '32345678-1234-4234-8234-123456789012'),
      );
      native.duringSnapshot = () => uid = 'bob';
      await expectLater(service.refresh(), throwsStateError);
      expect(cache.rows, isEmpty);
      expect(native.acknowledged, hasLength(1));
    },
  );

  test(
    'delivery cleanup does not resurrect locally cleared outgoing history',
    () async {
      final message = await service.send(
        thread: thread,
        recipient: bob,
        text: 'hello',
      );
      await cache.clearThread(thread.threadId);
      native.outgoing.add(
        NativeSmsStatus(
          id: message.messageId,
          state: 'delivered',
          segments: const [],
        ),
      );
      await service.refresh();
      expect(cache.rows, isEmpty);
      expect(native.outgoingAcknowledged, [message.messageId]);
    },
  );

  test(
    'persisted carrier updates survive restart without inventing read receipts',
    () async {
      final message = await service.send(
        thread: thread,
        recipient: bob,
        text: 'hello',
      );
      service.dispose();
      service = DataSmsService(
        native: native,
        crypto: crypto,
        cache: cache,
        currentUid: () => uid,
        isUnlocked: () => unlocked,
      );
      native.outgoing.add(
        NativeSmsStatus(
          id: message.messageId,
          state: 'delivered',
          segments: const [],
        ),
      );
      await service.refresh();
      final updated = await cache.loadById(message.messageId);
      expect(updated!.smsDeliveryState, 'delivered');
      expect(updated.smsError, isNull);
      expect(updated.readBy, isEmpty);
      expect(updated.deliveredTo, isEmpty);
      expect(native.submissions, 1);
      expect(native.outgoingAcknowledged, [message.messageId]);
    },
  );
}
