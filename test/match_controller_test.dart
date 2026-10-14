import 'package:flutter_test/flutter_test.dart';

import 'package:inkfight/game/rules/input_command.dart';
import 'package:inkfight/game/rules/match_controller.dart';
import 'package:inkfight/game/rules/match_rules.dart';

/// Drives the controller the way the arena will: one frame at a time, with the
/// slice the rules ask for.
void run(MatchController controller, int ms) {
  final rules = controller.rules;
  final slice = rules.tickMs / 1000;
  for (var elapsed = 0; elapsed < ms; elapsed += rules.tickMs) {
    controller.tick(slice);
  }
}

void press(MatchController c, FighterId who, InputAction action, int sequence) {
  c.submit(InputCommand(fighter: who, action: action, sequence: sequence));
}

void skipCountdown(MatchController c) => run(c, c.rules.countdownMs);

/// Walks [who] toward the other fighter until the gap is within [maxGap].
/// The step is one tick of walking, so the gap lands in (maxGap - step,
/// maxGap] — callers pick [maxGap] with room for that step.
void walkUntilWithin(MatchController c, FighterId who, double maxGap) {
  final axis = who == FighterId.player ? 1.0 : -1.0;
  c.setMoveAxis(who, axis);
  var guard = 0;
  while (c.distanceBetween(FighterId.player, FighterId.rival) > maxGap &&
      guard++ < 600) {
    c.tick(c.rules.tickMs / 1000);
  }
  c.setMoveAxis(who, 0);
}

/// Holds the player's stick toward the rival until a light punch would reach —
/// the same walk a player makes in the arena.
void closeIn(MatchController c) {
  final rules = c.rules;
  c.setMoveAxis(FighterId.player, 1);
  var guard = 0;
  while (c.rival.x - c.player.x > rules.lightAttack.reach * .9 &&
      guard++ < 600) {
    c.tick(rules.tickMs / 1000);
  }
  c.setMoveAxis(FighterId.player, 0);
}

/// Walks in and kicks until the rival is out. Every heavy shoves the rival
/// back out of reach, so this is also a test of the movement loop.
void punchOut(MatchController c) {
  final rules = c.rules;
  final hits = (rules.health / rules.heavyAttack.damage).ceil();
  for (var i = 0; i < hits && !c.isFinished; i++) {
    closeIn(c);
    press(c, FighterId.player, InputAction.heavyKick, i * 2 + 1);
    run(c, rules.heavyAttack.totalMs + rules.heavyAttack.hitstunMs);
  }
}

