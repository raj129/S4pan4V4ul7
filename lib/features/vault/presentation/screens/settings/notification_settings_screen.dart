import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:photo_vault/core/presentation/theme/app_spacing.dart';
import 'package:photo_vault/core/widgets/app_surfaces.dart';
import 'package:photo_vault/core/widgets/base_screen_shell.dart';

class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BaseScreenShell(
      title: 'Notification settings',
      showDrawerMenu: false,
      drawerSelectedIndex: 6,
      body: ListView(
        padding: const EdgeInsets.only(
          top: AppSpacing.md,
          bottom: AppSpacing.xl,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.xl,
              AppSpacing.md,
            ),
            child: Text(
              'Choose a notification type to configure its message and alert.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          SettingsCard(
            children: [
              _NotificationTypeTile(
                key: const Key('notification-type-messages'),
                icon: Icons.chat_bubble_outline_rounded,
                badgeBg: cs.primaryContainer,
                badgeFg: cs.onPrimaryContainer,
                title: 'Chat messages',
                subtitle: 'Message text, sound, vibration, and flashlight.',
                onTap: () =>
                    unawaited(context.push('/settings/notifications/messages')),
              ),
              _NotificationTypeTile(
                key: const Key('notification-type-ring-requests'),
                icon: Icons.ring_volume_outlined,
                badgeBg: cs.tertiaryContainer,
                badgeFg: cs.onTertiaryContainer,
                title: 'Ring requests',
                subtitle: 'Ring alert behavior and notification text.',
                onTap: () => unawaited(
                  context.push('/settings/notifications/ring-requests'),
                ),
              ),
              _NotificationTypeTile(
                key: const Key('notification-type-background-location'),
                icon: Icons.location_on_outlined,
                badgeBg: cs.secondaryContainer,
                badgeFg: cs.onSecondaryContainer,
                title: 'Background location',
                subtitle: 'Text shown while live location is shared.',
                onTap: () => unawaited(
                  context.push('/settings/notifications/background-location'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NotificationTypeTile extends StatelessWidget {
  const _NotificationTypeTile({
    required this.icon,
    required this.badgeBg,
    required this.badgeFg,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final Color badgeBg;
  final Color badgeFg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minVerticalPadding: AppSpacing.md,
      leading: SettingsIconBadge(
        icon: icon,
        backgroundColor: badgeBg,
        iconColor: badgeFg,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
