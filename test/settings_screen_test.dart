import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inkfight/screens/settings_screen.dart';
import 'package:inkfight/state/ink_settings.dart';

/// The settings screen has no preference state of its own: the SOUND switch
/// reads and writes the injected [InkSettings], so leaving and coming back
/// shows what the model says — not what this mount of the screen remembered.
void main() {
  testWidgets('SOUND toggles through the model and outlives the screen', (
    tester,
  ) async {
    final settings = InkSettings();
    expect(settings.soundOn, isTrue, reason: 'sound is on by default');

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(settings: settings),
                ),
              ),
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(find.text('SOUND'), findsOneWidget);
    expect(find.text('ON'), findsOneWidget);

    // The flip writes the model, and the row re-reads it.
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(settings.soundOn, isFalse);
    expect(find.text('OFF'), findsOneWidget);

    // Leave, come back: a fresh mount of the screen still shows the model.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(find.text('OFF'), findsOneWidget);
    expect(
      tester.widget<Switch>(find.byType(Switch)).value,
      settings.soundOn,
      reason: 'the switch mirrors the model, not local memory',
    );

    // HAPTICS stays the static SOON row until the arena's flag exists.
    expect(find.text('HAPTICS'), findsOneWidget);
    expect(find.text('SOON'), findsOneWidget);
    expect(
      find.byType(Switch),
      findsOneWidget,
      reason: 'SOUND is the only control on this screen',
    );
  });
}
