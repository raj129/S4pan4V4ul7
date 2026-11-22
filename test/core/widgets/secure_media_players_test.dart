import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:photo_vault/core/widgets/secure_audio_player.dart';
import 'package:photo_vault/core/widgets/secure_video_player.dart';
import 'package:photo_vault/features/chat/application/media/android_chat_secure_media_service.dart';
import 'package:photo_vault/features/chat/presentation/widgets/chat_audio_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureVideoPlayer', () {
    testWidgets('shows error when bytes are empty', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SecureVideoPlayer(bytes: Uint8List(0))),
        ),
      );

      expect(find.text('Video data is empty.'), findsOneWidget);
    });

    testWidgets('shows size-limit error when bytes exceed 64 MB', (
      tester,
    ) async {
      final oversized = Uint8List(AndroidChatSecureMediaService.maxBytes + 1);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SecureVideoPlayer(bytes: oversized)),
        ),
      );

      expect(
        find.textContaining('larger than the 64 MB in-memory playback limit'),
        findsOneWidget,
      );
    });
  });

  group('SecureAudioController & ChatAudioPlayer', () {
    const channelName = 'photo_vault/chat_secure_media_test';
    late MethodChannel channel;
    late List<MethodCall> calls;
    late SecureAudioController controller;

    setUp(() {
      channel = const MethodChannel(channelName);
      calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      controller = SecureAudioController(
        service: AndroidChatSecureMediaService(channel: channel),
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      controller.dispose();
    });

    testWidgets('plays inline, updates progress, cycles speed, and switches', (
      tester,
    ) async {
      final audioBytes = Uint8List.fromList([1, 2, 3, 4]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ChatAudioPlayer(
                  controller: controller,
                  duration: '0:30',
                  loadBytes: () async => Uint8List.fromList(audioBytes),
                ),
                ChatAudioPlayer(
                  controller: controller,
                  duration: '0:15',
                  loadBytes: () async => Uint8List.fromList(audioBytes),
                ),
              ],
            ),
          ),
        ),
      );

      // Tap first play button
      await tester.tap(find.byIcon(Icons.play_arrow_rounded).first);
      await tester.pump();

      expect(calls.where((c) => c.method == 'startAudio').length, 1);
      final firstSessionId =
          (calls.firstWhere((c) => c.method == 'startAudio').arguments
                  as Map)['sessionId']
              as String;

      // Simulate native playing event
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channelName,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('audioState', {
                'sessionId': firstSessionId,
                'state': 'playing',
                'positionMs': 12000,
                'durationMs': 30000,
                'speed': 1.0,
              }),
            ),
            (_) {},
          );
      await tester.pump();

      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.text('0:12'), findsOneWidget);
      expect(find.text('1.0x'), findsOneWidget);

      // Cycle speed
      await tester.tap(find.text('1.0x'));
      await tester.pump();
      expect(find.text('1.25x'), findsOneWidget);
      expect(calls.any((c) => c.method == 'setAudioSpeed'), isTrue);

      // Tap second audio player — should start a new session
      await tester.tap(find.byIcon(Icons.play_arrow_rounded).first);
      await tester.pump();
      expect(calls.where((c) => c.method == 'startAudio').length, 2);
    });

    testWidgets('SecureAudioPlayerSheet renders controls and stops on close', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecureAudioPlayerSheet(
              bytes: Uint8List.fromList([5, 6, 7]),
              title: 'Voice Note',
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Voice Note'), findsOneWidget);
      expect(find.byIcon(Icons.replay_10_rounded), findsOneWidget);
      expect(find.byIcon(Icons.forward_10_rounded), findsOneWidget);
      expect(calls.where((c) => c.method == 'startAudio').length, 1);

      // Replace widget to trigger dispose
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      expect(calls.any((c) => c.method == 'stopAudio'), isTrue);
    });
  });
}
