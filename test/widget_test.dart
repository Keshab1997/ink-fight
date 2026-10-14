import 'package:flutter_test/flutter_test.dart';

import 'package:inkfight/main.dart';

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
}
