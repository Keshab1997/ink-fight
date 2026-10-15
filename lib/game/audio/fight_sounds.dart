import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';

/// Every sound the fight can make, one per row of the cue table in
/// `docs/technical/GAME_FEEL.md` §4.
///
/// The arena speaks cues and never file names: replacing an asset, or muting
/// a build outright, touches only [FlameFightSounds], never a call site.
enum FightCue {
  /// A light connect: the short tick.
  hitLight,

  /// A heavy connect: the low thud with the ink-splat tail.
  hitHeavy,

  /// A hit the defender guarded: the wooden clack.
  blocked,

  /// A light swing starting — heard whether or not it lands: the thin whoosh.
  whooshLight,

  /// A heavy swing starting: the longer whoosh.
  whooshHeavy,

  /// A jump ending on its own feet: the soft tap.
  stepTap,

  /// The blow that ended the match: the gong, then silence.
  koGong,

  /// One counting beat of the intro — 3 · 2 · 1. The asset's own note says
  /// it plays three times: the FIGHT! beat stays silent.
  countdownBlip,

  /// The result stamping in: the short sting.
  roundSting,
}

/// The seam between the fight and whatever makes noise.
///
/// The game only ever calls [play] and [warmUp], so the same fight runs with
/// a recording fake in a test, in silence on the debug path, and for real
/// through [FlameFightSounds] on a device — and no test ever loads an audio
/// plugin.
abstract interface class FightSounds {
  /// Plays [cue] once. Called straight from the frame loop: an implementation
  /// must not throw and must not await — anything that takes real time
  /// belongs in [warmUp].
  void play(FightCue cue);

  /// Pre-loads everything [play] may need, so a round's first cue is the
  /// sound itself and not a first-decode hitch. Called once from the game's
  /// `onLoad`, outside the frame loop, and never allowed to fail a load.
  Future<void> warmUp();
}

/// The default: no sound at all. Every test and the debug path get this
/// unless they hand in something else.
class SilentFightSounds implements FightSounds {
  const SilentFightSounds();

  @override
  void play(FightCue cue) {}

  @override
  Future<void> warmUp() async {}
}

/// The real thing: the nine mono files in `assets/audio/`, played through
/// [FlameAudio]'s global cache — whose prefix is already `assets/audio/`, so
/// every cue maps to a bare file name.
///
/// Kept off the plugin in tests by construction: nothing here runs unless a
/// test mounts a screen or game without handing in its own [FightSounds].
class FlameFightSounds implements FightSounds {
  const FlameFightSounds();

  /// The file behind each cue. A switch expression on purpose: a new
  /// [FightCue] without a file stops the build instead of going silent.
  static String _fileOf(FightCue cue) => switch (cue) {
    FightCue.hitLight => 'hit_light.wav',
    FightCue.hitHeavy => 'hit_heavy.wav',
    FightCue.blocked => 'blocked.wav',
    FightCue.whooshLight => 'whoosh_light.wav',
    FightCue.whooshHeavy => 'whoosh_heavy.wav',
    FightCue.stepTap => 'step_tap.wav',
    FightCue.koGong => 'ko_gong.wav',
    FightCue.countdownBlip => 'countdown_blip.wav',
    FightCue.roundSting => 'round_sting.wav',
  };

  @override
  void play(FightCue cue) {
    // Fire and forget: the frame loop never waits on the mixer, and a
    // failure — a platform with no audio implementation, a device that lost
    // its output — must never take a fight frame down with it.
    unawaited(_playSafely(_fileOf(cue)));
  }

  @override
  Future<void> warmUp() async {
    try {
      await FlameAudio.audioCache.loadAll([
        for (final cue in FightCue.values) _fileOf(cue),
      ]);
    } catch (error) {
      // Same contract as [play]: audio never breaks the fight. A debug build
      // says so once; a release build stays quiet about it.
      if (kDebugMode) {
        debugPrint('fight sounds: warm-up failed ($error)');
      }
    }
  }

  Future<void> _playSafely(String file) async {
    try {
      // Each cue plays through its own short-lived low-latency player; the
      // cache load in [warmUp] is what keeps the first one from hitching.
      await FlameAudio.play(file);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('fight sounds: $file failed to play ($error)');
      }
    }
  }
}
