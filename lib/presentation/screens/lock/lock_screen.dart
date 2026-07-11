import 'package:flutter/material.dart';

import '../../../domain/entities/user_mode.dart';
import '../gallery/vault_gallery_screen.dart';

class LockScreen extends StatelessWidget {
  const LockScreen({required this.mode, super.key});

  final UserMode mode;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Unlock Vault')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Selected mode: ${mode.title}'),
            const SizedBox(height: 12),
            const Text('App PIN and biometric flows will be implemented next.'),
            const Spacer(),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => VaultGalleryScreen(mode: mode),
                  ),
                );
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
