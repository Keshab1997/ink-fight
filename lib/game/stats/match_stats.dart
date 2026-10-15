import 'package:flutter/foundation.dart';

import '../audio/fight_sounds.dart';
import '../rules/match_controller.dart';
import '../rules/match_rules.dart';

/// Player-perspective presentation totals. Observes resolved events exactly
/// once at the arena's drain; never drains the controller or changes a rule.
class MatchStats extends ChangeNotifier {
  int _hitsLanded = 0;
  int _blocks = 0;
  int _combo = 0;
  int _maxCombo = 0;
  int _hitPitchCombo = 0;
  int _comboBreakVersion = 0;

  int get hitsLanded => _hitsLanded;

  /// Successful guards by the player, not attacks the rival blocked.
  int get blocks => _blocks;
  int get combo => _combo;
  int get maxCombo => _maxCombo;

  /// Context for the cue immediately following onHit in the arena's drain.
  /// Never lends the player's streak to a rival's hit or a blocked/whiff cue.
  int get hitPitchCombo => _hitPitchCombo;

  /// Monotone event serial: catches even a break/rebuild within one sim
  /// frame. Muting consumes the serial rather than replaying it later.
  int get comboBreakVersion => _comboBreakVersion;

  void onHit(HitEvent event) {
    _hitPitchCombo = 0;
    var changed = false;
    if (event.kind == HitKind.hit && event.attacker == FighterId.player) {
      _hitsLanded++;
      _combo++;
      _hitPitchCombo = _combo;
      if (_combo > _maxCombo) {
        _maxCombo = _combo;
      }
      changed = true;
    } else if ((event.kind == HitKind.whiff &&
            event.attacker == FighterId.player) ||
        (event.kind == HitKind.hit && event.defender == FighterId.player)) {
      changed = _combo != 0;
      _breakCombo();
    } else if (event.kind == HitKind.blocked &&
        event.defender == FighterId.player) {
      _blocks++;
      changed = true;
    }
    // A guard isn't a clean hit taken; a rival whiff doesn't break the
    // player's run. Only the requested whiff/hit-taken boundaries reset it.
    if (changed) {
      notifyListeners();
    }
  }

  void _breakCombo() {
    // The visible combo begins at two hits; a lone jab isn't an unravel.
    if (_combo >= 2) _comboBreakVersion++;
    _combo = 0;
    _hitPitchCombo = 0;
  }

  /// Presentation-only round boundary. Lifetime totals survive for the card.
  void finishRound() {
    if (_combo == 0) return;
    _breakCombo();
    notifyListeners();
  }

  void reset() {
    _hitsLanded = 0;
    _blocks = 0;
    _combo = 0;
    _maxCombo = 0;
    _hitPitchCombo = 0;
    notifyListeners();
  }
}

/// Screen-owned clock feedback. Consume each displayed second once, even
/// while muted; pauses hold sim time, rematches re-arm on their countdown.
/// Skipped seconds never queue a catch-up burst of sounds.
class MatchClockCues {
  int? _lastSecond;

  FightCue? update(MatchPhase phase, int remainingMs) {
    if (phase != MatchPhase.fighting) {
      _lastSecond = null;
      return null;
    }
    final second = (remainingMs / 1000).ceil();
    if (second == _lastSecond) {
      return null;
    }
    _lastSecond = second;
    if (second <= 0 || second > 10) {
      return null;
    }
    // One cue, never a tick plus a blip at the 3/2/1 boundary.
    return second <= 3 ? FightCue.countdownBlip : FightCue.clockTick;
  }
}

/// A presentation snapshot, never a rules decision or a HUD-owned round count.
class RoundResult {
  const RoundResult({required this.number, required this.outcome});
  final int number;
  final MatchOutcome outcome;
}

/// Reads consecutive authoritative score snapshots to describe the round that
/// just closed. Never advances a round, awards wins, or delays a countdown.
/// If observation skips rounds, show nothing rather than inventing a result.
class RoundResultTracker {
  ({int roundNumber, int playerWins, int rivalWins})? _previous;
  RoundResult? _result;

  RoundResult? observe({
    required int roundNumber,
    required int playerWins,
    required int rivalWins,
  }) {
    final previous = _previous;
    _previous = (
      roundNumber: roundNumber,
      playerWins: playerWins,
      rivalWins: rivalWins,
    );
    if (roundNumber == 1 || previous == null) {
      return _result = null;
    }
    if (roundNumber == previous.roundNumber) return _result;
    _result = null;
    if (roundNumber != previous.roundNumber + 1) return null;
    final playerDelta = playerWins - previous.playerWins;
    final rivalDelta = rivalWins - previous.rivalWins;
    final outcome = switch ((playerDelta, rivalDelta)) {
      (1, 0) => MatchOutcome.playerWin,
      (0, 1) => MatchOutcome.rivalWin,
      (0, 0) => MatchOutcome.draw,
      _ => null,
    };
    if (outcome != null) {
      _result = RoundResult(number: previous.roundNumber, outcome: outcome);
    }
    return _result;
  }
}
