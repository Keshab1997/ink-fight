import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inkfight/screens/settings_screen.dart';
import 'package:inkfight/state/ink_settings.dart';

/// The settings screen has no preference state of its own: each switch reads
/// and writes the injected [InkSettings], so leaving the screen and coming
/// back shows what the model says — not what the previous mount remembered.
void main() {
  /// Mounts a route stack whose only job is to let the test open the settings
  /// screen, leave it, and open a fresh mount of it again.
  Future<void> pumpLauncher(WidgetTester tester, InkSettings settings) async {
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
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  }

  Future<void> leave(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
  }

  /// The switch in the row labelled [label] — row order is not this test's
  /// business, so the switch is found through the label's own row shell.
  Finder switchOf(String label) => find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
    matching: find.byType(Switch),
  );

  testWidgets('SOUND toggles through the model and outlives the screen', (
    tester,
  ) async {
    final settings = InkSettings();
    expect(settings.soundOn, isTrue, reason: 'sound is on by default');
    await pumpLauncher(tester, settings);
    await open(tester);

    expect(find.text('ON'), findsNWidgets(2), reason: 'both switches start on');

    await tester.tap(switchOf('SOUND'));
    await tester.pumpAndSettle();

    expect(settings.soundOn, isFalse);
    expect(
      settings.hapticsOn,
      isTrue,
      reason: 'the switches are independent settings',
    );
    expect(find.text('OFF'), findsOneWidget);

    // Leave, come back: a fresh mount of the screen still shows the model.
    await leave(tester);
    await open(tester);
    expect(
      tester.widget<Switch>(switchOf('SOUND')).value,
      isFalse,
      reason: 'a fresh mount shows the model, not local memory',
    );
  });

  testWidgets('HAPTICS toggles the model and outlives the screen', (
    tester,
  ) async {
    final settings = InkSettings();
    expect(settings.hapticsOn, isTrue, reason: 'haptics are on by default');
    await pumpLauncher(tester, settings);
    await open(tester);

    await tester.tap(switchOf('HAPTICS'));
    await tester.pumpAndSettle();

    expect(settings.hapticsOn, isFalse);
    expect(settings.soundOn, isTrue, reason: 'SOUND was not touched');
    expect(
      find.text('SOON'),
      findsNothing,
      reason: 'the row is a real control now, not a placeholder',
    );

    // The switch that reaches the arena must also survive a re-entry.
    await leave(tester);
    await open(tester);
    expect(
      tester.widget<Switch>(switchOf('HAPTICS')).value,
      isFalse,
      reason: 'a fresh mount shows the model, not local memory',
    );
    expect(
      tester.widget<Switch>(switchOf('SOUND')).value,
      isTrue,
      reason: 'SOUND still mirrors the model too',
    );
  });
}
