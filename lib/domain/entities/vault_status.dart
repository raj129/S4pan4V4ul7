/// Whether a vault has been created on this device.
enum VaultStatus {
  /// No vault exists — show first-launch onboarding.
  notCreated,

  /// Vault creation is in progress (app restarted mid-creation).
  /// Treat as [notCreated]: clean up and restart onboarding.
  creating,

  /// Vault exists and is locked — show lock screen.
  ready,
}
