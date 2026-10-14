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
}
