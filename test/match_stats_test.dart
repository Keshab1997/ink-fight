import 'package:flutter_test/flutter_test.dart';
import 'package:inkfight/game/audio/fight_sounds.dart';
import 'package:inkfight/game/rules/match_controller.dart';
import 'package:inkfight/game/rules/match_rules.dart';
import 'package:inkfight/game/stats/match_stats.dart';

HitEvent event(FighterId attacker, HitKind kind, {bool ko = false}) => HitEvent(
  attacker: attacker,
  defender: attacker == FighterId.player ? FighterId.rival : FighterId.player,
  kind: kind,
  heavy: false,
  x: 150,
  ko: ko,
);

void main() {
  test('clean player hits count once, including the knockout', () {
    final stats = MatchStats();
    addTearDown(stats.dispose);
    var notifications = 0;
    stats.addListener(() => notifications++);
    stats.onHit(event(FighterId.player, HitKind.hit));
    stats.onHit(event(FighterId.player, HitKind.hit));
    stats.onHit(event(FighterId.player, HitKind.hit, ko: true));
    expect(stats.hitsLanded, 3);
    expect(stats.combo, 3);
    expect(stats.maxCombo, 3);
    expect(stats.blocks, 0);
    expect(notifications, 3);
  });

  test(
    'player whiff and clean hit taken break streak, not lifetime totals',
    () {
      final stats = MatchStats();
      addTearDown(stats.dispose);
      for (var i = 0; i < 3; i++) {
        stats.onHit(event(FighterId.player, HitKind.hit));
      }
      stats.onHit(event(FighterId.player, HitKind.whiff));
      expect(stats.combo, 0);
      expect(stats.maxCombo, 3);
      for (var i = 0; i < 2; i++) {
        stats.onHit(event(FighterId.player, HitKind.hit));
      }
      stats.onHit(event(FighterId.rival, HitKind.hit));
      expect(stats.combo, 0);
      expect(stats.hitsLanded, 5);
      expect(stats.maxCombo, 3);
    },
  );

  test('only player guards count; rival whiffs and blocks preserve run', () {
    final stats = MatchStats();
    addTearDown(stats.dispose);
    stats.onHit(event(FighterId.player, HitKind.hit));
    stats.onHit(event(FighterId.rival, HitKind.whiff));
    stats.onHit(event(FighterId.player, HitKind.blocked));
    stats.onHit(event(FighterId.rival, HitKind.blocked));
    expect(stats.combo, 1);
    expect(stats.hitsLanded, 1);
    expect(stats.blocks, 1);
  });

  test('rematch resets every presentation total and notifies the HUD', () {
    final stats = MatchStats();
    addTearDown(stats.dispose);
    stats.onHit(event(FighterId.player, HitKind.hit));
    stats.onHit(event(FighterId.rival, HitKind.blocked));
    var notified = false;
    stats.addListener(() => notified = true);
    stats.reset();
    expect(
      [stats.hitsLanded, stats.blocks, stats.combo, stats.maxCombo],
      [0, 0, 0, 0],
    );
    expect(notified, isTrue);
  });

  test('10 through 4 tick; 3 through 1 blip, one cue per displayed second', () {
    final clock = MatchClockCues();
    expect(clock.update(MatchPhase.fighting, 10001), isNull);
    for (var second = 10; second >= 1; second--) {
      expect(
        clock.update(MatchPhase.fighting, second * 1000),
        second <= 3 ? FightCue.countdownBlip : FightCue.clockTick,
      );
      expect(clock.update(MatchPhase.fighting, second * 1000 - 16), isNull);
      expect(clock.update(MatchPhase.fighting, second * 1000 - 500), isNull);
    }
    expect(clock.update(MatchPhase.fighting, 0), isNull);
    expect(clock.update(MatchPhase.finished, 3000), isNull);
  });

  test('no replay for missed seconds, paused seconds or muted beats', () {
    final clock = MatchClockCues();
    expect(clock.update(MatchPhase.fighting, 10000), FightCue.clockTick);
    expect(clock.update(MatchPhase.fighting, 7500), FightCue.clockTick);
    // The caller can mute a returned cue; it still consumes that second.
    expect(clock.update(MatchPhase.fighting, 7500), isNull);
    expect(clock.update(MatchPhase.fighting, 2500), FightCue.countdownBlip);
    expect(clock.update(MatchPhase.fighting, 2500), isNull);
  });

  test('countdown re-arms a rematch, intro and finished clocks never tick', () {
    final clock = MatchClockCues();
    expect(clock.update(MatchPhase.fighting, 10000), FightCue.clockTick);
    expect(clock.update(MatchPhase.countdown, 10000), isNull);
    expect(clock.update(MatchPhase.fighting, 10000), FightCue.clockTick);
    expect(clock.update(MatchPhase.finished, 2000), isNull);
  });
}
