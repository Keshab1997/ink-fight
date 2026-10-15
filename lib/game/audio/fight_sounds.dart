import 'dart:async';
import 'dart:math';

// `flame_audio` re-exports the preloaded AudioPlayer API.
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

  /// Restrained final-ten-seconds tick; counting blips replace it at 3/2/1.
  clockTick,

  /// A two-or-more-hit streak unravelling; soft, falling low-mid air.
  comboUnravel,

  /// A quiet low body pulse in otherwise quiet, critical-health combat.
  lowHealthPulse,
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

/// Optional cancellation keeps existing FightSounds fakes/source users intact.
/// Real tension playback supports immediate stop; no audio timer owns its life.
abstract interface class CancellableFightSounds implements FightSounds {
  void stop(FightCue cue);
}

extension FightSoundsCancellation on FightSounds {
  void stopCue(FightCue cue) {
    final sounds = this;
    if (sounds is CancellableFightSounds) sounds.stop(cue);
  }
}

/// Screen-owned pulse pacing on simulation time, not wall time. No catch-up,
/// no pulses on paused clocks, and fresh quiet time after mute/busy/recovery.
class LowHealthTensionCues {
  int? _round;
  int? _previousClock;
  int? _quietSince;
  int? _lastPulse;

  void interrupt() {
    _quietSince = null;
    _lastPulse = null;
  }

  bool update({
    required int roundNumber,
    required int remainingMs,
    required bool eligible,
    required bool busy,
  }) {
    if (_round != roundNumber ||
        (_previousClock != null && remainingMs > _previousClock!)) {
      interrupt();
    }
    _round = roundNumber;
    _previousClock = remainingMs;
    if (!eligible || busy) {
      interrupt();
      return false;
    }
    _quietSince ??= remainingMs;
    if (_quietSince! - remainingMs < 600 ||
        (_lastPulse != null && _lastPulse! - remainingMs < 1800)) {
      return false;
    }
    _lastPulse = remainingMs;
    return true;
  }
}

/// Last-line mixer priority: every foreground cue can interrupt a pulse, and
/// the following quiet guard drops tension requests instead of queueing them.
@visibleForTesting
class FightCuePriority {
  int? _foregroundMs;
  bool allow(FightCue cue, int nowMs) {
    if (cue != FightCue.lowHealthPulse) {
      _foregroundMs = nowMs;
      return true;
    }
    return _foregroundMs == null || nowMs - _foregroundMs! >= 600;
  }
}

/// The default: no sound at all. Every test and the debug path get this
/// unless they hand in something else.
class SilentFightSounds implements CancellableFightSounds {
  const SilentFightSounds();

  @override
  void play(FightCue cue) {}

  @override
  Future<void> warmUp() async {}

  @override
  void stop(FightCue cue) {}
}

/// Small per-play changes for physical contacts, swings and footfalls.
/// Musical and clock cues stay fixed. The .8 base volume leaves room for +10% gain
/// without clipping at the player's volume ceiling.
@visibleForTesting
class FightSoundVariation {
  const FightSoundVariation(this.rate, this.volume);

  final double rate;
  final double volume;

  static bool varies(FightCue cue) => switch (cue) {
    FightCue.hitLight ||
    FightCue.hitHeavy ||
    FightCue.blocked ||
    FightCue.whooshLight ||
    FightCue.whooshHeavy ||
    FightCue.stepTap => true,
    _ => false,
  };

  static bool isHit(FightCue cue) =>
      cue == FightCue.hitLight || cue == FightCue.hitHeavy;

  /// The first hit is neutral; the next four add five percentage points
  /// each, capped at +20%. Per-play jitter remains centred on that step.
  static double comboLift(FightCue cue, int combo) =>
      isHit(cue) ? (combo - 1).clamp(0, 4) * .05 : 0;

