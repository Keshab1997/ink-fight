import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/audio/fight_sounds.dart';
import 'screens/app_routes.dart';
import 'screens/home_screen.dart';
import 'state/ink_settings.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Immersive landscape: the fight owns the whole sheet of paper, and the
  // status bar only comes back when the player swipes for it. Skipped on web,
  // where there is no status bar to hide and the browser owns the chrome --
  // calling SystemChrome there is noise in the console, not a visual change.
  if (!kIsWeb) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  runApp(InkFightApp(settings: InkSettings()));
}

class InkFightApp extends StatelessWidget {
  const InkFightApp({super.key, required this.settings, this.sounds});

  /// The app's one preference model, built in `main()` and handed to the
  /// routes table — session-scoped by design (see [InkSettings]).
  final InkSettings settings;

  /// The arena's audio seam. `null` in the app itself, where the fight
  /// screen builds the real one; tests hand in a silent fake so no test
  /// ever loads an audio plugin.
  final FightSounds? sounds;

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
      routes: InkRoutes.table(settings, sounds: sounds),
      onUnknownRoute: (_) =>
          MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
    );
  }
}
