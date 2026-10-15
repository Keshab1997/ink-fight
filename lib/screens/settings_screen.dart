import 'package:flutter/material.dart';

import '../state/ink_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/ink_back_button.dart';

/// Settings, in the ink palette: a paper sheet with two panels, a working sound
/// switch, and the small print about the build.
///
/// The screen is reachable two ways — the home menu's SETTINGS button and the
/// web deep link `#/settings` — and both land on this one route, so the back
/// button has somewhere to return to either way.
///
/// [settings] is the app's one preference model, handed in by the routes
/// table: both rows read and write it directly, so what a switch shows is
/// what the model says — even after leaving and coming back. Nothing local
/// lives here: no preference setState, no placeholder field. HAPTICS is a
/// real control now: its switch drives `hapticsEnabled` on the fight
/// screen's game, the flag behind the arena's vibrate-on-impact cues.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.settings});

  final InkSettings settings;

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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 5,
                      child: _Panel(
                        title: 'AUDIO / HAPTICS',
                        child: Column(
                          children: [
                            ListenableBuilder(
                              listenable: settings,
                              builder: (context, _) => Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _ToggleRow(
                                    label: 'SOUND',
                                    caption: 'HIT CUES AND UI TAPS',
                                    value: settings.soundOn,
                                    onChanged: (value) =>
                                        settings.soundOn = value,
                                  ),
                                  const SizedBox(height: 10),
                                  // Audio and haptics are independent
                                  // settings (design document): the arena
                                  // reads this one through its game's
                                  // `hapticsEnabled` flag, which the fight
                                  // screen keeps in sync with the model.
                                  _ToggleRow(
                                    label: 'HAPTICS',
                                    caption: 'INDEPENDENT FROM SOUND',
                                    value: settings.hapticsOn,
                                    onChanged: (value) =>
                                        settings.hapticsOn = value,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      flex: 4,
                      child: _Panel(
                        title: 'ABOUT',
                        child: Column(
                          children: [
                            _StaticRow(
                              label: 'CREDITS',
                              caption: 'Keshab Studios',
                            ),
                            SizedBox(height: 10),
                            _StaticRow(
                              label: 'VERSION',
                              caption: _buildVersion,
                            ),
                            SizedBox(height: 10),
                            _StaticRow(
                              label: 'MODE',
                              caption: 'BOT FIGHT / PRACTICE',
                            ),
                          ],
                        ),
                      ),
                    ),
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

/// Kept in step with `version:` in pubspec.yaml by hand — reading it at runtime
/// needs a dependency, and this screen is not worth a package yet.
const _buildVersion = '1.0.0+1';

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const InkBackButton(),
        const SizedBox(width: 14),
        const Text(
          'SETTINGS',
          style: TextStyle(
            color: InkColors.ink,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.6,
          ),
        ),
        const Spacer(),
        Text(
          'SAVED FOR THIS SESSION ONLY',
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

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: InkColors.white.withValues(alpha: .78),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: InkColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: InkColors.muted,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.caption,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String caption;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      label: label,
      caption: caption,
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Switch(
            value: value,
            onChanged: onChanged,
            thumbColor: const WidgetStatePropertyAll(InkColors.white),
            trackColor: WidgetStatePropertyAll(
              value ? InkColors.ink : InkColors.paperDeep,
            ),
            trackOutlineColor: const WidgetStatePropertyAll(InkColors.line),
          ),
          Text(
            value ? 'ON' : 'OFF',
            style: const TextStyle(
              color: InkColors.inkSoft,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _StaticRow extends StatelessWidget {
  const _StaticRow({required this.label, required this.caption});

  final String label;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return _RowShell(label: label, caption: caption);
  }
}

/// The one shape both row kinds share: label on the left, something on the
/// right, caption underneath.
class _RowShell extends StatelessWidget {
  const _RowShell({required this.label, required this.caption, this.trailing});

  final String label;
  final String caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: InkColors.paper.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: InkColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: InkColors.ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    caption,
                    style: const TextStyle(
                      color: InkColors.muted,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: .4,
                    ),
                  ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
