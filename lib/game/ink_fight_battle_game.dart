import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'bot/bot_strategy.dart';
import 'rules/fighter_state.dart';
import 'rules/input_command.dart';
import 'rules/match_controller.dart';
import 'rules/match_rules.dart';

/// The arena view: a thin Flame layer over the deterministic [MatchController].
///
/// Nothing here decides what a hit does - the controller does (see
/// `rules/match_controller.dart`). This file only turns fighter states into
/// sprites: positions along the arena line, mirrored facings, the animation
/// that matches the current action, and the jump arc. Frames are discovered
/// from the asset manifest, so a new batch from the art pipeline is picked up
/// without touching this file.
class InkFightBattleGame extends FlameGame {
  InkFightBattleGame({BotProfile botProfile = BotProfile.easy})
    : _bot = BotController(profile: botProfile, fighter: FighterId.rival);

  /// The match this arena displays; read-only for HUD and tests.
  MatchController get match => _match;

  /// Bumped whenever a value the HUD shows actually changes, so the screen
  /// can listen instead of rebuilding every frame.
  final ValueNotifier<int> hudVersion = ValueNotifier(0);

  final MatchController _match = MatchController();
  final BotController _bot;
  int _playerSequence = 0;
  int _lastHudSnapshot = 0;

  SpriteAnimationComponent? _player;
  SpriteAnimationComponent? _rival;
  _FighterAnims? _playerAnims;
  _FighterAnims? _rivalAnims;
  double _baselineY = 0;
  bool _loaded = false;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    images.prefix = '';

    final frames = await _runtimeFrames();
    _playerAnims = await _buildAnims(frames, 'player_ink_fighter');
    _rivalAnims = await _buildAnims(frames, 'bot_crimson_rival');

    _player = SpriteAnimationComponent(
      animation: _playerAnims!.idle,
      // Flame requires an explicit size when autoResize is off; _layout()
      // below replaces this placeholder with the real arena dimensions.
      size: Vector2.all(1),
      autoResize: false,
      anchor: Anchor.bottomCenter,
    );
    _rival = SpriteAnimationComponent(
      animation: _rivalAnims!.idle,
      size: Vector2.all(1),
      autoResize: false,
      anchor: Anchor.bottomCenter,
    );

