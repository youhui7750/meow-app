import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meow_food_butler/firebase_options.dart';
import 'package:meow_food_butler/services/navigation.dart'; // Import your navigation layout directly
import 'package:meow_food_butler/services/shared_url_notifier.dart';
import 'package:meow_food_butler/theme/theme.dart';
import 'package:meow_food_butler/utils/theme_util.dart';
import 'package:meow_food_butler/view_models/saved_view_model.dart';
import 'package:provider/provider.dart';

const MethodChannel _sharedTextChannel = MethodChannel('meow_food_butler/shared_text');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const FoodButlerApp());
}

class FoodButlerApp extends StatefulWidget {
  const FoodButlerApp({super.key});

  @override
  State<FoodButlerApp> createState() => _FoodButlerAppState();
}

class _FoodButlerAppState extends State<FoodButlerApp> {
  final SharedUrlNotifier _sharedUrlNotifier = SharedUrlNotifier();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchSharedText();
    });
    _sharedTextChannel.setMethodCallHandler(_handleNativeMethod);
  }

  Future<void> _fetchSharedText() async {
    try {
      final sharedText = await _sharedTextChannel.invokeMethod<String>('getSharedText');
      _dispatchSharedText(sharedText);
    } on MissingPluginException {
      // Web/desktop builds do not provide the Android share-intent channel.
    } catch (error) {
      debugPrint('Failed to get shared text: $error');
    }
  }

  Future<dynamic> _handleNativeMethod(MethodCall call) async {
    if (call.method == 'sharedText') {
      _dispatchSharedText(call.arguments as String?);
    }
    return null;
  }

  void _dispatchSharedText(String? text) {
    if (text == null || text.trim().isEmpty) return;
    final url = _extractFirstUrl(text);
    if (url == null) return;

    _sharedUrlNotifier.updateSharedUrl(url);
    AppNavigation.router.go(AppNavigation.mapPath);
  }

  String? _extractFirstUrl(String text) {
    final match = RegExp(r'https?://[^\s]+').firstMatch(text.trim());
    return match?.group(0);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = View.of(context).platformDispatcher.platformBrightness;
    TextTheme textTheme = createTextTheme(
      context,
      'Nunito',
      'Fraunces',
    );
    MaterialTheme theme = MaterialTheme(textTheme);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SavedViewModel()),
        ChangeNotifierProvider<SharedUrlNotifier>(create: (_) => _sharedUrlNotifier),
      ],
      child: MaterialApp.router(
        title: 'Food Butler',
        theme: brightness == Brightness.light ? theme.light() : theme.dark(),
        // Bind router delegates straight to your GoRouter architecture schema
        routerConfig: AppNavigation.router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
