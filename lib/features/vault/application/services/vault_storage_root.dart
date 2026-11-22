import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// App-owned folder under Android/media for this package. Apps may write here
/// without storage permission on Android 11+, and it survives uninstall.
/// Null when external storage is unavailable or not on Android.
Future<Directory?> resolveAppMediaRoot() async {
  if (!Platform.isAndroid) return null;
  final external = await getExternalStorageDirectory();
  if (external == null) return null;
  final marker =
      '${Platform.pathSeparator}Android${Platform.pathSeparator}data${Platform.pathSeparator}';
  final extPath = external.path;
  if (!extPath.contains(marker)) return null;
  final split = extPath.split(marker);
  final packageName = split[1].split(Platform.pathSeparator).first;
  final root = Directory(p.join(split[0], 'Android', 'media', packageName));
  if (!await root.exists()) await root.create(recursive: true);
  return root;
}

/// Where one vault's ciphertext lives on disk.
///
/// Shared by import and backup restore so a restored photo lands exactly where
/// import would have put it. [useExternalMirror] selects Android/media (kept
/// across reinstall) when available; otherwise app-private support storage.
/// Each [vaultId] gets its own directory.
Future<Directory> resolveVaultRoot({
  required bool useExternalMirror,
  required String vaultId,
}) async {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(vaultId)) {
    throw ArgumentError.value(vaultId, 'vaultId', 'Invalid vault ID');
  }
  if (!useExternalMirror || !Platform.isAndroid) {
    final baseDir = await getApplicationSupportDirectory();
    return Directory(p.join(baseDir.path, 'vault', vaultId));
  }
  final external = await getExternalStorageDirectory();
  if (external == null) {
    final baseDir = await getApplicationSupportDirectory();
    return Directory(p.join(baseDir.path, 'vault', vaultId));
  }

  final marker =
      '${Platform.pathSeparator}Android${Platform.pathSeparator}data${Platform.pathSeparator}';
  final extPath = external.path;
  if (extPath.contains(marker)) {
    final split = extPath.split(marker);
    final packageAndRest = split[1];
    final packageName = packageAndRest.split(Platform.pathSeparator).first;
    final mediaRoot = Directory(
      p.join(split[0], 'Android', 'media', packageName, 'vault', vaultId),
    );
    if (!await mediaRoot.exists()) {
      await mediaRoot.create(recursive: true);
    }
    return mediaRoot;
  }

  final fallback = Directory(p.join(external.path, 'vault', vaultId));
  if (!await fallback.exists()) {
    await fallback.create(recursive: true);
  }
  return fallback;
}
