import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../state/chat/chat_auth_cubit.dart';

/// Full-page Google Sign-In screen for the chat module.
class ChatSignInScreen extends StatelessWidget {
  const ChatSignInScreen({this.isLocalMode = false, super.key});

  final bool isLocalMode;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.lock_outline, size: 72, color: Color(0xFF4A6CF7)),
              const SizedBox(height: 24),
              Text(
                'Secure Chat',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isLocalMode
                    ? 'Chat needs Google sign-in even when vault is local-only.\nSign in with your Gmail account to continue.'
                    : 'End-to-end encrypted 1:1 messaging.\nSign in with your Gmail account to start.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              BlocConsumer<ChatAuthCubit, ChatAuthState>(
                listener: (context, state) {
                  if (state is ChatAuthError) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(state.message)),
                    );
                  }
                },
                builder: (context, state) {
                  if (state is ChatAuthLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return FilledButton.icon(
                    icon: const Icon(Icons.login),
                    label: const Text('Sign in with Google'),
                    onPressed: () => context.read<ChatAuthCubit>().signIn(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
