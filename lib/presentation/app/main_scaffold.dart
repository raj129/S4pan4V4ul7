import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../application/services/import_manager.dart';

class MainScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  final ImportManager importManager;

  const MainScaffold({
    required this.navigationShell,
    required this.importManager,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          navigationShell,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: ListenableBuilder(
                listenable: importManager,
                builder: (context, _) {
                  final progress = importManager.progress;
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
      drawer: NavigationDrawer(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
          Navigator.of(context).pop(); // Close drawer
        },
        children: const [
          Padding(
            padding: EdgeInsets.fromLTRB(28, 16, 16, 10),
            child: Text('Photo Vault'),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library),
            label: Text('Photos'),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: Text('Chat'),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.delete_outline),
            selectedIcon: Icon(Icons.delete),
            label: Text('Bin'),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.folder_open_outlined),
            selectedIcon: Icon(Icons.folder_open),
            label: Text('Files'),
          ),
        ],
      ),
    );
  }
}
