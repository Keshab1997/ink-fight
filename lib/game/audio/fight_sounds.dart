import 'dart:async';

// `flame_audio` re-exports `audioplayers`, which is where [AudioPool] lives —
// hence no direct import here, and the direct dependency in `pubspec.yaml`
// because the pools *are* that package's API.
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

/// The real thing: the nine mono files in `assets/audio/`, played through one
/// pre-warmed [AudioPool] per cue.
///
/// The pool is the point. `FlameAudio.play` builds a fresh player and hands it
/// the asset on *every* call, so each cue paid a load before it made a sound:
/// on a phone that is the difference between a hit landing on its frame and
/// arriving a beat late, and during a walk — a tap every half second — the
/// mixer never caught up at all. A pool sets each player's source once, in
/// [warmUp], so [play] is a `resume()` on a player that is already loaded.
///
/// Kept off the plugin in tests by construction: nothing here runs unless a
/// test mounts a screen or game without handing in its own [FightSounds].
class FlameFightSounds implements FightSounds {
  const FlameFightSounds();

  /// One pool per cue, built by [warmUp] and shared process-wide — there is
  /// one audio device, and rebuilding the players on every screen mount would
  /// reintroduce the very hitch the pools exist to remove.
  static final Map<FightCue, AudioPool> _pools = <FightCue, AudioPool>{};

  /// How many copies of a cue may overlap. A stride tap, an impact and its
  /// whoosh can share a frame; the sparse cues never need more than a pair.
  static int _voicesOf(FightCue cue) => switch (cue) {
    FightCue.stepTap => 4,
    FightCue.hitLight || FightCue.whooshLight => 3,
    _ => 2,
  };

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
    final pool = _pools[cue];
    // Nothing to play through yet — a cue that beat the warm-up, or a
    // platform with no audio at all. Staying silent beats throwing into the
    // frame loop, which is the one thing this class must never do.
    if (pool == null) {
      return;
    }
    unawaited(_startSafely(pool, cue));
  }

  @override
  Future<void> warmUp() async {
    for (final cue in FightCue.values) {
      if (_pools.containsKey(cue)) {
        continue;
      }
      try {
        _pools[cue] = await AudioPool.createFromAsset(
          // Bare file name: the cache in play carries the `assets/audio/`
          // prefix for us, exactly as [FlameAudio.play] did.
          path: _fileOf(cue),
          audioCache: FlameAudio.audioCache,
          minPlayers: 1,
          // Default media player mode on purpose: it is the mode where a
          // finished clip returns its player to the pool, so a long fight
          // never grows past [maxPlayers] players.
          maxPlayers: _voicesOf(cue),
        );
      } catch (error) {
        // Same contract as [play]: audio never breaks the fight. A debug
        // build says so; a release build stays quiet about it.
        if (kDebugMode) {
          debugPrint('fight sounds: ${_fileOf(cue)} warm-up failed ($error)');
        }
      }
    }
  }

  Future<void> _startSafely(AudioPool pool, FightCue cue) async {
    try {
      // Fire and forget: the frame loop never waits on the mixer, and a
      // failure — a device that lost its output, say — must never take a
      // fight frame down with it.
      await pool.start();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('fight sounds: ${_fileOf(cue)} failed to play ($error)');
      }
    }
  }
}