    add(_rival!);
    add(_player!);
    _loaded = true;
    _layout(size);
  }

  /// Every runtime frame, grouped by `character/action` and sorted, so the
  /// animation recipes below always see the whole delivered cycle.
  Future<Map<String, List<String>>> _runtimeFrames() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final byDir = <String, List<String>>{};
    for (final key in manifest.listAssets()) {
      if (!key.startsWith('assets/characters/runtime/')) {
        continue;
      }
      byDir
          .putIfAbsent(key.substring(0, key.lastIndexOf('/')), () => [])
          .add(key);
    }
    for (final cycle in byDir.values) {
      cycle.sort();
    }
    return byDir;
  }

  Future<_FighterAnims> _buildAnims(
    Map<String, List<String>> frames,
    String character,
  ) async {
    Future<SpriteAnimation> cycle(
      String action, {
      required double stepTime,
      bool loop = false,
      bool bookendIdle = false,
    }) async {
      final paths = frames['assets/characters/runtime/$character/$action'];
      if (paths == null || paths.isEmpty) {
        throw StateError('no runtime frames for $character/$action');
      }
      final idleFirst = [
        'assets/characters/runtime/$character/idle/'
            '${character}_idle_000.png',
      ];
      final sequence = [
        if (bookendIdle) ...idleFirst,
        ...paths,
        if (bookendIdle) ...idleFirst,
      ];
      final sprites = <Sprite>[];
      for (final path in sequence) {
        sprites.add(Sprite(await images.load(path)));
      }
      return SpriteAnimation.spriteList(
        sprites,
        stepTime: stepTime,
        loop: loop,
      );
    }

    return _FighterAnims(
      idle: await cycle('idle', stepTime: .14, loop: true),
      walk: await cycle('walk', stepTime: .09, loop: true),
      jump: await cycle('jump', stepTime: .1),
      lightPunch: await cycle('light_punch', stepTime: .09, bookendIdle: true),
      heavyKick: await cycle('heavy_kick', stepTime: .12, bookendIdle: true),
      block: await cycle('block', stepTime: .1, loop: true),
      hurt: await cycle('hurt', stepTime: .1),
      victory: await cycle('victory', stepTime: .12, loop: true),
      // The rival has no defeat cycle yet; the view falls back to hurt.
      defeat: frames.containsKey('assets/characters/runtime/$character/defeat')
          ? await cycle('defeat', stepTime: .12)
          : null,
    );
  }

  /// Winner poses, loser falls (or stings, until a defeat cycle exists).
  SpriteAnimation _endPose(_FighterAnims anims, FighterState state) {
    final outcome = _match.outcome;
    if (outcome == MatchOutcome.draw) {
      return anims.idle;
    }
    final playerWon = outcome == MatchOutcome.playerWin;
    final won = (state.id == FighterId.player) == playerWon;
    return won ? anims.victory : (anims.defeat ?? anims.hurt);
  }

  /// Touch intents, in the shape the online mode will send them later.
  void sendPlayerAction(InputAction action) {
    if (_match.isFinished) {
      return;
    }
    _match.submit(
      InputCommand(
        fighter: FighterId.player,
        action: action,
        sequence: ++_playerSequence,
      ),
    );
  }

  /// Held MOVE control: walk towards the rival while pressed.
  void setPlayerMoving(bool moving) {
    if (_match.isFinished) {
      return;
    }
    _match.setMoveAxis(FighterId.player, moving ? 1 : 0);
  }

  /// Back to the countdown with full health; the arena keeps its layout.
  void restartMatch() {
    _match.reset();
    _bot.reset();
    _playerSequence = 0;
    _syncFromMatch();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!_loaded) {
      return;
    }
    _bot.update(dt, _match);
    _match.tick(dt);
    _syncFromMatch();
  }

  void _syncFromMatch() {
    if (!_loaded || _player == null || _rival == null) {
      return;
    }
    final player = _match.stateOf(FighterId.player);
    final rival = _match.stateOf(FighterId.rival);
    _apply(_player!, _playerAnims!, player);
    _apply(_rival!, _rivalAnims!, rival);

    final snapshot = Object.hash(
      player.health,
      rival.health,
      _match.timeRemainingMs ~/ 1000,
      _match.phase,
      _match.outcome,
    );
    if (snapshot != _lastHudSnapshot) {
      _lastHudSnapshot = snapshot;
      hudVersion.value++;
    }
  }

  void _apply(
    SpriteAnimationComponent component,
    _FighterAnims anims,
    FighterState state,
  ) {
    component.position.x = state.x / _match.rules.arenaWidth * size.x;
    // Frames are drawn facing right; `facing` mirrors whoever stands right.
    component.scale.x = state.facing;

    if (_match.isFinished) {
      component.animation = _endPose(anims, state);
      component.position.y = _baselineY;
      return;
    }
    component.animation = anims.forAction(state.action);

    var y = _baselineY;
    if (state.isAirborne) {
      final progress = 1 - state.jumpRemainingMs / _match.rules.jumpMs;
      y -= math.sin(math.pi * progress.clamp(0, 1)) * component.size.y * .16;
    }
    component.position.y = y;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _layout(size);
  }

  void _layout(Vector2 viewportSize) {
    if (!_loaded || viewportSize.x <= 0 || viewportSize.y <= 0) {
      return;
    }

    final fighterSize = math.min(viewportSize.y * .74, viewportSize.x * .31);
    final sizeVector = Vector2.all(fighterSize);
    _player!.size = sizeVector;
    _rival!.size = sizeVector;
    // The runtime frames carry ~12% transparent padding under the feet, so
    // sink the anchor by that share to put the soles on the arena floor.
    _baselineY = viewportSize.y * .80 + fighterSize * .121;
    _syncFromMatch();
  }

  @override
  void render(ui.Canvas canvas) {
    final paper = ui.Paint()..color = InkColors.paper;
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, size.x, size.y), paper);

    final grid = ui.Paint()
      ..color = InkColors.line.withValues(alpha: .24)
      ..strokeWidth = 1;
    for (double x = 0; x < size.x; x += 48) {
      canvas.drawLine(ui.Offset(x, 0), ui.Offset(x, size.y), grid);
    }
    for (double y = 0; y < size.y; y += 48) {
      canvas.drawLine(ui.Offset(0, y), ui.Offset(size.x, y), grid);
    }

    final floor = size.y * .80;
    final arenaLine = ui.Paint()
      ..color = InkColors.ink.withValues(alpha: .16)
      ..strokeWidth = 1.4
      ..style = ui.PaintingStyle.stroke;
    canvas.drawLine(ui.Offset(0, floor), ui.Offset(size.x, floor), arenaLine);
    canvas.drawOval(
      ui.Rect.fromCenter(
        center: ui.Offset(size.x / 2, floor),
        width: size.x * .56,
        height: size.y * .18,
      ),
      arenaLine,
    );

    super.render(canvas);
  }
}

/// The seven animation cycles one fighter view needs.
class _FighterAnims {
  _FighterAnims({
    required this.idle,
    required this.walk,
    required this.jump,
    required this.lightPunch,
    required this.heavyKick,
    required this.block,
    required this.hurt,
    required this.victory,
    this.defeat,
  });

  final SpriteAnimation idle;
  final SpriteAnimation walk;
  final SpriteAnimation jump;
  final SpriteAnimation lightPunch;
  final SpriteAnimation heavyKick;
  final SpriteAnimation block;
  final SpriteAnimation hurt;
  final SpriteAnimation victory;
  final SpriteAnimation? defeat;

  SpriteAnimation forAction(FighterAction action) => switch (action) {
    FighterAction.idle => idle,
    FighterAction.walk => walk,
    FighterAction.jump => jump,
    FighterAction.lightPunch => lightPunch,
    FighterAction.heavyKick => heavyKick,
    FighterAction.block => block,
    FighterAction.hitstun || FighterAction.blockstun => hurt,
  };
}
