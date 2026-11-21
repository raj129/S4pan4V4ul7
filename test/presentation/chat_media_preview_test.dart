import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/features/chat/application/crypto/chat_crypto_service.dart';
import 'package:photo_vault/features/chat/application/media/android_chat_downloads.dart';
import 'package:photo_vault/features/chat/application/media/android_chat_local_media.dart';
import 'package:photo_vault/features/chat/application/media/media_send_status.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_message.dart';
import 'package:photo_vault/features/chat/domain/entities/message_metadata.dart';
import 'package:photo_vault/features/chat/domain/repositories/message_repository.dart';
import 'package:photo_vault/features/chat/presentation/screens/chat_image_viewer_screen.dart';
import 'package:photo_vault/features/chat/presentation/widgets/attachment_upload_progress.dart';
import 'package:photo_vault/features/chat/presentation/widgets/chat_media_preview.dart';
import 'package:photo_vault/features/chat/presentation/widgets/message_bubble.dart';
import 'package:photo_vault/core/presentation/theme/app_theme.dart';

class _UnusedMedia implements MediaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedCrypto implements ChatCryptoService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Loader extends ChatMediaLoader {
  _Loader({super.downloads})
    : super(mediaRepository: _UnusedMedia(), cryptoService: _UnusedCrypto());
  int calls = 0;
  final List<String?> senders = [];
  final List<Uint8List> ownedResults = [];
  Future<Uint8List> Function()? response;
  @override
  Future<Uint8List> load({
    required String threadId,
    required String storagePath,
    String? senderId,
    ChatMediaLoadToken? token,
  }) {
    calls++;
    senders.add(senderId);
    // Match the loader's consumer-owned return contract.
    return (response?.call() ?? Completer<Uint8List>().future).then((bytes) {
      final owned = Uint8List.fromList(bytes);
      ownedResults.add(owned);
      return owned;
    });
  }
}

class _Downloads extends AndroidChatDownloads {
  _Downloads() : super(currentUid: () => 'me', pollInterval: Duration.zero);

  AndroidDownloadJob? currentJob;

  @override
  AndroidDownloadJob? job(String path) =>
      currentJob?.storagePath == path ? currentJob : null;

  void update(AndroidDownloadJob job) {
    currentJob = job;
    notifyListeners();
  }
}

