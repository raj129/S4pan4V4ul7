import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../application/services/import_manager.dart';
import '../../core/widgets/app_navigation_drawer.dart';
import '../../core/widgets/main_scaffold_scope.dart';

/// Hosts the four top-level tabs (Chat, Photos, Bin, Files) behind a single
/// shared [Scaffold] + drawer.
///
/// Publishes a [MainScaffoldScope] so any descendant screen — including
/// ones that build their own nested `Scaffold` for their app bar — can open
/// this drawer reliably via `openAppNavigationDrawer(context)` instead of
/// the ambiguous `Scaffold.of(context)`.
class MainScaffold extends StatefulWidget {
  const MainScaffold({
    required this.navigationShell,
    required this.importManager,
    super.key,
  });

  final StatefulNavigationShell navigationShell;
  final ImportManager importManager;

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  void _onDestinationSelected(int index) {
    if (index == 4) {
      Navigator.of(context).pop();
      context.go('/settings');
      return;
    }

    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return MainScaffoldScope(
      openDrawer: _openDrawer,
      child: Scaffold(
        key: _scaffoldKey,
        body: Stack(
          children: [
            widget.navigationShell,
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: ListenableBuilder(
                  listenable: widget.importManager,
                  builder: (context, _) {
                    final progress = widget.importManager.progress;
                    if (progress.status == ImportJobStatus.running) {
                      return LinearProgressIndicator(
                        value: progress.ratio,
                        backgroundColor: Colors.transparent,
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ],
        ),
        drawer: AppNavigationDrawer(
          selectedIndex: widget.navigationShell.currentIndex,
          onDestinationSelected: _onDestinationSelected,
        ),
      ),
    );
  }
}
