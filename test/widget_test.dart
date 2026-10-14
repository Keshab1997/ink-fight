import 'package:flutter_test/flutter_test.dart';

import 'package:inkfight/main.dart';

void main() {
  testWidgets('shows the INK FIGHT landscape menu', (tester) async {
    await tester.pumpWidget(const InkFightApp());

    expect(find.text('INK\nFIGHT'), findsOneWidget);
    expect(find.text('Doodle Combat'), findsOneWidget);
    expect(find.text('BOT FIGHT'), findsOneWidget);
    expect(find.text('ONLINE 1V1'), findsOneWidget);
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
