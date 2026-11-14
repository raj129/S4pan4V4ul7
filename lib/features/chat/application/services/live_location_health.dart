import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../vault/data/repositories/storage_string_kv.dart';

/// Bounded local evidence, without coordinates, identities or exception messages.
class LiveLocationHealth {
  LiveLocationHealth({StorageStringKv? store, DateTime Function()? clock})
    : _store = store,
      _clock = clock ?? DateTime.now {
    _pending = _load();
  }

  static const storageKey = 'chat.live_location_health.v1';
  static const capacity = 50;
  final StorageStringKv? _store;
  final DateTime Function() _clock;
  final List<Map<String, Object>> _events = [];
  late Future<void> _pending;
  bool _dirty = false;
  bool _saving = false;

  List<Map<String, Object>> get events =>
      List.unmodifiable(_events.map(Map<String, Object>.unmodifiable));

  Future<void> get settled => _pending;

  void record(String event, {int? attempt, Object? error}) {
    final entry = <String, Object>{
      'event': event,
      'at': _clock().toUtc().millisecondsSinceEpoch,
      'attempt': ?attempt,
      if (error != null) 'errorType': error.runtimeType.toString(),
    };
    final previous = _events.lastOrNull;
    if (previous != null &&
        previous['event'] == event &&
        previous['attempt'] == attempt &&
        previous['errorType'] == entry['errorType'] &&
        (entry['at']! as int) - (previous['at']! as int) < 1000) {
      return;
    }
    _events.add(entry);
    if (_events.length > capacity) _events.removeAt(0);
    _dirty = true;
    if (_saving) return;
    _saving = true;
    _pending = _pending.then((_) async {
      try {
        while (_dirty) {
          _dirty = false;
          final store = _store;
          if (store != null) {
            await store
                .write(storageKey, jsonEncode(_events))
                .timeout(const Duration(seconds: 2));
          }
        }
      } catch (_) {
        debugPrint('Live-location diagnostic storage unavailable.');
      } finally {
        _saving = false;
      }
    });
  }

  Future<void> _load() async {
    final store = _store;
    if (store == null) return;
    try {
      final raw = await store
          .read(storageKey)
          .timeout(const Duration(seconds: 2));
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) throw const FormatException();
      final restored = <Map<String, Object>>[];
      for (final item in decoded) {
        if (item is! Map || item['event'] is! String || item['at'] is! int) {
          throw const FormatException();
        }
        restored.add({
          'event': item['event'] as String,
          'at': item['at'] as int,
          if (item['attempt'] is int) 'attempt': item['attempt'] as int,
          if (item['errorType'] is String)
            'errorType': item['errorType'] as String,
        });
      }
      _events.insertAll(0, restored);
      if (_events.length > capacity) {
        _events.removeRange(0, _events.length - capacity);
      }
    } catch (_) {
      debugPrint('Live-location diagnostic history unavailable.');
    }
  }
}
