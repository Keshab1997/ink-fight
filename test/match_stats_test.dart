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
  group('read-only round result feedback', () {
    for (final outcome in MatchOutcome.values) {
      test('consecutive scores describe $outcome once', () {
        final tracker = RoundResultTracker();
        expect(
          tracker.observe(roundNumber: 1, playerWins: 0, rivalWins: 0),
          isNull,
        );
        final player = outcome == MatchOutcome.playerWin ? 1 : 0;
        final rival = outcome == MatchOutcome.rivalWin ? 1 : 0;
        final result = tracker.observe(
          roundNumber: 2,
          playerWins: player,
          rivalWins: rival,
        );
        expect(result!.number, 1);
        expect(result.outcome, outcome);
        expect(
          tracker.observe(roundNumber: 2, playerWins: player, rivalWins: rival),
          same(result),
        );
        expect(
          tracker.observe(roundNumber: 1, playerWins: 0, rivalWins: 0),
          isNull,
          reason:
              'rematch/restart clears presentation, not a fake round result',
        );
      });
    }
    test('round lost then round won is not a match decision', () {
      final tracker = RoundResultTracker();
      tracker.observe(roundNumber: 1, playerWins: 0, rivalWins: 0);
      expect(
        tracker.observe(roundNumber: 2, playerWins: 0, rivalWins: 1)!.outcome,
        MatchOutcome.rivalWin,
      );
      final result = tracker.observe(
        roundNumber: 3,
        playerWins: 1,
        rivalWins: 1,
      )!;
      expect(result.number, 2);
      expect(result.outcome, MatchOutcome.playerWin);
      // A winning score changes inside the last round. There is no new
      // round snapshot; the real match outcome is read separately by the card.
      expect(
        tracker.observe(roundNumber: 3, playerWins: 2, rivalWins: 1),
        same(result),
      );
    });
    test('late mount or skipped rounds never invent the last result', () {
      final tracker = RoundResultTracker();
      expect(
        tracker.observe(roundNumber: 2, playerWins: 1, rivalWins: 0),
        isNull,
      );
      expect(
        tracker.observe(roundNumber: 4, playerWins: 2, rivalWins: 1),
        isNull,
      );
      final result = tracker.observe(
        roundNumber: 5,
        playerWins: 2,
        rivalWins: 1,
      )!;
      expect(result.number, 4);
      expect(result.outcome, MatchOutcome.draw);
    });
    test('ambiguous score deltas are not guessed', () {
      final tracker = RoundResultTracker();
      tracker.observe(roundNumber: 1, playerWins: 0, rivalWins: 0);
      expect(
        tracker.observe(roundNumber: 2, playerWins: 1, rivalWins: 1),
        isNull,
      );
    });
  });

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

  test(
    'pitch context follows the current resolved player hit, not the rival',
    () {
      final stats = MatchStats();
      addTearDown(stats.dispose);
      stats.onHit(event(FighterId.player, HitKind.hit));
      expect(stats.hitPitchCombo, 1);
      stats.onHit(event(FighterId.player, HitKind.hit));
      expect(stats.hitPitchCombo, 2);
      stats.onHit(event(FighterId.rival, HitKind.whiff));
      expect(stats.combo, 2);
      expect(stats.hitPitchCombo, 0);
      stats.onHit(event(FighterId.player, HitKind.hit));
      expect(stats.hitPitchCombo, 3);
      stats.onHit(event(FighterId.player, HitKind.whiff));
      expect(stats.hitPitchCombo, 0);
      stats.onHit(event(FighterId.player, HitKind.hit));
      expect(stats.hitPitchCombo, 1);
      stats.onHit(event(FighterId.rival, HitKind.hit));
      expect(
        stats.hitPitchCombo,
        0,
        reason: 'the rival never borrows the streak',
      );
      expect(stats.combo, 0);
      stats.onHit(event(FighterId.player, HitKind.hit));
      expect(stats.hitPitchCombo, 1);
      stats.reset();
      expect(stats.hitPitchCombo, 0);
    },
  );

  test('pitch context clears on guards even when a streak survives', () {
    final stats = MatchStats();
    addTearDown(stats.dispose);
    stats.onHit(event(FighterId.player, HitKind.hit));
    stats.onHit(event(FighterId.player, HitKind.hit));
    for (final attacker in FighterId.values) {
      stats.onHit(event(attacker, HitKind.blocked));
      expect(stats.hitPitchCombo, 0);
      expect(stats.combo, 2);
    }
  });

  test('each real combo break gets one serial, including a round ending', () {
    final stats = MatchStats();
    addTearDown(stats.dispose);
    stats.onHit(event(FighterId.player, HitKind.hit));
    stats.onHit(event(FighterId.player, HitKind.whiff));
    expect(
      stats.comboBreakVersion,
      0,
      reason: 'one hit is not a visible combo',
    );
    for (final breaker in [HitKind.whiff, HitKind.hit]) {
      stats.onHit(event(FighterId.player, HitKind.hit));
      stats.onHit(event(FighterId.player, HitKind.hit));
      stats.onHit(
        event(
          breaker == HitKind.whiff ? FighterId.player : FighterId.rival,
          breaker,
        ),
      );
    }
    expect(stats.comboBreakVersion, 2);
    stats.onHit(event(FighterId.player, HitKind.hit));
    stats.onHit(event(FighterId.player, HitKind.hit, ko: true));
    final hits = stats.hitsLanded;
    stats.finishRound();
    expect(stats.comboBreakVersion, 3);
    expect(stats.combo, 0);
    expect(stats.hitPitchCombo, 0);
    expect(stats.hitsLanded, hits);
    expect(stats.maxCombo, 2);
    stats.finishRound();
    expect(
      stats.comboBreakVersion,
      3,
      reason: 'finished frames never replay it',
    );
    stats.reset();
    expect(
      stats.comboBreakVersion,
      3,
      reason: 'rematch reset is not a fake break',
    );
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
