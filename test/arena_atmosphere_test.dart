import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkfight/game/bot/bot_strategy.dart';
import 'package:inkfight/game/effects/arena_atmosphere.dart';
import 'package:inkfight/game/effects/arena_footwork.dart';
import 'package:inkfight/game/effects/arena_ink_gravity.dart';
import 'package:inkfight/game/effects/arena_physical_paint.dart';
import 'package:inkfight/game/effects/arena_room.dart';
import 'package:inkfight/game/ink_fight_battle_game.dart';
import 'package:inkfight/game/rules/fighter_state.dart';
import 'package:inkfight/game/rules/input_command.dart';
import 'package:inkfight/game/rules/match_controller.dart';
import 'package:inkfight/game/rules/match_rules.dart';

const _viewport = ui.Size(960, 540);
const _height = 297.6;
const _floor = 432.0;

HitEvent hit({HitKind kind = HitKind.hit, bool heavy = false}) => HitEvent(
  attacker: FighterId.player,
  defender: FighterId.rival,
  kind: kind,
  heavy: heavy,
  x: 150,
  ko: false,
);

Future<ui.Image> raster(void Function(ui.Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(960, 540);
  picture.dispose();
  return image;
}

Future<Uint8List> pixels(void Function(ui.Canvas) draw) async {
  final image = await raster(draw);
  final bytes = (await image.toByteData())!.buffer.asUint8List();
  image.dispose();
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ArenaAtmosphere atmosphere() {
    final fx = ArenaAtmosphere();
    addTearDown(fx.dispose);
    return fx;
  }

  test(
    'paper fibres are identical after time, reset and resize roundtrip',
    () async {
      final fx = atmosphere();
      final before = await pixels((c) => fx.renderPaper(c, _viewport));
      expect(before.any((v) => v != 0), isTrue);
      fx.update(10);
      fx.reset();
      await pixels((c) => fx.renderPaper(c, const ui.Size(640, 360)));
      final after = await pixels((c) => fx.renderPaper(c, _viewport));
      expect(after, orderedEquals(before));
      fx.dispose();
      expect(
        await pixels((c) => fx.renderPaper(c, _viewport)),
        orderedEquals(before),
      );
      final another = atmosphere();
      expect(
        await pixels((c) => another.renderPaper(c, _viewport)),
        orderedEquals(before),
      );
    },
  );

  test('confirmed hits leave 2–4 dots; block one grey dot; whiff nothing', () {
    final fx = atmosphere();
    fx.onHit(hit(kind: HitKind.whiff), 300);
    expect(fx.markCount, 0);
    expect(fx.isFlashing(FighterId.rival), isFalse);
    fx.onHit(hit(kind: HitKind.blocked), 300);
    expect(fx.markCount, 1);
    expect(fx.markOpacities.single, .28);
    expect(fx.isFlashing(FighterId.rival), isFalse);
    fx.reset();
    fx.onHit(hit(), 300);
    expect(fx.markCount, inInclusiveRange(2, 4));
    expect(fx.isFlashing(FighterId.rival), isTrue);
    expect(fx.isFlashing(FighterId.player), isFalse);
  });

  test('stains persist all round, oldest fade under pressure, hard cap 24', () {
    final fx = atmosphere();
    fx.onHit(hit(), 300);
    final count = fx.markCount;
    fx.update(120);
    expect(fx.markCount, count);
    expect(fx.markOpacities.every((a) => a == .48), isTrue);
    while (fx.markCount <= 20) {
      fx.onHit(hit(heavy: true), 300);
    }
    final crowded = fx.markCount;
    fx.update(.2);
    expect(fx.markOpacities.first, closeTo(.24, .001));
    expect(fx.markOpacities.last, .48);
    fx.update(.21);
    expect(fx.markCount, lessThan(crowded));
    for (var i = 0; i < 100; i++) {
      fx.onHit(hit(), 300);
      expect(fx.markCount, lessThanOrEqualTo(ArenaAtmosphere.maxMarks));
    }
    fx.reset();
    expect(fx.markCount, 0);
    expect(fx.isFlashing(FighterId.rival), isFalse);
  });

  test('flash lasts 60 real ms; filters restore even if render throws', () {
    final fx = atmosphere();
    final player = SpriteAnimationComponent(size: Vector2.all(100));
    final rival = SpriteAnimationComponent(size: Vector2.all(100));
    const original = ui.ColorFilter.mode(
      ui.Color(0xFFC51F3A),
      ui.BlendMode.modulate,
    );
    rival.paint.colorFilter = original;
    fx.onHit(hit(), 300);
    fx.update(.05);
    expect(fx.isFlashing(FighterId.rival), isTrue);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    expect(
      () => fx.renderFighters(
        canvas,
        (_) {
          expect(player.paint.colorFilter, isNull);
          expect(
            rival.paint.colorFilter,
            const ui.ColorFilter.mode(ui.Color(0xFFFFFFFF), ui.BlendMode.srcIn),
          );
          throw StateError('render failure');
        },
        player,
        rival,
      ),
      throwsStateError,
    );
    expect(rival.paint.colorFilter, original);
    expect(player.paint.colorFilter, isNull);
    fx.update(.011);
    expect(fx.isFlashing(FighterId.rival), isFalse);
    fx.renderFighters(
      canvas,
      (_) => expect(rival.paint.colorFilter, original),
      player,
      rival,
    );
    recorder.endRecording().dispose();
  });

  test('white filter preserves sprite alpha, not a white rectangle', () async {
    final source = await raster(
      (c) => c.drawRect(
        const ui.Rect.fromLTWH(0, 0, 20, 20),
        ui.Paint()..color = const ui.Color(0xFF101010),
      ),
    );
    addTearDown(source.dispose);
    final sprite = SpriteAnimationComponent(
      animation: SpriteAnimation.spriteList([Sprite(source)], stepTime: 1),
      size: Vector2(960, 540),
    );
    final fx = atmosphere();
    fx.onHit(hit(), 300);
    final bytes = await pixels(
      (c) => fx.renderFighters(c, sprite.render, null, sprite),
    );
    expect(bytes.sublist((10 * 960 + 10) * 4, (10 * 960 + 10) * 4 + 4), [
      255,
      255,
      255,
      255,
    ]);
    expect(bytes[(100 * 960 + 100) * 4 + 3], 0);
    expect(sprite.paint.colorFilter, isNull);
  });

  test(
    'heavy streaks read exact active boundaries and obey .15h budget',
    () async {
      final fx = atmosphere();
      const rules = MatchRules.standard;
      final sprite = SpriteAnimationComponent(size: Vector2.all(_height))
        ..position = Vector2(480, _floor + _height * .121);
      const state = FighterState(
        id: FighterId.player,
        x: 150,
        health: 100,
        facing: 1,
        action: FighterAction.heavyKick,
      );
      final start = rules.heavyAttack.startupMs;
      final end = start + rules.heavyAttack.activeMs;
      for (final ms in [start - 1, start, end - 1, end]) {
        expect(
          fx.hasHeavyStreaks(state.copyWith(actionElapsedMs: ms), rules),
          ms >= start && ms < end,
        );
      }
      expect(
        fx.hasHeavyStreaks(
          state.copyWith(
            action: FighterAction.lightPunch,
            actionElapsedMs: start,
          ),
          rules,
        ),
        isFalse,
      );
      for (final facing in [-1.0, 1.0]) {
        final active = state.copyWith(actionElapsedMs: start, facing: facing);
        final bytes = await pixels(
          (c) => fx.renderHeavyStreaks(c, active, rules, sprite),
        );
        final cx = sprite.position.x + facing * _height * .39;
        final cy = _floor - _height * .50;
        var drawn = 0;
        for (var y = 0; y < 540; y++) {
          for (var x = 0; x < 960; x++) {
            if (bytes[(y * 960 + x) * 4 + 3] == 0) continue;
            drawn++;
            expect((x - cx).abs(), lessThan(_height * .15));
            expect((y - cy).abs(), lessThan(_height * .15));
            expect(y, greaterThan(150)); // well below the HUD
          }
        }
        expect(drawn, greaterThan(0));
      }
    },
  );

  test(
    'floor dots stay near contact, below fighters, and resize with the page',
    () async {
      final fx = atmosphere();
      fx.onHit(hit(kind: HitKind.blocked), 300);
      final bytes = await pixels(
        (c) => fx.renderFloor(c, _viewport, _floor, _height),
      );
      var drawn = 0;
      for (var y = 0; y < 540; y++) {
        for (var x = 0; x < 960; x++) {
          final offset = (y * 960 + x) * 4;
          if (bytes[offset + 3] == 0) continue;
          drawn++;
          expect((x - 480).abs(), lessThan(_height * .15));
          expect((y - _floor).abs(), lessThan(_height * .15));
          expect(bytes[offset], bytes[offset + 1]);
          expect(bytes[offset + 1], bytes[offset + 2]);
        }
      }
      expect(drawn, greaterThan(0));
      fx.update(90);
      expect(
        await pixels((c) => fx.renderFloor(c, _viewport, _floor, _height)),
        orderedEquals(bytes),
      );
      final small = await pixels(
        (c) => fx.renderFloor(c, const ui.Size(480, 270), 216, _height / 2),
      );
      expect(small.any((v) => v != 0), isTrue);
    },
  );

  test('arena hooks stain confirmed contact, persist through freeze, reset on rematch', () async {
    const passive = BotProfile(
      difficulty: BotDifficulty.easy,
      thinkIntervalMs: 60000,
      reactionMs: 60000,
      attackCooldownMs: 60000,
      blockChance: 0,
      heavyChance: 0,
      hesitationChance: 1,
      recoveryMs: 0,
      preferredGap: 90,
    );
    final game = InkFightBattleGame(botProfile: passive);
    game.onGameResize(Vector2(960, 540));
    await game.onLoad();
    // Mount Flame's queued children before rendering; no app build is needed.
    await game.ready();
    for (var i = 0; i < 130; i++) {
      game.update(1 / 60);
    }
    final before = await pixels(game.render);
    game.setPlayerMoving(true);
    for (var i = 0; i < 25; i++) {
      game.update(1 / 60);
    }
    game.setPlayerMoving(false);
    game.sendPlayerAction(InputAction.heavyKick);
    var landed = false;
    for (var i = 0; i < 60; i++) {
      game.update(1 / 60);
      if (game.match.rival.health < 100) {
        landed = true;
        break;
      }
    }
    expect(landed, isTrue);
    final directory = Directory('.agent-screens')..createSync(recursive: true);
    Future<void> capture(String name) async {
      final image = await raster(game.render);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('${directory.path}/$name.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
      image.dispose();
    }

    await capture('arena-hit-flash');
    final clock = game.match.timeRemainingMs;
    for (var i = 0; i < 4; i++) {
      game.update(1 / 60);
    }
    expect(game.match.timeRemainingMs, clock);
    await capture('arena-stains');
    for (var i = 0; i < 45; i++) {
      game.update(1 / 60);
    }
    await capture('arena-lasting-ink');
    final after = await pixels(game.render);
    // Restrict comparison to the floor band: bursts and silhouettes are not
    // allowed to masquerade as the lasting ink this test is looking for.
    final start = 438 * 960 * 4;
    final end = 446 * 960 * 4;
    expect(
      after.sublist(start, end),
      isNot(orderedEquals(before.sublist(start, end))),
    );
    game.restartMatch();
    await capture('arena-reset');
    final reset = await pixels(game.render);
    expect(
      reset.sublist(start, end),
      orderedEquals(before.sublist(start, end)),
    );
    expect(game.match.rival.health, 100);
  });

  group('physical arena paint', () {
    const playerState = FighterState(
      id: FighterId.player,
      x: 110,
      health: 100,
      facing: 1,
    );
    const rivalState = FighterState(
      id: FighterId.rival,
      x: 190,
      health: 100,
      facing: -1,
    );

    ArenaPhysicalPaint physical() =>
        ArenaPhysicalPaint()..layout(_viewport, _floor, _height);

    void sync(
      ArenaPhysicalPaint paint, {
      bool slowMo = false,
      double fall = 0,
      double beat = 0,
    }) {
      paint.syncWorld(
        player: playerState,
        rival: rivalState,
        koSlowMo: slowMo,
        koFallProgress: fall,
        koSlowMoProgress: beat,
      );
    }

    SpriteAnimationComponent standing(double x) =>
        SpriteAnimationComponent(size: Vector2.all(_height))
          ..position = Vector2(x, _floor + _height * .121);

    test('both shadows follow x, stay grounded, shrink/fade at apex, snap on landing', () {
      final paint = physical();
      final player = standing(352);
      final rival = standing(608);
      for (final pair in [
        (FighterId.player, player),
        (FighterId.rival, rival),
      ]) {
        final grounded = paint.shadowFor(pair.$1, pair.$2);
        expect(grounded.bounds.center, ui.Offset(pair.$2.position.x, _floor));
        expect(grounded.bounds.width / 2, lessThan(_height * .15));
        expect(grounded.opacity, closeTo(.20, .001));
        pair.$2.position.y -= _height * .16;
        final apex = paint.shadowFor(pair.$1, pair.$2);
        expect(apex.bounds.center.dy, _floor);
        expect(apex.bounds.width, closeTo(grounded.bounds.width * .55, .001));
        expect(apex.opacity, closeTo(grounded.opacity * .3, .001));
        pair.$2.position.y += _height * .16;
        pair.$2.scale.y = .94; // landing squash must not make a hovering shadow
        expect(paint.shadowFor(pair.$1, pair.$2), grounded);
        pair.$2.position.x += 70;
        expect(
          paint.shadowFor(pair.$1, pair.$2).bounds.center.dx,
          pair.$2.position.x,
        );
      }
    });

    test('only KO losers fade their shadows, reset restores both, timeout never fades', () {
      final paint = physical();
      final player = standing(352);
      final rival = standing(608);
      sync(paint, fall: 1); // a phase/progress value alone must not invent a KO
      expect(paint.shadowFor(FighterId.rival, rival).opacity, .20);
      paint.onHit(
        const HitEvent(
          attacker: FighterId.player,
          defender: FighterId.rival,
          kind: HitKind.hit,
          heavy: true,
          x: 150,
          ko: true,
        ),
        300,
      );
      sync(paint, slowMo: true, fall: .5, beat: .5);
      expect(paint.shadowFor(FighterId.rival, rival).opacity, .10);
      expect(paint.shadowFor(FighterId.player, player).opacity, .20);
      sync(paint, fall: 1, beat: 1);
      expect(paint.shadowFor(FighterId.rival, rival).opacity, 0);
      paint.reset();
      expect(paint.koCount, 0);
      expect(paint.ringCount, 0);
      expect(paint.shadowFor(FighterId.rival, rival).opacity, .20);
    });

    test('contact rings expand at contact, bounded 40/80 px, expire at 150 real ms', () async {
      for (final event in [
        hit(),
        hit(heavy: true),
        hit(kind: HitKind.blocked),
      ]) {
        final paint = physical();
        paint.onHit(event, 300);
        expect(paint.ringCount, 1);
        final early = await pixels(
          (c) => paint.renderBehindFighters(c, null, null),
        );
        paint.update(.13); // a held hit-stop pose does not stop this clock
        final late = await pixels(
          (c) => paint.renderBehindFighters(c, null, null),
        );
        ({int minX, int maxX, int minY, int maxY}) bounds(Uint8List data) {
          var minX = 960, maxX = -1, minY = 540, maxY = -1;
          for (var y = 0; y < 540; y++) {
            for (var x = 0; x < 960; x++) {
              if (data[(y * 960 + x) * 4 + 3] == 0) continue;
              if (x < minX) minX = x;
              if (x > maxX) maxX = x;
              if (y < minY) minY = y;
              if (y > maxY) maxY = y;
            }
          }
          return (minX: minX, maxX: maxX, minY: minY, maxY: maxY);
        }

        final a = bounds(early), b = bounds(late);
        expect(b.maxX - b.minX, greaterThan(a.maxX - a.minX));
        expect((b.minX - 480).abs(), lessThan(_height * .15));
        expect(
          (b.maxY - (_floor - _height * .43)).abs(),
          lessThan(_height * .15),
        );
        final diameter = event.kind == HitKind.blocked
            ? 24
            : event.heavy
            ? 80
            : 40;
        expect(b.maxX - b.minX, lessThanOrEqualTo(diameter + 2));
        paint.update(.021);
        expect(paint.ringCount, 0);
        expect(
          (await pixels((c) => paint.renderBehindFighters(c, null, null)))
              .every((v) => v == 0),
          isTrue,
        );
      }
      final paint = physical();
      paint.onHit(hit(kind: HitKind.whiff), 300);
      expect(paint.ringCount, 0);
      for (var i = 0; i < 100; i++) {
        paint.onHit(hit(), 300);
      }
      expect(paint.ringCount, lessThanOrEqualTo(8));
    });

    test('KO floor starts at defender x, stays in .15h budget, paints only in slow-mo', () async {
      final paint = physical();
      paint.onHit(
        const HitEvent(
          attacker: FighterId.player,
          defender: FighterId.rival,
          kind: HitKind.hit,
          heavy: true,
          x: 150,
          ko: true,
        ),
        300,
      );
      paint.update(.151); // discard contact ring to isolate KO floor paint
      sync(paint, slowMo: true, fall: .1, beat: .5);
      expect(paint.koCount, 1);
      final bytes = await pixels(
        (c) => paint.renderBehindFighters(c, null, null),
      );
      var count = 0;
      for (var y = 0; y < 540; y++) {
        for (var x = 0; x < 960; x++) {
          final p = (y * 960 + x) * 4;
          if (bytes[p + 3] == 0) continue;
          count++;
          expect((x - 190 / 300 * 960).abs(), lessThan(_height * .15));
          expect((y - _floor).abs(), lessThan(_height * .15));
          expect(bytes[p], bytes[p + 1]);
          expect(bytes[p + 1], bytes[p + 2]);
        }
      }
      expect(count, greaterThan(0));
      sync(
        paint,
        fall: .15,
        beat: 1,
      ); // freeze/result: no floor paint or radial streaks
      expect(
        (await pixels((c) => paint.renderBehindFighters(c, null, null)))
            .every((v) => v == 0),
        isTrue,
      );
      paint.reset();
      sync(paint, slowMo: true);
      expect(
        (await pixels((c) => paint.renderBehindFighters(c, null, null)))
            .every((v) => v == 0),
        isTrue,
      );
    });

    test(
      'paint behind fighters cannot overwrite their opaque sprite pixels',
      () async {
        final fx = atmosphere();
        final recorder = ui.PictureRecorder();
        fx.renderFloor(ui.Canvas(recorder), _viewport, _floor, _height);
        recorder.endRecording().dispose();
        final source = await raster(
          (c) => c.drawRect(
            const ui.Rect.fromLTWH(0, 0, 960, 540),
            ui.Paint()..color = const ui.Color(0xFF101010),
          ),
        );
        addTearDown(source.dispose);
        final sprite = SpriteAnimationComponent(
          animation: SpriteAnimation.spriteList([Sprite(source)], stepTime: 1),
          size: Vector2(960, 540),
        );
        fx.onHit(
          hit(kind: HitKind.blocked),
          300,
        ); // ring but no silhouette flash
        final bytes = await pixels(
          (c) => fx.renderFighters(c, sprite.render, sprite, null),
        );
        expect(
          bytes.asMap().entries.every(
            (entry) => entry.value == (entry.key % 4 == 3 ? 255 : 16),
          ),
          isTrue,
        );
      },
    );

    test('actual arena jump and KO render grounding and cinematic without changing clocks', () async {
      final game = InkFightBattleGame();
      game.hapticsEnabled = false;
      game.onGameResize(Vector2(960, 540));
      await game.onLoad();
      await game.ready();
      final directory = Directory('.agent-screens')
        ..createSync(recursive: true);
      Future<void> capture(String name) async {
        final image = await raster(game.render);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('${directory.path}/$name.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      }

      for (var i = 0; i < 130; i++) {
        game.update(1 / 60);
      }
      await capture('ground-shadows');
      game.sendPlayerAction(InputAction.jump);
      for (var i = 0; i < 20; i++) {
        game.update(1 / 60);
      }
      expect(game.match.player.isAirborne, isTrue);
      await capture('ground-shadow-apex');
      for (var i = 0; i < 4200 && !game.match.isFinished; i++) {
        game.update(1 / 60);
      }
      expect(game.match.isFinished, isTrue);
      expect(game.match.player.health, 0);
      expect(game.roundEndCardVisible, isFalse);
      for (var i = 0; i < 8; i++) {
        game.update(1 / 60);
      }
      await capture('ko-floor-slowmo');
      expect(game.roundEndCardVisible, isFalse);
      for (var i = 0; i < 15; i++) {
        game.update(1 / 60);
      }
      await capture('ko-floor-freeze');
      expect(game.roundEndCardVisible, isFalse);
      for (var i = 0; i < 70; i++) {
        game.update(1 / 60);
      }
      expect(game.roundEndCardVisible, isTrue);
      await capture('ko-floor-settled');
      game.restartMatch();
      expect(game.match.player.health, 100);
      await capture('ground-shadows-rematch');
    });
  });

  group('room physics (paint only)', () {
    const player = FighterState(
      id: FighterId.player,
      x: 110,
      health: 100,
      facing: 1,
    );
    const rival = FighterState(
      id: FighterId.rival,
      x: 190,
      health: 100,
      facing: -1,
    );
    const rules = MatchRules.standard;

    test('eight deterministic specks move at one quarter speed in KO and freeze on hold', () {
      final normal = ArenaRoom(), slow = ArenaRoom();
      final initial = normal.dustPositions;
      expect(initial, hasLength(8));
      expect(slow.dustPositions, initial);
      normal.advanceAir(realDt: .2, effectDt: .2, roundEnd: false);
      slow.advanceAir(realDt: .2, effectDt: .05, roundEnd: false);
      for (var i = 0; i < 8; i++) {
        final normalDelta = normal.dustPositions[i] - initial[i];
        final slowDelta = slow.dustPositions[i] - initial[i];
        expect(slowDelta.dx, closeTo(normalDelta.dx * .25, 1e-10));
        expect(slowDelta.dy, closeTo(normalDelta.dy * .25, 1e-10));
      }
      final held = slow.dustPositions;
      slow.advanceAir(realDt: .2, effectDt: 0, roundEnd: false);
      expect(slow.dustPositions, held);
      slow.reset();
      expect(slow.dustPositions, initial);
    });

    test(
      'round-end dust settles toward floor and horizontal drift damps away',
      () {
        final room = ArenaRoom();
        final initial = room.dustPositions;
        room.advanceAir(realDt: .2, effectDt: .2, roundEnd: true);
        final first = room.dustPositions;
        for (var i = 0; i < 8; i++) {
          expect(first[i].dy, greaterThan(initial[i].dy));
        }
        for (var i = 0; i < 30; i++) {
          room.advanceAir(realDt: .1, effectDt: .1, roundEnd: true);
        }
        final settled = room.dustPositions;
        room.advanceAir(realDt: .2, effectDt: .2, roundEnd: true);
        for (var i = 0; i < 8; i++) {
          expect(room.dustPositions[i].dy, 1);
          expect(
            (room.dustPositions[i].dx - settled[i].dx).abs(),
            lessThan(1e-6),
          );
        }
      },
    );

    test('only a confirmed heavy hit accelerates air, exactly 200 ms then normal drift', () {
      final normal = ArenaRoom(), gust = ArenaRoom();
      gust.onHit(hit(heavy: true, kind: HitKind.blocked));
      gust.onHit(hit(heavy: true, kind: HitKind.whiff));
      normal.advanceAir(realDt: .1, effectDt: .1, roundEnd: false);
      gust.advanceAir(realDt: .1, effectDt: .1, roundEnd: false);
      expect(gust.dustPositions, normal.dustPositions);
      final baseline = normal.dustPositions;
      gust.onHit(hit(heavy: true));
      normal.advanceAir(realDt: .2, effectDt: .2, roundEnd: false);
      gust.advanceAir(realDt: .2, effectDt: .2, roundEnd: false);
      for (var i = 0; i < 8; i++) {
        expect(
          gust.dustPositions[i].dx - baseline[i].dx,
          closeTo((normal.dustPositions[i].dx - baseline[i].dx) * 2.8, 1e-10),
        );
      }
      final beforeNormal = normal.dustPositions,
          beforeGust = gust.dustPositions;
      normal.advanceAir(realDt: .1, effectDt: .1, roundEnd: false);
      gust.advanceAir(realDt: .1, effectDt: .1, roundEnd: false);
      for (var i = 0; i < 8; i++) {
        expect(
          gust.dustPositions[i].dx - beforeGust[i].dx,
          closeTo(normal.dustPositions[i].dx - beforeNormal[i].dx, 1e-10),
        );
      }
    });

    test(
      'wall shove triggers once at either boundary, not for walking or reset',
      () {
        final room = ArenaRoom();
        final events = <FighterId>[];
        void observe(FighterState p, FighterState r) =>
            room.observeWalls(p, r, rules, (s) => events.add(s.id));
        observe(player, rival);
        observe(
          player.copyWith(x: rules.minX),
          rival,
        ); // walking contact: no shove
        expect(events, isEmpty);
        final p = player.copyWith(
          x: rules.minX,
          action: FighterAction.hitstun,
          pushVelocity: -40,
        );
        final r = rival.copyWith(
          x: rules.maxX,
          action: FighterAction.blockstun,
          pushVelocity: 20,
        );
        observe(p, r);
        expect(events, [FighterId.player, FighterId.rival]);
        for (var i = 0; i < 10; i++) {
          observe(p, r);
        }
        expect(events, hasLength(2));
        room.updateClocks(.01);
        expect(room.shakeOffset(_height).abs(), inExclusiveRange(0, .7));
        room.updateClocks(.12);
        expect(room.shakeOffset(_height), 0);
        observe(player, rival);
        observe(p, rival);
        expect(events, hasLength(3));
        room.reset();
        observe(p, r); // a load/reset snapshot must not invent an arrival
        expect(events, hasLength(3));
        expect(room.shakeOffset(_height), 0);
        expect(p.x, rules.minX);
        expect(p.pushVelocity, -40); // original immutable state was not edited
      },
    );

    test('boundary scuff reuses capped residue, fades in 450 ms and clears on reset', () {
      final fx = atmosphere();
      void advance(FighterState p) => fx.advanceRoom(
        realDt: .016,
        effectDt: .016,
        roundEnd: false,
        player: p,
        rival: rival,
        rules: rules,
      );
      advance(player);
      final wall = player.copyWith(
        x: rules.minX,
        pushVelocity: -40,
        action: FighterAction.hitstun,
      );
      advance(wall);
      expect(fx.markCount, 1);
      final dots = fx.markOpacities;
      fx.update(.225);
      expect(fx.markOpacities.single, closeTo(dots.single * .5, .001));
      fx.update(.226);
      expect(fx.markCount, 0);
      advance(wall); // no per-frame repeated contact
      expect(fx.markCount, 0);
      for (var i = 0; i < 100; i++) {
        advance(player);
        advance(wall);
      }
      expect(fx.markCount, 24);
      fx.reset();
      expect(fx.markCount, 0);
    });

    test('depth and dust stay monochrome and below HUD; rendering never advances dust', () async {
      final room = ArenaRoom();
      final before = room.dustPositions;
      final bytes = await pixels((c) {
        room.renderDepth(c, _viewport, _floor, _height);
        room.renderDust(c, _viewport, _floor, _height);
      });
      expect(room.dustPositions, before);
      final repeat = await pixels((c) {
        room.renderDepth(c, _viewport, _floor, _height);
        room.renderDust(c, _viewport, _floor, _height);
      });
      expect(repeat, orderedEquals(bytes));
      var count = 0;
      for (var y = 0; y < 540; y++) {
        for (var x = 0; x < 960; x++) {
          final offset = (y * 960 + x) * 4;
          if (bytes[offset + 3] == 0) continue;
          count++;
          expect(y, greaterThanOrEqualTo((_viewport.height * .28).floor()));
          expect(y, lessThan(_floor + _height * .15));
          expect(bytes[offset], bytes[offset + 1]);
          expect(bytes[offset + 1], bytes[offset + 2]);
        }
      }
      expect(count, greaterThan(0));
    });
  });

  group('the floor remembers footwork', () {
    const player = FighterState(
      id: FighterId.player,
      x: 110,
      health: 100,
      facing: 1,
    );
    const rival = FighterState(
      id: FighterId.rival,
      x: 190,
      health: 100,
      facing: -1,
    );

    Future<SpriteAnimationComponent> sole() async {
      final image = await raster(
        (c) => c.drawRect(
          const ui.Rect.fromLTWH(60, 10, 80, 185),
          ui.Paint()..color = const ui.Color(0xFFFFFFFF),
        ),
      );
      addTearDown(image.dispose);
      final sprite = Sprite(image, srcSize: Vector2.all(200));
      return SpriteAnimationComponent(
        size: Vector2.all(_height),
        anchor: Anchor.bottomCenter,
        animation: SpriteAnimation.spriteList(
          List.filled(8, sprite),
          stepTime: .1,
          loop: true,
        ),
      )..position = Vector2(480, _floor + _height * .121);
    }

    void observe(
      ArenaAtmosphere fx,
      SpriteAnimationComponent sprite,
      FighterState state, {
      double dt = .016,
    }) {
      fx.advanceRoom(
        realDt: dt,
        effectDt: dt,
        roundEnd: false,
        player: state,
        rival: rival,
        rules: MatchRules.standard,
        playerSprite: sprite,
        viewportWidth: 960,
        movementDt: dt,
      );
    }

    test('scuffs follow planted frame phases, never a frozen pose or walking into a wall; cap 16', () async {
      final fx = atmosphere(), sprite = await sole();
      observe(fx, sprite, player);
      final walk = player.copyWith(action: FighterAction.walk, x: 111);
      observe(fx, sprite, walk);
      expect(fx.footScuffCount, 1);
      sprite.animationTicker!.currentIndex = 4;
      observe(
        fx,
        sprite,
        walk,
      ); // no rules movement, even if the walk pose changes
      expect(fx.footScuffCount, 1);
      sprite.animationTicker!.currentIndex = 0;
      observe(fx, sprite, walk.copyWith(x: 112), dt: 0);
      expect(fx.footScuffCount, 1);
      observe(fx, sprite, walk.copyWith(x: 112));
      expect(fx.footScuffCount, 2);
      for (var i = 0; i < 40; i++) {
        sprite.animationTicker!.currentIndex = i.isEven ? 4 : 0;
        observe(fx, sprite, walk.copyWith(x: 113.0 + i));
      }
      expect(fx.footScuffCount, 16);
      fx.update(.5);
      expect(fx.footScuffCount, 16);
      fx.update(.501);
      expect(fx.footScuffCount, 0);
      fx.reset();
      observe(fx, sprite, walk);
      expect(fx.footScuffCount, 0, reason: 'first snapshot is not a footstep');
    });

    test(
      'jump and knockdown land once; interrupted jumps never invent a landing',
      () async {
        final fx = atmosphere(), sprite = await sole();
        observe(fx, sprite, player.copyWith(action: FighterAction.jump));
        observe(fx, sprite, player.copyWith(action: FighterAction.hitstun));
        expect(fx.footScuffCount, 0);
        observe(fx, sprite, player.copyWith(action: FighterAction.jump));
        observe(fx, sprite, player);
        observe(fx, sprite, player);
        expect(fx.footScuffCount, 1);
        observe(fx, sprite, player.copyWith(action: FighterAction.knockdown));
        observe(fx, sprite, player);
        expect(fx.footScuffCount, 2);
        expect(
          fx.scarCount,
          0,
          reason: 'a pose alone is never a confirmed knockdown event',
        );
        fx.reset();
        expect(fx.footScuffCount, 0);
      },
    );

    test('confirmed knockdown leaves a bounded body scar at fall completion, only two per match', () async {
      final fx = atmosphere(), sprite = await sole();
      const event = HitEvent(
        attacker: FighterId.rival,
        defender: FighterId.player,
        kind: HitKind.hit,
        heavy: true,
        x: 150,
        ko: false,
        knockdown: true,
      );
      observe(fx, sprite, player);
      final fallen = player.copyWith(action: FighterAction.knockdown);
      fx.onHit(event, 300);
      final contactMarks = fx.markCount;
      sprite.position.x = 500; // rendered travel, NOT state.x or event midpoint
      observe(fx, sprite, fallen);
      expect(fx.activeTrailCount, 1);
      expect(fx.markCount, greaterThan(contactMarks));
      expect(
        fx.scarCount,
        0,
        reason: 'do not stamp the floor while the body is still falling',
      );
      sprite.animationTicker!.setToLast();
      // Looping test cycle is not done: transition out of knockdown supplies
      // the same authoritative landing fallback used on a low-frame-rate device.
      sprite.position.x = 520;
      observe(fx, sprite, player);
      expect(fx.scarCount, 1);
      expect(fx.activeTrailCount, 0);
      expect(
        fx.markCount,
        contactMarks + 3,
        reason: 'three connected fragments from standing x=480 to the actual scar x=520',
      );
      // Resume the original persistence/budget fixture at a shared anchor;
      // its persistent contact dots must not be confused with a travel smear.
      fx.reset();
      sprite.position.x = 480;
      observe(fx, sprite, player);
      fx.onHit(event, 300);
      observe(fx, sprite, fallen);
      observe(fx, sprite, player);
      fx.update(120);
      expect(fx.scarCount, 1, reason: 'outlives ordinary fading effects');
      for (var i = 0; i < 5; i++) {
        fx.onHit(event, 300);
        observe(fx, sprite, fallen);
        observe(fx, sprite, player);
      }
      expect(fx.scarCount, 2);
      fx.update(120);
      // The scar snapshot ages both view clocks, just like the game: transient
      // travelling ink must have finished before measuring persistent floor ink.
      observe(fx, sprite, player, dt: 120);
      final bytes = await pixels(
        (c) => fx.renderFloor(c, _viewport, _floor, _height),
      );
      var marked = 0;
      for (var y = 0; y < 540; y++) {
        for (var x = 0; x < 960; x++) {
          if (bytes[(y * 960 + x) * 4 + 3] == 0) continue;
          marked++;
          expect((x - sprite.position.x).abs(), lessThan(_height * .15));
          expect((y - _floor).abs(), lessThan(_height * .15));
        }
      }
      expect(marked, greaterThan(0));
      fx.reset();
      expect(fx.scarCount, 0);
    });

    test('overlap shades only rear alpha, front stays pristine; render restores decorators', () async {
      final fx = atmosphere();
      final rear = await sole(), front = await sole();
      rear.position.x = 500;
      front.position.x = 410;
      final original = rear.decorator;
      void pair(ui.Canvas c) {
        rear.renderTree(c);
        front.renderTree(c);
      }

      final baseline = await pixels(pair);
      final beforeFrame = rear.animationTicker!.currentIndex;
      final shaded = await pixels(
        (c) => fx.renderFighters(c, pair, front, rear),
      );
      expect(rear.decorator, same(original));
      expect(rear.animationTicker!.currentIndex, beforeFrame);
      var changed = 0;
      final frontOnly = await pixels(front.renderTree);
      for (var i = 0; i < baseline.length; i += 4) {
        expect(
          shaded[i + 3],
          baseline[i + 3],
          reason: 'never add ink outside rear alpha',
        );
        if (frontOnly[i + 3] == 255) expect(shaded[i], baseline[i]);
        if (shaded[i] != baseline[i]) {
          changed++;
          expect(shaded[i], lessThan(baseline[i]));
        }
      }
      expect(changed, greaterThan(0));
      front.position.x = 50;
      expect(overlapDepth(rear, front), isNull);
      front.position.x = 410;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      expect(
        () => fx.renderFighters(
          canvas,
          (_) => throw StateError('render'),
          front,
          rear,
        ),
        throwsStateError,
      );
      expect(rear.decorator, same(original));
      recorder.endRecording().dispose();
    });

    test('actual close-range render preserves children order, poses and match state', () async {
      const passive = BotProfile(
        difficulty: BotDifficulty.easy,
        thinkIntervalMs: 60000,
        reactionMs: 60000,
        attackCooldownMs: 60000,
        blockChance: 0,
        heavyChance: 0,
        hesitationChance: 1,
        recoveryMs: 0,
        preferredGap: 90,
      );
      final game = InkFightBattleGame(botProfile: passive);
      game.hapticsEnabled = false;
      game.onGameResize(Vector2(960, 540));
      await game.onLoad();
      await game.ready();
      for (var i = 0; i < 130; i++) {
        game.update(1 / 60);
      }
      game.setPlayerMoving(true);
      for (var i = 0; i < 55; i++) {
        game.update(1 / 60);
      }
      game.setPlayerMoving(false);
      final children = game.children.toList();
      final p = game.match.player, r = game.match.rival;
      final clock = game.match.timeRemainingMs;
      final image = await raster(game.render);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('.agent-screens').createSync(recursive: true);
      File('.agent-screens/footwork-overlap.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
      image.dispose();
      expect(game.children.toList(), children);
      expect(game.match.player, same(p));
      expect(game.match.rival, same(r));
      expect(game.match.timeRemainingMs, clock);
      game.match.submit(
        const InputCommand(
          fighter: FighterId.rival,
          action: InputAction.heavyKick,
          sequence: 1,
        ),
      );
      game.sendPlayerAction(InputAction.heavyKick);
      var knockedDown = false;
      for (var i = 0; i < 150; i++) {
        game.update(1 / 60);
        knockedDown = knockedDown || game.match.rival.isKnockedDown;
      }
      expect(
        knockedDown,
        isTrue,
        reason: 'real counter-hit event, not a paint-invented scar',
      );
      final scarImage = await raster(game.render);
      final scarData = await scarImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      File('.agent-screens/knockdown-scar-arena.png')
          .writeAsBytesSync(scarData!.buffer.asUint8List());
      scarImage.dispose();
    });
  });

  test('heavy dust pull approaches the hit point for 200 ms, then returns to free drift', () {
    final free = ArenaRoom(), pulled = ArenaRoom();
    final initial = free.dustPositions;
    final target = const ui.Offset(.5, .43);
    pulled.onHit(hit(heavy: true), arenaWidth: 300);
    free.onHit(hit(heavy: true)); // same speed gust, no attraction target
    free.advanceAir(realDt: .2, effectDt: .2, roundEnd: false);
    pulled.advanceAir(realDt: .2, effectDt: .2, roundEnd: false);
    for (var i = 0; i < 8; i++) {
      expect(
        (pulled.dustPositions[i] - target).distance,
        lessThan((free.dustPositions[i] - target).distance),
      );
      expect(
        (pulled.dustPositions[i] - free.dustPositions[i]).distance,
        lessThanOrEqualTo(.0080001),
      );
    }
    final a = free.dustPositions, b = pulled.dustPositions;
    free.advanceAir(realDt: .1, effectDt: .1, roundEnd: false);
    pulled.advanceAir(realDt: .1, effectDt: .1, roundEnd: false);
    for (var i = 0; i < 8; i++) {
      expect(
        (pulled.dustPositions[i] - b[i]).dx,
        closeTo((free.dustPositions[i] - a[i]).dx, 1e-10),
      );
      expect(
        (pulled.dustPositions[i] - b[i]).dy,
        closeTo((free.dustPositions[i] - a[i]).dy, 1e-10),
      );
    }
    pulled.reset();
    expect(pulled.dustPositions, initial);
  });

  group('ink that obeys gravity', () {
    const player = FighterState(
      id: FighterId.player,
      x: 110,
      health: 100,
      facing: 1,
    );
    const rival = FighterState(
      id: FighterId.rival,
      x: 190,
      health: 100,
      facing: -1,
    );

    ArenaInkGravity gravity() =>
        ArenaInkGravity()..layout(_viewport.width, _height);

    void advance(ArenaAtmosphere fx, double dt, {FighterState p = player}) {
      fx.advanceRoom(
        realDt: dt,
        effectDt: dt,
        roundEnd: false,
        player: p,
        rival: rival,
        rules: MatchRules.standard,
      );
    }

    test('only confirmed heavy/knockdown events launch; cap 12; mirrored away from the blow', () {
      final fx = gravity();
      fx.onHit(hit(), 300);
      fx.onHit(hit(heavy: true, kind: HitKind.whiff), 300);
      fx.onHit(hit(heavy: true, kind: HitKind.blocked), 300);
      expect(fx.dropletCount, 0);
      fx.onHit(hit(heavy: true), 300);
      expect(fx.dropletCount, 3);
      fx.advance(.1, .1, (_) => fail('not at the floor yet'));
      expect(fx.droplets.every((d) => d.dx > 0), isTrue);
      fx.reset();
      fx.observeFacing(player.copyWith(facing: -1), rival);
      fx.onHit(hit(heavy: true), 300);
      fx.advance(.1, .1, (_) => fail('not at the floor yet'));
      expect(fx.droplets.every((d) => d.dx < 0), isTrue);
      fx.reset();
      const knockdown = HitEvent(
        attacker: FighterId.player,
        defender: FighterId.rival,
        kind: HitKind.hit,
        heavy: true,
        x: 150,
        ko: false,
        knockdown: true,
      );
      fx.onHit(knockdown, 300);
      expect(fx.dropletCount, 4);
      for (var i = 0; i < 100; i++) {
        fx.onHit(knockdown, 300);
      }
      expect(fx.dropletCount, 12);
      fx.reset();
      expect(fx.dropletCount, 0);
    });

    test('droplets rise then accelerate down; exact landing, independent of frame partition', () {
      final coarse = gravity(), fine = gravity();
      coarse.onHit(hit(heavy: true), 300);
      fine.onHit(hit(heavy: true), 300);
      final start = coarse.droplets;
      coarse.advance(.05, .05, (_) => fail('premature landing'));
      expect(coarse.droplets.first.y, lessThan(start.first.y));
      coarse.advance(.25, .25, (_) => fail('premature landing'));
      fine.advance(.1, .1, (_) => fail('premature landing'));
      fine.advance(.2, .2, (_) => fail('premature landing'));
      for (var i = 0; i < 3; i++) {
        expect(coarse.droplets[i].dx, closeTo(fine.droplets[i].dx, 1e-12));
        expect(coarse.droplets[i].y, closeTo(fine.droplets[i].y, 1e-12));
      }
      final a = <InkLanding>[], b = <InkLanding>[];
      coarse.advance(.5, .5, a.add);
      for (var i = 0; i < 50; i++) {
        fine.advance(.01, .01, b.add);
      }
      expect(a, hasLength(3));
      expect(b, hasLength(3));
      for (var i = 0; i < a.length; i++) {
        expect(a[i].xShare, closeTo(b[i].xShare, 1e-12));
        expect(a[i].radiusShare, b[i].radiusShare);
        expect(a[i].xShare, greaterThan(.5));
      }
      final t = (.20 + math.sqrt(.20 * .20 + 2 * 2.8 * .43)) / 2.8;
      expect(
        a.any((p) => (p.xShare - (.5 + .10 * t * _height / 960)).abs() < 1e-12),
        isTrue,
      );
      expect(coarse.dropletCount, 0);
      coarse.advance(
        10,
        10,
        (_) => fail('a dead droplet must never land twice'),
      );
      coarse.reset();
      coarse.onHit(hit(heavy: true), 300);
      coarse.advance(.3, .3, (_) => fail('premature landing'));
      for (var i = 0; i < 3; i++) {
        expect(
          coarse.droplets[i].y,
          closeTo(
            -.43 + [-.20, -.24, -.18][i] * .3 + .5 * 2.8 * .3 * .3,
            1e-12,
          ),
        );
      }
    });

    test(
      'effect clock scales arcs in KO and freezes them, without a second clock',
      () {
        final normal = gravity(), slow = gravity();
        normal.onHit(hit(heavy: true), 300);
        slow.onHit(hit(heavy: true), 300);
        normal.advance(.2, .2, (_) {});
        slow.advance(.05, .2, (_) {});
        for (var i = 0; i < 3; i++) {
          expect(
            slow.droplets[i].dx,
            closeTo(normal.droplets[i].dx * .25, 1e-12),
          );
        }
        final held = slow.droplets;
        slow.advance(0, .25, (_) => fail('frozen'));
        expect(slow.droplets, held);
      },
    );

    test(
      'every droplet landing joins the EXISTING 24-mark pool and fades there',
      () async {
        final fx = atmosphere();
        await pixels(
          (c) => fx.renderFloor(c, _viewport, _floor, _height),
        ); // establish view geometry
        fx.onHit(hit(heavy: true), 300);
        final immediate = fx.markCount;
        expect(fx.dropletCount, 3);
        advance(fx, .8);
        // Three contact drops and the first carried drip have landed; the
        // second carried drip is still falling from the hurt fighter.
        expect(fx.dropletCount, 1);
        expect(fx.markCount, immediate + 4);
        expect(
          fx.markOpacities.skip(immediate).every((a) => a > 0 && a <= .36),
          isTrue,
        );
        fx.update(1.6);
        expect(
          fx.markCount,
          immediate,
          reason: 'only existing normal hit residue remains',
        );
        for (var i = 0; i < 30; i++) {
          fx.onHit(hit(heavy: true), 300);
        }
        advance(fx, .8);
        expect(fx.markCount, lessThanOrEqualTo(24));
        fx.reset();
        expect(fx.markCount, 0);
        expect(fx.dropletCount, 0);
        expect(fx.wallRunCount, 0);
      },
    );

    test('wall splatter rises, runs down under gravity, settles at .10h, fades and caps', () {
      final fx = gravity();
      final wall = player.copyWith(
        x: MatchRules.standard.minX,
        pushVelocity: -40,
      );
      fx.onWall(wall, 300);
      expect(fx.wallRunCount, 2);
      fx.advance(.1, .1, (_) => fail('a wall run is not a flying droplet'));
      expect(fx.wallDisplacements.every((y) => y < 0), isTrue);
      fx.advance(.6, .6, (_) => fail('wall paint does not mint floor dots'));
      expect(fx.wallDisplacements.every((y) => y > 0 && y <= .1), isTrue);
      fx.advance(.2, .2, (_) {});
      expect(fx.wallDisplacements, [.1, .1]);
      fx.advance(.6, .6, (_) {});
      expect(fx.wallRunCount, 2);
      fx.advance(.11, .11, (_) {});
      expect(fx.wallRunCount, 0);
      for (var i = 0; i < 100; i++) {
        fx.onWall(wall, 300);
      }
      expect(fx.wallRunCount, 8);
      fx.reset();
      expect(fx.wallRunCount, 0);
    });

    test('only the existing boundary-shove gate emits wall runs, never walking/holding', () async {
      final fx = atmosphere();
      await pixels((c) => fx.renderFloor(c, _viewport, _floor, _height));
      advance(fx, .016);
      final wall = player.copyWith(x: MatchRules.standard.minX);
      advance(fx, .016, p: wall);
      expect(fx.wallRunCount, 0);
      final shoved = wall.copyWith(
        action: FighterAction.hitstun,
        pushVelocity: -40,
      );
      advance(fx, .016, p: shoved);
      expect(fx.wallRunCount, 2);
      expect(fx.markCount, 1);
      for (var i = 0; i < 10; i++) {
        advance(fx, .016, p: shoved);
      }
      expect(fx.wallRunCount, 2);
      expect(fx.markCount, 1);
      fx.reset();
      advance(fx, .016, p: shoved);
      expect(fx.wallRunCount, 0);
    });

    test('rendered trajectories stay in narrow contact-to-floor corridor, wall run within .15h', () async {
      final fx = gravity();
      fx.onHit(hit(heavy: true), 300);
      for (final dt in [.01, .09, .2, .2]) {
        fx.advance(dt, dt, (_) => fail('not at the floor'));
        final before = fx.droplets;
        final data = await pixels(
          (c) => fx.render(c, _viewport, _floor, _height),
        );
        expect(
          fx.droplets,
          before,
          reason: 'render must never advance a particle',
        );
        var drawn = 0;
        for (var y = 0; y < 540; y++) {
          for (var x = 0; x < 960; x++) {
            final p = (y * 960 + x) * 4;
            if (data[p + 3] == 0) continue;
            drawn++;
            expect((x - 480).abs(), lessThan(_height * .15));
            expect(y, greaterThan((_floor - _height * .46).floor()));
            expect(y, lessThanOrEqualTo(_floor + _height * .008));
            expect(data[p], data[p + 1]);
            expect(data[p + 1], data[p + 2]);
          }
        }
        expect(drawn, greaterThan(0));
      }
      fx.reset();
      fx.onWall(player.copyWith(x: 150, pushVelocity: -40), 300);
      fx.advance(.7, .7, (_) {});
      final wall = await pixels(
        (c) => fx.render(c, _viewport, _floor, _height),
      );
      for (var y = 0; y < 540; y++) {
        for (var x = 0; x < 960; x++) {
          if (wall[(y * 960 + x) * 4 + 3] == 0) continue;
          expect((x - 480).abs(), lessThan(_height * .15));
          expect((y - (_floor - _height * .43)).abs(), lessThan(_height * .15));
        }
      }
    });

    test('actual heavy hit renders travelling ink and lands it without render-side sim writes', () async {
      const passive = BotProfile(
        difficulty: BotDifficulty.easy,
        thinkIntervalMs: 60000,
        reactionMs: 60000,
        attackCooldownMs: 60000,
        blockChance: 0,
        heavyChance: 0,
        hesitationChance: 1,
        recoveryMs: 0,
        preferredGap: 90,
      );
      final game = InkFightBattleGame(botProfile: passive)
        ..hapticsEnabled = false;
      game.onGameResize(Vector2(960, 540));
      await game.onLoad();
      await game.ready();
      for (var i = 0; i < 130; i++) {
        game.update(1 / 60);
      }
      game.setPlayerMoving(true);
      for (var i = 0; i < 55; i++) {
        game.update(1 / 60);
      }
      game.setPlayerMoving(false);
      game.match.submit(
        const InputCommand(
          fighter: FighterId.rival,
          action: InputAction.heavyKick,
          sequence: 1000,
        ),
      );
      game.sendPlayerAction(InputAction.heavyKick);
      var hit = false;
      for (var i = 0; i < 60; i++) {
        game.update(1 / 60);
        if (game.match.rival.health < 100) {
          hit = true;
          break;
        }
      }
      expect(hit, isTrue);
      expect(
        game.match.rival.isKnockedDown,
        isTrue,
        reason: 'real counter-hit, not a painted or forged knockdown',
      );
      Directory('.agent-screens').createSync(recursive: true);
      Future<void> capture(String name) async {
        final p = game.match.player, r = game.match.rival;
        final clock = game.match.timeRemainingMs;
        final image = await raster(game.render);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('.agent-screens/$name.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
        expect(game.match.player, same(p));
        expect(game.match.rival, same(r));
        expect(game.match.timeRemainingMs, clock);
      }

      for (var i = 0; i < 7; i++) {
        game.update(1 / 60);
      }
      await capture('ink-gravity-rise');
      for (var i = 0; i < 20; i++) {
        game.update(1 / 60);
      }
      await capture('ink-gravity-fall');
      for (var i = 0; i < 15; i++) {
        game.update(1 / 60);
      }
      await capture('ink-gravity-landed');
      await capture('carried-ink-fall-trail');
      for (var i = 0; i < 16; i++) {
        game.update(1 / 60);
      }
      await capture('carried-ink-moving-body');
      for (var i = 0; i < 18; i++) {
        game.update(1 / 60);
      }
      await capture('carried-ink-last-drip');
    });
  });

  test(
    'landing residue order and fade are invariant to frame partitioning',
    () async {
      final coarse = atmosphere(), fine = atmosphere();
      const p = FighterState(
        id: FighterId.player,
        x: 110,
        health: 100,
        facing: 1,
      );
      const r = FighterState(
        id: FighterId.rival,
        x: 190,
        health: 100,
        facing: -1,
      );
      for (final fx in [coarse, fine]) {
        await pixels((c) => fx.renderFloor(c, _viewport, _floor, _height));
        fx.onHit(hit(heavy: true), 300);
      }
      void step(ArenaAtmosphere fx, double dt) {
        fx.update(dt);
        fx.advanceRoom(
          realDt: dt,
          effectDt: dt,
          roundEnd: false,
          player: p,
          rival: r,
          rules: MatchRules.standard,
        );
      }

      step(coarse, .8);
      for (var i = 0; i < 80; i++) {
        step(fine, .01);
      }
      expect(coarse.markCount, fine.markCount);
      for (var i = 0; i < coarse.markCount; i++) {
        expect(coarse.markOpacities[i], closeTo(fine.markOpacities[i], 1e-10));
      }
    },
  );
  group('fighters carry their ink', () {
    const p = FighterState(
      id: FighterId.player,
      x: 110,
      health: 100,
      facing: 1,
    );
    const r = FighterState(
      id: FighterId.rival,
      x: 190,
      health: 100,
      facing: -1,
    );
    const knockdown = HitEvent(
      attacker: FighterId.player,
      defender: FighterId.rival,
      kind: HitKind.hit,
      heavy: true,
      x: 150,
      ko: false,
      knockdown: true,
    );
    ArenaInkGravity gravity() => ArenaInkGravity()..layout(960, _height);
    void observe(
      ArenaInkGravity fx, {
      double x = .7,
      FighterState rival = r,
      bool done = false,
      double fall = 0,
    }) => fx.observeCarriers(
      p,
      rival,
      MatchRules.standard,
      rivalXShare: x,
      rivalFallComplete: done,
      rivalFallProgress: fall,
    );

    test('only confirmed heavy starts a source; new hits replace, never stack; two fighters and reset', () {
      final fx = gravity();
      observe(fx);
      fx.onHit(hit(), 300);
      fx.onHit(hit(heavy: true, kind: HitKind.blocked), 300);
      fx.onHit(hit(heavy: true, kind: HitKind.whiff), 300);
      expect(fx.activeDripCount, 0);
      for (var i = 0; i < 10; i++) {
        fx.onHit(hit(heavy: true), 300);
        fx.advance(.21, .21, (_) {});
        expect(fx.activeDripCount, 1);
        expect(
          fx.droplets.where((d) => d.radius == .0035),
          isEmpty,
          reason: 'a replacement must remove the previous release schedule',
        );
        expect(fx.dropletCount, lessThanOrEqualTo(12));
      }
      fx.onHit(hit(heavy: true, kind: HitKind.blocked), 300);
      fx.onHit(hit(heavy: true, kind: HitKind.whiff), 300);
      fx.advance(.011, .011, (_) {});
      expect(
        fx.droplets.where((d) => d.radius == .0035),
        hasLength(1),
        reason: 'blocks and whiffs do not re-arm OR cancel a confirmed source',
      );
      fx.onHit(hit(), 300);
      expect(
        fx.activeDripCount,
        0,
        reason: 'light replaces with no new sequence',
      );
      fx.onHit(hit(heavy: true), 300);
      fx.onHit(
        const HitEvent(
          attacker: FighterId.rival,
          defender: FighterId.player,
          kind: HitKind.hit,
          heavy: true,
          x: 150,
          ko: false,
        ),
        300,
      );
      expect(fx.activeDripCount, 2);
      fx.reset();
      expect(fx.activeDripCount, 0);
      expect(fx.activeTrailCount, 0);
      expect(fx.dropletCount, 0);
      fx.advance(10, 10, (_) => fail('reset leaked a delayed release'));
    });

    test('drips interpolate the moving rendered body, never the event midpoint; release age is exact', () {
      final fx = gravity();
      observe(fx);
      fx.onHit(hit(heavy: true), 300); // contact .5, defender rendered at .7
      observe(fx, x: .9);
      fx.advance(.4, .4, (_) {});
      final drip = fx.droplets.singleWhere((d) => d.radius == .0035);
      expect(
        drip.originX,
        closeTo(.7 + .2 * (.22 / .4) + .11 * _height / 960, 1e-12),
      );
      expect(drip.dx, closeTo(.08 * .18, 1e-12));
      expect(drip.y, closeTo(-.26 + .025 * .18 + 1.4 * .18 * .18, 1e-12));
      expect((drip.originX - .5).abs(), greaterThan(.3));
      expect(fx.activeDripCount, 1);
    });

    test('four releases self-end at 1.3 effect seconds; freeze/KO use existing clock; exact floor root', () {
      final fx = gravity();
      observe(fx);
      fx.onHit(hit(heavy: true), 300);
      final landings = <({double time, InkLanding mark})>[];
      var effectTime = 0.0;
      void step(double effect, double real) {
        effectTime += effect;
        fx.advance(effect, real, (mark) {
          landings.add((
            time: effectTime - mark.alreadyAgedMs / 1000 * effect / real,
            mark: mark,
          ));
        });
      }

      step(.21, .84); // KO quarter-speed: no release at .21, despite .84 real
      expect(fx.droplets.where((d) => d.radius == .0035), isEmpty);
      final held = fx.droplets;
      step(0, 10);
      expect(fx.droplets, held);
      expect(fx.activeDripCount, 1);
      step(.02, .08);
      expect(fx.droplets.where((d) => d.radius == .0035), hasLength(1));
      step(1.07, 1.07);
      expect(fx.activeDripCount, 0);
      step(.6, .6);
      expect(fx.dropletCount, 0);
      final carried = landings
          .where((d) => d.mark.radiusShare == .0035)
          .toList();
      expect(carried, hasLength(4));
      final flight = (-.025 + math.sqrt(.025 * .025 + 2 * 2.8 * .26)) / 2.8;
      for (var i = 0; i < 4; i++) {
        expect(
          carried[i].time,
          closeTo([.22, .58, .94, 1.30][i] + flight, 1e-12),
        );
        expect(
          carried[i].mark.xShare,
          closeTo(.7 + (i.isEven ? .11 : -.11) * _height / 960, 1e-12),
        );
      }
      step(10, 10);
      expect(
        landings,
        hasLength(7),
        reason: 'no lingering source and no double landing',
      );
      // Even without a supplied body snapshot, an unobserved source expires.
      final unobserved = gravity()..onHit(hit(heavy: true), 300);
      unobserved.advance(2, 2, (_) {});
      expect(unobserved.activeDripCount, 0);
    });

    test('release height follows jump lift and delivered fall pose, without touching state or sprites', () {
      final jumping = gravity(), fallen = gravity();
      final airborne = r.copyWith(
        action: FighterAction.jump,
        jumpRemainingMs: MatchRules.standard.jumpMs ~/ 2,
      );
      observe(jumping, rival: airborne);
      jumping.onHit(hit(heavy: true), 300);
      observe(jumping, rival: airborne);
      jumping.advance(.22, .22, (_) {});
      expect(
        jumping.droplets.singleWhere((d) => d.radius == .0035).y,
        closeTo(-.42, 1e-12),
      );
      observe(
        fallen,
        rival: r.copyWith(action: FighterAction.knockdown),
        fall: 1,
      );
      fallen.onHit(knockdown, 300);
      observe(
        fallen,
        rival: r.copyWith(action: FighterAction.knockdown),
        fall: 1,
      );
      fallen.advance(.22, .22, (_) {});
      expect(
        fallen.droplets.singleWhere((d) => d.radius == .0035).y,
        closeTo(-.055, 1e-12),
      );
      expect(airborne.jumpRemainingMs, MatchRules.standard.jumpMs ~/ 2);
      expect(r.action, FighterAction.idle);
    });

    test('linear moving source and interleaved knockdown deposits are frame-partition deterministic', () {
      List<({double time, InkLanding mark})> run(int frames) {
        final fx = gravity();
        observe(fx, x: .6);
        fx.onHit(knockdown, 300);
        final records = <({double time, InkLanding mark})>[];
        const duration = 1.9;
        for (var i = 1; i <= frames; i++) {
          final t = duration * i / frames;
          observe(
            fx,
            x: .6 + .22 * _height / 960 * t / duration,
            rival: r.copyWith(action: FighterAction.knockdown),
            done: i == frames,
          );
          fx.advance(duration / frames, duration / frames, (mark) {
            records.add((time: t - mark.alreadyAgedMs / 1000, mark: mark));
          });
        }
        expect(fx.activeDripCount, 0);
        expect(fx.activeTrailCount, 0);
        return records;
      }

      final coarse = run(1), fine = run(190), replay = run(190);
      expect(coarse, hasLength(13)); // four contact, four carried, five trail
      expect(fine, hasLength(coarse.length));
      for (var i = 0; i < coarse.length; i++) {
        expect(coarse[i].time, closeTo(fine[i].time, 1e-10));
        expect(coarse[i].mark.xShare, closeTo(fine[i].mark.xShare, 1e-10));
        expect(
          coarse[i].mark.widthShare ?? 0,
          closeTo(fine[i].mark.widthShare ?? 0, 1e-10),
        );
        expect(fine[i].mark.xShare, replay[i].mark.xShare);
        expect(fine[i].time, replay[i].time);
      }
    });

    test('only confirmed knockdown draws along actual body travel; flushes at fall point, then stops', () {
      final fx = gravity();
      observe(fx, x: .7);
      fx.onHit(hit(heavy: true), 300);
      expect(fx.activeTrailCount, 0);
      // A pose alone and an invalid blocked/whiff knockdown never draw trails.
      for (final kind in [HitKind.blocked, HitKind.whiff]) {
        fx.onHit(
          HitEvent(
            attacker: FighterId.player,
            defender: FighterId.rival,
            kind: kind,
            heavy: true,
            x: 150,
            ko: false,
            knockdown: true,
          ),
          300,
        );
      }
      final marks = <InkLanding>[];
      final down = r.copyWith(action: FighterAction.knockdown);
      observe(fx, x: .7 + .09 * _height / 960, rival: down);
      fx.advance(.1, .1, marks.add);
      expect(marks.where((m) => m.widthShare != null), isEmpty);
      observe(fx, x: .7);
      fx.advance(.01, .01, marks.add);
      fx.onHit(knockdown, 300);
      expect(fx.activeTrailCount, 1);
      observe(fx, x: .7 + .10 * _height / 960, rival: down);
      fx.advance(.1, .1, marks.add);
      expect(marks.where((m) => m.widthShare != null), hasLength(2));
      observe(fx, x: .7 + .10 * _height / 960, rival: down);
      fx.advance(.1, .1, marks.add);
      expect(
        marks.where((m) => m.widthShare != null),
        hasLength(2),
        reason: 'stationary body never floods the pool',
      );
      observe(fx, x: .7 + .12 * _height / 960, rival: down, done: true);
      fx.advance(.1, .1, marks.add);
      final trail = marks.where((m) => m.widthShare != null).toList();
      expect(trail, hasLength(3));
      expect(trail.first.xShare, closeTo(.7 + .0225 * _height / 960, 1e-12));
      final last = trail.last;
      expect(
        last.xShare + (last.widthShare! - .008) * .5 * _height / 960,
        closeTo(.7 + .12 * _height / 960, 1e-12),
      );
      expect(
        trail.every(
          (m) =>
              m.opacity == .20 &&
              m.radiusShare == .005 &&
              m.widthShare! <= .0531,
        ),
        isTrue,
      );
      expect(fx.activeTrailCount, 0);
      observe(fx, x: .95);
      fx.advance(2, 2, marks.add);
      expect(marks.where((m) => m.widthShare != null), hasLength(3));
    });

    test('long/reversed travel stays bounded to six fragments; reset removes pending trail', () {
      final fx = gravity();
      observe(fx, x: .4);
      fx.onHit(knockdown, 300);
      observe(fx, x: .9, rival: r.copyWith(action: FighterAction.knockdown));
      final marks = <InkLanding>[];
      fx.advance(.1, .1, marks.add);
      final trail = marks.where((m) => m.widthShare != null).toList();
      expect(trail, hasLength(6));
      expect(
        trail.last.xShare + trail.last.widthShare! * .5 * _height / 960 - .4,
        lessThan(.28 * _height / 960),
      );
      expect(fx.activeTrailCount, 0);
      fx.onHit(knockdown, 300);
      observe(fx, x: .2, rival: r.copyWith(action: FighterAction.knockdown));
      marks.clear();
      fx.advance(.1, .1, marks.add);
      final reverse = marks.where((m) => m.widthShare != null).toList();
      expect(reverse, hasLength(6));
      expect(reverse.last.xShare, lessThan(reverse.first.xShare));
      expect(reverse.map((m) => m.widthShare), trail.map((m) => m.widthShare));
      fx.onHit(knockdown, 300);
      fx.reset();
      observe(fx, x: .2, rival: r.copyWith(action: FighterAction.knockdown));
      fx.advance(2, 2, (_) => fail('reset leaked a trail or drop'));
    });

    test('body trails and carried landings share the existing cap/fade/reset and repeat pixels exactly', () async {
      Future<(Uint8List, ArenaAtmosphere)> run() async {
        final fx = atmosphere();
        await pixels((c) => fx.renderFloor(c, _viewport, _floor, _height));
        void step(FighterState rival, double dt) {
          fx.update(dt);
          fx.advanceRoom(
            realDt: dt,
            effectDt: dt,
            roundEnd: false,
            player: p,
            rival: rival,
            rules: MatchRules.standard,
          );
        }

        step(r, 0);
        for (var n = 0; n < 12; n++) {
          fx.onHit(knockdown, 300);
          for (var i = 1; i <= 10; i++) {
            step(
              r.copyWith(x: 190 + i * .5, action: FighterAction.knockdown),
              .025,
            );
            expect(fx.markCount, lessThanOrEqualTo(24));
            expect(fx.dropletCount, lessThanOrEqualTo(12));
            expect(fx.activeDripCount, lessThanOrEqualTo(1));
          }
          step(r.copyWith(x: 195), .01);
          step(r, 0);
        }
        expect(fx.activeTrailCount, 0);
        final data = await pixels(
          (c) => fx.renderFloor(c, _viewport, _floor, _height),
        );
        return (data, fx);
      }

      final (a, fx) = await run();
      final (b, _) = await run();
      expect(a, orderedEquals(b));
      expect(fx.markCount, greaterThan(0));
      for (var y = 0; y < 540; y++) {
        for (var x = 0; x < 960; x++) {
          final i = (y * 960 + x) * 4;
          if (a[i + 3] == 0) continue;
          expect(
            y,
            greaterThan(290),
            reason: 'body ink stays well below the HUD',
          );
          final monochrome = a[i] == a[i + 1] && a[i + 1] == a[i + 2];
          final crimson = a[i] >= a[i + 2] && a[i + 2] >= a[i + 1];
          expect(
            monochrome || crimson,
            isTrue,
            reason: 'only ink plus the existing crimson contact residue',
          );
        }
      }
      fx.onHit(
        hit(),
        300,
      ); // no more scheduled releases; only shared fading residue remains
      fx.advanceRoom(
        realDt: 2,
        effectDt: 2,
        roundEnd: false,
        player: p,
        rival: r,
        rules: MatchRules.standard,
      );
      fx.update(2);
      expect(
        fx.markOpacities.every((a) => a == .48),
        isTrue,
        reason:
            'trail fragments and landed droplets expire in the existing pool',
      );
      fx.reset();
      expect(fx.markCount, 0);
      expect(fx.activeDripCount, 0);
      expect(fx.activeTrailCount, 0);
      expect(fx.dropletCount, 0);
    });
  });
}
