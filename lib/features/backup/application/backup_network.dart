import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:photo_vault/features/vault/domain/repositories/settings_repository.dart';

/// Whether the current network may be used for cloud backup, honouring the
/// Wi-Fi-only setting. Independent of chat, so it works when chat is down.
Future<bool> backupNetworkAllowed(SettingsRepository settings) async {
  final results = await Connectivity().checkConnectivity();
  if (await settings.isBackupWifiOnly()) {
    return results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);
  }
  return results.any((r) => r != ConnectivityResult.none);
}
