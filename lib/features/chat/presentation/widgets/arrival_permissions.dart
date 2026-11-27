import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/platform/battery_optimization.dart';

/// Requests what arrival alerts need: foreground location, "Allow all the
/// time" background location, notifications, and battery optimization
/// exemption so alerts fire without opening the app.
///
/// Returns false when basic foreground location is refused; refused background
/// location or battery exemption still warns so the user knows why alerts may
/// wait until the app is opened.
Future<bool> ensureArrivalPermissions(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  var foreground = await Permission.locationWhenInUse.status;
  if (!foreground.isGranted) {
    foreground = await Permission.locationWhenInUse.request();
  }
  if (!foreground.isGranted) {
    if (foreground.isPermanentlyDenied && context.mounted) {
      await _promptOpenSettings(
        context,
        title: 'Location permission needed',
        message:
            'Arrival alerts need location access. Open App Settings and '
            'enable Location.',
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Allow location access to use arrival alerts.'),
        ),
      );
    }
    return false;
  }

  var always = await Permission.locationAlways.status;
  if (!always.isGranted) {
    always = await Permission.locationAlways.request();
  }
  if (!always.isGranted && context.mounted) {
    await _promptOpenSettings(
      context,
      title: 'Allow location all the time',
      message:
          'To send arrival alerts when the app is closed, set Location '
          'permission to "Allow all the time" in App Settings.',
    );
    always = await Permission.locationAlways.status;
    if (!always.isGranted && context.mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Choose "Allow all the time" so alerts also work when the app is '
            'in the background.',
          ),
        ),
      );
    }
  }

  await Permission.notification.request();

  if (Platform.isAndroid && context.mounted) {
    await ensureBackgroundAllowed(
      context,
      reason:
          'so arrival alerts send automatically in the background without '
          'opening the app',
    );
  }
  return true;
}

Future<void> _promptOpenSettings(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final open = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.location_on_outlined),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Open Settings'),
        ),
      ],
    ),
  );
  if (open == true) {
    await openAppSettings();
  }
}
