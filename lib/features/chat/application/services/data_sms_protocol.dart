import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

class DataSmsEstimate {
  const DataSmsEstimate(this.characters, this.segments);
  final int characters;
  final int segments;
}

class DataSmsPacket {
  const DataSmsPacket.v1({required this.threadId, required this.ciphertext})
    : version = 1,
      sentAtMs = null,
      encryptedBytes = null;

  const DataSmsPacket.v2({required this.sentAtMs, required this.encryptedBytes})
    : version = 2,
      threadId = null,
      ciphertext = null;

  final int version;
  final String? threadId;
  final String? ciphertext;
  final int? sentAtMs;
  final Uint8List? encryptedBytes;
}

/// Data SMS application framing. V2 omits routing and identity data already
/// available from the native message ID and the sender's phone number.
class DataSmsProtocol {
  static const bytesPerSegment = 112;
  static const legacyBytesPerSegment = 99;
  static const maxSegments = 10;
  static const encryptionOverhead = 28;
  static const compactOverhead = 1 + 6 + encryptionOverhead;
  static const _v2 = 2;
  static const _timestampBytes = 6;

  /// V1 envelope retained for compatibility with messages already in transit.
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
    final length = utf8.encode(trimmed).length + compactOverhead;
    return DataSmsEstimate(trimmed.characters.length, segmentCount(length));
  }

  static int segmentCount(int bytes) =>
      (bytes + bytesPerSegment - 1) ~/ bytesPerSegment;

  /// V2 wire bytes: version(1), timestamp(6), AES-GCM nonce+ciphertext+tag.
  /// [encryptedBytes] is nonce(12) + ciphertext + tag(16).
  static Uint8List packV2({
    required int sentAtMs,
    required Uint8List encryptedBytes,
  }) {
    if (sentAtMs < 0 || sentAtMs >= 1 << (_timestampBytes * 8)) {
      throw const FormatException('Invalid Data SMS timestamp.');
    }
    if (encryptedBytes.length < encryptionOverhead) {
      throw const FormatException('Invalid encrypted Data SMS payload.');
    }
    final result = Uint8List(1 + _timestampBytes + encryptedBytes.length);
    result[0] = _v2;
    var timestamp = sentAtMs;
    for (var index = _timestampBytes; index > 0; index--) {
      result[index] = timestamp & 0xff;
      timestamp >>= 8;
    }
    result.setRange(1 + _timestampBytes, result.length, encryptedBytes);
    if (segmentCount(result.length) > maxSegments) {
      throw const FormatException('Data SMS exceeds the 10-segment limit.');
    }
    return result;
  }

  /// Legacy V1 route + base64 AES-GCM ciphertext packet.
  static Uint8List pack(String threadId, String encryptedBase64) {
    final route = utf8.encode(threadId);
    if (route.isEmpty || route.length > 511) {
      throw const FormatException('Invalid data SMS conversation.');
    }
    final ciphertext = base64Decode(encryptedBase64);
    final result = Uint8List(2 + route.length + ciphertext.length);
    ByteData.sublistView(result).setUint16(0, route.length);
    result.setRange(2, 2 + route.length, route);
    result.setRange(2 + route.length, result.length, ciphertext);
    if (legacySegmentCount(result.length) > maxSegments) {
      throw const FormatException('Data SMS exceeds the 10-segment limit.');
    }
    return result;
  }

  static DataSmsPacket unpack(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > bytesPerSegment * maxSegments) {
      throw const FormatException('Invalid data SMS size.');
    }
    if (bytes.first == _v2) {
      if (bytes.length < compactOverhead + 1) {
        throw const FormatException('Invalid compact Data SMS size.');
      }
      var sentAtMs = 0;
      for (var index = 1; index <= _timestampBytes; index++) {
        sentAtMs = (sentAtMs << 8) | bytes[index];
      }
      if (sentAtMs > 8640000000000000) {
        throw const FormatException('Invalid compact Data SMS timestamp.');
      }
      return DataSmsPacket.v2(
        sentAtMs: sentAtMs,
        encryptedBytes: Uint8List.fromList(bytes.sublist(1 + _timestampBytes)),
      );
    }

    if (bytes.length < 31 ||
        bytes.length > legacyBytesPerSegment * maxSegments) {
      throw const FormatException('Invalid legacy Data SMS size.');
    }
    final length = ByteData.sublistView(bytes).getUint16(0);
    if (length == 0 || length > 511 || length + 30 > bytes.length) {
      throw const FormatException('Invalid data SMS route.');
    }
    return DataSmsPacket.v1(
      threadId: utf8.decode(bytes.sublist(2, 2 + length)),
      ciphertext: base64Encode(bytes.sublist(2 + length)),
    );
  }

  static int legacySegmentCount(int bytes) =>
      (bytes + legacyBytesPerSegment - 1) ~/ legacyBytesPerSegment;
}
