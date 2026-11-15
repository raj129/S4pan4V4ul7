import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/application/crypto/chat_crypto_service.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_message.dart';
import 'package:photo_vault/features/chat/domain/repositories/message_repository.dart';
import 'package:photo_vault/features/chat/presentation/widgets/chat_media_preview.dart';
import 'package:photo_vault/features/chat/presentation/widgets/message_bubble.dart';
import 'package:photo_vault/features/chat/presentation/widgets/reply_swipe.dart';

class _NoMediaRepository implements MediaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

const _childKey = ValueKey('swipe-child');

Future<void> _pumpSwipe(
  WidgetTester tester, {
  double width = 320,
  VoidCallback? onReply,
  TextDirection direction = TextDirection.ltr,
  Widget? child,
}) => tester.pumpWidget(
  MaterialApp(
    home: Directionality(
      textDirection: direction,
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: ReplySwipe(
              onReply: onReply,
              child:
                  child ??
                  const ColoredBox(
                    key: _childKey,
                    color: Colors.transparent,
                    child: SizedBox(height: 80, width: double.infinity),
                  ),
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<TestGesture> _startSwipe(
  WidgetTester tester, {
  double sign = 1,
  bool resetDistance = true,
}) async {
  final gesture = await tester.startGesture(
    tester.getTopLeft(find.byType(ReplySwipe)) + const Offset(5, 5),
  );
  // Resolve the gesture arena before measuring drag displacement.
  await gesture.moveBy(Offset(20 * sign, 0));
  await tester.pump();
  if (resetDistance) {
    await gesture.moveBy(Offset(-20 * sign, 0));
    await tester.pump();
  }
  return gesture;
}

void main() {
  testWidgets('equal drags move less as tension grows, with bounded travel', (
    tester,
  ) async {
    await _pumpSwipe(tester, onReply: () {});
    final origin = tester.getTopLeft(find.byKey(_childKey)).dx;
    final gesture = await _startSwipe(tester);
    final positions = <double>[0];
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
      positions.add(tester.getTopLeft(find.byKey(_childKey)).dx - origin);
    }
    expect(positions[1], inExclusiveRange(9, 10));
    for (var i = 2; i < positions.length; i++) {
      expect(
        positions[i] - positions[i - 1],
        lessThan(positions[i - 1] - positions[i - 2]),
      );
    }
    await gesture.moveBy(const Offset(3000, 0));
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(_childKey)).dx - origin,
      lessThanOrEqualTo(96),
    );
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(_childKey)).dx, origin);
  });

  for (final width in [120.0, 320.0]) {
    for (final delta in [-1.0, 0.0, 1.0]) {
      testWidgets('raw threshold at width $width, offset $delta', (
        tester,
      ) async {
        var replies = 0;
        await _pumpSwipe(tester, width: width, onReply: () => replies++);
        final origin = tester.getTopLeft(find.byKey(_childKey)).dx;
        final gesture = await _startSwipe(tester);
        await gesture.moveBy(Offset(width * 0.25 + delta, 0));
        await tester.pump();
        final displaced = tester.getTopLeft(find.byKey(_childKey)).dx;
        expect(displaced - origin, lessThan(width * 0.25 + delta));
        expect(replies, 0);
        await gesture.up();
        expect(replies, delta < 0 ? 0 : 1);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final returning = tester.getTopLeft(find.byKey(_childKey)).dx;
        expect(returning, greaterThan(origin));
        expect(returning, lessThan(displaced));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.byKey(_childKey)).dx, origin);
      });
    }
  }

  testWidgets('reversal disarms reply; haptic fires once per gesture', (
    tester,
  ) async {
    var replies = 0;
    final haptics = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    await _pumpSwipe(tester, onReply: () => replies++);
    final origin = tester.getTopLeft(find.byKey(_childKey)).dx;
    final gesture = await _startSwipe(tester);
    await gesture.moveBy(const Offset(90, 0));
    await tester.pump();
    final stretched = tester.getTopLeft(find.byKey(_childKey)).dx;
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(_childKey)).dx, lessThan(stretched));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(_childKey)).dx,
      closeTo(stretched, 0.001),
    );
    await gesture.moveBy(const Offset(-90, 0));
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(_childKey)).dx, origin);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(replies, 0);
    expect(haptics, hasLength(1));
    expect(haptics.single.arguments, 'HapticFeedbackType.lightImpact');

    final next = await _startSwipe(tester);
    await next.moveBy(const Offset(90, 0));
    await next.up();
    await tester.pumpAndSettle();
    expect(replies, 1);
    expect(haptics, hasLength(2));
  });

  testWidgets('cancel and wrong-direction movement never reply', (
    tester,
  ) async {
    var replies = 0;
    await _pumpSwipe(tester, onReply: () => replies++);
    final origin = tester.getTopLeft(find.byKey(_childKey));
    final wrong = await _startSwipe(tester, sign: -1, resetDistance: false);
    await wrong.moveBy(const Offset(-100, 0));
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(_childKey)), origin);
    await wrong.up();
    await tester.pumpAndSettle();

    final cancelled = await _startSwipe(tester);
    await cancelled.moveBy(const Offset(100, 0));
    await cancelled.cancel();
    await tester.pumpAndSettle();
    expect(replies, 0);
    expect(tester.getTopLeft(find.byKey(_childKey)), origin);
  });

  testWidgets('disabled and mid-drag-disabled swipes cannot reply', (
    tester,
  ) async {
    var replies = 0;
    await _pumpSwipe(tester);
    final origin = tester.getTopLeft(find.byKey(_childKey));
    await tester.drag(find.byKey(_childKey), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(_childKey)), origin);

    await _pumpSwipe(tester, onReply: () => replies++);
    final gesture = await _startSwipe(tester);
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    await _pumpSwipe(tester);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(replies, 0);
    expect(tester.getTopLeft(find.byKey(_childKey)), origin);
  });

  testWidgets('start-to-end direction follows RTL', (tester) async {
    var replies = 0;
    await _pumpSwipe(
      tester,
      onReply: () => replies++,
      direction: TextDirection.rtl,
    );
    final origin = tester.getTopLeft(find.byKey(_childKey)).dx;
    final gesture = await _startSwipe(tester, sign: -1);
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(_childKey)).dx, lessThan(origin));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(replies, 1);
    expect(tester.getTopLeft(find.byKey(_childKey)).dx, origin);
  });

  testWidgets('narrow messages still have room to reveal the reply icon', (
    tester,
  ) async {
    await _pumpSwipe(tester, width: 100, onReply: () {});
    final origin = tester.getTopLeft(find.byKey(_childKey)).dx;
    final gesture = await _startSwipe(tester);
    await gesture.moveBy(const Offset(300, 0));
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(_childKey)).dx - origin,
      inExclusiveRange(80, 96),
    );
    await gesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets('removing a widget during a drag cannot trigger a reply', (
    tester,
  ) async {
    var replies = 0;
    await _pumpSwipe(tester, onReply: () => replies++);
    final gesture = await _startSwipe(tester);
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await gesture.up();
    await tester.pumpAndSettle();
    expect(replies, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('return can be interrupted without a position jump', (
    tester,
  ) async {
    var replies = 0;
    await _pumpSwipe(tester, onReply: () => replies++);
    final gesture = await _startSwipe(tester);
    await gesture.moveBy(const Offset(3000, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    final before = tester.getTopLeft(find.byKey(_childKey));
    final next = await _startSwipe(tester, resetDistance: false);
    expect(
      tester.getTopLeft(find.byKey(_childKey)).dx,
      closeTo(before.dx, 0.001),
    );
    await next.moveBy(const Offset(-10, 0));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await next.up();
    await tester.pumpAndSettle();
    expect(replies, 1, reason: 'a new gesture must meet its own raw threshold');
  });

  testWidgets('child tap, double-tap and long-press remain available', (
    tester,
  ) async {
    var taps = 0;
    var doubles = 0;
    var holds = 0;
    await _pumpSwipe(
      tester,
      onReply: () {},
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => taps++,
        onDoubleTap: () => doubles++,
        onLongPress: () => holds++,
        child: const ColoredBox(
          key: _childKey,
          color: Colors.transparent,
          child: SizedBox(width: double.infinity, height: 80),
        ),
      ),
    );
    await tester.tap(find.byKey(_childKey));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(taps, 1);
    await tester.tap(find.byKey(_childKey));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(_childKey));
    await tester.pumpAndSettle();
    expect(doubles, 1);
    await tester.longPress(find.byKey(_childKey));
    await tester.pumpAndSettle();
    expect(holds, 1);
  });

  testWidgets('horizontal reply recognizer does not block vertical scrolling', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var replies = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: scroll,
            children: [
              ReplySwipe(
                onReply: () => replies++,
                child: const ColoredBox(
                  key: _childKey,
                  color: Colors.transparent,
                  child: SizedBox(width: double.infinity, height: 180),
                ),
              ),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      ),
    );
    await tester.drag(find.byKey(_childKey), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    expect(replies, 0);
  });

  for (final kind in ['incoming', 'outgoing', 'file', 'deleted']) {
    testWidgets('$kind MessageBubble uses its actual swipe-area width', (
      tester,
    ) async {
      var replies = 0;
      final loader = ChatMediaLoader(
        mediaRepository: _NoMediaRepository(),
        cryptoService: ChatCryptoService(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: ChatMessage(
                messageId: 'm1',
                threadId: 't1',
                senderId: kind == 'outgoing' ? 'me' : 'other',
                encryptedText: 'x',
                sentAt: DateTime.utc(2024),
                deletedFor: const [],
                deletedForEveryone: kind == 'deleted',
                mediaType: kind == 'file' ? MessageType.file : null,
                localDecryptedText: kind == 'file' ? 'report.pdf' : 'hello',
              ),
              isMine: kind == 'outgoing',
              myUid: 'me',
              otherUid: 'other',
              mediaLoader: loader,
              onDeleteForMe: () {},
              onReply: () => replies++,
            ),
          ),
        ),
      );
      expect(find.byType(ReplySwipe), findsOneWidget);
      final width = tester.getSize(find.byType(ReplySwipe)).width;
      final gesture = await _startSwipe(tester);
      await gesture.moveBy(Offset(width * 0.25 + 1, 0));
      await tester.pump();
      expect(replies, 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(replies, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final gate in ['selection', 'direction', 'no callback']) {
    testWidgets('MessageBubble preserves $gate disabled gate', (tester) async {
      var replies = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: ChatMessage(
                messageId: 'm1',
                threadId: 't1',
                senderId: 'other',
                encryptedText: 'x',
                sentAt: DateTime.utc(2024),
                deletedFor: const [],
                localDecryptedText: 'hello',
              ),
              isMine: false,
              myUid: 'me',
              otherUid: 'other',
              mediaLoader: ChatMediaLoader(
                mediaRepository: _NoMediaRepository(),
                cryptoService: ChatCryptoService(),
              ),
              onDeleteForMe: () {},
              onReply: gate == 'no callback' ? null : () => replies++,
              isSelectionMode: gate == 'selection',
              canReplyFromLeftToRight: gate != 'direction',
            ),
          ),
        ),
      );
      final swipe = tester.widget<ReplySwipe>(find.byType(ReplySwipe));
      expect(swipe.onReply, isNull);
      await tester.drag(find.byType(ReplySwipe), const Offset(250, 0));
      await tester.pumpAndSettle();
      expect(replies, 0);
    });
  }
}
