import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:photo_vault/core/presentation/theme/app_spacing.dart';
import 'package:photo_vault/core/widgets/base_screen_shell.dart';

class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BaseScreenShell(
      title: 'Notification settings',
      showDrawerMenu: false,
      drawerSelectedIndex: 6,
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(
            'Choose a notification type to configure its message and alert.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          _NotificationTypeTile(
            key: const Key('notification-type-messages'),
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Chat messages',
            subtitle: 'Message text, sound, vibration, and flashlight.',
            onTap: () =>
                unawaited(context.push('/settings/notifications/messages')),
          ),
          const SizedBox(height: AppSpacing.sm),
          _NotificationTypeTile(
            key: const Key('notification-type-ring-requests'),
            icon: Icons.ring_volume_outlined,
            title: 'Ring requests',
            subtitle: 'Ring alert behavior and notification text.',
            onTap: () => unawaited(
              context.push('/settings/notifications/ring-requests'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _NotificationTypeTile(
            key: const Key('notification-type-background-location'),
            icon: Icons.location_on_outlined,
            title: 'Background location',
            subtitle: 'Text shown while live location is shared.',
            onTap: () => unawaited(
              context.push('/settings/notifications/background-location'),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTypeTile extends StatelessWidget {
  const _NotificationTypeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        minVerticalPadding: AppSpacing.md,
        leading: Icon(icon, color: colors.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
