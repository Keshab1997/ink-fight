import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game/audio/fight_sounds.dart';
import '../game/bot/bot_strategy.dart';
import '../game/ink_fight_battle_game.dart';
import '../game/rules/input_command.dart';
import '../game/rules/match_rules.dart';
import '../game/stats/match_stats.dart';
import '../state/ink_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/virtual_joystick.dart';

class BotFightScreen extends StatefulWidget {
  const BotFightScreen({
    super.key,
    this.difficulty = BotDifficulty.normal,
    required this.settings,
    this.sounds,
  });

  /// The preset the practice bot plays on; the menu hands it in, and Normal is
  /// the default the design document asks for (GDD §8).
  final BotDifficulty difficulty;

  /// The app's preferences; the routes table hands in the app's one model.
  /// The screen reads the HAPTICS and SOUND switches off it and keeps the
  /// game's own `hapticsEnabled` and `soundEnabled` flags in sync for as
  /// long as it is alive.
  final InkSettings settings;

  /// The audio seam the game plays through; `null` — the app's own path —
  /// means the real [FlameFightSounds]. Tests hand in a silent or recording
  /// fake so no test ever loads an audio plugin.
  final FightSounds? sounds;

  @override
  State<BotFightScreen> createState() => _BotFightScreenState();
}

