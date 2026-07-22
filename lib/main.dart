import 'package:flutter/widgets.dart';
import 'presentation/app/vault_app.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_options.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await GoogleSignIn.instance.initialize(
    serverClientId: '209716874258-p9n2n9jmu87oqqu84703hf9kvuodokdn.apps.googleusercontent.com',
  );
  runApp(const VaultApp());
}
