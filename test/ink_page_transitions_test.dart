import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inkfight/main.dart';
import 'package:inkfight/screens/difficulty_screen.dart';
import 'package:inkfight/state/ink_settings.dart';
import 'package:inkfight/theme/app_theme.dart';
import 'package:inkfight/widgets/ink_page_transitions.dart';

/// Runs the builder the way a pushed route does — detached route, stopped
/// clocks — on bare scaffolding, so the only transition in the tree is the
/// one the builder made and the test can read its type exactly.
Future<void> pumpTransition(
  WidgetTester tester, {
  required bool disableAnimations,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Theme(
        data: InkFightTheme.light,
        child: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Builder(
            builder: (context) =>
                const InkPageTransitionsBuilder().buildTransitions<void>(
                  MaterialPageRoute<void>(builder: (_) => const SizedBox()),
                  context,
                  const AlwaysStoppedAnimation<double>(0.5),
                  const AlwaysStoppedAnimation<double>(0),
                  const SizedBox(key: Key('page')),
                ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('reduced motion fades instead of wiping', (tester) async {
    await pumpTransition(tester, disableAnimations: true);

    expect(find.byType(FadeTransition), findsOneWidget);
    expect(find.byKey(const Key('page')), findsOneWidget);
  });

  testWidgets('motion wipes the page in from the right', (tester) async {
    await pumpTransition(tester, disableAnimations: false);

    expect(find.byType(InkWipeTransition), findsOneWidget);
    expect(find.byKey(const Key('page')), findsOneWidget);
  });

  test('the theme wires the wipe on every platform', () {
    final builders = InkFightTheme.light.pageTransitionsTheme.builders;

    for (final platform in TargetPlatform.values) {
      expect(
        builders[platform],
        isA<InkPageTransitionsBuilder>(),
        reason: platform.name,
      );
    }
  });

  testWidgets('menu to difficulty travels on the ink wipe', (tester) async {
    await tester.pumpWidget(InkFightApp(settings: InkSettings()));

    await tester.tap(find.text('BOT FIGHT'));
    // The push is built by the first frame; only then does the incoming
    // route's transition exist to be measured. The second pump puts the
    // clock 100 ms into the 300 ms route: mid-flight, neither end.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Both routes wear the wipe (the menu settles underneath while the
    // picker travels); the traveller is the one mid-flight.
    final wipes = tester.widgetList<InkWipeTransition>(
      find.byType(InkWipeTransition),
    );
    expect(wipes, isNotEmpty);
    expect(
      wipes.map((wipe) => wipe.progress.value),
      contains(inInclusiveRange(0.05, 0.9)),
    );

    await tester.pumpAndSettle();
    expect(find.byType(DifficultyScreen), findsOneWidget);
    expect(find.text('EASY'), findsOneWidget);
  });
}
