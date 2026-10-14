import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_routes.dart';

/// Settings, in the ink palette: a paper sheet with a rule across the top, a
/// couple of rows, and nothing that needs the network.
///
/// The screen is reachable two ways — the home menu's SETTINGS button and the
/// web deep link `#/settings` — and both land on the same route, so the back
/// button has somewhere to return to either way.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _BackButton(),
                  const SizedBox(width: 14),
                  Text(
                    'SETTINGS',
                    style: TextStyle(
                      color: InkColors.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.6,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: InkColors.white.withValues(alpha: .78),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: InkColors.line),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Audio, haptics and accessibility options are next. '
                      'This screen is wired to the named route so the menu '
                      'and the web deep link both land here.',
                      style: TextStyle(
                        color: InkColors.muted,
                        fontSize: 12,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
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
            // back to the menu rather than leaving the player on a blank page.
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
              return;
            }
            Navigator.of(context).pushReplacementNamed(InkRoutes.home);
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
