import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Optional test hook to observe non-fatal errors in unit/widget tests.
@visibleForTesting
void Function(Object error, StackTrace stackTrace, {String? reason})?
testNonFatalErrorSink;

/// Records a caught, non-fatal exception to Firebase Crashlytics when Firebase
/// is initialized. Safe to call in unit tests where Firebase is not configured.
void reportNonFatalError(
  Object error,
  StackTrace stackTrace, {
  String? reason,
}) {
  testNonFatalErrorSink?.call(error, stackTrace, reason: reason);
  try {
    if (Firebase.apps.isEmpty) return;
    unawaited(
      FirebaseCrashlytics.instance.recordError(
        error,
        stackTrace,
        reason: reason,
      ),
    );
  } catch (_) {}
}
