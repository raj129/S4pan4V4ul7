import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'application/services/chat_backup_scheduler.dart';
import 'application/services/push_notification_service.dart';
import 'application/services/video_compressor.dart';
import 'firebase_options.dart';
import 'presentation/app/vault_app.dart';
import 'presentation/widgets/chat/animated_emoji.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (defaultTargetPlatform == TargetPlatform.android) {
    FirebaseMessaging.onBackgroundMessage(handleChatPushInBackground);
  }

  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // Guarded so a platform failure or a slow Play Services call can never keep
  // the first frame from rendering; sign-in surfaces its own error later.
  try {
    await GoogleSignIn.instance
        .initialize(serverClientId: googleServerClientId)
        .timeout(const Duration(seconds: 5));
  } catch (e, stack) {
    FirebaseCrashlytics.instance.recordError(e, stack);
  }

  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/animated_emoji/LICENSE');
    yield LicenseEntryWithLineBreaks(['Noto Animated Emoji'], text);
  });
  unawaited(AnimatedEmojiRegistry.ensureLoaded());

  runApp(const VaultApp());

  unawaited(
    VideoCompressor.cleanStaleOutputs().then(
      (_) {},
      onError: (Object e, StackTrace s) {
        FirebaseCrashlytics.instance.recordError(e, s);
      },
    ),
  );

  // Nightly (~2 AM) chat backup, even while the app is closed.
  unawaited(
    scheduleNightlyChatBackup().catchError((Object e, StackTrace s) {
      FirebaseCrashlytics.instance.recordError(e, s);
    }),
  );
}
