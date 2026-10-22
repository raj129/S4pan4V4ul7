import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/features/chat/application/media/android_chat_secure_media_service.dart';
import 'package:photo_vault/features/chat/application/crypto/chat_crypto_service.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_message.dart';
import 'package:photo_vault/features/chat/domain/repositories/message_repository.dart';
import 'package:photo_vault/features/chat/presentation/screens/chat_image_viewer_screen.dart';
import 'package:photo_vault/features/chat/presentation/widgets/chat_media_preview.dart';

class _Unused implements MediaRepository, ChatCryptoService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Loader extends ChatMediaLoader {
  _Loader(this.source)
      : super(mediaRepository: _Unused(), cryptoService: _Unused());

  final Future<Uint8List> source;
  final owned = <Uint8List>[];
  final senders = <String?>[];
  int loads = 0;

  @override
  Future<Uint8List> fetchUncached({
    required String threadId,
    required String storagePath,
    String? senderId,
  }) async {
    senders.add(senderId);
    final bytes = Uint8List.fromList(await source);
    owned.add(bytes);
    return bytes;
  }

  @override
  Future<Uint8List> load({
    required String threadId,
    required String storagePath,
    String? senderId,
  }) {
    loads++;
    return fetchUncached(
      threadId: threadId,
      storagePath: storagePath,
      senderId: senderId,
    );
  }
}

class _Media extends AndroidChatSecureMediaService {
  final methods = <String>[];
  final buffers = <Uint8List>[];
  Completer<void>? viewing;
  int closes = 0;

  Future<void> _show(String method, Uint8List bytes) {
    methods.add(method);
    buffers.add(bytes);
    return viewing?.future ?? Future.value();
  }

  @override
  Future<void> showPdf(Uint8List bytes) => _show('pdf', bytes);

  @override
  Future<void> showVideo(Uint8List bytes) => _show('video', bytes);

  @override
  Future<void> showAudio(Uint8List bytes) => _show('audio', bytes);

  @override
  Future<void> close() async {
    closes++;
    viewing?.complete();
  }
}

ChatMessage _message(String name) =>
    ChatMessage(
      messageId: 'm',
      threadId: 't',
      senderId: 'sender',
      encryptedText: 'encrypted-name',
      localDecryptedText: name,
      sentAt: DateTime.utc(2026),
      deletedFor: const [],
      mediaType: MessageType.file,
      mediaRef: 'remote-path-does-not-indicate-direction',
    );

Widget _tile(String name, _Loader loader, _Media media) =>
    MaterialApp(
      home: Scaffold(
        body: ChatDocumentTile(
          message: _message(name),
          loader: loader,
          service: media,
          textColor: Colors.black,
        ),
      ),
    );

void main() {
  for (final (name, header, expected) in [
    ('not-a-pdf.jpg', '%PDF-1.7', 'pdf'),
    ('recording.wav', 'RIFF0000WAVE', 'audio'),
    ('recording.ogg', 'OggS', 'audio'),
    ('movie.mp4', 'unrecognized-header', 'video'),
    ('recording.m4a', 'unrecognized-header', 'audio'),
  ]) {
    testWidgets(
      'generic $name routes to in-app $expected',
          (tester) async {
        final caller = Uint8List.fromList(
          header.codeUnits,
        ).asUnmodifiableView();
        final loader = _Loader(Future.value(caller));
        final media = _Media();
        await tester.pumpWidget(_tile(name, loader, media));
        await tester.tap(find.text(name));
        await tester.pumpAndSettle();
        expect(media.methods, [expected]);
        expect(loader.senders, ['sender']);
        expect(media.buffers.single.every((byte) => byte == 0), isTrue);
        expect(caller, header.codeUnits);
        await tester.pumpWidget(const SizedBox.shrink());
        loader.dispose();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets(
    'image header overrides document name and uses owned image viewer',
        (tester) async {
      final caller = Uint8List.fromList(
        img.encodePng(img.Image(width: 2, height: 2)),
      ).asUnmodifiableView();
      final loader = _Loader(Future.value(caller));
      final media = _Media();
      await tester.pumpWidget(_tile('photo.pdf', loader, media));
      await tester.tap(find.text('photo.pdf'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ChatImageViewerScreen), findsOneWidget);
      final provider =
      tester
          .widget<Image>(find.byType(Image))
          .image as MemoryImage;
      expect(identical(provider.bytes, loader.owned.single), isFalse);
      expect(provider.bytes, caller);
      expect(loader.loads, 0);
      expect(loader.senders, ['sender']);
      expect(media.methods, isEmpty);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(provider.bytes.every((byte) => byte == 0), isTrue);
      expect(loader.owned.single.every((byte) => byte == 0), isTrue);
      expect(caller.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      await tester.pumpWidget(const SizedBox.shrink());
      loader.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'unsupported archives remain in-app with explicit vault guidance',
        (tester) async {
      final loader = _Loader(Future.value(Uint8List.fromList([80, 75, 3, 4])));
      final media = _Media();
      await tester.pumpWidget(_tile('archive.zip', loader, media));
      await tester.tap(find.text('archive.zip'));
      await tester.pumpAndSettle();
      expect(find.textContaining('move it to the vault'), findsOneWidget);
      expect(media.methods, isEmpty);
      expect(loader.owned.single.every((byte) => byte == 0), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      loader.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'disposed document tile fences a late authenticated load',
        (tester) async {
      final pending = Completer<Uint8List>();
      final loader = _Loader(pending.future);
      final media = _Media();
      await tester.pumpWidget(_tile('movie.mp4', loader, media));
      await tester.tap(find.text('movie.mp4'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(Uint8List.fromList([1, 2, 3]));
      await tester.pump();
      expect(media.methods, isEmpty);
      expect(loader.owned.single.every((byte) => byte == 0), isTrue);
      expect(tester.takeException(), isNull);
      loader.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'disposing an active native document viewer closes and wipes',
        (tester) async {
      final loader = _Loader(Future.value(Uint8List.fromList([1, 2, 3])));
      final media = _Media()
        ..viewing = Completer<void>();
      await tester.pumpWidget(_tile('movie.mp4', loader, media));
      await tester.tap(find.text('movie.mp4'));
      await tester.pump();
      expect(media.methods, ['video']);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(media.closes, 1);
      expect(loader.owned.single.every((byte) => byte == 0), isTrue);
      expect(tester.takeException(), isNull);
      loader.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
