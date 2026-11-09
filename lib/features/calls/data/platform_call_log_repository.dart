import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/call_log_entry.dart';
import '../domain/call_log_repository.dart';

/// Android call log through the `photo_vault/call_log` channel.
class PlatformCallLogRepository implements CallLogRepository {
  const PlatformCallLogRepository({
    MethodChannel channel = const MethodChannel(_channelName),
  }) : _channel = channel;

  static const _channelName = 'photo_vault/call_log';

  final MethodChannel _channel;

  @override
  bool get isSupported => Platform.isAndroid;

  @override
  Future<bool> requestPermissions() async {
    if (!isSupported) return false;
    final status = await _invokeMap('request');
    return status?['read'] == true && status?['write'] == true;
  }

  @override
  Future<List<CallLogEntry>> list({int limit = 500}) async {
    if (!isSupported) return const [];
    final List<Map<Object?, Object?>>? rows;
    try {
      rows = await _channel.invokeListMethod<Map<Object?, Object?>>('list', {
        'limit': limit,
      });
    } on PlatformException catch (e) {
      throw CallLogException(e.message ?? e.code);
    }
    if (rows == null) return const [];
    return [
      for (final row in rows)
        if (CallLogType.fromPlatform(_int(row['type'])) case final type?)
          CallLogEntry(
            id: row['id'] as String? ?? '',
            number: row['number'] as String? ?? '',
            name: _nonBlank(row['name'] as String?),
            type: type,
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              _int(row['timestampMs']),
            ),
            durationSeconds: _int(row['durationSeconds']),
          ),
    ];
  }

  @override
  Future<bool> add({
    required String number,
    required CallLogType type,
    required DateTime timestamp,
    String? name,
    int durationSeconds = 0,
  }) async {
    if (!isSupported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('insert', {
        'number': number,
        'type': type.platformValue,
        'timestampMs': timestamp.millisecondsSinceEpoch,
        'name': name,
        'durationSeconds': durationSeconds,
      });
      return ok == true;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> update({
    required String id,
    required DateTime timestamp,
    required int durationSeconds,
  }) async {
    if (!isSupported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('update', {
        'id': id,
        'timestampMs': timestamp.millisecondsSinceEpoch,
        'durationSeconds': durationSeconds,
      });
      return ok == true;
    } on PlatformException {
      return false;
    }
  }

  Future<Map<Object?, Object?>?> _invokeMap(String method) async {
    try {
      return await _channel.invokeMapMethod<Object?, Object?>(method);
    } on PlatformException {
      return null;
    }
  }

  static int _int(Object? value) => switch (value) {
    final int v => v,
    final num v => v.toInt(),
    _ => 0,
  };

  static String? _nonBlank(String? value) =>
      value == null || value.trim().isEmpty ? null : value;
}
