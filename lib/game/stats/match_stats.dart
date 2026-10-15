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

  int get hitsLanded => _hitsLanded;

  /// Successful guards by the player, not attacks the rival blocked.
  int get blocks => _blocks;
  int get combo => _combo;
  int get maxCombo => _maxCombo;

  void onHit(HitEvent event) {
    var changed = false;
    if (event.kind == HitKind.hit && event.attacker == FighterId.player) {
      _hitsLanded++;
      _combo++;
      if (_combo > _maxCombo) {
        _maxCombo = _combo;
      }
      changed = true;
    } else if ((event.kind == HitKind.whiff &&
            event.attacker == FighterId.player) ||
        (event.kind == HitKind.hit && event.defender == FighterId.player)) {
      changed = _combo != 0;
      _combo = 0;
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

  void reset() {
    _hitsLanded = 0;
    _blocks = 0;
    _combo = 0;
    _maxCombo = 0;
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
