import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../application/services/chat_identity_service.dart';
import '../../state/chat/chat_auth_cubit.dart';

/// Banner shown when a chat key backup exists but could not be unwrapped.
///
/// This is the reinstall / new-device case: the ciphertext is present in
/// Firestore, but until the correct PIN unwraps the identity key, none of it
/// decrypts. Without this the user would just see an empty or garbled thread
/// list with no explanation.
class HistoryLockedBanner extends StatelessWidget {
  const HistoryLockedBanner({super.key, required this.result});

  final IdentitySyncResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wrongPin = result == IdentitySyncResult.wrongPin;
    return MaterialBanner(
      backgroundColor: scheme.errorContainer,
      leading: Icon(Icons.lock_outline, color: scheme.onErrorContainer),
      content: Text(
        wrongPin
            ? 'That PIN did not unlock your chat history. Try again with the '
                  'PIN you used on your previous device.'
            : 'Your earlier messages are locked. Enter your vault PIN to '
                  'restore chat history on this device.',
        style: TextStyle(color: scheme.onErrorContainer),
      ),
      actions: [
        TextButton(
          onPressed: () => _promptForPin(context),
          child: const Text('Unlock'),
        ),
      ],
    );
  }

  Future<void> _promptForPin(BuildContext context) async {
    // Captured before the await: the banner is stateless, so there is no
    // `mounted` flag to guard a later lookup with.
    final cubit = context.read<ChatAuthCubit>();
    final messenger = ScaffoldMessenger.of(context);

    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const _PinPromptDialog(),
    );
    if (pin == null || pin.isEmpty) return;

    final outcome = await cubit.unlockHistory(pin);
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (outcome) {
          IdentitySyncResult.restored => 'Chat history unlocked.',
          IdentitySyncResult.wrongPin => 'Incorrect PIN.',
          _ => 'Could not unlock chat history.',
        }),
      ),
    );
  }
}

class _PinPromptDialog extends StatefulWidget {
  const _PinPromptDialog();

  @override
  State<_PinPromptDialog> createState() => _PinPromptDialogState();
}

class _PinPromptDialogState extends State<_PinPromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Unlock chat history'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter the vault PIN from the device where these chats were sent. '
            'Without it, older messages cannot be recovered.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'PIN',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Unlock'),
        ),
      ],
    );
  }
}
