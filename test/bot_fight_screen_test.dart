import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inkfight/game/bot/bot_strategy.dart';
import 'package:inkfight/game/ink_fight_battle_game.dart';
import 'package:inkfight/game/rules/match_rules.dart';
import 'package:inkfight/screens/bot_fight_screen.dart';

/// Screen-level coverage for the live HUD and the decided-match card.
/// The headless view/controller behaviour lives in `bot_fight_game_test.dart`.
void main() {
  testWidgets('a decided match shows the outcome card and rematch resets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 720);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    // Image decoding is real async, so the whole mount has to happen inside
    // `runAsync`: in a fake-async zone the game's `onLoad` never finishes
    // loading its frames and the widget never hands back a mounted game.
    //
    // Do not wait on `game.loaded` here - that is the *component* lifecycle
    // future, and it only completes once GameWidget's loader has mounted the
    // game. Awaiting it from the test zone waits forever. Flame's own hook for
    // exactly this situation is `toBeLoaded()` (see
    // flame/test/game/game_widget/game_widget_test.dart), and `ready()` then
    // flushes the component tree so both fighters exist before we tick.
    late final InkFightBattleGame game;
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: BotFightScreen()));
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

    // An idle player loses to the practice bot; simulate it headlessly.
    for (var i = 0; i < 4200 && !game.match.isFinished; i++) {
      game.update(1 / 60);
    }
    expect(game.match.isFinished, isTrue);
    await tester.pump();

    // The HUD reads the controller, not a placeholder.
    final health = game.match.stateOf(FighterId.player).health;
    expect(
      find.text('${(health / game.match.rules.health * 100).round()}%'),
      findsOneWidget,
    );
    expect(find.text('END'), findsOneWidget);

    // The knockout blow plays its cinema before the card may stamp in
    // (GAME_FEEL §5): 350 ms of slow motion, then a 250 ms frozen beat.
    expect(health, 0, reason: 'the normal bot finishes an idle player');
    expect(game.roundEndCardVisible, isFalse);
    expect(find.text('REMATCH'), findsNothing);
    var guard = 0;
    while (!game.roundEndCardVisible && guard++ < 90) {
      await tester.pump(const Duration(milliseconds: 17));
    }
    expect(game.roundEndCardVisible, isTrue);
    expect(guard, greaterThanOrEqualTo(35), reason: '~600 ms of cinema');

    expect(find.text('REMATCH'), findsOneWidget);
    expect(
      find.text(
        game.match.outcome == MatchOutcome.playerWin
            ? 'YOU WIN'
            : 'CRIMSON RIVAL WINS',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('REMATCH'));
    await tester.pump();
    expect(find.text('REMATCH'), findsNothing);
    expect(find.text('READY'), findsOneWidget);
    expect(find.text('100%'), findsNWidgets(2));
    expect(game.match.phase, MatchPhase.countdown);
    // A rematch drops the cinema with the rest of the feel state.
    expect(game.roundEndCardVisible, isFalse);
  });

  testWidgets('the chosen difficulty reaches the practice bot', (tester) async {
    tester.view.physicalSize = const Size(1600, 720);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    // Normal is the default the design document asks for (GDD §8).
    expect(const BotFightScreen().difficulty, BotDifficulty.normal);

    // Same mount recipe as the card test above: the frames decode in a real
    // async zone, and `toBeLoaded()` + `ready()` hand back a mounted game.
    late final InkFightBattleGame game;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const MaterialApp(home: BotFightScreen(difficulty: BotDifficulty.hard)),
      );
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

    expect(game.botProfile, BotProfile.hard);
  });
}
