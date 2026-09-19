import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../presentation/theme/app_spacing.dart';
import 'app_navigation_drawer.dart';

class BaseScreenShell extends StatelessWidget {
  BaseScreenShell({
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.showDrawerMenu = true,
    this.drawerSelectedIndex = -1,
    super.key,
  }) : _scaffoldKey = GlobalKey<ScaffoldState>();

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final bool showDrawerMenu;
  final int drawerSelectedIndex;
  final GlobalKey<ScaffoldState> _scaffoldKey;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(title),
        leading: showDrawerMenu
            ? IconButton(
                tooltip: 'Open navigation',
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              )
            : null,
        actions: actions == null
            ? null
            : [...actions!, const SizedBox(width: AppSpacing.xs)],
      ),
      drawer: showDrawerMenu
          ? AppNavigationDrawer(
              selectedIndex: drawerSelectedIndex,
              onDestinationSelected: (index) {
                Navigator.of(context).pop();
                switch (index) {
                  case 0:
                    context.go('/chat');
                    break;
                  case 1:
                    context.go('/gallery');
                    break;
                  case 2:
                    context.go('/trash');
                    break;
                  case 3:
                    context.go('/files');
                    break;
                  case 4:
                    context.go('/settings');
                    break;
                  default:
                    break;
                }
              },
            )
          : null,
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}
