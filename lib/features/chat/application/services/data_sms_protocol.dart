import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

class DataSmsEstimate {
  const DataSmsEstimate(this.characters, this.segments);
  final int characters;
  final int segments;
}

/// One application chunk per sendDataMessage call; no text-SMS encoding rules.
class DataSmsProtocol {
  static const bytesPerSegment = 99;
  static const maxSegments = 10;
  static const encryptionOverhead = 28;
  static const _sampleId = '00000000-0000-4000-8000-000000000000';

  static String body({
    required String id,
    required String threadId,
    required String senderId,
    required String recipientId,
    required int sentAt,
    required String text,
  }) => jsonEncode({
    'v': 1,
    'id': id,
    't': threadId,
    's': senderId,
    'r': recipientId,
    'at': sentAt,
    'text': text.trim(),
  });

  static DataSmsEstimate estimate({
    required String text,
    required String threadId,
    required String senderId,
    required String recipientId,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const DataSmsEstimate(0, 0);
    final length =
        utf8
            .encode(
              body(
                id: _sampleId,
                threadId: threadId,
                senderId: senderId,
                recipientId: recipientId,
                sentAt: DateTime.now().toUtc().millisecondsSinceEpoch,
                text: trimmed,
              ),
            )
            .length +
        encryptionOverhead +
        2 +
        utf8.encode(threadId).length;
    return DataSmsEstimate(trimmed.characters.length, segmentCount(length));
  }

  static int segmentCount(int bytes) =>
      (bytes + bytesPerSegment - 1) ~/ bytesPerSegment;

  static Uint8List pack(String threadId, String encryptedBase64) {
    final route = utf8.encode(threadId);
    if (route.isEmpty || route.length > 512) {
      throw const FormatException('Invalid data SMS conversation.');
    }
    final ciphertext = base64Decode(encryptedBase64);
    final result = Uint8List(2 + route.length + ciphertext.length);
    ByteData.sublistView(result).setUint16(0, route.length);
    result.setRange(2, 2 + route.length, route);
    result.setRange(2 + route.length, result.length, ciphertext);
    if (segmentCount(result.length) > maxSegments) {
      throw const FormatException('Data SMS exceeds the 10-segment limit.');
    }
    return result;
  }

  static ({String threadId, String ciphertext}) unpack(Uint8List bytes) {
    if (bytes.length < 31 || bytes.length > bytesPerSegment * maxSegments) {
      throw const FormatException('Invalid data SMS size.');
    }
    final length = ByteData.sublistView(bytes).getUint16(0);
    if (length == 0 || length > 512 || length + 30 > bytes.length) {
      throw const FormatException('Invalid data SMS route.');
    }
    return (
      threadId: utf8.decode(bytes.sublist(2, 2 + length)),
      ciphertext: base64Encode(bytes.sublist(2 + length)),
    );
  }
}
