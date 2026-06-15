import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// Mode View Screens
import 'package:meow_food_butler/views/map/main_map_screen.dart';
import 'package:meow_food_butler/views/chat/chat_screen.dart';
import 'package:meow_food_butler/views/saved/saved_screen.dart';

/// Global navigator keys for handling context-less actions if required
final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final GlobalKey<NavigatorState> _mapNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'mapChan');
final GlobalKey<NavigatorState> _chatNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'chatChan');
final GlobalKey<NavigatorState> _savedNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'savedChan');

class AppNavigation {
  AppNavigation._();

  static const String mapPath = '/map';
  static const String chatPath = '/chat';
  static const String savedPath = '/saved';

  /// Configuration schema mapping application routes
  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: mapPath,
    debugLogDiagnostics: true,
    routes: [
      /// StatefulShellRoute creates an immutable persistent viewport frame 
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          // Returns the wrapper containing our permanent bottom navigation arrangement
          return ScaffoldWithNestedNavigation(navigationShell: navigationShell);
        },
        branches: [
          /// Branch 1: Map Channel
          StatefulShellBranch(
            navigatorKey: _mapNavigatorKey,
            routes: [
              GoRoute(
                path: mapPath,
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: MainMapScreen(),
                ),
              ),
            ],
          ),

          /// Branch 2: AI Chat Assistant Channel
          StatefulShellBranch(
            navigatorKey: _chatNavigatorKey,
            routes: [
              GoRoute(
                path: chatPath,
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: ChatScreen(),
                ),
              ),
            ],
          ),

          /// Branch 3: Saved Experiences Library
          StatefulShellBranch(
            navigatorKey: _savedNavigatorKey,
            routes: [
              GoRoute(
                path: savedPath,
                pageBuilder: (context, state) => NoTransitionPage(
                  child: SavedScreen(
                    initialSearchQuery: state.uri.queryParameters['q'],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

// ==========================================================================
// PERSISTENT NAVIGATION SHELL WRAPPER
// ==========================================================================

class ScaffoldWithNestedNavigation extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const ScaffoldWithNestedNavigation({
    super.key,
    required this.navigationShell,
  });

  void _onTap(int index) {
    // Navigates to the designated branch while preserving stack state
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell, // Houses the active sub-route stack directly
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Map',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble),
              label: 'Assistant',
            ),
            NavigationDestination(
              icon: Icon(Icons.bookmark_border),
              selectedIcon: Icon(Icons.bookmark),
              label: 'Saved',
            ),
          ],
          onDestinationSelected: _onTap,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          indicatorColor: Theme.of(context).colorScheme.primaryContainer,
          elevation: 0,
        ),
      ),
    );
  }
}

// ==========================================================================
// DUMMY PLACEHOLDER COMPONENT (For initialization testing)
// ==========================================================================

class DummyPlaceholderScaffold extends StatelessWidget {
  final String title;
  final Color color;
  const DummyPlaceholderScaffold({super.key, required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: color.withOpacity(0.2),
      appBar: AppBar(title: Text(title), centerTitle: true, elevation: 0, backgroundColor: Colors.transparent),
      body: Center(
        child: Text(
          title,
          style: TextStyle(fontSize: 20, color: color, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
