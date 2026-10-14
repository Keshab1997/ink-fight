import 'dart:async' as async;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';

import '../theme/app_theme.dart';

class InkFightBattleGame extends FlameGame {
  static const _playerIdlePath =
      'assets/characters/runtime/player_ink_fighter/idle/player_ink_fighter_idle_000.png';
  static const _playerPunchPath =
      'assets/characters/runtime/player_ink_fighter/light_punch/player_ink_fighter_light_punch_002.png';
  static const _playerKickPath =
      'assets/characters/runtime/player_ink_fighter/heavy_kick/player_ink_fighter_heavy_kick_003.png';
  static const _rivalIdlePath =
      'assets/characters/runtime/bot_crimson_rival/idle/bot_crimson_rival_idle_000.png';

  SpriteAnimationComponent? _player;
  SpriteAnimationComponent? _rival;
  SpriteAnimation? _playerIdle;
  SpriteAnimation? _playerPunch;
  SpriteAnimation? _playerKick;
  bool _loaded = false;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    images.prefix = '';

    _playerIdle = await _loadAnimation([_playerIdlePath], stepTime: 1);
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

    final rivalIdle = await _loadAnimation([_rivalIdlePath], stepTime: 1);

    _player = SpriteAnimationComponent(
      animation: _playerIdle,
      autoResize: false,
      anchor: Anchor.bottomCenter,
    );
    _rival = SpriteAnimationComponent(
      animation: rivalIdle,
      autoResize: false,
      anchor: Anchor.bottomCenter,
    );

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
    final baseline = viewportSize.y * .80;

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
      _ => _playerIdle,
    };
    if (animation == null) {
      return;
    }

    _player!.animation = animation;
    final duration = action == 'heavy_kick' ? 860 : 700;
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
