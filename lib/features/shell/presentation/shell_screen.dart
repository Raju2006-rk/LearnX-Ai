import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The bottom-navigation scaffold that hosts the Home, AI, and Account
/// branches of the authenticated app.
///
/// Rendered by a [StatefulShellRoute.indexedStack] so each destination keeps
/// its own navigation state and is preserved across tab switches. Selecting a
/// destination switches the active branch. (Requirements 12.1, 12.2)
class ShellScreen extends StatelessWidget {
  const ShellScreen({required this.navigationShell, super.key});

  /// The shell provided by go_router that manages the indexed branch stacks.
  final StatefulNavigationShell navigationShell;

  void _onDestinationSelected(int index) {
    // `initialLocation` restores the branch's first route when the currently
    // selected destination is tapped again.
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'AI',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}
