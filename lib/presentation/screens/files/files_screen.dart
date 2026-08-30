import 'package:flutter/material.dart';

import '../../../core/widgets/base_screen_shell.dart';

class FilesScreen extends StatelessWidget {
  const FilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BaseScreenShell(
      title: 'Encrypted Files',
      drawerSelectedIndex: 3,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            const Text(
              'Secure File Storage',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Store any file type in your vault.'),
          ],
        ),
      ),
    );
  }
}
