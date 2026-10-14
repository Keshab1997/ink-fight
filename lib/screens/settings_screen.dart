import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_routes.dart';

/// Settings, in the ink palette: a paper sheet with two panels, a working sound
/// switch, and the small print about the build.
///
/// The screen is reachable two ways — the home menu's SETTINGS button and the
/// web deep link `#/settings` — and both land on this one route, so the back
/// button has somewhere to return to either way.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Placeholder state, on purpose: the switch works for the session it is
  /// flipped in and forgets on restart. Nothing in the app plays a sound yet,
  /// so a switch that claims to save a preference would be dressing up a lie;
  /// persistence arrives with the local store the design document asks for.
  bool _soundOn = true;

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
                            _ToggleRow(
                              label: 'SOUND',
                              caption: 'HIT CUES AND UI TAPS',
                              value: _soundOn,
                              onChanged: (value) =>
                                  setState(() => _soundOn = value),
                            ),
                            const SizedBox(height: 10),
                            // The design document asks for audio and haptics to
                            // be independent settings, and TactileFeedback is
                            // not wired yet — so this row says so instead of
                            // pretending to be a control.
                            const _StaticRow(
                              label: 'HAPTICS',
                              caption: 'INDEPENDENT FROM SOUND',
                              tag: 'SOON',
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
        const _BackButton(),
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
  const _StaticRow({required this.label, required this.caption, this.tag});

  final String label;
  final String caption;

  /// Marks a row that is not a control yet, so it never looks pressable.
  final String? tag;

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      label: label,
      caption: caption,
      muted: tag != null,
      trailing: tag == null
          ? null
          : DecoratedBox(
              decoration: BoxDecoration(
                color: InkColors.paperDeep,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: InkColors.line),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                child: Text(
                  tag!,
                  style: const TextStyle(
                    color: InkColors.muted,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
    );
  }
}

/// The one shape both row kinds share: label on the left, something on the
/// right, caption underneath.
class _RowShell extends StatelessWidget {
  const _RowShell({
    required this.label,
    required this.caption,
    this.trailing,
    this.muted = false,
  });

  final String label;
  final String caption;
  final Widget? trailing;
  final bool muted;

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
                    style: TextStyle(
                      color: muted ? InkColors.muted : InkColors.ink,
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
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Back',
      child: Material(
        color: InkColors.ink,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () {
            // A deep link can open this screen with nothing behind it, so fall
            // back to the menu rather than leaving the player on a dead page.
            final navigator = Navigator.of(context);
            if (navigator.canPop()) {
              navigator.pop();
              return;
            }
            navigator.pushReplacementNamed(InkRoutes.home);
          },
          child: const SizedBox(
            width: 42,
            height: 42,
            child: Icon(Icons.arrow_back_rounded, color: InkColors.white),
          ),
        ),
      ),
    );
  }
}
