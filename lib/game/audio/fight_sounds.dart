import 'dart:async';
import 'dart:math';

// `flame_audio` re-exports the preloaded AudioPlayer API.
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

  /// A light swing starting — heard whether or not it lands: the body-first whoosh.
  whooshLight,

  /// A heavy swing starting: the longer whoosh.
  whooshHeavy,

  /// A jump ending on its own feet: the soft tap.
  stepTap,

  /// The blow that ended the match: the gong, then silence.
  koGong,

  /// One counting beat of the intro — 3 · 2 · 1.
  countdownBlip,

  /// FIGHT! and the result stamping in: the short sting.
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

/// Small per-play changes for physical contacts, swings and footfalls.
/// Musical cues stay fixed. The .8 base volume leaves room for +10% gain
/// without clipping at the player's volume ceiling.
@visibleForTesting
class FightSoundVariation {
  const FightSoundVariation(this.rate, this.volume);

  final double rate;
  final double volume;

  static FightSoundVariation sample(FightCue cue, Random random) {
    final varies = switch (cue) {
      FightCue.hitLight ||
      FightCue.hitHeavy ||
      FightCue.blocked ||
      FightCue.whooshLight ||
      FightCue.whooshHeavy ||
      FightCue.stepTap => true,
      _ => false,
    };
    if (!varies) {
      return const FightSoundVariation(1, .8);
    }
    return FightSoundVariation(
      1 + (random.nextDouble() * 2 - 1) * .04,
      .8 * (1 + (random.nextDouble() * 2 - 1) * .1),
    );
  }
}

/// Preloaded, bounded voices per cue: source loading happens only in
/// [warmUp], never on a hit frame. AudioPool.start exposes volume but not
/// playback rate; owning the voices lets us set both before resume without
/// mutating another overlapping hit. Tests can still use SilentFightSounds.
class FlameFightSounds implements FightSounds {
  const FlameFightSounds();

  /// One pool per cue, built by [warmUp] and shared process-wide — there is
  /// one audio device, and rebuilding the players on every screen mount would
  /// reintroduce the very hitch the pools exist to remove.
  static final Map<FightCue, _FightVoicePool> _pools = {};
  static final Random _random = Random();
  static Future<void>? _warming;

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
    unawaited(
      _startSafely(pool, cue, FightSoundVariation.sample(cue, _random)),
    );
  }

  @override
  Future<void> warmUp() => _warming ??= _warmPools();

  static Future<void> _warmPools() async {
    for (final cue in FightCue.values) {
      if (_pools.containsKey(cue)) {
        continue;
      }
      try {
        _pools[cue] = await _FightVoicePool.create(
          _fileOf(cue),
          _voicesOf(cue),
        );
      } catch (error) {
        if (kDebugMode) {
          debugPrint('fight sounds: ${_fileOf(cue)} warm-up failed ($error)');
        }
      }
    }
    // Failed cues may retry on a later mount; simultaneous warm-ups share
    // the in-flight future rather than leaking duplicate players.
    _warming = null;
  }

  Future<void> _startSafely(
    _FightVoicePool pool,
    FightCue cue,
    FightSoundVariation variation,
  ) async {
    try {
      // Fire and forget: the frame loop never waits on the mixer, and a
      // failure — a device that lost its output, say — must never take a
      // fight frame down with it.
      await pool.start(variation);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('fight sounds: ${_fileOf(cue)} failed to play ($error)');
      }
    }
  }
}

/// A voice is reserved synchronously, before any platform await. Excess
/// simultaneous plays are dropped rather than allocating cold players or
/// changing the pitch of a sound already in flight.
class _FightVoicePool {
  _FightVoicePool(this.voices);
  final List<_FightVoice> voices;

  static Future<_FightVoicePool> create(String file, int count) async {
    final voices = <_FightVoice>[];
    try {
      for (var i = 0; i < count; i++) {
        final player = AudioPlayer()..audioCache = FlameAudio.audioCache;
        final voice = _FightVoice(player);
        voices.add(voice);
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setSource(AssetSource(file));
      }
      return _FightVoicePool(voices);
    } catch (_) {
      await Future.wait(voices.map((voice) => voice.dispose()));
      rethrow;
    }
  }

  Future<void> start(FightSoundVariation variation) async {
    for (final voice in voices) {
      if (!voice.busy) {
        voice.busy = true;
        await voice.start(variation);
        return;
      }
    }
  }
}

class _FightVoice {
  _FightVoice(this.player) {
    _completion = player.onPlayerComplete.listen((_) => busy = false);
  }

  final AudioPlayer player;
  late final StreamSubscription<void> _completion;
  bool busy = false;

  Future<void> start(FightSoundVariation variation) async {
    try {
      // Playback rate changes pitch and duration slightly. Some platforms
      // do not support it: still play the contact with its gain variation.
      try {
        await player.setPlaybackRate(variation.rate);
      } catch (_) {
        // An unsupported pitch control must never mute the whole cue.
      }
      await player.setVolume(variation.volume);
      await player.resume();
    } catch (_) {
      busy = false;
      rethrow;
    }
  }

  Future<void> dispose() async {
    await _completion.cancel();
    await player.dispose();
  }
}
