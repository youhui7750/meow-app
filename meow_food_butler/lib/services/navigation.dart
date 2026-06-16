import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:meow_food_butler/view_models/saved_view_model.dart';

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

class ScaffoldWithNestedNavigation extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const ScaffoldWithNestedNavigation({
    super.key,
    required this.navigationShell,
  });

  @override
  State<ScaffoldWithNestedNavigation> createState() =>
      _ScaffoldWithNestedNavigationState();
}

class _ScaffoldWithNestedNavigationState
    extends State<ScaffoldWithNestedNavigation> {
  StreamSubscription<RestaurantImportEvent>? _importSub;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _processingSnackBar;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _importSub?.cancel();
    _importSub = context
        .read<SavedViewModel>()
        .importEvents
        .listen(_handleImportEvent);
  }

  void _handleImportEvent(RestaurantImportEvent event) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    if (event.isStarted) {
      _processingSnackBar?.close();
      _processingSnackBar = messenger.showSnackBar(
        SnackBar(
          duration: const Duration(minutes: 2),
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '正在擷取「${event.restaurantName}」的餐廳資訊…',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    } else if (event.isCompleted) {
      _processingSnackBar?.close();
      _processingSnackBar = null;
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              const Icon(
                Icons.check_circle,
                size: 22,
                color: Color(0xFF4CAF50),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '「${event.restaurantName}」已成功加入地圖！',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    } else if (event.isReviewCreated) {
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              const Icon(
                Icons.edit_note,
                size: 22,
                color: Color(0xFF90CAF9),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '「${event.restaurantName}」用餐記錄已儲存',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  void _onTap(int index) {
    // Pop the current branch's own Flutter navigator to root BEFORE switching.
    // goBranch only resets GoRouter's routing state, not the underlying
    // Navigator stack — so screens pushed via Navigator.push() (e.g.
    // ExperienceDetailScreen) would otherwise survive the tab switch.
    final branchKeys = [
      _mapNavigatorKey,
      _chatNavigatorKey,
      _savedNavigatorKey,
    ];
    final currentKey = branchKeys[widget.navigationShell.currentIndex];
    if (currentKey.currentState?.canPop() == true) {
      currentKey.currentState!.popUntil((route) => route.isFirst);
    }
    widget.navigationShell.goBranch(index, initialLocation: true);
  }

  @override
  void dispose() {
    _importSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.navigationShell, // Houses the active sub-route stack directly
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
          selectedIndex: widget.navigationShell.currentIndex,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Restaurants',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble),
              label: 'Assistant',
            ),
            NavigationDestination(
              icon: Icon(Icons.bookmark_border),
              selectedIcon: Icon(Icons.bookmark),
              label: 'Experiences',
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
