import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inkfight/game/ink_fight_battle_game.dart';

/// Headless smoke test for the asset-backed bot fight arena: the game must
/// load its runtime frames, mount both fighters, and react to every player
/// action. The widget overlay is covered by `widget_test.dart`; this file
/// covers the Flame game underneath it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<InkFightBattleGame> loadedGame() async {
    final game = InkFightBattleGame();
    game.onGameResize(Vector2(960, 540));
    await game.onLoad();
    return game;
  }

  List<SpriteAnimationComponent> fightersOf(InkFightBattleGame game) =>
      game.children.whereType<SpriteAnimationComponent>().toList();

  test('arena loads both fighters from the runtime frames', () async {
    final game = await loadedGame();
    final fighters = fightersOf(game);

    // Rival is added first, player second (see onLoad).
    expect(fighters, hasLength(2));
    final rival = fighters[0];
    final player = fighters[1];

    expect(player.animation, isNotNull);
    expect(rival.animation, isNotNull);
    // The idle cycle breathes over the four delivered frames.
    expect(player.animation!.frames, hasLength(4));
    expect(rival.animation!.frames, hasLength(4));

    // Rival is mirrored to face the player, who stands on the left.
    expect(rival.scale.x, -1);
    expect(player.scale.x, 1);
    expect(player.position.x, lessThan(rival.position.x));

    // Soles (frame content ends ~12% above the anchored image bottom) rest
    // on the arena floor line at 80% of the viewport height.
    expect(player.position.y - player.size.y * .121, closeTo(540 * .80, 1));
    expect(rival.position.y - rival.size.y * .121, closeTo(540 * .80, 1));
    expect(player.size.x, greaterThan(0));
  });

  test('every player action swaps in its own animation', () async {
    final game = await loadedGame();
    final player = fightersOf(game)[1];

    final idle = player.animation;
    final seen = <SpriteAnimation>{idle!};

    for (final action in ['light_punch', 'heavy_kick', 'block', 'jump']) {
      game.playPlayerAction(action);
      expect(
        player.animation,
        isNot(idle),
        reason: '$action should leave the idle animation',
      );
      seen.add(player.animation!);
      player.animation = idle; // reset for the next action
    }

    // Idle + four distinct action animations.
    expect(seen, hasLength(5));
  });

  test('unknown actions and pre-load calls are ignored safely', () async {
    final game = InkFightBattleGame();
    // Before onLoad nothing is mounted; the guard must swallow the call.
    game.playPlayerAction('light_punch');

    game.onGameResize(Vector2(960, 540));
    await game.onLoad();
    final player = game.children.whereType<SpriteAnimationComponent>().last;
    final idle = player.animation;
    game.playPlayerAction('taunt'); // not wired yet
    expect(player.animation, idle);
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
