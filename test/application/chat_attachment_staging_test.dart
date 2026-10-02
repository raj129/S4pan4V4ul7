import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/application/services/chat_attachment_staging.dart';

void main() {
  late Directory directory;
  late FileAttachmentStagingStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('chat-staging-test-');
    store = FileAttachmentStagingStore(directory: directory);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('encrypted media and preview survive a store round trip', () async {
    final media = Uint8List.fromList([1, 2, 3, 4]);
    final thumbnail = Uint8List.fromList([5, 6]);

    await store.writeMedia('message-1', media);
    await store.writeThumbnail('message-1', thumbnail);

    expect(await store.readMedia('message-1'), media);
    expect(await store.readThumbnail('message-1'), thumbnail);
  });

  test('orphaned staged files are removed without touching queued media', () async {
    await store.writeMedia('pending', Uint8List.fromList([1]));
    await store.writeMedia('orphan', Uint8List.fromList([2]));

    await store.cleanOrphans({'pending'});

    expect(await store.readMedia('pending'), Uint8List.fromList([1]));
    expect(await store.readMedia('orphan'), isNull);
  });
}
