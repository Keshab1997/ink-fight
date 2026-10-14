import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inkfight/main.dart';
import 'package:inkfight/screens/app_routes.dart';
import 'package:inkfight/screens/bot_fight_screen.dart';
import 'package:inkfight/screens/settings_screen.dart';

/// Puts the app on a given route the way the browser does: the platform's
/// default route name is what a web build reads out of the URL fragment
/// (`…/preview/main/#/settings` → `/settings`).
Future<void> pumpDeepLink(WidgetTester tester, String route) async {
  tester.binding.platformDispatcher.defaultRouteNameTestValue = route;
  addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
  await tester.pumpWidget(const InkFightApp());
}

void main() {
  testWidgets('shows the INK FIGHT landscape menu', (tester) async {
    await tester.pumpWidget(const InkFightApp());

    expect(find.text('INK FIGHT'), findsOneWidget);
    expect(find.text('DOODLE COMBAT'), findsOneWidget);
    expect(find.text('BOT FIGHT'), findsOneWidget);
    expect(find.text('ONLINE 1V1'), findsOneWidget);
    expect(find.text('SETTINGS'), findsOneWidget);
  });

  testWidgets('opens the first bot fight arena', (tester) async {
    await tester.pumpWidget(const InkFightApp());

    await tester.tap(find.text('BOT FIGHT'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('CRIMSON RIVAL'), findsOneWidget);
    expect(find.text('PUNCH'), findsOneWidget);
    expect(find.text('KICK'), findsOneWidget);
  });

  testWidgets('online mode explains that it is planned', (tester) async {
    await tester.pumpWidget(const InkFightApp());

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
    await tester.pumpWidget(const InkFightApp());

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
    await tester.pumpWidget(const InkFightApp());
    await tester.tap(find.text('SETTINGS'));
    await tester.pumpAndSettle();

    expect(find.text('ON'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('OFF'), findsOneWidget);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('back returns to the menu', (tester) async {
    await tester.pumpWidget(const InkFightApp());
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

  test('the route names are the URLs the web build has to serve', () {
    expect(InkRoutes.home, '/');
    expect(InkRoutes.botFight, '/bot-fight');
    expect(InkRoutes.settings, '/settings');
  });
}