  /// Warm bins include the escalation ceiling plus the old +/-4% jitter.
  /// 2% spacing avoids a cold source change on the escalating hit frame.
  static List<double> pitchRates(FightCue cue) => isHit(cue)
      ? List<double>.generate(15, (i) => .96 + i * .02)
      : const [.96, .98, 1.0, 1.02, 1.04];

  static FightSoundVariation sample(
    FightCue cue,
    Random random, {
    int combo = 0,
  }) {
    if (!varies(cue)) {
      return FightSoundVariation(1, switch (cue) {
        FightCue.lowHealthPulse => .35,
        FightCue.clockTick || FightCue.comboUnravel => .5,
        _ => .8,
      });
    }
    return FightSoundVariation(
      1 + comboLift(cue, combo) + (random.nextDouble() * 2 - 1) * .04,
      .8 * (1 + (random.nextDouble() * 2 - 1) * .1),
    );
  }
}

/// Preloaded, bounded voices per cue: source loading happens only in
/// [warmUp], never on a hit frame. AudioPool.start exposes volume but not
/// playback rate. Worse, media players often preserve pitch when changing
/// speed. Pre-resampling small PCM pitch banks in warmUp gives real pitch
/// variation on every platform, with no decoding or source changes on a hit.
/// Each voice owns its source, so overlapping hits cannot alter each other.
class FlameFightSounds implements CancellableFightSounds {
  const FlameFightSounds({this.hitCombo});

  /// Read synchronously at play time, after stats.onHit, not on a later HUD
  /// tick. The cue API stays unchanged; no asset names leave this class.
  final int Function()? hitCombo;

  /// One pool per cue, built by [warmUp] and shared process-wide — there is
  /// one audio device, and rebuilding the players on every screen mount would
  /// reintroduce the very hitch the pools exist to remove.
  static final Map<FightCue, _FightVoicePool> _pools = {};
  static final Random _random = Random();
  static final Stopwatch _cueClock = Stopwatch()..start();
  static final FightCuePriority _priority = FightCuePriority();
  static Future<void>? _warming;

  /// Fixed-pitch cues need only a pair. Physical cues use independent warm
  /// pitch bins (15 for escalating hits, five for the other contacts).
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
    FightCue.clockTick => 'clock_tick.wav',
    FightCue.comboUnravel => 'combo_unravel.wav',
    FightCue.lowHealthPulse => 'low_health_pulse.wav',
  };

  @override
  void play(FightCue cue) {
    if (!_priority.allow(cue, _cueClock.elapsedMilliseconds)) return;
    if (cue != FightCue.lowHealthPulse) stop(FightCue.lowHealthPulse);
    final pool = _pools[cue];
    // Nothing to play through yet — a cue that beat the warm-up, or a
    // platform with no audio at all. Staying silent beats throwing into the
    // frame loop, which is the one thing this class must never do.
    if (pool == null) {
      return;
    }
    unawaited(
      _startSafely(
        pool,
        cue,
        FightSoundVariation.sample(
          cue,
          _random,
          combo: FightSoundVariation.isHit(cue) ? hitCombo?.call() ?? 0 : 0,
        ),
      ),
    );
  }

  @override
  void stop(FightCue cue) {
    _pools[cue]?.cancel();
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
          rates: FightSoundVariation.varies(cue)
              ? FightSoundVariation.pitchRates(cue)
              : List<double>.filled(_voicesOf(cue), 1),
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

  static Future<_FightVoicePool> create(
    String file, {
    required List<double> rates,
  }) async {
    final voices = <_FightVoice>[];
    final varied = rates.any((rate) => rate != 1);
    final data = varied ? await rootBundle.load('assets/audio/$file') : null;
    final wav = data?.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    try {
      for (final rate in rates) {
        final player = AudioPlayer()..audioCache = FlameAudio.audioCache;
        final voice = _FightVoice(player, rate);
        voices.add(voice);
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setSource(
          wav == null
              ? AssetSource(file)
              : BytesSource(
                  pitchShiftFightWav(wav, rate),
                  mimeType: 'audio/wav',
                ),
        );
      }
      return _FightVoicePool(voices);
    } catch (_) {
      await Future.wait(voices.map((voice) => voice.dispose()));
      rethrow;
    }
  }

  void cancel() {
    for (final voice in voices) {
      if (voice.busy) voice.cancel();
    }
  }

  Future<void> start(FightSoundVariation variation) async {
    _FightVoice? chosen;
    for (final voice in voices) {
      if (!voice.busy &&
          (chosen == null ||
              (voice.rate - variation.rate).abs() <
                  (chosen.rate - variation.rate).abs())) {
        chosen = voice;
      }
    }
    if (chosen != null) {
      chosen.busy = true;
      await chosen.start(variation);
    }
  }
}

