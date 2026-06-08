import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:meow_food_butler/firebase_options.dart';
import 'package:meow_food_butler/services/navigation.dart'; // Import your navigation layout directly
import 'package:meow_food_butler/theme/theme.dart';
import 'package:meow_food_butler/utils/theme_util.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const FoodButlerApp());
}

class FoodButlerApp extends StatelessWidget {
  const FoodButlerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = View.of(context).platformDispatcher.platformBrightness;
    TextTheme textTheme = createTextTheme(context, "Abril Fatface", "Abril Fatface");
    MaterialTheme theme = MaterialTheme(textTheme);
    return MaterialApp.router(
      title: 'Food Butler',
      theme: brightness == Brightness.light ? theme.light() : theme.dark(),
      // Bind router delegates straight to your GoRouter architecture schema
      routerConfig: AppNavigation.router,
      debugShowCheckedModeBanner: false,
    );
  }
}