import 'package:flame/flame.dart';
import 'package:flame/game.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inkfight/game/bot/bot_strategy.dart';
import 'package:inkfight/game/ink_fight_battle_game.dart';
import 'package:inkfight/game/rules/match_rules.dart';
import 'package:inkfight/main.dart';
import 'package:inkfight/screens/app_routes.dart';
import 'package:inkfight/screens/bot_fight_screen.dart';
import 'package:inkfight/screens/difficulty_screen.dart';
import 'package:inkfight/screens/home_screen.dart';
import 'package:inkfight/screens/settings_screen.dart';
import 'package:inkfight/state/ink_settings.dart';
import 'package:inkfight/theme/app_theme.dart';

/// Puts the app on a given route the way the browser does: the platform's
/// default route name is what a web build reads out of the URL fragment
/// (`…/preview/main/#/settings` → `/settings`).
Future<void> pumpDeepLink(WidgetTester tester, String route) async {
  tester.binding.platformDispatcher.defaultRouteNameTestValue = route;
  addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
  await tester.pumpWidget(InkFightApp(settings: InkSettings()));
}

/// Mirrors [InkFightApp] but with a navigator observer, so a test can read the
/// route arguments a tap pushed.
Widget _appWithObserver(_RouteRecorder observer) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: InkFightTheme.light,
    navigatorObservers: [observer],
    // The table already maps '/' to the menu, so no `home:` (the two clash).
    routes: InkRoutes.table(InkSettings()),
  );
}

class _RouteRecorder extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

