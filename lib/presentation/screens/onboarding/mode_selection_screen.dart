import 'package:flutter/material.dart';

import '../../../application/usecases/select_mode_usecase.dart';
import '../../../domain/entities/user_mode.dart';

class ModeSelectionScreen extends StatefulWidget {
  const ModeSelectionScreen({required this.selectModeUseCase, super.key});

  final SelectModeUseCase selectModeUseCase;

  @override
  State<ModeSelectionScreen> createState() => _ModeSelectionScreenState();
}

class _ModeSelectionScreenState extends State<ModeSelectionScreen> {
  bool _isSaving = false;

  Future<void> _pickMode(UserMode mode) async {
    setState(() {
      _isSaving = true;
    });

    await widget.selectModeUseCase.execute(mode);

    if (!mounted) {
      return;
    }

    setState(() {
      _isSaving = false;
    });

    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to Photo Vault')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Choose how to start. You can switch to Google-enabled mode later in settings.',
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: UserMode.values.length,
                itemBuilder: (context, index) {
                  final mode = UserMode.values[index];
                  return Card(
                    child: ListTile(
                      title: Text(mode.title),
                      subtitle: Text(mode.description),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded),
                      onTap: _isSaving ? null : () => _pickMode(mode),
                    ),
                  );
                },
              ),
            ),
            if (_isSaving)
              const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}
