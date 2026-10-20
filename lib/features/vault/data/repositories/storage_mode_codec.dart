import '../../domain/entities/user_mode.dart';

class StorageModeCodec {
  static String serialize(UserMode mode) {
    return switch (mode) {
      UserMode.localOnly => 'localOnly',
      UserMode.googleEnabled => 'googleEnabled',
      UserMode.hybrid => 'hybrid',
    };
  }

  static UserMode? parse(String? value) {
    return switch (value) {
      'localOnly' => UserMode.localOnly,
      'googleEnabled' => UserMode.googleEnabled,
      'hybrid' => UserMode.hybrid,
      _ => null,
    };
  }
}
