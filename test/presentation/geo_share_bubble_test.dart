import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_message.dart';
import 'package:photo_vault/features/chat/domain/entities/geo_share.dart';
import 'package:photo_vault/features/chat/presentation/widgets/geo_share_bubble.dart';

void main() {
  testWidgets('arrival card shows the message sent time in local time', (
    tester,
  ) async {
    final sentAt = DateTime.utc(2026, 11, 9, 6, 3);
    final message = _message(
      share: const GeoShare.arrival(point: GeoPoint(1, 2), label: 'Office'),
      sentAt: sentAt,
    );

    await tester.pumpWidget(_app(message));

    expect(
      find.text('Sent ${DateFormat.jm().format(sentAt.toLocal())}'),
      findsOneWidget,
    );
  });

  testWidgets('pin and route cards do not show arrival sent-time text', (
    tester,
  ) async {
    final sentAt = DateTime.utc(2026, 11, 9, 6, 3);
    for (final share in [
      const GeoShare.pin(point: GeoPoint(1, 2), label: 'Home'),
      const GeoShare.route(origin: GeoPoint(1, 2), destination: GeoPoint(3, 4)),
    ]) {
      await tester.pumpWidget(_app(_message(share: share, sentAt: sentAt)));
      expect(find.textContaining('Sent '), findsNothing);
    }
  });
}

ChatMessage _message({required GeoShare share, required DateTime sentAt}) =>
    ChatMessage(
      messageId: 'message',
      threadId: 'thread',
      senderId: 'sender',
      encryptedText: '',
      sentAt: sentAt,
      deletedFor: const [],
      mediaType: switch (share.kind) {
        GeoShareKind.pin => MessageType.pin,
        GeoShareKind.route => MessageType.route,
        GeoShareKind.arrival => MessageType.arrival,
      },
      localDecryptedText: share.encode(),
    );

Widget _app(ChatMessage message) => MaterialApp(
  home: Scaffold(body: GeoShareBubble(message: message, isMine: false)),
);
