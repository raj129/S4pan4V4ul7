import 'package:flutter/material.dart';

import '../presentation/theme/app_spacing.dart';

String? navigationPathForDestination(int index) => switch (index) {
  0 => '/chat',
  1 => '/gallery',
  2 => '/trash',
  3 => '/files',
  4 => '/notes',
  5 => '/calls',
  6 => '/settings',
  7 => '/settings/developer',
  8 => '/chat/my-locations',
  _ => null,
};

/// Destinations that open above the current tab instead of replacing it.
bool isPushedDestination(int index) => index == 7 || index == 8;

/// Tells the drawer, wherever it is hosted, which optional entries apply.
/// Evaluated when the drawer is built, i.e. each time it is opened.
class AppDrawerScope extends InheritedWidget {
  const AppDrawerScope({
    super.key,
    required this.hasMyLocations,
    required super.child,
  });

  final bool Function() hasMyLocations;

  static bool myLocationsAvailable(BuildContext context) =>
      context
          .getInheritedWidgetOfExactType<AppDrawerScope>()
          ?.hasMyLocations() ??
      false;

  @override
  bool updateShouldNotify(AppDrawerScope oldWidget) => false;
}

/// The app's single navigation drawer UI.
///
/// Extracted out of `MainScaffold` so the drawer's destinations are defined
/// in exactly one place and can be reused/tested independently of the
/// shell that hosts it.
class AppNavigationDrawer extends StatelessWidget {
  const AppNavigationDrawer({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.showMyLocations,
  });

  /// Index of the currently active top-level destination (Chat, Photos,
  /// Bin, Files, Settings).
  final int selectedIndex;

  final ValueChanged<int> onDestinationSelected;

  /// Overrides [AppDrawerScope]; saved places and arrival alerts need chat
  /// sign-in on Android.
  final bool? showMyLocations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return NavigationDrawer(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xxl,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  color: theme.colorScheme.onPrimaryContainer,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Photo Vault',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Encrypted private space',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Divider(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const NavigationDrawerDestination(
          icon: Icon(Icons.chat_bubble_outline),
          selectedIcon: Icon(Icons.chat_bubble),
          label: Text('Chat'),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.photo_library_outlined),
          selectedIcon: Icon(Icons.photo_library),
          label: Text('Photos'),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.delete_outline),
          selectedIcon: Icon(Icons.delete),
          label: Text('Bin'),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.folder_open_outlined),
          selectedIcon: Icon(Icons.folder_open),
          label: Text('Files'),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.checklist_rtl_rounded),
          selectedIcon: Icon(Icons.checklist_rounded),
          label: Text('Notes & Lists'),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.call_outlined),
          selectedIcon: Icon(Icons.call),
          label: Text('Call log'),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: Text('Settings'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.sm,
          ),
          child: Text(
            'Location',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.location_searching_outlined),
          selectedIcon: Icon(Icons.location_searching),
          label: Text('Mock location'),
        ),
        if (showMyLocations ?? AppDrawerScope.myLocationsAvailable(context))
          const NavigationDrawerDestination(
            icon: Icon(Icons.pin_drop_outlined),
            selectedIcon: Icon(Icons.pin_drop),
            label: Text('My locations'),
          ),
      ],
    );
  }
}
