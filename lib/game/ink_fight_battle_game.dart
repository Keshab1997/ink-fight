import 'dart:async' as async;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';

import '../theme/app_theme.dart';

class InkFightBattleGame extends FlameGame {
  static const _playerIdlePath =
      'assets/characters/runtime/player_ink_fighter/idle/player_ink_fighter_idle_000.png';
  static const _playerIdleFrames = [
    _playerIdlePath,
    'assets/characters/runtime/player_ink_fighter/idle/player_ink_fighter_idle_001.png',
    'assets/characters/runtime/player_ink_fighter/idle/player_ink_fighter_idle_002.png',
    'assets/characters/runtime/player_ink_fighter/idle/player_ink_fighter_idle_003.png',
  ];
  static const _playerPunchPath =
      'assets/characters/runtime/player_ink_fighter/light_punch/player_ink_fighter_light_punch_002.png';
  static const _playerKickPath =
      'assets/characters/runtime/player_ink_fighter/heavy_kick/player_ink_fighter_heavy_kick_003.png';
  static const _playerBlockPath =
      'assets/characters/runtime/player_ink_fighter/block/player_ink_fighter_block_001.png';
  static const _playerJumpPath =
      'assets/characters/runtime/player_ink_fighter/jump/player_ink_fighter_jump_002.png';
  static const _rivalIdlePath =
      'assets/characters/runtime/bot_crimson_rival/idle/bot_crimson_rival_idle_000.png';
  static const _rivalIdleFrames = [
    _rivalIdlePath,
    'assets/characters/runtime/bot_crimson_rival/idle/bot_crimson_rival_idle_001.png',
    'assets/characters/runtime/bot_crimson_rival/idle/bot_crimson_rival_idle_002.png',
    'assets/characters/runtime/bot_crimson_rival/idle/bot_crimson_rival_idle_003.png',
  ];

  SpriteAnimationComponent? _player;
  SpriteAnimationComponent? _rival;
  SpriteAnimation? _playerIdle;
  SpriteAnimation? _playerPunch;
  SpriteAnimation? _playerKick;
  SpriteAnimation? _playerBlock;
  SpriteAnimation? _playerJump;
  bool _loaded = false;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    images.prefix = '';

    _playerIdle = await _loadAnimation(_playerIdleFrames, stepTime: .14);
    _playerPunch = await _loadAnimation(
      [_playerIdlePath, _playerPunchPath, _playerIdlePath],
      stepTime: .16,
      loop: false,
    );
    _playerKick = await _loadAnimation(
      [_playerIdlePath, _playerKickPath, _playerIdlePath],
      stepTime: .18,
      loop: false,
    );
    _playerBlock = await _loadAnimation(
      [_playerIdlePath, _playerBlockPath, _playerIdlePath],
      stepTime: .16,
      loop: false,
    );
    _playerJump = await _loadAnimation(
      [_playerIdlePath, _playerJumpPath, _playerIdlePath],
      stepTime: .18,
      loop: false,
    );

    final rivalIdle = await _loadAnimation(_rivalIdleFrames, stepTime: .14);

    // Flame requires an explicit size when autoResize is off; _layout()
    // below replaces this placeholder with the real arena dimensions.
    _player = SpriteAnimationComponent(
      animation: _playerIdle,
      size: Vector2.all(1),
      autoResize: false,
      anchor: Anchor.bottomCenter,
    );
    _rival = SpriteAnimationComponent(
      animation: rivalIdle,
      size: Vector2.all(1),
      autoResize: false,
      anchor: Anchor.bottomCenter,
    );

    // Frames are drawn facing right; the rival stands on the right, so
    // mirror him to face the player.
    _rival!.scale.x = -1;

    add(_rival!);
    add(_player!);
    _loaded = true;
    _layout(size);

    // The first playable slice keeps the rival idle until bot AI is connected.
    _rival!.animation = rivalIdle;
  }

  Future<SpriteAnimation> _loadAnimation(
    List<String> paths, {
    required double stepTime,
    bool loop = true,
  }) async {
    final sprites = <Sprite>[];
    for (final path in paths) {
      sprites.add(Sprite(await images.load(path)));
    }
    return SpriteAnimation.spriteList(sprites, stepTime: stepTime, loop: loop);
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
    // The runtime frames carry ~12% transparent padding under the feet, so
    // sink the anchor by that share to put the soles on the arena floor.
    final baseline = viewportSize.y * .80 + fighterSize * .121;

    _player!
      ..size = sizeVector
      ..position = Vector2(viewportSize.x * .29, baseline);
    _rival!
      ..size = sizeVector
      ..position = Vector2(viewportSize.x * .71, baseline);
  }

  void playPlayerAction(String action) {
    if (!_loaded) {
      return;
    }

    final animation = switch (action) {
      'light_punch' => _playerPunch,
      'heavy_kick' => _playerKick,
      'block' => _playerBlock,
      'jump' => _playerJump,
      _ => _playerIdle,
    };
    if (animation == null) {
      return;
    }

    _player!.animation = animation;
    final duration = switch (action) {
      'heavy_kick' => 860,
      'block' => 640,
      'jump' => 720,
      _ => 700,
    };
    async.Timer(Duration(milliseconds: duration), () {
      if (_player?.isMounted ?? false) {
        _player!.animation = _playerIdle;
      }
    });
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