class _BotFightScreenState extends State<BotFightScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final InkFightBattleGame _game;

  /// Screen-local frame clock. The HUD rebuilds on `hudVersion`, which only
  /// moves when health, the clock's second, the phase or the outcome moves —
  /// so everything that must ease between those bumps (the health trail, the
  /// countdown beats, the buttons' busy read) rides this ticker instead of
  /// the arena. It carries the ticker's elapsed time, so easing math reads
  /// real frame deltas and tests read fake-async ones. It ticks for the
  /// screen's whole life, paused or not: the listeners below are three tiny
  /// subtrees, never the whole HUD.
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<Duration> _frame = ValueNotifier(Duration.zero);

  /// The pause overlay is up, and the engine is stopped with it: the match,
  /// the bot and the ink all freeze together because `pauseEngine` stops the
  /// one loop that drives them.
  bool _paused = false;

  /// True while a pause the *system* started — backgrounding, a call, the
  /// app switcher — is waiting for the player's choice. On return the fight
  /// does not silently resume: the overlay goes up over the stopped engine
  /// and the player picks RESUME, RESTART or QUIT.
  bool _pausedBySystem = false;

  /// The one-time controls card. It greets every fresh mount of this screen
  /// and stays away after GOT IT — a plain State field on purpose: no
  /// persistence, no settings, no pubspec change.
  bool _showControlsHelp = true;

  @override
  void initState() {
    super.initState();
    _game = InkFightBattleGame(
      botProfile: BotProfile.forDifficulty(widget.difficulty),
      // The app path is the real thing; a test hands in its own seam.
      sounds: widget.sounds ?? const FlameFightSounds(),
    );
    _applyPreferences();
    widget.settings.addListener(_applyPreferences);
    WidgetsBinding.instance.addObserver(this);
    _ticker.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.settings.removeListener(_applyPreferences);
    _ticker.dispose();
    _frame.dispose();
    _game.pauseEngine();
    super.dispose();
  }

  bool _wasFightBeat = false;
  final MatchClockCues _clockCues = MatchClockCues();

  void _onTick(Duration elapsed) {
    _frame.value = elapsed;
    // Flame's simulation ticker may run after this screen's ticker. Sample
    // after paint so this cue sees the exact state the chip/arena just drew,
    // instead of the previous frame (a one-frame-late FIGHT! sting).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final match = _game.match;
      final fightBeat =
          match.phase == MatchPhase.countdown &&
          match.countdownRemainingMs <= match.rules.countdownMs ~/ 4;
      if (fightBeat && !_wasFightBeat && _game.soundEnabled) {
        _game.sounds.play(FightCue.roundSting);
      }
      // Consume muted beats too: enabling sound mid-beat must not cue late.
      // Leaving the beat arms the next rematch. The arena still owns the
      // 3/2/1 blips and the result sting; this screen adds only FIGHT!.
      _wasFightBeat = fightBeat;
      final clockCue = _clockCues.update(match.phase, match.timeRemainingMs);
      if (clockCue != null && _game.soundEnabled) {
        _game.sounds.play(clockCue);
      }
    });
  }

  /// Keeps the game's two cue gates on the model's two switches. The
  /// settings screen can flip either one while this screen sits in the
  /// stack, and the next swing, hit or gong cues — or stays silent and
  /// still — accordingly. Plain field writes on the game, so no setState is
  /// involved: nothing in this widget renders the flags; the platform
  /// channels are what the player notices.
  void _applyPreferences() {
    _game.hapticsEnabled = widget.settings.hapticsOn;
    _game.soundEnabled = widget.settings.soundOn;
  }

  /// The app's lifecycle, as the platform reports it. Losing focus already
  /// freezes a live fight — an incoming call or the app switcher should not
  /// let the round clock run down off-screen — and coming back hands the
  /// choice to the player instead of resuming mid-combo.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _returnFromSystemPause();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _pauseForSystem();
      case AppLifecycleState.detached:
        break; // dispose() stops the engine; there is nothing to choose here
    }
  }

  void _pauseForSystem() {
    // A decided match has nothing left to freeze, and its card must stay
    // uncovered when the player comes back — so no flag, no overlay.
    if (_game.roundEndCardVisible) {
      return;
    }
    // A pause the player opened themselves already has the overlay up; the
    // engine is already stopped and the flag must not hijack the return.
    if (_paused) {
      return;
    }
    _game.pauseEngine();
    _pausedBySystem = true;
  }

  void _returnFromSystemPause() {
    if (!_pausedBySystem) {
      return;
    }
    _pausedBySystem = false;
    // Show the overlay but keep the engine stopped: the round clock neither
    // ran while away nor eats the gap now, and nothing moves until the
    // player taps RESUME, RESTART or QUIT.
    setState(() => _paused = true);
  }

  /// A decided match cannot be paused — the round-end card already owns
  /// REMATCH and the way out.
  void _pause() {
    if (_paused || _game.roundEndCardVisible) {
      return;
    }
    _game.pauseEngine();
    setState(() => _paused = true);
  }

  void _resume() {
    if (!_paused) {
      return;
    }
    _game.resumeEngine();
    setState(() => _paused = false);
  }

  void _restartFromPause() {
    _game.restartMatch();
    _resume();
  }

  /// QUIT TO MENU unwinds the whole arena chain — the fight and the
  /// difficulty picker it was opened from — so the player lands on the menu
  /// the button promises. The never-popping case is the deep-linked arena,
  /// whose route *is* the first one: there is no menu underneath to return
  /// to, and [popUntil] stops immediately rather than emptying the navigator.
  void _quitToMenu() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// System back, one layer at a time: the help card dismisses, the pause
  /// overlay resumes, a decided match leaves like the card's LEAVE button,
  /// and a live fight opens the pause overlay instead of popping to the menu.
  void _onBackGesture(bool didPop) {
    if (didPop) {
      return;
    }
    if (_showControlsHelp) {
      setState(() => _showControlsHelp = false);
      return;
    }
    if (_paused) {
      _resume();
      return;
    }
    if (_game.roundEndCardVisible) {
      Navigator.of(context).pop();
      return;
    }
    _pause();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) => _onBackGesture(didPop),
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: GameWidget(game: _game)),
              Positioned(
                top: 12,
                left: 12,
                child: _RoundIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back to menu',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              Positioned(
                top: 14,
                left: 72,
                right: 72,
                child: _BattleHud(game: _game, tick: _frame),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: ValueListenableBuilder<int>(
                  valueListenable: _game.hudVersion,
                  // Hidden once the round-end card is up: a decided match
                  // cannot be paused.
                  builder: (context, _, _) => _game.roundEndCardVisible
                      ? const SizedBox.shrink()
                      : _RoundIconButton(
                          icon: Icons.pause_rounded,
                          tooltip: 'Pause the match',
                          onTap: _pause,
                        ),
                ),
              ),
              Positioned.fill(
                child: ValueListenableBuilder<int>(
                  valueListenable: _game.hudVersion,
                  // The card waits for the arena: a knockout plays its
                  // slow-motion and frozen beat first (GAME_FEEL §5), a match
                  // the clock decided stamps in at once.
                  builder: (context, _, _) => _game.roundEndCardVisible
                      ? _RoundEndCard(game: _game, onLeave: _quitToMenu)
                      : const SizedBox.shrink(),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: _BattleControls(
                  onPunch: () => _game.sendPlayerAction(InputAction.lightPunch),
                  onKick: () => _game.sendPlayerAction(InputAction.heavyKick),
                  onBlock: () => _game.sendPlayerAction(InputAction.block),
                  onJump: () => _game.sendPlayerAction(InputAction.jump),
                  onMoveAxis: _game.setPlayerMoveAxis,
                  game: _game,
                  tick: _frame,
                ),
              ),
              if (_paused)
                Positioned.fill(
                  child: _PauseOverlay(
                    onResume: _resume,
                    onRestart: _restartFromPause,
                    onQuit: _quitToMenu,
                    onControls: () => setState(() => _showControlsHelp = true),
                  ),
                ),
              if (_showControlsHelp)
                Positioned.fill(
                  child: _ControlsHelpCard(
                    onDismiss: () => setState(() => _showControlsHelp = false),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BattleHud extends StatelessWidget {
  const _BattleHud({required this.game, required this.tick});

  final InkFightBattleGame game;

  /// The screen ticker: the chip's beats and the bars' trails ride it (see
  /// [_TimerChip] and [_HudHealth]), while the row itself still rebuilds on
  /// `hudVersion` only.
  final ValueListenable<Duration> tick;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: game.hudVersion,
      builder: (context, _, _) {
        final rules = game.match.rules;
        final player = game.match.stateOf(FighterId.player);
        final rival = game.match.stateOf(FighterId.rival);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ListenableBuilder(
                listenable: game.stats,
                builder: (context, _) => _HudHealth(
                  label: 'YOU',
                  value: player.health / rules.health,
                  tick: tick,
                  combo: game.match.isFinished ? 0 : game.stats.combo,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // The only corner of the HUD on the frame clock: the beats fall
            // between hudVersion bumps, so the chip repaints them itself.
            ListenableBuilder(
              listenable: tick,
              builder: (context, _) => _TimerChip(game: game),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _HudHealth(
                label: 'CRIMSON RIVAL',
                value: rival.health / rules.health,
                tick: tick,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The clock between the health bars: the countdown's beat while the match
/// counts in, the round clock while it fights, `END` once decided.
///
/// The beat split is the screen's own four-count, but the length it splits
/// comes from the rules — never a hardcoded 2000.
class _TimerChip extends StatelessWidget {
  const _TimerChip({required this.game});

  final InkFightBattleGame game;

  /// Beats in the countdown: 3 · 2 · 1 · FIGHT!.
  static const int _countdownBeats = 4;

  /// FIGHT! strobes this many times across its beat, on sim time, so a
  /// paused countdown holds its flash instead of blinking behind glass.
  static const int _fightBlinksPerBeat = 4;

  /// The dim half of the FIGHT! strobe.
  static const double _fightFlashDim = .45;

  @override
  Widget build(BuildContext context) {
    final match = game.match;
    var label = 'END';
    var opacity = 1.0;
    if (match.phase == MatchPhase.countdown) {
      final beatMs = match.rules.countdownMs ~/ _countdownBeats;
      final index = ((match.countdownRemainingMs - 1) ~/ beatMs).clamp(
        0,
        _countdownBeats - 1,
      );
      label = switch (index) {
        3 => '3',
        2 => '2',
        1 => '1',
        _ => 'FIGHT!',
      };
      if (index == 0) {
        final blinkMs = beatMs ~/ _fightBlinksPerBeat;
        opacity = ((match.countdownRemainingMs ~/ blinkMs) % 2 == 0)
            ? 1.0
            : _fightFlashDim;
      }
    } else if (!match.isFinished) {
      final totalSeconds = (match.timeRemainingMs / 1000).ceil();
      final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
      final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
      label = '$minutes : $seconds';
    }
    final urgent =
        match.phase == MatchPhase.fighting &&
        match.timeRemainingMs > 0 &&
        match.timeRemainingMs <= 10000;
    // Slow, restrained tint, driven by sim time: pauses hold their pulse.
    // No size/position motion and no full-white flash near the health bars.
    final pulse =
        .28 +
        .12 * math.cos(2 * math.pi * (10000 - match.timeRemainingMs) / 1600);
    return Container(
      key: const ValueKey('timer-chip-plate'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: urgent
            ? Color.lerp(InkColors.ink, const Color(0xFFC51F3A), pulse)
            : InkColors.ink,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Opacity(
        opacity: opacity,
        child: Text(
          label,
          style: const TextStyle(
            color: InkColors.white,
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

/// The decided-match card: outcome, a rematch, and the way out.
class _RoundEndCard extends StatelessWidget {
  const _RoundEndCard({required this.game, required this.onLeave});

  final InkFightBattleGame game;

  /// What LEAVE does. The screen hands in its QUIT TO MENU helper, so both
  /// ways out of a finished match unwind the whole arena chain and land the
  /// player on the menu — not on the difficulty picker the fight was opened
  /// from.
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final label = switch (game.match.outcome) {
      MatchOutcome.playerWin => 'YOU WIN',
      MatchOutcome.rivalWin => 'CRIMSON RIVAL WINS',
      MatchOutcome.draw || null => 'DRAW',
    };
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, progress, child) => ColoredBox(
        color: InkColors.ink.withValues(alpha: .38 * progress),
        child: Center(
          child: Opacity(
            key: const ValueKey('round-end-stamp-opacity'),
            opacity: progress,
            child: Transform.scale(
              key: const ValueKey('round-end-stamp-scale'),
              scale: 1.06 - .06 * progress,
              child: child,
            ),
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
        decoration: BoxDecoration(
          color: InkColors.white,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: InkColors.ink, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 44,
              height: 4,
              child: ColoredBox(color: Color(0xFFC51F3A)),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                color: InkColors.ink,
                fontSize: 19,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            _ResultStats(stats: game.stats),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  color: InkColors.ink,
                  borderRadius: BorderRadius.circular(13),
                  child: InkWell(
                    onTap: game.restartMatch,
                    borderRadius: BorderRadius.circular(13),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 11,
                      ),
                      child: Text(
                        'REMATCH',
                        style: TextStyle(
                          color: InkColors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Material(
                  color: InkColors.white,
                  borderRadius: BorderRadius.circular(13),
                  child: InkWell(
                    onTap: onLeave,
                    borderRadius: BorderRadius.circular(13),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 11,
                      ),
                      child: Text(
                        'LEAVE',
                        style: TextStyle(
                          color: InkColors.inkSoft,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Whole-match player totals, not the final streak or the rival's blocks.
class _ResultStats extends StatelessWidget {
  const _ResultStats({required this.stats});
  final MatchStats stats;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 252,
      child: Row(
        children: [
          for (final entry in <String, int>{
            'HITS LANDED': stats.hitsLanded,
            'BLOCKS': stats.blocks,
            'MAX COMBO': stats.maxCombo,
          }.entries)
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${entry.value}',
                    key: ValueKey('result-${entry.key}'),
                    style: const TextStyle(
                      color: InkColors.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        color: InkColors.inkSoft,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A small stamp contained in the player's existing label row. It never
/// floats over the readable fill or enters the fighters' canvas space.
class _ComboStamp extends StatelessWidget {
  const _ComboStamp({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('combo-$count'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, progress, child) => Opacity(
        key: const ValueKey('combo-opacity'),
        opacity: progress,
        child: Transform.scale(
          key: const ValueKey('combo-scale'),
          scale: 1.06 - .06 * progress,
          child: child,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: const BoxDecoration(color: InkColors.ink),
        child: Text(
          '$count HITS',
          style: const TextStyle(
            color: InkColors.white,
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: .5,
          ),
        ),
      ),
    );
  }
}

/// The dialog vocabulary the pause and help overlays share with
/// [_RoundEndCard]: ink wash over the arena, a white panel on a thin line.
/// The full-screen gesture absorber keeps stray taps off the controls and
/// the canvas underneath — dialogs close through their own buttons only.
class _InkDialog extends StatelessWidget {
  const _InkDialog({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: ColoredBox(
        color: InkColors.ink.withValues(alpha: .38),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Container(
              padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
              decoration: BoxDecoration(
                color: InkColors.white,
                borderRadius: BorderRadius.circular(19),
                border: Border.all(color: InkColors.line),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: children),
            ),
          ),
        ),
      ),
    );
  }
}

/// One dialog action row, in the round-end card's button language.
class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 216,
      child: Material(
        color: primary ? InkColors.ink : InkColors.white,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: primary ? InkColors.ink : InkColors.line,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: primary ? InkColors.white : InkColors.inkSoft,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The paused fight: resume, restart, read the controls, or leave. The
/// round-end card's REMATCH and LEAVE are deliberately not duplicated here —
/// a decided match never reaches this overlay.
class _PauseOverlay extends StatelessWidget {
  const _PauseOverlay({
    required this.onResume,
    required this.onRestart,
    required this.onQuit,
    required this.onControls,
  });

  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onQuit;
  final VoidCallback onControls;

  @override
  Widget build(BuildContext context) {
    return _InkDialog(
      children: [
        const Text(
          'PAUSED',
          style: TextStyle(
            color: InkColors.ink,
            fontSize: 19,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        _DialogButton(label: 'RESUME', onTap: onResume, primary: true),
        const SizedBox(height: 10),
        _DialogButton(label: 'RESTART', onTap: onRestart),
        const SizedBox(height: 10),
        _DialogButton(label: 'CONTROLS', onTap: onControls),
        const SizedBox(height: 10),
        _DialogButton(label: 'QUIT TO MENU', onTap: onQuit),
      ],
    );
  }
}

/// The one-time greeting for the new controls: what the joystick does and
/// what the four buttons are. The lines are single strings on purpose, so
/// the card never doubles the arena's own PUNCH / KICK labels for finders.
class _ControlsHelpCard extends StatelessWidget {
  const _ControlsHelpCard({required this.onDismiss});

  final VoidCallback onDismiss;

  static const TextStyle _line = TextStyle(
    color: InkColors.inkSoft,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: .4,
    height: 1.45,
  );

  @override
  Widget build(BuildContext context) {
    return _InkDialog(
      children: [
        const Text(
          'CONTROLS',
          style: TextStyle(
            color: InkColors.ink,
            fontSize: 19,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'DRAG the joystick left / right to retreat and advance.',
          style: _line,
        ),
        const SizedBox(height: 8),
        const Text('PUSH the joystick up to jump.', style: _line),
        const SizedBox(height: 8),
        const Text(
          'The four buttons are PUNCH / KICK / BLOCK / JUMP.',
          style: _line,
        ),
        const SizedBox(height: 18),
        _DialogButton(label: 'GOT IT', onTap: onDismiss, primary: true),
      ],
    );
  }
}

/// One health bar: the label and the number snap, the bar itself remembers.
///
/// Two layers: the crisp bar jumps to the new value at once, and a damage
/// trail behind it eases down over ~250 ms so the eye reads how much just
/// went missing, plus a white flash on the drop. The easing rides [tick] —
/// the screen's own frame clock — and both layers are pure paint over
/// `value`. Ticker time finishes the drain even while the engine is paused.
class _HudHealth extends StatefulWidget {
  const _HudHealth({
    required this.label,
    required this.value,
    required this.tick,
    this.combo = 0,
  });

  final String label;
  final int combo;
  final double value;
  final ValueListenable<Duration> tick;

  /// Finite, monotone drain: exact at the live edge before the KO card.
  static const double _trailDurationMs = 260;

  /// Flash decay time constant: visibly gone in ~200 ms.
  static const double _flashTauMs = 70;

  /// Peak opacity of the white wash on a drop.
  static const double _flashPeak = .5;

  /// Close enough to settled that the bar snaps exact and holds still.
  static const double _snapEpsilon = .001;

  static const double _barHeight = 6;

  @override
  State<_HudHealth> createState() => _HudHealthState();
}

class _HudHealthState extends State<_HudHealth> {
  late double _trail;
  late double _trailStart;
  double _trailElapsedMs = _HudHealth._trailDurationMs;
  double _flash = 0;
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _trail = widget.value;
    _trailStart = _trail;
    _lastTick = widget.tick.value;
    widget.tick.addListener(_onTick);
  }

  @override
  void didUpdateWidget(covariant _HudHealth oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tick != widget.tick) {
      oldWidget.tick.removeListener(_onTick);
      _lastTick = widget.tick.value;
      widget.tick.addListener(_onTick);
    }
    if (widget.value < oldWidget.value) {
      // Damage: the crisp bar snaps, the trail keeps the old edge, the bar
      // flashes.
      _flash = 1;
      _trailStart = math.max(_trail, widget.value);
      _trailElapsedMs = 0;
    } else if (widget.value > oldWidget.value) {
      // Healing (a rematch): nothing was lost, so there is no trail to run.
      _trail = widget.value;
      _trailStart = _trail;
      _trailElapsedMs = _HudHealth._trailDurationMs;
      _flash = 0;
    }
  }

  @override
  void dispose() {
    widget.tick.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    final elapsed = widget.tick.value;
    final dtMs = (elapsed - _lastTick).inMicroseconds / 1000;
    _lastTick = elapsed;
    if (dtMs <= 0) {
      return;
    }
    final target = widget.value;
    _trailElapsedMs = math.min(
      _HudHealth._trailDurationMs,
      _trailElapsedMs + dtMs,
    );
    final progress = _trailElapsedMs / _HudHealth._trailDurationMs;
    // Never a spring: interpolation cannot cross below the live bar, and
    // at t=1 the endpoint is assigned exactly, including a KO's zero.
    final trail = progress >= 1
        ? target
        : (_trailStart +
                  (target - _trailStart) *
                      Curves.easeOutCubic.transform(progress))
              .clamp(target, 1.0);
    final faded = _flash * math.exp(-dtMs / _HudHealth._flashTauMs);
    final flash = faded < _HudHealth._snapEpsilon ? 0.0 : faded;
    if (_trail == trail && _flash == flash) {
      return;
    }
    setState(() {
      _trail = trail;
      _flash = flash;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      decoration: BoxDecoration(
        color: InkColors.white.withValues(alpha: .78),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: InkColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // The rival's name is long and the bar is narrow on small
              // windows: the label scales down to fit (the home screen's
              // FittedBox discipline) instead of pushing the number out.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    height: 18,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.label,
                          maxLines: 1,
                          style: const TextStyle(
                            color: InkColors.inkSoft,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                          ),
                        ),
                        if (widget.combo >= 2) ...[
                          const SizedBox(width: 6),
                          _ComboStamp(count: widget.combo),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Text(
                '${(widget.value * 100).round()}%',
                style: const TextStyle(
                  color: InkColors.muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: _HudHealth._barHeight,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // The trail: where the bar was a quarter-second ago.
                  LinearProgressIndicator(
                    value: _trail,
                    backgroundColor: InkColors.paperDeep,
                    color: InkColors.inkSoft,
                  ),
                  // The truth, snapped: a transparent track so the trail
                  // shows through the segment that just went missing.
                  LinearProgressIndicator(
                    key: ValueKey('health-live-${widget.label}'),
                    value: widget.value,
                    backgroundColor: Colors.transparent,
                    color: InkColors.ink,
                  ),
                  // The flash: a white wash that dies with _flash.
                  Opacity(
                    opacity: _flash * _HudHealth._flashPeak,
                    child: const ColoredBox(color: InkColors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BattleControls extends StatelessWidget {
  const _BattleControls({
    required this.onPunch,
    required this.onKick,
    required this.onBlock,
    required this.onJump,
    required this.onMoveAxis,
    required this.game,
    required this.tick,
  });

  final VoidCallback onPunch;
  final VoidCallback onKick;
  final VoidCallback onBlock;
  final VoidCallback onJump;

  /// The joystick's -1 … +1: back and forth along the arena line. Its upward
  /// flick shares [onJump] with the button.
  final ValueChanged<double> onMoveAxis;

  /// Read-only: the buttons ask the rules whether the player can act, so the
  /// busy state is a report, never a guess the screen keeps itself.
  final InkFightBattleGame game;

  /// The screen ticker; only the action buttons ride it (see below).
  final ValueListenable<Duration> tick;

  /// The touch budget of one action button; never smaller than the old row.
  static const double _actionWidth = 78;
  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // One row wants the joystick, a breathing gap and all four 78 dp
        // buttons (~464 dp). A window too narrow for that — 360 dp wide —
        // stacks the buttons into a 2×2 grid on the right instead: the
        // targets never shrink, the row just folds.
        final wantsRow =
            constraints.maxWidth >=
            VirtualJoystick.defaultSize + 24 + 4 * _actionWidth + 3 * _gap;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _ArenaStatus(label: 'BOT FIGHT / PRACTICE'),
                const SizedBox(height: _gap),
                VirtualJoystick(onAxisChanged: onMoveAxis, onJump: onJump),
              ],
            ),
            const Spacer(),
            // Only the buttons ride the ticker: whether the player can act
            // is a per-frame read of the rules, and nothing else down here
            // moves that fast. The joystick keeps its own spring.
            ListenableBuilder(
              listenable: tick,
              builder: (context, _) {
                final busy = !game.match.stateOf(FighterId.player).canAct;
                final actions = <Widget>[
                  _ControlButton(
                    label: 'PUNCH',
                    icon: Icons.bolt_rounded,
                    onTap: onPunch,
                    primary: true,
                    busy: busy,
                  ),
                  _ControlButton(
                    label: 'KICK',
                    icon: Icons.sports_martial_arts_rounded,
                    onTap: onKick,
                    busy: busy,
                  ),
                  _ControlButton(
                    label: 'BLOCK',
                    icon: Icons.shield_outlined,
                    onTap: onBlock,
                    busy: busy,
                  ),
                  _ControlButton(
                    label: 'JUMP',
                    icon: Icons.north_rounded,
                    onTap: onJump,
                    busy: busy,
                  ),
                ];
                if (wantsRow) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: _gap),
                        actions[i],
                      ],
                    ],
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        actions[0],
                        const SizedBox(width: _gap),
                        actions[1],
                      ],
                    ),
                    const SizedBox(height: _gap),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        actions[2],
                        const SizedBox(width: _gap),
                        actions[3],
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// One action button: idle, pressed, and busy.
///
/// Pressed answers the finger at once: an ink fill and a small scale, from
/// the button's own tapped state. Busy is quieter: the row hands in whether
/// the player can act (a per-frame read of the rules), and a committed
/// fighter's buttons sit dimmed. Busy never eats the tap — the controller
/// already drops what it cannot take, so the button reports instead of
/// deciding.
class _ControlButton extends StatefulWidget {
  const _ControlButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
  final bool busy;

  /// Pressed scale: a small give under the finger.
  static const double _pressedScale = .93;

  /// Busy dim: quiet, still legible.
  static const double _busyOpacity = .55;

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final background = widget.primary ? InkColors.ink : InkColors.white;
    final pressedBackground = widget.primary
        ? InkColors.inkSoft
        : InkColors.paperDeep;
    final foreground = widget.primary ? InkColors.white : InkColors.inkSoft;

    return Opacity(
      opacity: widget.busy ? _ControlButton._busyOpacity : 1,
      child: Transform.scale(
        scale: _pressed ? _ControlButton._pressedScale : 1,
        child: Material(
          color: _pressed ? pressedBackground : background,
          borderRadius: BorderRadius.circular(15),
          child: InkWell(
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            borderRadius: BorderRadius.circular(15),
            child: Container(
              width: 78,
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: widget.primary ? InkColors.ink : InkColors.line,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, color: foreground, size: 19),
                  const SizedBox(height: 3),
                  Text(
                    widget.label,
                    maxLines: 1,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: InkColors.ink,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, color: InkColors.white),
          ),
        ),
      ),
    );
  }
}

class _ArenaStatus extends StatelessWidget {
  const _ArenaStatus({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: InkColors.white.withValues(alpha: .78),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: InkColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        child: Text(
          label,
          style: const TextStyle(
            color: InkColors.inkSoft,
            fontSize: 8,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}
