import 'package:flutter/material.dart';

import '../../../domain/entities/user_mode.dart';

class VaultGalleryScreen extends StatelessWidget {
  const VaultGalleryScreen({required this.mode, super.key});

  final UserMode mode;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vault Gallery')),
      body: Center(
        child: Text(
          'Vault initialized in ${mode.title}. Import pipeline is next.',
        ),
      ),
    );
  }
}
