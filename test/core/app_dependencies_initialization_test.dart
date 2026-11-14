import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/core/di/app_dependencies.dart';

void main() {
  test(
    'concurrent initialize calls share the same initialization operation',
    () async {
      final dependencies = AppDependencies(persistentState: false);
      final first = dependencies.initialize();
      final second = dependencies.initialize();

      expect(identical(first, second), isTrue);
      await Future.wait([first, second]);
      await dependencies.dispose();
    },
  );
}
