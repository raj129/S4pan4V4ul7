import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/presentation/state/chat/active_upload_registry.dart';
import 'package:photo_vault/presentation/state/chat/media_send_status.dart';

void main() {
  late ActiveUploadRegistry registry;

  setUp(() => registry = ActiveUploadRegistry());

  test('publishes a snapshot whenever progress changes', () async {
    final snapshots = <Map<String, MediaSendStatus>>[];
    final sub = registry.changes.listen(snapshots.add);
    addTearDown(sub.cancel);

    registry.setStatus('a', const MediaSendStatus.preparing());
    registry.setStatus('a', const MediaSendStatus.preparing());
    registry.setStatus('a', null);
    registry.setStatus('a', null);
    await Future<void>.delayed(Duration.zero);

    expect(snapshots, hasLength(2));
    expect(snapshots.first.keys, ['a']);
    expect(snapshots.last, isEmpty);
  });

  test('the published snapshot cannot be mutated', () {
    registry.setStatus('a', const MediaSendStatus.preparing());

    expect(
      () => registry.statuses['b'] = const MediaSendStatus.preparing(),
      throwsUnsupportedError,
    );
  });

  test('advance never moves the ring backwards', () {
    registry.advance('a', MediaSendPhase.encrypting, 0.45);
    registry.advance('a', MediaSendPhase.preparing, 0.2);
    registry.advance('a', MediaSendPhase.uploading, 0.8);

    expect(registry.statusOf('a')?.progress, 0.8);
    expect(registry.statusOf('a')?.phase, MediaSendPhase.uploading);
  });

  test(
    'a token is shared until released, then forgotten with its progress',
    () {
      final token = registry.register('a');
      registry.setStatus('a', const MediaSendStatus.preparing());

      expect(registry.register('a'), same(token));
      expect(registry.tokenOf('a'), same(token));
      expect(registry.isActive('a'), isTrue);

      registry.release('a');

      expect(registry.tokenOf('a'), isNull);
      expect(registry.statusOf('a'), isNull);
      expect(registry.isActive('a'), isFalse);
    },
  );

  test('only one caller may deliver a message at a time', () {
    expect(registry.tryBeginDelivery('a'), isTrue);
    expect(registry.tryBeginDelivery('a'), isFalse);
    expect(registry.isActive('a'), isTrue);
    expect(registry.activeIds, {'a'});

    registry.endDelivery('a');

    expect(registry.isActive('a'), isFalse);
    expect(registry.tryBeginDelivery('a'), isTrue);
  });
}
