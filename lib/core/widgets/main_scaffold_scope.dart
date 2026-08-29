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
    required super.child,
  });

  final VoidCallback openDrawer;

  static MainScaffoldScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<MainScaffoldScope>();
  }

  @override
  bool updateShouldNotify(MainScaffoldScope oldWidget) =>
      openDrawer != oldWidget.openDrawer;
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
  Scaffold.of(context).openDrawer();
}
