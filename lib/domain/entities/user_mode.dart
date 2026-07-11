enum UserMode { localOnly, googleEnabled, hybrid }

extension UserModeLabel on UserMode {
  String get title {
    switch (this) {
      case UserMode.localOnly:
        return 'Continue locally';
      case UserMode.googleEnabled:
        return 'Sign in with Google';
      case UserMode.hybrid:
        return 'Hybrid mode';
    }
  }

  String get description {
    switch (this) {
      case UserMode.localOnly:
        return 'No sign-in. Encrypted vault data stays on this device.';
      case UserMode.googleEnabled:
        return 'Enable encrypted VMK backup and optional photo sync.';
      case UserMode.hybrid:
        return 'Start local now and enable Google backup/sync later.';
    }
  }
}