void main() {
  test('the countdown gates input and the clock starts full', () {
    final c = MatchController();
    final rules = c.rules;

    expect(c.phase, MatchPhase.countdown);

    press(c, FighterId.player, InputAction.lightPunch, 1);
    run(c, rules.tickMs * 5);
    expect(c.player.action, FighterAction.idle, reason: 'intro, input ignored');

    run(c, rules.countdownMs - rules.tickMs * 5);
    expect(c.phase, MatchPhase.fighting);
    expect(c.timeRemainingMs, rules.roundMs);
  });

  test('a jab whiffs at the opening gap and lands once you close in', () {
    final c = MatchController();
    final rules = c.rules;
    skipCountdown(c);

    expect(
      c.rival.x - c.player.x,
      greaterThan(rules.lightAttack.reach),
      reason: 'the opening gap should keep movement meaningful',
    );

    press(c, FighterId.player, InputAction.lightPunch, 1);
    run(c, rules.lightAttack.totalMs);
    expect(c.rival.health, rules.health, reason: 'out of range');

    closeIn(c);
    press(c, FighterId.player, InputAction.lightPunch, 2);
    run(c, rules.lightAttack.totalMs);
    expect(c.rival.health, rules.health - rules.lightAttack.damage);
  });

  test('one swing deals its damage once, not once per tick', () {
    final c = MatchController();
    final rules = c.rules;
    skipCountdown(c);
    closeIn(c);

    final before = c.rival.health;
    press(c, FighterId.player, InputAction.lightPunch, 1);
    run(c, rules.lightAttack.totalMs);
    expect(c.rival.health, before - rules.lightAttack.damage);

    run(c, rules.lightAttack.totalMs);
    expect(c.rival.health, before - rules.lightAttack.damage);
  });

  test('a block absorbs the jab and only chips the heavy kick', () {
    final c = MatchController();
    final rules = c.rules;
    skipCountdown(c);
    closeIn(c);

    press(c, FighterId.rival, InputAction.block, 1);
    press(c, FighterId.player, InputAction.lightPunch, 1);
    run(c, rules.lightAttack.totalMs);
    expect(c.rival.health, rules.health);

    // The blocked jab leaves blockstun behind, not a dropped guard: the rival
    // has to hold block again, which is what makes chip damage add up.
    run(c, rules.lightAttack.blockstunMs);
    press(c, FighterId.rival, InputAction.block, 2);
    press(c, FighterId.player, InputAction.heavyKick, 2);
    run(c, rules.heavyAttack.totalMs);
    expect(c.rival.health, rules.health - rules.heavyAttack.blockedDamage);
  });

  test('a landed hit locks the defender out until the stun ends', () {
    final c = MatchController();
    final rules = c.rules;
    skipCountdown(c);
    closeIn(c);

    press(c, FighterId.player, InputAction.lightPunch, 1);
    run(c, rules.lightAttack.startupMs + rules.tickMs * 2);

    expect(c.rival.isStunned, isTrue);
    expect(c.rival.canAct, isFalse);

    press(c, FighterId.rival, InputAction.lightPunch, 9);
    expect(
      c.rival.action,
      FighterAction.hitstun,
      reason: 'input during hitstun is dropped, never queued',
    );

    run(c, rules.lightAttack.hitstunMs);
    expect(c.rival.canAct, isTrue);
  });

  test('an attack is a committed window: recovery cannot be cancelled', () {
    final c = MatchController();
    final rules = c.rules;
    skipCountdown(c);
    closeIn(c);

    press(c, FighterId.player, InputAction.lightPunch, 1);
    run(c, rules.tickMs * 2);
    press(c, FighterId.player, InputAction.heavyKick, 2);
    expect(c.player.action, FighterAction.lightPunch);

    run(c, rules.lightAttack.totalMs);
    expect(c.player.action, FighterAction.idle);
  });

  test('the jump is airborne time: no action until the fighter lands', () {
    final c = MatchController();
    final rules = c.rules;
    skipCountdown(c);

    press(c, FighterId.player, InputAction.jump, 1);
    run(c, rules.tickMs);
    expect(c.player.isAirborne, isTrue);

    press(c, FighterId.player, InputAction.lightPunch, 2);
    press(c, FighterId.player, InputAction.block, 3);
    expect(c.player.action, FighterAction.jump, reason: 'no acting mid-air');

    run(c, rules.jumpMs);
    expect(c.player.action, FighterAction.idle);
  });

  test('a jab passes under an airborne rival, the heavy kick does not', () {
    final c = MatchController();
    final rules = c.rules;
    skipCountdown(c);
    closeIn(c);

    press(c, FighterId.rival, InputAction.jump, 1);
    press(c, FighterId.player, InputAction.lightPunch, 1);
    run(c, rules.lightAttack.totalMs);
    expect(c.rival.health, rules.health, reason: 'the jab goes under them');

    press(c, FighterId.rival, InputAction.jump, 2);
    press(c, FighterId.player, InputAction.heavyKick, 2);
    run(c, rules.heavyAttack.startupMs - rules.tickMs * 2);
    expect(c.rival.isAirborne, isTrue, reason: 'still in the air on impact');

    run(c, rules.tickMs * 4);
    expect(c.rival.health, rules.health - rules.heavyAttack.damage);
  });

  test('the pushbox keeps the two fighters from overlapping', () {
    final c = MatchController();
    final rules = c.rules;
    skipCountdown(c);

    c.setMoveAxis(FighterId.player, 1);
    run(c, 3000);

    expect(
      c.rival.x - c.player.x,
      greaterThanOrEqualTo(rules.minFighterDistance - .001),
    );
    expect(c.player.x, lessThanOrEqualTo(c.rival.x));
  });

  test('a fighter stops at the arena wall', () {
    final c = MatchController();
    final rules = c.rules;
    skipCountdown(c);

    c.setMoveAxis(FighterId.player, -1);
    run(c, 5000);
    expect(c.player.x, rules.minX);
  });

  test('a knockout ends the match and names the winner', () {
    final c = MatchController();
    final rules = c.rules;
    skipCountdown(c);
    punchOut(c);

    expect(c.isFinished, isTrue);
    expect(c.phase, MatchPhase.finished);
    expect(c.outcome, MatchOutcome.playerWin);
    expect(c.rival.health, 0);
    expect(
      c.player.health,
      rules.health,
      reason: 'a bot that never fights back',
    );

    // Nothing moves once the result is in.
    final frozen = c.player.x;
    press(c, FighterId.player, InputAction.lightPunch, 99);
    run(c, rules.tickMs * 10);
    expect(c.player.x, frozen);
  });

  test('the clock decides a match nobody closes out', () {
    final c = MatchController();
    final rules = c.rules;
    skipCountdown(c);

    run(c, rules.roundMs);
    expect(c.isFinished, isTrue);
    expect(c.timeRemainingMs, 0);
    expect(c.outcome, MatchOutcome.draw, reason: 'level health on the buzzer');
  });

  test('a timeout goes to the healthier fighter', () {
    final c = MatchController();
    final rules = c.rules;
    skipCountdown(c);
    closeIn(c);

    press(c, FighterId.player, InputAction.lightPunch, 1);
    run(c, rules.lightAttack.totalMs);
    expect(c.rival.health, lessThan(c.player.health));

    run(c, rules.roundMs);
    expect(c.outcome, MatchOutcome.playerWin);
    expect(c.timeRemainingMs, 0);
  });

  test('a stale sequence number is dropped, not replayed', () {
    final c = MatchController();
    final rules = c.rules;
    skipCountdown(c);
    closeIn(c);

    press(c, FighterId.player, InputAction.lightPunch, 5);
    run(c, rules.lightAttack.totalMs);

    press(c, FighterId.player, InputAction.heavyKick, 4);
    expect(c.player.action, FighterAction.idle, reason: 'an old packet');

    press(c, FighterId.player, InputAction.lightPunch, 6);
    expect(c.player.action, FighterAction.lightPunch);
  });

  test('a long stall does not fast-forward the match', () {
    final c = MatchController();
    final rules = c.rules;
    skipCountdown(c);

    final before = c.timeRemainingMs;
    c.tick(10);
    expect(before - c.timeRemainingMs, lessThanOrEqualTo(rules.maxCatchUpMs));
    expect(c.isFinished, isFalse);
  });

  test('a rematch resets the clock, the health and any held input', () {
    final c = MatchController();
    final rules = c.rules;
    skipCountdown(c);
    punchOut(c);
    expect(c.isFinished, isTrue);

    c.setMoveAxis(FighterId.player, 1);
    c.reset();

    expect(c.phase, MatchPhase.countdown);
    expect(c.outcome, isNull);
    expect(c.timeRemainingMs, rules.roundMs);
    expect(c.player.health, rules.health);
    expect(c.rival.health, rules.health);
    expect(c.player.x, rules.startX);
    expect(c.rival.x, rules.rivalStartX);
    expect(c.player.facing, 1);
    expect(c.rival.facing, -1);

    // The stick from the last match does not carry into the new one.
    run(c, rules.countdownMs + 500);
    expect(c.player.x, rules.startX);
  });

  test('the same script produces the same match twice', () {
    List<Object?> script(MatchController c) {
      final rules = c.rules;
      skipCountdown(c);
      c.setMoveAxis(FighterId.player, 1);
      run(c, 400);
      c.setMoveAxis(FighterId.player, 0);
      press(c, FighterId.player, InputAction.lightPunch, 1);
      run(c, 200);
      press(c, FighterId.rival, InputAction.block, 1);
      press(c, FighterId.player, InputAction.heavyKick, 2);
      run(c, 400);
      c.setMoveAxis(FighterId.player, -1);
      press(c, FighterId.rival, InputAction.jump, 2);
      run(c, rules.tickMs * 40);

      return <Object?>[
        c.player.x,
        c.rival.x,
        c.player.health,
        c.rival.health,
        c.player.action,
        c.rival.action,
        c.timeRemainingMs,
        c.phase,
        c.outcome,
      ];
    }

    expect(script(MatchController()), script(MatchController()));
  });

  test('an out-of-reach swing deals no damage, from either side', () {
    final c = MatchController();
    final rules = c.rules;
    skipCountdown(c);

    // The opening gap is 80 units, past both attacks' reach.
    press(c, FighterId.player, InputAction.lightPunch, 1);
    run(c, rules.lightAttack.totalMs);
    expect(c.rival.health, rules.health);

    press(c, FighterId.rival, InputAction.lightPunch, 1);
    run(c, rules.lightAttack.totalMs);
    expect(c.player.health, rules.health);

    press(c, FighterId.player, InputAction.heavyKick, 2);
    run(c, rules.heavyAttack.totalMs);
    expect(c.rival.health, rules.health);

    press(c, FighterId.rival, InputAction.heavyKick, 2);
    run(c, rules.heavyAttack.totalMs);
    expect(c.player.health, rules.health);
  });

  test('a swing the target walks into only during recovery stays a whiff', () {
    final c = MatchController();
    final rules = c.rules;
    final heavy = rules.heavyAttack;
    final slice = rules.tickMs / 1000;
    skipCountdown(c);

    press(c, FighterId.player, InputAction.heavyKick, 1);
    final events = <HitEvent>[];
    for (var i = 0; i < 60; i++) {
      // The rival starts walking in a few ticks after the kick. It reaches
      // the kick's reach only after the active window has closed.
      if (i == 7) {
        c.setMoveAxis(FighterId.rival, -1);
      }
      c.tick(slice);
      final elapsedMs = (i + 1) * rules.tickMs;
      final inActiveWindow =
          elapsedMs >= heavy.startupMs &&
          elapsedMs < heavy.startupMs + heavy.activeMs;
      if (inActiveWindow) {
        expect(
          c.distanceBetween(FighterId.player, FighterId.rival),
          greaterThan(heavy.reach),
          reason: 'the window must stay out of range the whole time',
        );
      }
      expect(c.rival.health, rules.health, reason: 'no retroactive hit');
      events.addAll(c.drainHitEvents());
    }

    expect(
      c.distanceBetween(FighterId.player, FighterId.rival),
      lessThanOrEqualTo(heavy.reach),
      reason: 'the rival did walk into range, after the swing',
    );
    expect(events, hasLength(1));
    expect(events.single.kind, HitKind.whiff);
    expect(events.single.attacker, FighterId.player);
    expect(events.single.heavy, isTrue);
  });

  test('distanceBetween and isInReach agree with what the loop does', () {
    final c = MatchController();
    final rules = c.rules;
    skipCountdown(c);

    expect(
      c.distanceBetween(FighterId.player, FighterId.rival),
      c.rival.x - c.player.x,
    );
    expect(
      c.distanceBetween(FighterId.rival, FighterId.player),
      c.distanceBetween(FighterId.player, FighterId.rival),
      reason: 'distance is symmetric',
    );
    expect(c.isInReach(FighterId.player), isFalse, reason: 'idle reaches nothing');

    // At the opening gap the swing is mid-window and still geometry says no,
    // and the loop agrees: no damage.
    press(c, FighterId.player, InputAction.lightPunch, 1);
    run(c, rules.lightAttack.startupMs + rules.tickMs * 2);
    expect(c.player.action, FighterAction.lightPunch);
    expect(c.isInReach(FighterId.player), isFalse);
    run(c, rules.lightAttack.totalMs);
    expect(c.rival.health, rules.health);

    // Closed in, the same swing is in reach inside its window, and the loop
    // lands it.
    closeIn(c);
    press(c, FighterId.player, InputAction.lightPunch, 2);
    run(c, rules.lightAttack.startupMs + rules.tickMs * 2);
    expect(c.isInReach(FighterId.player), isTrue);
    expect(
      c.distanceBetween(FighterId.player, FighterId.rival),
      lessThanOrEqualTo(rules.lightAttack.reach),
    );
    final events = <HitEvent>[];
    run(c, rules.lightAttack.totalMs);
    events.addAll(c.drainHitEvents());
    expect(c.rival.health, rules.health - rules.lightAttack.damage);
    expect(events.where((e) => e.kind == HitKind.hit), hasLength(1));
  });

  test('the heavy kick reaches a gap the jab cannot', () {
    final c = MatchController();
    final rules = c.rules;
    skipCountdown(c);

    // Stop between the jab's reach and the kick's reach.
    walkUntilWithin(c, FighterId.player, 52);
    final gap = c.distanceBetween(FighterId.player, FighterId.rival);
    expect(gap, greaterThan(rules.lightAttack.reach));
    expect(gap, lessThanOrEqualTo(rules.heavyAttack.reach));

    press(c, FighterId.player, InputAction.lightPunch, 1);
    run(c, rules.lightAttack.totalMs);
    expect(c.rival.health, rules.health, reason: 'the jab falls short');

    press(c, FighterId.player, InputAction.heavyKick, 2);
    run(c, rules.heavyAttack.startupMs + rules.tickMs * 2);
    expect(c.isInReach(FighterId.player), isTrue);
    run(c, rules.heavyAttack.totalMs);
    expect(c.rival.health, rules.health - rules.heavyAttack.damage);
  });

  test('a whiffed heavy kick stays punishable from the edge of its reach', () {
    final c = MatchController();
    final rules = c.rules;
    final heavy = rules.heavyAttack;
    final slice = rules.tickMs / 1000;
    skipCountdown(c);

    // Stand just outside the kick's reach, so its whole active window misses.
    walkUntilWithin(c, FighterId.rival, heavy.reach + 2);
    press(c, FighterId.player, InputAction.heavyKick, 1);

    var rivalPunched = false;
    int? landedAtMs;
    var elapsedMs = 0;
    for (var i = 0; i < 80; i++) {
      // Once the kick's window has closed, the rival walks in and jabs as
      // soon as its own jab would reach.
      if (elapsedMs >= heavy.startupMs + heavy.activeMs) {
        c.setMoveAxis(FighterId.rival, -1);
      }
      if (!rivalPunched &&
          c.rival.canAct &&
          c.distanceBetween(FighterId.player, FighterId.rival) <=
              rules.lightAttack.reach) {
        press(c, FighterId.rival, InputAction.lightPunch, 1);
        rivalPunched = true;
      }
      c.tick(slice);
      elapsedMs += rules.tickMs;
      for (final event in c.drainHitEvents()) {
        if (event.kind == HitKind.hit && event.attacker == FighterId.rival) {
          landedAtMs ??= elapsedMs;
        }
      }
    }

    expect(rivalPunched, isTrue, reason: 'the rival closed in and jabbed');
    expect(landedAtMs, isNotNull, reason: 'the jab connected');
    expect(
      landedAtMs!,
      lessThanOrEqualTo(heavy.totalMs),
      reason: 'the jab lands while the kick is still in recovery',
    );
    expect(c.player.health, rules.health - rules.lightAttack.damage);
  });
}
