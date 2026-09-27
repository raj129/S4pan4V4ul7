import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_options.dart';
import 'presentation/app/vault_app.dart';
import 'presentation/widgets/chat/animated_emoji.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // Guarded so a platform failure or a slow Play Services call can never keep
  // the first frame from rendering; sign-in surfaces its own error later.
  try {
    await GoogleSignIn.instance
        .initialize(
          serverClientId:
              '209716874258-p9n2n9jmu87oqqu84703hf9kvuodokdn.apps.googleusercontent.com',
        )
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
}