class _FightVoice {
  _FightVoice(this.player, this.rate) {
    _completion = player.onPlayerComplete.listen((_) => unawaited(_finish()));
  }

  final AudioPlayer player;
  final double rate;
  late final StreamSubscription<void> _completion;
  bool busy = false;
  int _generation = 0;

  void cancel() {
    _generation++;
    unawaited(_finish());
  }

  Future<void> start(FightSoundVariation variation) async {
    final generation = ++_generation;
    try {
      await player.setVolume(variation.volume);
      // Cancellation can arrive during prepare or native resume. Never let
      // an in-flight async start resurrect a muted/recovered pulse.
      if (generation != _generation) return;
      await player.resume();
      if (generation != _generation) await player.stop();
    } catch (_) {
      busy = false;
      rethrow;
    }
  }

  Future<void> _finish() async {
    try {
      // Rewind without releasing the source, then return the warm voice.
      await player.stop();
    } catch (_) {
      // Audio failure is never a game failure.
    } finally {
      busy = false;
    }
  }

  Future<void> dispose() async {
    await _completion.cancel();
    await player.dispose();
  }
}

/// Resample our generator's canonical 44-byte-header mono PCM WAV, keeping
/// 22050 Hz / 16-bit format. Shortening the waveform raises actual pitch;
/// no player time-stretch setting can silently preserve it. Warm-up only.
@visibleForTesting
Uint8List pitchShiftFightWav(Uint8List wav, double rate) {
  final input = ByteData.sublistView(wav);
  if (wav.length < 46 ||
      rate <= 0 ||
      !rate.isFinite ||
      input.getUint32(0, Endian.little) != 0x46464952 ||
      input.getUint32(8, Endian.little) != 0x45564157 ||
      input.getUint32(12, Endian.little) != 0x20746d66 ||
      input.getUint32(16, Endian.little) != 16 ||
      input.getUint16(20, Endian.little) != 1 ||
      input.getUint16(22, Endian.little) != 1 ||
      input.getUint32(24, Endian.little) != 22050 ||
      input.getUint16(34, Endian.little) != 16 ||
      input.getUint32(36, Endian.little) != 0x61746164 ||
      input.getUint32(40, Endian.little) != wav.length - 44) {
    throw const FormatException('Expected generated mono 22050 Hz PCM WAV');
  }
  if (rate == 1) {
    return wav;
  }
  final sourceFrames = (wav.length - 44) ~/ 2;
  final frames = (sourceFrames / rate).floor();
  final bytes = Uint8List(44 + frames * 2)..setRange(0, 44, wav);
  final output = ByteData.sublistView(bytes);
  output.setUint32(4, bytes.length - 8, Endian.little);
  output.setUint32(40, frames * 2, Endian.little);
  for (var i = 0; i < frames; i++) {
    final position = (i * rate).clamp(0, sourceFrames - 1).toDouble();
    final left = position.floor();
    final right = min(left + 1, sourceFrames - 1);
    final a = input.getInt16(44 + left * 2, Endian.little);
    final b = input.getInt16(44 + right * 2, Endian.little);
    final sample = (a + (b - a) * (position - left)).round();
    output.setInt16(44 + i * 2, sample, Endian.little);
  }
  return bytes;
}
