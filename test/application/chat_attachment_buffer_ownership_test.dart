import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/application/media/android_chat_secure_media_service.dart';

void main() {
  test('native read-only selection is copied before secure cleanup', () {
    final borrowed = Uint8List.fromList([1, 2, 3]).asUnmodifiableView();
    expect(() => borrowed.fillRange(0, 3, 0), throwsUnsupportedError);
    final attachment = SecureMediaAttachment.fromMap({
      'bytes': borrowed,
      'fileName': 'sample.bin',
      'mimeType': 'application/octet-stream',
      'sourceUri': 'content://test/document/1',
      'sourceFlags': 1,
    });
    attachment.bytes.fillRange(0, attachment.bytes.length, 0);
    expect(borrowed, [1, 2, 3]);
    expect(attachment.sourceUri, 'content://test/document/1');
    expect(attachment.sourceFlags, 1);
  });
}
