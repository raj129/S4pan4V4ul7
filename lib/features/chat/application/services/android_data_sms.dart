import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Ciphertext awaiting authentication and durable import. The phone number is
/// untrusted metadata, not proof of the sender's identity.
class NativeSmsIncoming {
  const NativeSmsIncoming({
    required this.id,
    required this.phone,
    required this.payload,
    int? segments,
  }) : _segments = segments;

  final String id;
  final String phone;
  final Uint8List payload;
  final int? _segments;
  int get segments =>
      _segments ??
      (payload.length + AndroidDataSms.payloadBytesPerSegment - 1) ~/
          AndroidDataSms.payloadBytesPerSegment;
}

class NativeSmsSegment {
  const NativeSmsSegment({
    required this.index,
    required this.submit,
    required this.sent,
    required this.delivery,
    this.error,
  });

  final int index;
  final String submit;
  final String sent;
  final String delivery;
  final String? error;

  factory NativeSmsSegment._fromMap(Map<Object?, Object?> map) =>
      NativeSmsSegment(
        index: map['index'] as int,
        submit: map['submit'] as String,
        sent: map['sent'] as String,
        delivery: map['delivery'] as String,
        error: map['error'] as String?,
      );
}

class NativeSmsStatus {
  const NativeSmsStatus({
    required this.id,
    required this.state,
    required this.segments,
    this.error,
  });

  final String id;
  final String state;
  final List<NativeSmsSegment> segments;
  final String? error;

  factory NativeSmsStatus._fromMap(Map<Object?, Object?> map) =>
      NativeSmsStatus(
        id: map['id'] as String,
        state: map['state'] as String,
        segments: (map['segments'] as List<Object?>)
            .map(
              (item) =>
                  NativeSmsSegment._fromMap(item as Map<Object?, Object?>),
            )
            .toList(growable: false),
        error: map['error'] as String?,
      );
}

class NativeSmsSnapshot {
  const NativeSmsSnapshot({required this.incoming, required this.outgoing});

  final List<NativeSmsIncoming> incoming;
  final List<NativeSmsStatus> outgoing;
}

/// Android-only, port-addressed encrypted data SMS transport.
///
/// The caller must pass ciphertext, authenticate received envelopes, and only
/// acknowledge an incoming message after it has been durably saved. Poll
/// [snapshot] while the authorized Flutter session is active.
class AndroidDataSms {
  const AndroidDataSms();

  static const payloadBytesPerSegment = 99;
  static const maxSegments = 10;
  static const MethodChannel _channel = MethodChannel('photo_vault/data_sms');

  Future<bool> isSupported() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Requests the declared SEND_SMS and RECEIVE_SMS Android permissions.
  Future<void> requestPermission() async {
    if (!await isSupported()) {
      throw PlatformException(
        code: 'unsupported',
        message: 'Data SMS is unavailable',
      );
    }
    final status = await Permission.sms.request();
    if (!status.isGranted) {
      throw PlatformException(
        code: 'permission_denied',
        message: 'SMS permission denied',
      );
    }
  }

  /// Sends once; the native queue never automatically retries ambiguous calls.
  Future<NativeSmsStatus> send({
    required String messageId,
    required Uint8List payload,
    required String phone,
  }) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>('send', {
      'messageId': messageId,
      'payload': payload,
      'phone': phone,
    });
    if (result == null) throw StateError('Missing data SMS send status');
    return NativeSmsStatus._fromMap(result);
  }

  Future<NativeSmsSnapshot> snapshot() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>('pending');
    if (result == null) throw StateError('Missing data SMS snapshot');
    final incoming = (result['incoming'] as List<Object?>)
        .map((item) {
          final map = item as Map<Object?, Object?>;
          final payload = map['payload'] as Uint8List;
          return NativeSmsIncoming(
            id: map['id'] as String,
            phone: map['phone'] as String,
            payload: payload,
            segments:
                (payload.length + payloadBytesPerSegment - 1) ~/
                payloadBytesPerSegment,
          );
        })
        .toList(growable: false);
    final outgoing = (result['outgoing'] as List<Object?>)
        .map((item) => NativeSmsStatus._fromMap(item as Map<Object?, Object?>))
        .toList(growable: false);
    return NativeSmsSnapshot(incoming: incoming, outgoing: outgoing);
  }

  Future<void> acknowledge({
    required String messageId,
    required String source,
  }) => _channel.invokeMethod<void>('acknowledge', {
    'messageId': messageId,
    'source': source,
  });

  /// Releases delivered native status only after it has been durably saved.
  Future<void> acknowledgeOutgoing({required String messageId}) => _channel
      .invokeMethod<void>('acknowledgeOutgoing', {'messageId': messageId});
}
