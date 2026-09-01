import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../application/services/contact_discovery_service.dart';
import '../../state/chat/contact_discovery_cubit.dart';
import '../../state/chat/user_lookup_cubit.dart';
import 'thread_screen.dart';

/// Screen for starting a chat: matched contacts first, email fallback below.
class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // Kick off the scan immediately; the permission prompt appears on the
    // first attempt and the result is cached in the cubit afterwards.
    context.read<ContactDiscoveryCubit>().scan();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Chat'),
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: BlocListener<UserLookupCubit, UserLookupState>(
        listener: (context, state) {
          if (state is UserLookupFound) {
            openThreadScreen(
              context,
              thread: state.thread,
              otherUser: state.user,
              replace: true,
            );
          } else if (state is UserLookupError) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _buildEmailForm(context),
            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              'From your contacts',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _buildContactList(context),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailForm(BuildContext context) {
    return BlocBuilder<UserLookupCubit, UserLookupState>(
      builder: (context, state) {
        return Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Enter Gmail address',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _controller,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'user@gmail.com',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Please enter an email address.';
                  }
                  final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
                  if (!emailRegex.hasMatch(v.trim())) {
                    return 'Enter a valid email address.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              if (state is UserLookupLoading)
                const Center(child: CircularProgressIndicator())
              else
                FilledButton(
                  onPressed: () {
                    if (_formKey.currentState?.validate() ?? false) {
                      context.read<UserLookupCubit>().lookupByEmail(
                        _controller.text,
                      );
                    }
                  },
                  child: const Text('Find user'),
                ),
              if (state is UserLookupNotFound) ...[
                const SizedBox(height: 24),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.person_off_outlined,
                          color: Theme.of(
                            context,
                          ).colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${state.email} is not registered.',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildContactList(BuildContext context) {
    return BlocBuilder<ContactDiscoveryCubit, ContactDiscoveryState>(
      builder: (context, state) {
        switch (state) {
          case ContactDiscoveryIdle():
          case ContactDiscoveryLoading():
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            );

          case ContactDiscoveryFailed(:final message):
            return _Notice(
              icon: Icons.error_outline,
              text: 'Could not read contacts: $message',
              actionLabel: 'Retry',
              onAction: () => context.read<ContactDiscoveryCubit>().scan(),
            );

          case ContactDiscoveryLoaded(:final result):
            if (!result.permissionGranted) {
              return _Notice(
                icon: Icons.contacts_outlined,
                text:
                    'Contacts permission was denied. You can still start a '
                    'chat by typing an email address above.',
                actionLabel: 'Try again',
                onAction: () => context.read<ContactDiscoveryCubit>().scan(),
              );
            }
            if (result.matches.isEmpty) {
              return _Notice(
                icon: Icons.person_search_outlined,
                text: result.scannedEmails == 0
                    ? 'None of your contacts have an email address saved.'
                    : 'None of your ${result.scannedEmails} contact email '
                          'addresses are registered yet.',
                actionLabel: 'Rescan',
                onAction: () => context.read<ContactDiscoveryCubit>().scan(),
              );
            }
            return Column(
              children: [
                for (final match in result.matches)
                  _ContactTile(match: match),
              ],
            );
        }
      },
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.match});

  final MatchedContact match;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundImage: match.user.photoUrl != null
            ? NetworkImage(match.user.photoUrl!)
            : null,
        child: match.user.photoUrl == null
            ? Text(match.user.initials)
            : null,
      ),
      title: Text(match.contactName),
      subtitle: Text(
        match.user.email,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chat_bubble_outline, size: 20),
      onTap: () =>
          context.read<UserLookupCubit>().lookupByEmail(match.user.email),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
            TextButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

