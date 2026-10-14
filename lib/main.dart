import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/app_routes.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const InkFightApp());
}

class InkFightApp extends StatelessWidget {
  const InkFightApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'INK FIGHT: Doodle Combat',
      theme: InkFightTheme.light,
      // Deliberately no `home:` and no `initialRoute:`. Flutter only reads the
      // platform's default route name when the app does not pin a start route
      // of its own, and that name is the whole web deep link: the preview at
      // `…/preview/main/#/settings` arrives as `/settings` and lands on the
      // settings screen without any router package.
      routes: InkRoutes.table,
      onUnknownRoute: (_) =>
          MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
    );
  }
}
