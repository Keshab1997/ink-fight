import 'package:flutter/material.dart';

import 'bot_fight_screen.dart';
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
  static const botFight = '/bot-fight';
  static const settings = '/settings';

  /// The navigator's table, exactly what `MaterialApp.routes` wants.
  static Map<String, WidgetBuilder> get table => <String, WidgetBuilder>{
    home: (_) => const HomeScreen(),
    botFight: (_) => const BotFightScreen(),
    settings: (_) => const SettingsScreen(),
  };
}
