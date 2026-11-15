import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/application/crypto/chat_crypto_service.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_message.dart';
import 'package:photo_vault/features/chat/domain/repositories/message_repository.dart';
import 'package:photo_vault/features/chat/presentation/widgets/chat_media_preview.dart';
import 'package:photo_vault/features/chat/presentation/widgets/data_sms_meta.dart';
import 'package:photo_vault/features/chat/presentation/widgets/message_bubble.dart';

class _NoMedia implements MediaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoCrypto implements ChatCryptoService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'sent and received emoji SMS keep distinct colored bubbles and safe actions',
    (tester) async {
      final theme = ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      );
      for (final isMine in [true, false]) {
        final sms = ChatMessage(
          messageId: 'emoji',
          threadId: 'alice_bob',
          senderId: isMine ? 'alice' : 'bob',
          encryptedText: 'encrypted',
          localDecryptedText: '🙂',
          sentAt: DateTime.utc(2026),
          deletedFor: const [],
          transport: MessageTransport.dataSms,
          smsSegments: 2,
          smsDeliveryState: 'delivered',
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: MessageBubble(
                message: sms,
                isMine: isMine,
                myUid: 'alice',
                otherUid: 'bob',
                mediaLoader: ChatMediaLoader(
                  mediaRepository: _NoMedia(),
                  cryptoService: _NoCrypto(),
                ),
                onDeleteForMe: () {},
                onReply: () {},
                onReact: (_) {},
                onEdit: () {},
                onForward: () {},
                onDeleteForEveryone: () {},
                isOffline: true,
              ),
            ),
          ),
        );
        final color = isMine
            ? theme.colorScheme.tertiaryContainer
            : theme.colorScheme.secondaryContainer;
        expect(
          find.byWidgetPredicate(
            (widget) => widget is Material && widget.color == color,
          ),
          findsOneWidget,
        );
        expect(find.text('Data SMS · 2 segments'), findsOneWidget);
        expect(find.text('Waiting for connection'), findsNothing);
        await tester.longPress(find.text('Data SMS · 2 segments'));
        await tester.pumpAndSettle();
        expect(find.text('Delete for me'), findsOneWidget);
        expect(find.text('Reply'), findsNothing);
        expect(find.text('Edit'), findsNothing);
        expect(find.text('Forward'), findsNothing);
        expect(find.text('Delete for everyone'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  ChatMessage message(String state) => ChatMessage(
    messageId: 'sms',
    threadId: 'alice_bob',
    senderId: 'alice',
    encryptedText: 'encrypted',
    sentAt: DateTime.utc(2026),
    deletedFor: const [],
    transport: MessageTransport.dataSms,
    smsSegments: 3,
    smsDeliveryState: state,
  );

  testWidgets('SMS labels distinguish device delivery from reading', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DataSmsMeta(
            message: message('delivered'),
            isMine: true,
            color: Colors.black,
          ),
        ),
      ),
    );
    expect(find.text('Data SMS · 3 segments'), findsOneWidget);
    expect(find.text('Device delivered'), findsOneWidget);
    expect(find.textContaining('Read'), findsNothing);
  });

  testWidgets('sent without a carrier report stays unconfirmed offline', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DataSmsMeta(
            message: message('sent'),
            isMine: true,
            color: Colors.black,
          ),
        ),
      ),
    );
    expect(find.text('Sent; delivery unconfirmed'), findsOneWidget);
    expect(find.textContaining('Waiting for connection'), findsNothing);
  });

  testWidgets('received SMS shows count without sender delivery state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DataSmsMeta(
            message: message('received'),
            isMine: false,
            color: Colors.black,
          ),
        ),
      ),
    );
    expect(find.text('Data SMS · 3 segments'), findsOneWidget);
    expect(find.text('Sending'), findsNothing);
  });
}
