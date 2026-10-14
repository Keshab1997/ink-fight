import 'package:flutter/material.dart';

import '../screens/app_routes.dart';
import '../theme/app_theme.dart';

/// The square ink back button every menu sheet shares.
///
/// A deep link can open a sheet with nothing behind it, so when there is no
/// route to pop the button falls back to the menu rather than leaving the
/// player on a dead page.
class InkBackButton extends StatelessWidget {
  const InkBackButton({super.key});

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
