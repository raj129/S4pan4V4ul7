import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../state/chat/chat_auth_cubit.dart';
import '../../theme/app_spacing.dart';

/// Full-page Google Sign-In screen for the chat module.
class ChatSignInScreen extends StatelessWidget {
  const ChatSignInScreen({this.isLocalMode = false, super.key});

  final bool isLocalMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.xxl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Hero mark: a tinted disc keeps the lock from reading as a
                  // bare error icon.
                  Center(
                    child: Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cs.primary.withValues(alpha: 0.10),
                      ),
                      child: Icon(
                        Icons.lock_outline_rounded,
                        size: 48,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Secure Chat',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    isLocalMode
                        ? 'Chat needs Google sign-in even when your vault is '
                            'local-only. Sign in with your Gmail account to '
                            'continue.'
                        : 'End-to-end encrypted 1:1 messaging. Sign in with '
                            'your Gmail account to start.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  BlocConsumer<ChatAuthCubit, ChatAuthState>(
                    listener: (context, state) {
                      if (state is ChatAuthError) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(state.message)),
                        );
                      }
                    },
                    builder: (context, state) {
                      final loading = state is ChatAuthLoading;
                      return FilledButton.icon(
                        icon: loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.login_rounded),
                        label: Text(
                          loading ? 'Signing in…' : 'Sign in with Google',
                        ),
                        onPressed: loading
                            ? null
                            : () => context.read<ChatAuthCubit>().signIn(),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 14,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          'Messages are encrypted on your device',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
