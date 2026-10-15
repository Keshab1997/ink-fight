import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkfight/game/bot/bot_strategy.dart';
import 'package:inkfight/game/effects/arena_atmosphere.dart';
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
}
