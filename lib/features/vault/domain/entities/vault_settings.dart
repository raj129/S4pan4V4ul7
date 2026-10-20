import 'user_mode.dart';

/// Persisted settings created when the vault is first set up.
class VaultSettings {
  const VaultSettings({
    required this.mode,
    required this.appLockOnOpen,
    required this.autoLockOnBackground,
    required this.photoSyncEnabled,
    required this.vmkBackupEnabled,
  });

  final UserMode mode;
  final bool appLockOnOpen;
  final bool autoLockOnBackground;

  /// Photo sync is always disabled until the user explicitly enables it,
  /// even in Google-enabled mode.
  final bool photoSyncEnabled;

  /// VMK backup is enabled by default only when [mode] is [UserMode.googleEnabled].
  final bool vmkBackupEnabled;

  factory VaultSettings.defaults({required UserMode mode}) {
    return VaultSettings(
      mode: mode,
      appLockOnOpen: true,
      autoLockOnBackground: true,
      photoSyncEnabled: false,
      // VMK backup on by default only when Google-enabled.
      vmkBackupEnabled: mode == UserMode.googleEnabled,
    );
  }
}
