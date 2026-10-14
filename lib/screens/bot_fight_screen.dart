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

class _BotFightScreenState extends State<BotFightScreen> {
  late final InkFightBattleGame _game;

  /// The pause overlay is up, and the engine is stopped with it: the match,
  /// the bot and the ink all freeze together because `pauseEngine` stops the
  /// one loop that drives them.
  bool _paused = false;

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
  }

  @override
  void dispose() {
    _game.pauseEngine();
    super.dispose();
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

class _HudHealth extends StatelessWidget {
  const _HudHealth({required this.label, required this.value});

  final String label;
  final double value;

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
              Text(
                label,
                style: const TextStyle(
                  color: InkColors.inkSoft,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              Text(
                '${(value * 100).round()}%',
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
            child: LinearProgressIndicator(
              minHeight: 6,
              value: value,
              backgroundColor: InkColors.paperDeep,
              color: InkColors.ink,
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
  });

  final VoidCallback onPunch;
  final VoidCallback onKick;
  final VoidCallback onBlock;
  final VoidCallback onJump;

  /// The joystick's -1 … +1: back and forth along the arena line. Its upward
  /// flick shares [onJump] with the button.
  final ValueChanged<double> onMoveAxis;

  /// The touch budget of one action button; never smaller than the old row.
  static const double _actionWidth = 78;
  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      _ControlButton(
        label: 'PUNCH',
        icon: Icons.bolt_rounded,
        onTap: onPunch,
        primary: true,
      ),
      _ControlButton(
        label: 'KICK',
        icon: Icons.sports_martial_arts_rounded,
        onTap: onKick,
      ),
      _ControlButton(
        label: 'BLOCK',
        icon: Icons.shield_outlined,
        onTap: onBlock,
      ),
      _ControlButton(label: 'JUMP', icon: Icons.north_rounded, onTap: onJump),
    ];

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
            if (wantsRow)
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: _gap),
                actions[i],
              ]
            else
              Column(
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
              ),
          ],
        );
      },
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final background = primary ? InkColors.ink : InkColors.white;
    final foreground = primary ? InkColors.white : InkColors.inkSoft;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          width: 78,
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: primary ? InkColors.ink : InkColors.line),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foreground, size: 19),
              const SizedBox(height: 3),
              Text(
                label,
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
