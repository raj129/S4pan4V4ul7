import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/crypto/services/chat_crypto_service.dart';
import 'package:photo_vault/domain/entities/chat_message.dart';
import 'package:photo_vault/domain/repositories/message_repository.dart';
import 'package:photo_vault/presentation/screens/chat_screens/chat_image_viewer_screen.dart';
import 'package:photo_vault/presentation/widgets/chat/chat_media_preview.dart';

class _UnusedMedia implements MediaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedCrypto implements ChatCryptoService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Loader extends ChatMediaLoader {
  _Loader()
    : super(mediaRepository: _UnusedMedia(), cryptoService: _UnusedCrypto());
  int calls = 0;
  Future<Uint8List> Function()? response;
  @override
  Future<Uint8List> load({
    required String threadId,
    required String storagePath,
  }) {
    calls++;
    return response?.call() ?? Completer<Uint8List>().future;
  }
}

void main() {
  testWidgets('chat loader provider observes changes without owning disposal', (
    tester,
  ) async {
    final loader = _Loader();
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          ChangeNotifierProvider<ChatMediaLoader>.value(value: loader),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              final media = context.watch<ChatMediaLoader>();
              return Text(media.cached('preview') == null ? 'empty' : 'ready');
            },
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('empty'), findsOneWidget);
    loader.seed('preview', Uint8List.fromList([1]));
    await tester.pump();
    expect(find.text('ready'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    loader.seed('preview', Uint8List.fromList([2]));
    expect(loader.cached('preview'), [2]);
    loader.dispose();
  });

  final image = Uint8List.fromList(
    img.encodePng(img.Image(width: 2, height: 2)),
  );
  final message = ChatMessage(
    messageId: 'm',
    threadId: 't',
    senderId: 'alice',
    encryptedText: 'e',
    sentAt: DateTime.utc(2026),
    deletedFor: const [],
    mediaType: MessageType.image,
    mediaRef: 'image',
  );

  testWidgets('same-reference seed immediately updates an open thumbnail', (
    tester,
  ) async {
    final loader = _Loader();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMediaPreview(message: message, loader: loader),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    loader.seed('image', image);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    loader.dispose();
  });

  testWidgets('full viewer can retry a failed load without reopening', (
    tester,
  ) async {
    final loader = _Loader();
    loader.response = () => Future.error(TimeoutException('network stalled'));
    await tester.pumpWidget(
      MaterialApp(
        home: ChatImageViewerScreen(message: message, loader: loader),
      ),
    );
    await tester.pump();
    expect(find.byTooltip('Retry'), findsOneWidget);
    loader.response = () async => image;
    await tester.tap(find.byTooltip('Retry'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(loader.calls, 2);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    loader.dispose();
  });
}
