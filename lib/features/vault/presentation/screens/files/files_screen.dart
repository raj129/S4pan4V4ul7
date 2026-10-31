import 'package:flutter/material.dart';

import 'package:photo_vault/core/widgets/app_state_views.dart';
import 'package:photo_vault/core/widgets/base_screen_shell.dart';

class FilesScreen extends StatelessWidget {
  const FilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BaseScreenShell(
      title: 'Encrypted Files',
      drawerSelectedIndex: 3,
      body: const EmptyView(
        icon: Icons.folder_open_outlined,
        title: 'Secure File Storage',
        subtitle:
            'Store documents and private files encrypted inside your vault.',
      ),
    );
  }
}
