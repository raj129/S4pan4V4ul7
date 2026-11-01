import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Whether Android's battery optimisation may stop the app in the background.
///
/// Doze and OEM "battery savers" kill or freeze background work (live location
/// sharing, arrival alerts, chat backups) even when it runs in a foreground
/// service. Being exempt is the single most effective fix, but Android only
/// lets the user grant it, so the app explains why and asks.
abstract interface class BatteryOptimization {
  /// True when the app is exempt, or on platforms where this does not apply.
  Future<bool> isExempt();

  /// Shows the system prompt. Returns whether the app is now exempt.
  Future<bool> requestExemption();
}

class AndroidBatteryOptimization implements BatteryOptimization {
  const AndroidBatteryOptimization();

  @override
  Future<bool> isExempt() async {
    if (!Platform.isAndroid) return true;
    try {
      return await Permission.ignoreBatteryOptimizations.isGranted;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<bool> requestExemption() async {
    if (!Platform.isAndroid) return true;
    try {
      return (await Permission.ignoreBatteryOptimizations.request()).isGranted;
    } catch (_) {
      return false;
    }
  }
}

/// Contextual prompts are shown at most once per app session so they never
/// nag; Settings can always ask again.
bool _promptedThisSession = false;

@visibleForTesting
void resetBatteryPromptForTest() => _promptedThisSession = false;

/// Explains why the exemption matters and asks for it, then returns whether
/// the app is exempt.
Future<bool> ensureBackgroundAllowed(
  BuildContext context, {
  BatteryOptimization service = const AndroidBatteryOptimization(),
  String reason =
      'so live location, arrival alerts and backups keep running while the '
      'app is closed',
  bool onlyOncePerSession = false,
}) async {
  if (await service.isExempt()) return true;
  if (onlyOncePerSession) {
    if (_promptedThisSession) return false;
    _promptedThisSession = true;
  }
  if (!context.mounted) return false;
  final proceed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.battery_saver_outlined),
      title: const Text('Keep running in background'),
      content: Text(
        'Android may pause this app to save battery. Allow it to run in the '
        'background $reason.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Allow'),
        ),
      ],
    ),
  );
  if (proceed != true) return false;
  return service.requestExemption();
}
