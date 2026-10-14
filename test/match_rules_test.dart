import 'package:flutter_test/flutter_test.dart';

import 'package:inkfight/game/rules/match_rules.dart';

/// The tuning table is the only place a combat constant may live, and these
/// tests are what keeps it honest against docs/product/GAME_DESIGN_DOCUMENT.md
/// §6–§8. `match_controller_test.dart` covers what the table does to a match.
void main() {
  const rules = MatchRules.standard;

  test('one round, 60 seconds, 100 health — the bot fight MVP', () {
    expect(rules.health, 100);
    expect(rules.roundMs, 60000);
    expect(rules.countdownMs, greaterThan(0));
    expect(rules.blockHoldMs, greaterThan(rules.lightAttack.totalMs));
  });

  test('a match opens out of reach, so closing distance is part of it', () {
    expect(
      rules.rivalStartX - rules.startX,
      greaterThan(rules.heavyAttack.reach),
    );
    expect(rules.minX, greaterThan(0));
    expect(rules.maxX, lessThan(rules.arenaWidth));
    expect(rules.maxX - rules.minX, greaterThan(rules.minFighterDistance * 4));
  });

  test('a knockout is reachable inside the round', () {
    final heavies = (rules.health / rules.heavyAttack.damage).ceil();
    expect(heavies * rules.heavyAttack.totalMs, lessThan(rules.roundMs));

    final lights = (rules.health / rules.lightAttack.damage).ceil();
    expect(
      lights,
      greaterThan(heavies),
      reason: 'the jab is the slower route to a knockout, by design',
    );
  });

  test('every attack is startup, then active, then recovery', () {
    for (final frame in [rules.lightAttack, rules.heavyAttack]) {
      expect(frame.startupMs, greaterThan(0));
      expect(frame.activeMs, greaterThan(0));
      expect(frame.recoveryMs, greaterThan(0));
      expect(
        frame.totalMs,
        frame.startupMs + frame.activeMs + frame.recoveryMs,
      );
      expect(frame.hitstunMs, greaterThan(0));
      expect(frame.blockstunMs, greaterThan(0));
    }
  });

  test('the hitbox opens after startup and is shut by recovery', () {
    final frame = rules.lightAttack;

    expect(frame.isActiveAt(0), isFalse);
    expect(frame.isActiveAt(frame.startupMs - rules.tickMs), isFalse);
    expect(frame.isActiveAt(frame.startupMs), isTrue);
    expect(frame.isActiveAt(frame.startupMs + frame.activeMs - 1), isTrue);
    expect(frame.isActiveAt(frame.startupMs + frame.activeMs), isFalse);
    expect(frame.isActiveAt(frame.totalMs), isFalse);
  });

  test('the heavy kick is slower, longer and stronger than the jab', () {
    final light = rules.lightAttack;
    final heavy = rules.heavyAttack;

    expect(heavy.startupMs, greaterThan(light.startupMs));
    expect(heavy.totalMs, greaterThan(light.totalMs));
    expect(heavy.damage, greaterThan(light.damage));
    expect(heavy.reach, greaterThan(light.reach));
    expect(heavy.knockback, greaterThan(light.knockback));
    expect(heavy.hitstunMs, greaterThan(light.hitstunMs));
  });

  test('blocking absorbs a jab outright and only chips a heavy', () {
    final light = rules.lightAttack;
    final heavy = rules.heavyAttack;

    expect(light.blockedDamage, 0);
    expect(heavy.blockedDamage, greaterThan(0));
    expect(heavy.blockedDamage, lessThan(heavy.damage));
    expect(heavy.blockstunMs, greaterThan(light.blockstunMs));
    expect(rules.blockPushbackFactor, inInclusiveRange(0, 1));
    expect(rules.airControlFactor, inInclusiveRange(0, 1));
  });

  test('the simulation advances one 60 FPS frame or less at a time', () {
    expect(rules.tickMs, lessThanOrEqualTo(17));
    expect(rules.maxCatchUpMs, greaterThanOrEqualTo(rules.tickMs * 2));
  });
}
