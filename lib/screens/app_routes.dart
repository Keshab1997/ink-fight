import 'package:flutter/material.dart';

import '../state/ink_settings.dart';
import 'bot_fight_screen.dart';
import 'difficulty_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

/// The app's route names, in one place.
///
/// Every navigation in the app goes through these names, and the web build
/// reads them straight out of the URL fragment — the preview at
/// `…/preview/main/#/settings` opens the settings screen because Flutter hands
/// the app `defaultRouteName` = `/settings` and [InkFightApp] hands that to the
/// navigator untouched. A typo here would be a dead deep link, so screens ask
/// for these constants instead of writing the strings themselves.
abstract final class InkRoutes {
  static const home = '/';
  static const difficulty = '/difficulty';
  static const botFight = '/bot-fight';
  static const settings = '/settings';

  /// The navigator's table, exactly what `MaterialApp.routes` wants.
  ///
  /// [preferences] is the app's one preference model: the table closes over
  /// it, so every route — deep links included — builds screens that read and
  /// write the same instance. The parameter is deliberately not named
  /// `settings`: that identifier is already the `/settings` route constant
  /// above, and a parameter of the same name would shadow it into a map key.
  static Map<String, WidgetBuilder> table(InkSettings preferences) =>
      <String, WidgetBuilder>{
        home: (_) => const HomeScreen(),
        difficulty: (_) => const DifficultyScreen(),
        botFight: (_) => const BotFightScreen(),
        settings: (_) => SettingsScreen(settings: preferences),
      };
}
