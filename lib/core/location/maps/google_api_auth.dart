import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Credentials for Google REST APIs (Routes, Places) using the same key that
/// powers the Maps SDK.
///
/// The key comes from `--dart-define=GOOGLE_MAPS_ANDROID_API_KEY` when given,
/// otherwise from the Android manifest. Keys restricted to Android apps are
/// only accepted when the call identifies the app, so the package name and
/// signing-certificate SHA-1 are sent as `X-Android-Package` / `X-Android-Cert`.
class GoogleApiAuth {
  GoogleApiAuth({String? apiKey, MethodChannel? channel, bool? isAndroid})
    : _explicitKey = apiKey,
      _channel = channel ?? const MethodChannel(channelName),
      _isAndroid = isAndroid ?? Platform.isAndroid;

  /// Shared instance used by the app's services.
  static final GoogleApiAuth instance = GoogleApiAuth();

  static const channelName = 'com.system.calculator/maps_diagnostics';
  static const _defined = String.fromEnvironment('GOOGLE_MAPS_ANDROID_API_KEY');

  final String? _explicitKey;
  final MethodChannel _channel;
  final bool _isAndroid;

  _Identity? _cached;

  Future<_Identity> _identity() async {
    final cached = _cached;
    if (cached != null) return cached;
    var key = (_explicitKey ?? _defined).trim();
    String? package;
    String? sha1;
    if (_isAndroid) {
      try {
        final raw = await _channel.invokeMapMethod<String, String>(
          'getMapsApiIdentity',
        );
        if (key.isEmpty) key = (raw?['key'] ?? '').trim();
        package = _blankToNull(raw?['package']);
        sha1 = _blankToNull(raw?['sha1']);
      } on PlatformException {
        // Keep the Dart-defined key without app identity.
      } on MissingPluginException {
        // Widget tests and non-Android hosts.
      }
    }
    final identity = _Identity(key, package, sha1);
    // Don't cache a miss: the plugin may simply not have been ready.
    if (key.isNotEmpty) _cached = identity;
    return identity;
  }

  static String? _blankToNull(String? v) =>
      v == null || v.trim().isEmpty ? null : v.trim();

  Future<bool> get isConfigured async => (await _identity()).key.isNotEmpty;

  /// Headers for a Google REST call. Throws [StateError] without a key.
  Future<Map<String, String>> headers({String? fieldMask}) async {
    final id = await _identity();
    if (id.key.isEmpty) {
      throw StateError('No Google Maps API key is configured.');
    }
    return {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': id.key,
      'X-Goog-FieldMask': ?fieldMask,
      'X-Android-Package': ?id.package,
      'X-Android-Cert': ?id.sha1,
    };
  }

  /// The raw key, for APIs that take it as a query parameter.
  Future<String> get key async => (await _identity()).key;

  /// App-identity headers only, for query-parameter style APIs.
  Future<Map<String, String>> identityHeaders() async {
    final id = await _identity();
    return {'X-Android-Package': ?id.package, 'X-Android-Cert': ?id.sha1};
  }

  /// Turns a failed Google response into a message that says what to fix.
  static String describeFailure(int status, String body, {String api = 'API'}) {
    String? message;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) message = error['message'] as String?;
        message ??= decoded['error_message'] as String?;
      }
    } catch (_) {}
    final lower = (message ?? '').toLowerCase();
    if (lower.contains('has not been used') ||
        lower.contains('is disabled') ||
        lower.contains('not enabled') ||
        lower.contains('legacy api')) {
      return '$api is not enabled for this Google Cloud project. Enable it '
          'in the Google Cloud console.';
    }
    if (status == 403 || lower.contains('not authorized')) {
      return '$api rejected the request (HTTP $status). Enable the API and '
          'check the key allows this app (package and SHA-1).'
          '${message == null ? '' : ' $message'}';
    }
    return '$api failed (HTTP $status)${message == null ? '' : ': $message'}';
  }
}

class _Identity {
  const _Identity(this.key, this.package, this.sha1);
  final String key;
  final String? package;
  final String? sha1;
}