void main() {
  setUp(() {
    // The decoded-frame cache is global and keyed by asset path, and a test
    // that leaves the arena while its sprites are still decoding leaves a
    // half-finished future in it — born in *that* test's async zone, which is
    // dead by the time the next test runs. Awaiting the same key then never
    // completes, so whichever test loads the fight next hangs instead of
    // failing. Clearing before each test keeps every mount decoding its own
    // frames. (Cost us a ten-minute CI timeout to find.)
    Flame.images.clearCache();
    Flame.assets.clearCache();
  });

  testWidgets('shows the INK FIGHT landscape menu', (tester) async {
    await tester.pumpWidget(InkFightApp(settings: InkSettings()));

    expect(find.text('INK FIGHT'), findsOneWidget);
    expect(find.text('DOODLE COMBAT'), findsOneWidget);
    expect(find.text('BOT FIGHT'), findsOneWidget);
    expect(find.text('ONLINE 1V1'), findsOneWidget);
    expect(find.text('SETTINGS'), findsOneWidget);
  });

  testWidgets('the menu shows the two hero fighters at full vignette', (
    tester,
  ) async {
    await tester.pumpWidget(InkFightApp(settings: InkSettings()));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNWidgets(2));
    expect(find.text('YOU'), findsOneWidget);
    expect(find.text('CRIMSON RIVAL'), findsOneWidget);
    expect(find.text('100%'), findsNWidgets(2));
  });

  testWidgets('the menu clock comes from the rules table', (tester) async {
    await tester.pumpWidget(InkFightApp(settings: InkSettings()));
    await tester.pumpAndSettle();

    final totalSeconds = MatchRules.standard.roundMs ~/ 1000;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');

    expect(find.text('$minutes : $seconds'), findsOneWidget);
  });

  testWidgets('the menu does not overflow at 360x640', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(InkFightApp(settings: InkSettings()));
    await tester.pumpAndSettle();

    expect(find.text('Rotate your device'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the menu does not overflow at small landscape 640x360', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 360);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(InkFightApp(settings: InkSettings()));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the menu does not overflow at wide landscape 1600x720', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 720);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(InkFightApp(settings: InkSettings()));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('menu BOT FIGHT opens the difficulty picker', (tester) async {
    await tester.pumpWidget(InkFightApp(settings: InkSettings()));

    await tester.tap(find.text('BOT FIGHT'));
    await tester.pumpAndSettle();

    expect(find.byType(DifficultyScreen), findsOneWidget);
    expect(find.text('EASY'), findsOneWidget);
    expect(find.text('NORMAL'), findsOneWidget);
    expect(find.text('HARD'), findsOneWidget);
    expect(find.text('RECOMMENDED'), findsOneWidget);
    expect(find.byType(BotFightScreen), findsNothing, reason: 'not yet');
  });

  testWidgets('picking NORMAL opens the bot fight arena', (tester) async {
    await tester.pumpWidget(InkFightApp(settings: InkSettings()));
    await tester.tap(find.text('BOT FIGHT'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('NORMAL'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(BotFightScreen), findsOneWidget);
    // The one-time controls card greets a player entering the arena, and
    // GOT IT dismisses it for the rest of this screen's life.
    expect(find.text('GOT IT'), findsOneWidget);
    await tester.tap(find.text('GOT IT'));
    await tester.pump();
    expect(find.text('GOT IT'), findsNothing);
    expect(find.text('CRIMSON RIVAL'), findsOneWidget);
    // The card's copy names the buttons in one sentence, so the arena's own
    // labels stay unique finders.
    expect(find.text('PUNCH'), findsOneWidget);
    expect(find.text('KICK'), findsOneWidget);
  });

  testWidgets('picking HARD pushes the arena with HARD as its argument', (
    tester,
  ) async {
    final observer = _RouteRecorder();
    await tester.pumpWidget(_appWithObserver(observer));
    await tester.tap(find.text('BOT FIGHT'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('HARD'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(BotFightScreen), findsOneWidget);
    final arenaRoute = observer.pushed.last;
    expect(arenaRoute.settings.name, InkRoutes.botFight);
    expect(arenaRoute.settings.arguments, BotDifficulty.hard);
  });

  testWidgets('back from the picker returns to the menu', (tester) async {
    await tester.pumpWidget(InkFightApp(settings: InkSettings()));
    await tester.tap(find.text('BOT FIGHT'));
    await tester.pumpAndSettle();
    expect(find.byType(DifficultyScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(DifficultyScreen), findsNothing);
  });

  testWidgets('the READY badge also opens the picker', (tester) async {
    await tester.pumpWidget(InkFightApp(settings: InkSettings()));

    await tester.tap(find.text('BOT MODE READY'));
    await tester.pumpAndSettle();

    expect(find.byType(DifficultyScreen), findsOneWidget);
  });

  testWidgets('the difficulty deep link lands on the picker, back goes home', (
    tester,
  ) async {
    await pumpDeepLink(tester, InkRoutes.difficulty);
    await tester.pumpAndSettle();

    expect(find.byType(DifficultyScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.byType(DifficultyScreen), findsNothing);
    expect(find.text('DOODLE COMBAT'), findsOneWidget);
  });

  testWidgets('online mode explains that it is planned', (tester) async {
    await tester.pumpWidget(InkFightApp(settings: InkSettings()));

    await tester.tap(find.text('ONLINE 1V1'));
    await tester.pump();

    expect(
      find.text('Online 1v1 is coming after the bot fight slice.'),
      findsOneWidget,
    );
  });

  testWidgets('the menu opens settings through the named route', (
    tester,
  ) async {
    await tester.pumpWidget(InkFightApp(settings: InkSettings()));

    await tester.tap(find.text('SETTINGS'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('AUDIO / HAPTICS'), findsOneWidget);
    expect(find.text('SOUND'), findsOneWidget);
    expect(find.text('CREDITS'), findsOneWidget);
    expect(find.text('VERSION'), findsOneWidget);
    expect(find.text('DOODLE COMBAT'), findsNothing, reason: 'menu is covered');
  });

  testWidgets('the sound switch flips without leaving the screen', (
    tester,
  ) async {
    final settings = InkSettings();
    await tester.pumpWidget(InkFightApp(settings: settings));
    await tester.tap(find.text('SETTINGS'));
    await tester.pumpAndSettle();

    // SOUND and HAPTICS are both real switches now, so the text alone cannot
    // tell them apart: flip the sound row and ask the model.
    expect(settings.soundOn, isTrue);
    expect(find.text('ON'), findsNWidgets(2));
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(settings.soundOn, isFalse);
    expect(
      find.text('OFF'),
      findsOneWidget,
      reason: 'only the sound row flipped',
    );
    expect(find.text('ON'), findsOneWidget, reason: 'haptics still on');
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('back returns to the menu', (tester) async {
    await tester.pumpWidget(InkFightApp(settings: InkSettings()));
    await tester.tap(find.text('SETTINGS'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('DOODLE COMBAT'), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
  });

  testWidgets('the web deep link opens settings directly', (tester) async {
    await pumpDeepLink(tester, InkRoutes.settings);

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('DOODLE COMBAT'), findsNothing, reason: 'not the menu');
  });

  testWidgets('a deep link with nothing behind it can still get home', (
    tester,
  ) async {
    await pumpDeepLink(tester, InkRoutes.settings);

    // No menu below this route, so back falls through to a fresh menu rather
    // than popping into an empty navigator.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.text('DOODLE COMBAT'), findsOneWidget);
  });

  testWidgets('the arena deep link lands on the arena', (tester) async {
    await pumpDeepLink(tester, InkRoutes.botFight);
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(BotFightScreen), findsOneWidget);
  });

  testWidgets('QUIT TO MENU from the pause overlay lands back on the menu', (
    tester,
  ) async {
    await tester.pumpWidget(InkFightApp(settings: InkSettings()));
    await tester.tap(find.text('BOT FIGHT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NORMAL'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(BotFightScreen), findsOneWidget);

    await tester.tap(find.text('GOT IT'));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
    expect(find.text('PAUSED'), findsOneWidget);

    await tester.tap(find.text('QUIT TO MENU'));
    await tester.pumpAndSettle();

    // The one whole-screen chain: the menu is back, the arena is gone, and
    // the picker went with it.
    expect(find.byType(BotFightScreen), findsNothing);
    expect(find.byType(DifficultyScreen), findsNothing);
    expect(find.text('DOODLE COMBAT'), findsOneWidget);
  });

  testWidgets('LEAVE from the round-end card lands back on the menu', (
    tester,
  ) async {
    // The arena's sprites decode in real async, so the walk to the fight
    // happens inside `runAsync` — otherwise the game's `onLoad` is stranded
    // in the fake-async zone and the match never runs (the recipe the screen
    // tests use).
    late final InkFightBattleGame game;
    await tester.runAsync(() async {
      await tester.pumpWidget(InkFightApp(settings: InkSettings()));
      await tester.tap(find.text('BOT FIGHT'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('NORMAL'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      game =
          tester
                  .widget<GameWidget<FlameGame>>(
                    find.byWidgetPredicate((w) => w is GameWidget<FlameGame>),
                  )
                  .game!
              as InkFightBattleGame;
      await game.toBeLoaded();
      await game.ready();
    });
    await tester.pump();
    expect(find.byType(BotFightScreen), findsOneWidget);

    await tester.tap(find.text('GOT IT'));
    await tester.pump();

    // An idle player loses to the practice bot: run the match headlessly to
    // its decided card, exactly as the screen tests do.
    for (var i = 0; i < 4200 && !game.match.isFinished; i++) {
      game.update(1 / 60);
    }
    expect(game.match.isFinished, isTrue);
    await tester.pump();
    var guard = 0;
    while (!game.roundEndCardVisible && guard++ < 90) {
      await tester.pump(const Duration(milliseconds: 17));
    }
    expect(find.text('REMATCH'), findsOneWidget);

    await tester.tap(find.text('LEAVE'));
    await tester.pumpAndSettle();

    // LEAVE unwinds like QUIT TO MENU: the menu is back, and both the arena
    // and the picker it was opened from are gone.
    expect(find.byType(BotFightScreen), findsNothing);
    expect(find.byType(DifficultyScreen), findsNothing);
    expect(find.text('DOODLE COMBAT'), findsOneWidget);
  });

  test('the route names are the URLs the web build has to serve', () {
    expect(InkRoutes.home, '/');
    expect(InkRoutes.botFight, '/bot-fight');
    expect(InkRoutes.settings, '/settings');
  });
}
