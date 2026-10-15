import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inkfight/game/bot/bot_strategy.dart';
import 'package:inkfight/game/ink_fight_battle_game.dart';
import 'package:inkfight/game/rules/input_command.dart';
import 'package:inkfight/game/rules/match_rules.dart';

/// How many frames the art pipeline actually SHIPPED for [fighter]'s [cycle].
///
/// The runtime manifest is the single source of truth (`tool/process_character_assets.py`
/// writes it). Read live on purpose: an in-between frame landing later must make the
/// motion smoother, never break a hard-coded count in this file. Cycles whose recipe
/// uses a sub-range of the delivered frames (block raise / release) are asserted in
/// `game_feel_test.dart`, where the expected count is part of the recipe contract.
Future<int> deliveredFrames(String fighter, String cycle) async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final prefix = 'assets/characters/runtime/$fighter/$cycle/';
  return manifest.listAssets().where((key) => key.startsWith(prefix)).length;
}

/// The fighter files as the pipeline names them, indexed like [fightersOf]:
/// the rival is [0], the player is [1].
const List<String> _kFighterFiles = <String>[
  'bot_crimson_rival',
  'player_ink_fighter',
];

/// Headless smoke test for the arena view over the deterministic match
/// controller: the view must place, mirror and animate fighters exactly as
/// the controller's states say. The widget overlay is covered by
/// `widget_test.dart`; the controller's own rules by `match_*_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<InkFightBattleGame> loadedGame({
    BotProfile? botProfile,
    MatchRules rules = const MatchRules(roundsToWin: 1),
  }) async {
    final game = InkFightBattleGame(
      rules: rules,
      botProfile: botProfile ?? BotProfile.easy,
    );
    game.onGameResize(Vector2(960, 540));
    await game.onLoad();
    return game;
  }

  List<SpriteAnimationComponent> fightersOf(InkFightBattleGame game) =>
      game.children.whereType<SpriteAnimationComponent>().toList();

  void tick(InkFightBattleGame game, int frames) {
    for (var i = 0; i < frames; i++) {
      game.update(1 / 60);
    }
  }

  /// Past the 2000 ms intro countdown, into live combat.
  void pastCountdown(InkFightBattleGame game) => tick(game, 130);

  test(
    'automatic round reset snaps both fighters idle and rematch clears score',
    () async {
      final game = await loadedGame(rules: const MatchRules(health: 6));
      final match = game.match;
      // Drive rules only so this smoke test has no bot or hit-stop timing.
      while (match.countdownRemainingMs > 0) {
        match.tick(.016);
      }
      match.setMoveAxis(FighterId.player, 1);
      while (match.distanceBetween(FighterId.player, FighterId.rival) > 40) {
        match.tick(.016);
      }
      match.setMoveAxis(FighterId.player, 0);
      game.update(.001);
      game.sendPlayerAction(InputAction.lightPunch);
      while (match.roundNumber == 1) {
        match.tick(.016);
      }
      game.update(.001);
      expect(match.roundNumber, 2);
      expect(match.playerRoundWins, 1);
      expect(match.drainHitEvents(), isEmpty, reason: 'game consumed the KO');
      expect(game.liveEffectCount, 0);
      expect(game.hitStopRemainingMs, 0);
      expect(game.stats.hitsLanded, 0);
      expect(match.phase, MatchPhase.countdown);
      expect(game.roundEndCardVisible, isFalse);
      final fighters = fightersOf(game);
      expect(fighters[1].position.x, lessThan(fighters[0].position.x));
      final positions = fighters.map((f) => f.position.x).toList();
      for (final fighter in fighters) {
        expect(
          fighter.animation!.loop,
          isTrue,
          reason: 'idle, not KO/end pose',
        );
        expect(fighter.animationTicker!.currentIndex, 0);
      }
      game.restartMatch();
      expect(match.roundNumber, 1);
      expect(match.playerRoundWins, 0);
      expect(match.rivalRoundWins, 0);
      expect(fighters.map((f) => f.position.x), orderedEquals(positions));
      expect(match.countdownRemainingMs, match.rules.countdownMs);
    },
  );

  test('arena loads both fighters at the controller start positions', () async {
    final game = await loadedGame();
    final fighters = fightersOf(game);
    expect(fighters, hasLength(2));
    final rival = fighters[0];
    final player = fighters[1];

    // startX 110 / arenaWidth 300, mapped onto the 960-wide viewport.
    expect(player.position.x, closeTo(110 / 300 * 960, 1));
    expect(rival.position.x, closeTo(190 / 300 * 960, 1));
    // Frames are drawn facing right; the controller mirrors the rival.
    expect(player.scale.x, 1);
    expect(rival.scale.x, -1);

    // Soles (frame content ends ~12% above the anchored image bottom) rest
    // on the arena floor line at 80% of the viewport height.
    expect(player.position.y - player.size.y * .121, closeTo(540 * .80, 1));
    expect(rival.position.y - rival.size.y * .121, closeTo(540 * .80, 1));
    // The idle cycle breathes over however many frames the art delivered —
    // one breath lasts 560 ms whether that is four keyframes or more.
    expect(
      player.animation!.frames,
      hasLength(await deliveredFrames(_kFighterFiles[1], 'idle')),
    );
  });

  test('holding MOVE walks the player on the delivered cycle', () async {
    // A passive bot keeps this test about walking, not about being punched.
    final game = await loadedGame(
      botProfile: const BotProfile(
        difficulty: BotDifficulty.easy,
        thinkIntervalMs: 60000,
        reactionMs: 60000,
        attackCooldownMs: 60000,
        blockChance: 0,
        heavyChance: 0,
        hesitationChance: 1,
        recoveryMs: 0,
        preferredGap: 90,
      ),
    );
    pastCountdown(game);
    final player = fightersOf(game)[1];
    final start = player.position.x;

    game.setPlayerMoving(true);
    tick(game, 20);
    expect(player.position.x, greaterThan(start));
    expect(
      player.animation!.frames,
      hasLength(await deliveredFrames(_kFighterFiles[1], 'walk')),
    ); // delivered walk cycle

    game.setPlayerMoving(false);
    tick(game, 2);
    expect(
      player.animation!.frames,
      hasLength(await deliveredFrames(_kFighterFiles[1], 'idle')),
    ); // back to idle
  });

  test(
    'a walked-in punch damages the rival and plays the hurt cycle',
    () async {
      final game = await loadedGame();
      pastCountdown(game);
      final rival = fightersOf(game)[0];

      game.setPlayerMoving(true);
      final jabReach = game.match.rules.lightAttack.reach;
      var landed = false;
      for (var i = 0; i < 400 && !landed; i++) {
        final player = game.match.stateOf(FighterId.player);
        final gap = (game.match.stateOf(FighterId.rival).x - player.x).abs();
        if (gap > jabReach * .9) {
          game.setPlayerMoving(true);
        } else {
          game.setPlayerMoving(false);
          if (player.canAct) {
            game.sendPlayerAction(InputAction.lightPunch);
          }
        }
        tick(game, 1);
        landed = game.match.stateOf(FighterId.rival).health < 100;
      }

      expect(landed, isTrue, reason: 'the light punch should connect');
      expect(
        rival.animation!.frames,
        hasLength(await deliveredFrames(_kFighterFiles[0], 'hurt')),
      ); // hurt cycle
    },
  );

  test('commands before load never crash the view', () async {
    final game = InkFightBattleGame();
    game.sendPlayerAction(InputAction.lightPunch);
    game.setPlayerMoving(true);
    game.update(1 / 60);
    expect(game.children.whereType<SpriteAnimationComponent>(), isEmpty);
  });

  test('every deployed runtime frame is a decodable image', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final frames =
        manifest
            .listAssets()
            .where((key) => key.startsWith('assets/characters/runtime/'))
            .toList()
          ..sort();

    expect(frames, isNotEmpty);
    for (final frame in frames) {
      final bytes = await rootBundle.load(frame);
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      expect(codec.frameCount, greaterThan(0), reason: frame);
      codec.dispose();
    }
  });
}
