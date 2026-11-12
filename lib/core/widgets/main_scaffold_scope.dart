import 'package:flutter/material.dart';

/// Exposes the app's single shared drawer to any descendant widget — even
/// ones that build their own nested [Scaffold].
///
/// Several top-level screens (gallery, trash, files, chat) each used to
/// build their own `Scaffold` and call `Scaffold.of(context).openDrawer()`
/// from their menu button. Because `Scaffold.of` resolves to the *nearest*
/// ancestor `Scaffold` — which was their own drawerless one, not the shell's
/// — the menu button silently did nothing (or threw) on every screen except
/// whichever one happened to have no nested `Scaffold`. This scope fixes
/// that by giving descendants a direct handle to the shell's drawer,
/// regardless of how many `Scaffold`s sit in between.
class MainScaffoldScope extends InheritedWidget {
  const MainScaffoldScope({
    super.key,
    required this.openDrawer,
    this.onLock,
    required super.child,
  });

  final VoidCallback openDrawer;
  final VoidCallback? onLock;

  static MainScaffoldScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<MainScaffoldScope>();
  }

  @override
  bool updateShouldNotify(MainScaffoldScope oldWidget) =>
      openDrawer != oldWidget.openDrawer || onLock != oldWidget.onLock;
}

/// Provides an app-wide lock callback to all descendant widgets.
class VaultLockScope extends InheritedWidget {
  const VaultLockScope({
    super.key,
    required this.onLock,
    required super.child,
  });

  final VoidCallback onLock;

  static VaultLockScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<VaultLockScope>();
  }

  @override
  bool updateShouldNotify(VaultLockScope oldWidget) =>
      onLock != oldWidget.onLock;
}

/// Quick lock action button matching the lock button on the chat thread.
class QuickLockActionButton extends StatelessWidget {
  const QuickLockActionButton({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.lock_outline_rounded, color: color),
      tooltip: 'Lock vault',
      onPressed: () => lockApp(context),
    );
  }
}

/// Locks the vault and navigates back to calculator mode.
void lockApp(BuildContext context) {
  final scope = MainScaffoldScope.maybeOf(context);
  if (scope?.onLock != null) {
    scope!.onLock!();
    return;
  }
  final lockScope = VaultLockScope.maybeOf(context);
  if (lockScope != null) {
    lockScope.onLock();
    return;
  }
}

/// Opens the app's shared navigation drawer.
///
/// Prefers [MainScaffoldScope] (the shell's drawer) when available, and
/// falls back to the nearest [Scaffold] otherwise so screens can still be
/// used/tested standalone outside the shell.
void openAppNavigationDrawer(BuildContext context) {
  final scope = MainScaffoldScope.maybeOf(context);
  if (scope != null) {
    scope.openDrawer();
    return;
  }

  final scaffold = Scaffold.maybeOf(context);
  if (scaffold != null) {
    scaffold.openDrawer();
  }
}
