import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Requests what arrival alerts need. Returns false when the basic location
/// permission is refused; a refused background permission only warns, since
/// alerts still work while the app is open.
Future<bool> ensureArrivalPermissions(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final foreground = await Permission.locationWhenInUse.request();
  if (!foreground.isGranted) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Allow location access to use arrival alerts.'),
      ),
    );
    return false;
  }
  final always = await Permission.locationAlways.request();
  if (!always.isGranted) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Choose "Allow all the time" so alerts also work when the app is in '
          'the background.',
        ),
      ),
    );
  }
  await Permission.notification.request();
  return true;
}
