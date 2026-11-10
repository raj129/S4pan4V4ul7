import 'package:flutter/material.dart';

import '../media/animated_media.dart';

class HdrPreviewToggleButton extends StatelessWidget {
  const HdrPreviewToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final preference = HdrPreviewPreference.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: preference.enabled,
      builder: (context, enabled, _) => IconButton(
        tooltip: enabled
            ? 'HDR preview on; tap to turn off'
            : 'HDR preview off; tap to turn on',
        icon: Icon(enabled ? Icons.hdr_on_rounded : Icons.hdr_off_rounded),
        onPressed: () async {
          try {
            await preference.toggle();
          } catch (error) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Could not save HDR preview setting: $error'),
              ),
            );
          }
        },
      ),
    );
  }
}
