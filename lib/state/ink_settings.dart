import 'package:flutter/foundation.dart';

/// The app's preferences, in one place.
///
/// Honest scope: this model is **session-scoped**. It lives in memory for as
/// long as the app runs, every screen reads and writes the same instance, and
/// a fresh launch starts from the defaults again. Nothing here claims to
/// survive a restart — the local store the roadmap asks for is the next step,
/// and when it lands, this class is the only place that grows the load/save.
///
/// Injected through the constructor (`main()` builds the app's one instance
/// and hands it to the routes table; tests build their own), so there is no
/// global mutable singleton to reset between tests and no inherited-widget
/// ceremony for the handful of values that exist today.
class InkSettings extends ChangeNotifier {
  InkSettings({this._soundOn = true});

  bool _soundOn;

  /// The SOUND row on the settings screen, and the gate the arena's audio
  /// will read when it lands. On by default: the design document asks for
  /// sound the player can turn off, not silence the player has to turn on.
  bool get soundOn => _soundOn;

  set soundOn(bool value) {
    if (_soundOn == value) {
      return;
    }
    _soundOn = value;
    notifyListeners();
  }
}
