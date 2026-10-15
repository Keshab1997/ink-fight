import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../game/bot/bot_strategy.dart';
import '../game/ink_fight_battle_game.dart';
import '../game/rules/input_command.dart';
import '../game/rules/match_rules.dart';
import '../theme/app_theme.dart';
import '../widgets/virtual_joystick.dart';

class BotFightScreen extends StatefulWidget {
  const BotFightScreen({super.key, this.difficulty = BotDifficulty.normal});

  /// The preset the practice bot plays on; the menu hands it in, and Normal is
  /// the default the design document asks for (GDD §8).
  final BotDifficulty difficulty;

  @override
  State<BotFightScreen> createState() => _BotFightScreenState();
}

class _BotFightScreenState extends State<BotFightScreen>
    with WidgetsBindingObserver {
  late final InkFightBattleGame _game;

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
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _game.pauseEngine();
    super.dispose();
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
                child: _BattleHud(game: _game),
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
                      ? _RoundEndCard(game: _game)
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
                ),
              ),
              if (_paused)
                Positioned.fill(
                  child: _PauseOverlay(
                    onResume: _resume,
                    onRestart: _restartFromPause,
                    onQuit: () => Navigator.of(context).pop(),
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
  const _BattleHud({required this.game});

  final InkFightBattleGame game;

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
              child: _HudHealth(
                label: 'YOU',
                value: player.health / rules.health,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: InkColors.ink,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Text(
                _timerLabel(),
                style: const TextStyle(
                  color: InkColors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _HudHealth(
                label: 'CRIMSON RIVAL',
                value: rival.health / rules.health,
              ),
            ),
          ],
        );
      },
    );
  }

  String _timerLabel() {
    final match = game.match;
    if (match.phase == MatchPhase.countdown) {
      return 'READY';
    }
    if (match.isFinished) {
      return 'END';
    }
    final totalSeconds = (match.timeRemainingMs / 1000).ceil();
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes : $seconds';
  }
}

/// The decided-match card: outcome, a rematch, and the way out.
class _RoundEndCard extends StatelessWidget {
  const _RoundEndCard({required this.game});

  final InkFightBattleGame game;

  @override
  Widget build(BuildContext context) {
    final label = switch (game.match.outcome) {
      MatchOutcome.playerWin => 'YOU WIN',
      MatchOutcome.rivalWin => 'CRIMSON RIVAL WINS',
      MatchOutcome.draw || null => 'DRAW',
    };
    return ColoredBox(
      color: InkColors.ink.withValues(alpha: .38),
      child: Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
          decoration: BoxDecoration(
            color: InkColors.white,
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: InkColors.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: InkColors.ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
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
                      onTap: () => Navigator.of(context).pop(),
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
  final VoidCallba