Uint8List _ownedBytes(ImageProvider provider) {
  final memory = provider is ResizeImage ? provider.imageProvider : provider;
  return (memory as MemoryImage).bytes;
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
  const uploadStatus = MediaSendStatus(
    phase: MediaSendPhase.uploading,
    progress: .5,
  );
  const failedUploadStatus = MediaSendStatus(
    phase: MediaSendPhase.uploading,
    progress: .5,
    lifecycle: MediaUploadLifecycle.failed,
  );

  testWidgets('audio upload progress appears once inside the message bubble', (
    tester,
  ) async {
    final loader = _Loader();
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MessageBubble(
            message: message.copyWith(mediaType: MessageType.audio),
            isMine: true,
            myUid: 'me',
            otherUid: 'alice',
            mediaLoader: loader,
            onDeleteForMe: () {},
            sendStatus: failedUploadStatus,
            onRetry: () => retries++,
          ),
        ),
      ),
    );

    expect(find.byType(AttachmentUploadProgress), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(retries, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    loader.dispose();
  });

  testWidgets(
    'image upload renders circular progress overlay and below-bubble actions',
    (tester) async {
      final loader = _Loader();
      var pauses = 0;
      var cancels = 0;
      const measuredUpload = MediaSendStatus(
        phase: MediaSendPhase.uploading,
        progress: .25,
        lifecycle: MediaUploadLifecycle.uploading,
        processedBytes: 256,
        totalBytes: 1024,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: MessageBubble(
              message: message,
              isMine: true,
              myUid: 'me',
              otherUid: 'alice',
              mediaLoader: loader,
              onDeleteForMe: () {},
              sendStatus: measuredUpload,
              onPauseUpload: () => pauses++,
              onCancelUpload: () => cancels++,
            ),
          ),
        ),
      );

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        find.descendant(
          of: find.byType(ChatMediaPreview),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ChatMediaPreview),
          matching: find.text('25%'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ChatMediaPreview),
          matching: find.text('256 B / 1.0 KB'),
        ),
        findsOneWidget,
      );
      expect(find.byType(AttachmentTransferActions), findsOneWidget);
      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(pauses, 1);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(cancels, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      loader.dispose();
    },
  );

  for (final mediaType in [MessageType.gif, MessageType.sticker]) {
    testWidgets('$mediaType upload uses the visual attachment controls', (
      tester,
    ) async {
      final loader = _Loader();
      const pausedUpload = MediaSendStatus(
        phase: MediaSendPhase.uploading,
        progress: .4,
        lifecycle: MediaUploadLifecycle.paused,
        processedBytes: 400,
        totalBytes: 1000,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: MessageBubble(
              message: message.copyWith(
                mediaType: mediaType,
                status: MessageStatus.sending,
              ),
              isMine: true,
              myUid: 'me',
              otherUid: 'alice',
              mediaLoader: loader,
              onDeleteForMe: () {},
              sendStatus: pausedUpload,
              onResumeUpload: () {},
              onCancelUpload: () {},
            ),
          ),
        ),
      );

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        find.descendant(
          of: find.byType(ChatMediaPreview),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(find.byType(AttachmentTransferActions), findsOneWidget);
      expect(find.text('Sending'), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.byIcon(Icons.pause_circle_outline_rounded), findsOneWidget);

      final sending = tester.getTopLeft(find.text('Sending'));
      final paused = tester.getTopLeft(find.text('Paused'));
      final metaRow = find
          .ancestor(of: find.text('Sending'), matching: find.byType(Row))
          .first;
      final timestamp = tester
          .widget<Row>(metaRow)
          .children
          .whereType<Text>()
          .first;
      final gap = sending.dx - tester.getTopRight(find.byWidget(timestamp)).dx;
      expect(gap, greaterThanOrEqualTo(4));
      expect(paused.dx, greaterThan(sending.dx));
      await tester.pumpWidget(const SizedBox.shrink());
      loader.dispose();
    });
  }

  testWidgets('paused visual download appears after message status', (
    tester,
  ) async {
    final downloads = _Downloads();
    final loader = _Loader(downloads: downloads);
    downloads.update(
      const AndroidDownloadJob(
        uid: 'me',
        storagePath: 'preview',
        threadId: 't',
        state: MediaUploadLifecycle.paused,
        processedBytes: 250,
        totalBytes: 1000,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MessageBubble(
            message: message.copyWith(
              mediaType: MessageType.gif,
              status: MessageStatus.sending,
              mediaMeta: const MediaMeta(thumbRef: 'preview'),
            ),
            isMine: true,
            myUid: 'me',
            otherUid: 'alice',
            mediaLoader: loader,
            onDeleteForMe: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Sending'), findsOneWidget);
    expect(find.text('Paused'), findsOneWidget);
    final sending = tester.getTopLeft(find.text('Sending'));
    final paused = tester.getTopLeft(find.text('Paused'));
    expect(paused.dx, greaterThan(sending.dx));
    expect(find.byType(AttachmentTransferActions), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    loader.dispose();
    downloads.dispose();
  });

  testWidgets('document upload renders only one AttachmentUploadProgress', (
    tester,
  ) async {
    final loader = _Loader();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MessageBubble(
            message: message.copyWith(
              mediaType: MessageType.file,
              localDecryptedText: 'report.pdf',
            ),
            isMine: true,
            myUid: 'me',
            otherUid: 'alice',
            mediaLoader: loader,
            onDeleteForMe: () {},
            sendStatus: uploadStatus,
          ),
        ),
      ),
    );

    expect(find.byType(AttachmentUploadProgress), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    loader.dispose();
  });

  testWidgets('failed media attachment exposes retry and cancel actions', (
    tester,
  ) async {
    final loader = _Loader();
    var retries = 0;
    var discards = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MessageBubble(
            message: message.copyWith(status: MessageStatus.failed),
            isMine: true,
            myUid: 'me',
            otherUid: 'alice',
            mediaLoader: loader,
            onDeleteForMe: () {},
            onRetry: () => retries++,
            onDiscard: () => discards++,
          ),
        ),
      ),
    );

    expect(find.byType(AttachmentTransferActions), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ChatMediaPreview),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(retries, 1);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(discards, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    loader.dispose();
  });

  for (final mediaType in [MessageType.gif, MessageType.sticker]) {
    testWidgets('$mediaType renders without a message bubble', (tester) async {
      final loader = _Loader();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: MessageBubble(
              message: message.copyWith(mediaType: mediaType),
              isMine: false,
              myUid: 'me',
              otherUid: 'alice',
              mediaLoader: loader,
              onDeleteForMe: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      final media = find.byType(ChatMediaPreview);
      final bareContainer = find
          .ancestor(of: media, matching: find.byType(AnimatedContainer))
          .first;
      expect(media, findsOneWidget);
      expect(bareContainer, findsOneWidget);
      expect(
        (tester.widget<AnimatedContainer>(bareContainer).decoration!
                as BoxDecoration)
            .color,
        Colors.transparent,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      loader.dispose();
    });
  }

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
    expect(loader.senders, ['alice']);
    await tester.pumpWidget(const SizedBox.shrink());
    loader.dispose();
  });

  for (final pixelRatio in [1.0, 6.0]) {
    testWidgets('bubble bounds original-source decoding at DPR $pixelRatio', (
      tester,
    ) async {
      final original = Uint8List.fromList(
        img.encodePng(img.Image(width: 200, height: 2000)),
      );
      final loader = _Loader()..seed('image', original);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(devicePixelRatio: pixelRatio),
            child: ChatMediaPreview(message: message, loader: loader),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final provider =
          tester.widget<Image>(find.byType(Image)).image as ResizeImage;
      expect(provider.width, (220 * pixelRatio).ceil().clamp(1, 1024));
      expect(provider.height, (165 * pixelRatio).ceil().clamp(1, 1024));
      expect(provider.policy, ResizeImagePolicy.fit);
      await tester.runAsync(() async {
        final decoded = Completer<ImageInfo>();
        final stream = provider.resolve(ImageConfiguration.empty);
        final listener = ImageStreamListener(
          (info, _) => decoded.complete(info),
        );
        stream.addListener(listener);
        final info = await decoded.future;
        expect(info.image.width, lessThanOrEqualTo(provider.width!));
        expect(info.image.height, lessThanOrEqualTo(provider.height!));
        expect(info.image.width / info.image.height, closeTo(0.1, 0.01));
        stream.removeListener(listener);
        info.dispose();
      });
      await tester.pumpWidget(const SizedBox.shrink());
      expect(original.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      loader.dispose();
    });
  }

  testWidgets(
    'progress notifications preserve preview ownership until disposal',
    (tester) async {
      final loader = _Loader()..seed('image', image);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatMediaPreview(message: message, loader: loader),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final provider = tester.widget<Image>(find.byType(Image)).image;
      final owned = _ownedBytes(provider);
      final cacheKey = await provider.obtainKey(ImageConfiguration.empty);
      expect(identical(owned, image), isFalse);
      loader.seed('unrelated-progress', Uint8List.fromList([1]));
      await tester.pumpAndSettle();
      expect(tester.widget<Image>(find.byType(Image)).image, provider);
      expect(owned, image);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(owned.every((byte) => byte == 0), isTrue);
      expect(image.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(loader.cached('image'), image);
      expect(
        PaintingBinding.instance.imageCache.containsKey(cacheKey),
        isFalse,
      );
      loader.dispose();
    },
  );

  testWidgets(
    'late thumbnail completion after disposal does not retain plaintext',
    (tester) async {
      final pending = Completer<Uint8List>();
      final loader = _Loader()..response = () => pending.future;
      await tester.pumpWidget(
        MaterialApp(
          home: ChatMediaPreview(message: message, loader: loader),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(image);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(loader.ownedResults.single.every((byte) => byte == 0), isTrue);
      expect(image.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      loader.dispose();
    },
  );

  testWidgets('full viewer owns and wipes its copy without wiping the caller', (
    tester,
  ) async {
    final loader = _Loader()..response = () async => image;
    await tester.pumpWidget(
      MaterialApp(
        home: ChatImageViewerScreen(message: message, loader: loader),
      ),
    );
    await tester.pumpAndSettle();
    final provider =
        tester.widget<Image>(find.byType(Image)).image as MemoryImage;
    final owned = provider.bytes;
    expect(loader.senders, ['alice']);
    loader.seed('unrelated-progress', Uint8List.fromList([1]));
    await tester.pumpAndSettle();
    expect(tester.widget<Image>(find.byType(Image)).image, provider);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(owned.every((byte) => byte == 0), isTrue);
    expect(image.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(PaintingBinding.instance.imageCache.containsKey(provider), isFalse);
    loader.dispose();
  });

  testWidgets('disposing one preview does not wipe another consumer', (
    tester,
  ) async {
    final loader = _Loader()..seed('image', image);
    Widget screen({required bool showFirst}) => MaterialApp(
      home: Column(
        children: [
          if (showFirst)
            ChatMediaPreview(
              key: const ValueKey('first'),
              message: message,
              loader: loader,
            ),
          ChatMediaPreview(
            key: const ValueKey('second'),
            message: message,
            loader: loader,
          ),
        ],
      ),
    );
    await tester.pumpWidget(screen(showFirst: true));
    await tester.pumpAndSettle();
    final providers = tester
        .widgetList<Image>(find.byType(Image))
        .map((widget) => widget.image)
        .toList();
    expect(
      identical(_ownedBytes(providers.first), _ownedBytes(providers.last)),
      isFalse,
    );
    await tester.pumpWidget(screen(showFirst: false));
    await tester.pumpAndSettle();
    expect(_ownedBytes(providers.first).every((byte) => byte == 0), isTrue);
    expect(_ownedBytes(providers.last), image);
    expect(tester.widget<Image>(find.byType(Image)).image, providers.last);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    loader.dispose();
  });

  for (final fullScreen in [false, true]) {
    testWidgets(
      '${fullScreen ? 'full viewer' : 'preview'} fences a previous message load',
      (tester) async {
        final pending = Completer<Uint8List>();
        final loader = _Loader()..response = () => pending.future;
        Widget screen(ChatMessage current) => MaterialApp(
          home: fullScreen
              ? ChatImageViewerScreen(message: current, loader: loader)
              : ChatMediaPreview(message: current, loader: loader),
        );
        await tester.pumpWidget(screen(message));
        loader.response = () async => image;
        await tester.pumpWidget(
          screen(message.copyWith(mediaRef: 'new-image')),
        );
        await tester.pumpAndSettle();
        final displayed = tester.widget<Image>(find.byType(Image)).image;
        pending.complete(image);
        await tester.pumpAndSettle();
        expect(tester.widget<Image>(find.byType(Image)).image, displayed);
        expect(loader.ownedResults.last.every((byte) => byte == 0), isTrue);
        expect(_ownedBytes(displayed), image);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        loader.dispose();
      },
    );
  }

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

  for (final code in [
    'source_unavailable',
    'local_media_moved',
    'storage_full',
    'local_media_storage_full',
    'local_media_unauthorized',
  ]) {
    for (final fullScreen in [false, true]) {
      testWidgets(
        '${fullScreen ? 'full viewer' : 'preview'} displays $code without retrying',
        (tester) async {
          const detail = 'Local attachment needs attention. Open the vault.';
          final loader = _Loader()
            ..response = () =>
                Future.error(ChatLocalMediaException(code, detail));
          await tester.pumpWidget(
            MaterialApp(
              home: fullScreen
                  ? ChatImageViewerScreen(message: message, loader: loader)
                  : ChatMediaPreview(message: message, loader: loader),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(detail), findsOneWidget);
          expect(find.byIcon(Icons.refresh_rounded), findsNothing);
          await tester.pump(const Duration(seconds: 20));
          expect(loader.calls, 1);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          loader.dispose();
        },
      );
    }
  }
}
