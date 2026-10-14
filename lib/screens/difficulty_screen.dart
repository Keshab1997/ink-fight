import 'package:flutter/material.dart';

import '../game/bot/bot_strategy.dart';
import '../theme/app_theme.dart';
import '../widgets/ink_back_button.dart';
import 'app_routes.dart';

/// The bot-fight picker: three rows, one per practice preset, in the same ink
/// sheet style as the settings screen.
///
/// Tapping a row pushes the arena with that [BotDifficulty] as the route
/// argument. The one-liners are the design document's bot descriptions
/// (docs/product/GAME_DESIGN_DOCUMENT.md §8), and Normal is marked as the
/// recommended default.
class DifficultyScreen extends StatelessWidget {
  const DifficultyScreen({super.key});

  static const _choices = <_Choice>[
    _Choice(
      difficulty: BotDifficulty.easy,
      label: 'EASY',
      blurb: 'slower reaction, fewer attacks, visible openings',
    ),
    _Choice(
      difficulty: BotDifficulty.normal,
      label: 'NORMAL',
      blurb: 'blocks occasionally, approaches, attacks after a clear cue',
      recommended: true,
    ),
    _Choice(
      difficulty: BotDifficulty.hard,
      label: 'HARD',
      blurb: 'better timing and spacing, still has recoverable patterns',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Header(),
              const SizedBox(height: 12),
              Expanded(
                child: Column(
                  children: [
                    for (var i = 0; i < _choices.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      Expanded(child: _DifficultyRow(choice: _choices[i])),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Choice {
  const _Choice({
    required this.difficulty,
    required this.label,
    required this.blurb,
    this.recommended = false,
  });

  final BotDifficulty difficulty;
  final String label;
  final String blurb;
  final bool recommended;
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const InkBackButton(),
        const SizedBox(width: 14),
        const Text(
          'CHOOSE DIFFICULTY',
          style: TextStyle(
            color: InkColors.ink,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.6,
          ),
        ),
        const Spacer(),
        Text(
          'BOT FIGHT / PRACTICE',
          style: TextStyle(
            color: InkColors.muted.withValues(alpha: .9),
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

class _DifficultyRow extends StatelessWidget {
  const _DifficultyRow({required this.choice});

  final _Choice choice;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: InkColors.white.withValues(alpha: .78),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () =>
            Navigator.of(context)
                .pushNamed(InkRoutes.botFight, arguments: choice.difficulty),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: choice.recommended ? InkColors.ink : InkColors.line,
              width: choice.recommended ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          choice.label,
                          style: const TextStyle(
                            color: InkColors.ink,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.4,
                          ),
                        ),
                        if (choice.recommended) ...[
                          const SizedBox(width: 12),
                          const _RecommendedTag(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      choice.blurb,
                      style: const TextStyle(
                        color: InkColors.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.arrow_forward_rounded, color: InkColors.ink),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecommendedTag extends StatelessWidget {
  const _RecommendedTag();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: InkColors.ink,
        borderRadius: BorderRadius.circular(99),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Text(
          'RECOMMENDED',
          style: TextStyle(
            color: InkColors.white,
            fontSize: 8,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}
