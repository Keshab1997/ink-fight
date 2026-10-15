import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:inkfight/game/audio/fight_sounds.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('tension is sparse, sim-clock paced and never catches up', () {
    final tension = LowHealthTensionCues();
    bool sample(int clock) => tension.update(
      roundNumber: 1,
      remainingMs: clock,
      eligible: true,
      busy: false,
    );
    expect(sample(60000), isFalse);
    expect(sample(59401), isFalse);
    expect(sample(59400), isTrue);
    expect(sample(59400), isFalse, reason: 'paused sim clock never pulses');
    expect(sample(58000), isFalse);
    expect(sample(57600), isTrue);
    expect(
      sample(30000),
      isTrue,
      reason: 'a missed interval yields one pulse only',
    );
    expect(sample(30000), isFalse);
  });

  test('tension rearms only after fresh quiet time on mute, busy, recovery or round reset', () {
    final tension = LowHealthTensionCues();
    bool sample(
      int clock, {
      bool eligible = true,
      bool busy = false,
      int round = 1,
    }) => tension.update(
      roundNumber: round,
      remainingMs: clock,
      eligible: eligible,
      busy: busy,
    );
    expect(sample(60000), isFalse);
    expect(sample(59400), isTrue);
    expect(sample(59000, eligible: false), isFalse);
    expect(sample(58000), isFalse, reason: 'no unmute catch-up');
    expect(sample(57400), isTrue);
    expect(sample(57000, busy: true), isFalse);
    expect(sample(56000), isFalse);
    expect(sample(55400), isTrue);
    tension.interrupt();
    expect(
      sample(54000),
      isFalse,
      reason: 'foreground cue interrupts the quiet guard',
    );
    expect(sample(53400), isTrue);
    expect(sample(60000, round: 2), isFalse);
    expect(sample(59400, round: 2), isTrue);
    expect(
      sample(60000, round: 2),
      isFalse,
      reason: 'restored clock resets pacing',
    );
  });

  test('every foreground cue has priority over low-health audio', () {
    for (final cue in FightCue.values.where(
      (c) => c != FightCue.lowHealthPulse,
    )) {
      final priority = FightCuePriority();
      expect(priority.allow(FightCue.lowHealthPulse, 0), isTrue);
      expect(priority.allow(cue, 10), isTrue);
      expect(priority.allow(FightCue.lowHealthPulse, 10), isFalse);
      expect(priority.allow(FightCue.lowHealthPulse, 609), isFalse);
      expect(priority.allow(FightCue.lowHealthPulse, 610), isTrue);
    }
  });

  test(
    'low pulse is restrained body-first mono PCM, not a high alarm',
    () async {
      final data = await rootBundle.load('assets/audio/low_health_pulse.wav');
      final wav = ByteData.sublistView(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      expect(wav.getUint16(22, Endian.little), 1);
      expect(wav.getUint32(24, Endian.little), 22050);
      expect(wav.getUint16(34, Endian.little), 16);
      expect(data.lengthInBytes, lessThan(60000));
      expect((data.lengthInBytes - 44) / 44100, closeTo(.180, .001));
      final samples = [
        for (var i = 44; i < data.lengthInBytes; i += 2)
          wav.getInt16(i, Endian.little),
      ];
      final peak = samples.map((s) => s.abs()).reduce(max);
      expect(peak / 32767, inInclusiveRange(.20, .23));
      final peakIndex = samples.indexWhere((s) => s.abs() == peak);
      expect(
        peakIndex / 22050,
        lessThan(.030),
        reason: 'body first, not a long airy lead-in',
      );
      var crossings = 0;
      for (var i = 1; i < samples.length; i++) {
        if (samples[i - 1] < 0 && samples[i] >= 0) crossings++;
      }
      expect(
        crossings / .180,
        inInclusiveRange(100, 220),
        reason: 'low body, not a warning beep',
      );
      final play = FightSoundVariation.sample(
        FightCue.lowHealthPulse,
        Random(3),
        combo: 100,
      );
      expect(play.rate, 1);
      expect(play.volume, .35);
      expect(FightSoundVariation.varies(FightCue.lowHealthPulse), isFalse);
      const SilentFightSounds().stopCue(FightCue.lowHealthPulse);
    },
  );

  test('pitch variants change actual PCM pitch, not just a playback setting', () async {
    final asset = await rootBundle.load('assets/audio/whoosh_light.wav');
    final original = asset.buffer.asUint8List(
      asset.offsetInBytes,
      asset.lengthInBytes,
    );
    final originalFrames = (original.length - 44) ~/ 2;
    for (final rate in [.96, .98, 1.0, 1.02, 1.04]) {
      final variant = pitchShiftFightWav(original, rate);
      final pcm = ByteData.sublistView(variant);
      expect((variant.length - 44) ~/ 2, (originalFrames / rate).floor());
      expect(pcm.getUint32(4, Endian.little), variant.length - 8);
      expect(pcm.getUint32(40, Endian.little), variant.length - 44);
      expect(pcm.getUint16(22, Endian.little), 1);
      expect(pcm.getUint32(24, Endian.little), 22050);
      expect(pcm.getUint16(34, Endian.little), 16);
      expect(variant.length, lessThan(60000));
      if (rate == 1) {
        expect(variant, orderedEquals(original));
      } else {
        // Output sample at n reads input at n*rate: faster oscillations for
        // >1, slower for <1. Verify real waveform resampling, not just header.
        const index = 1000;
        final position = index * rate;
        final left = position.floor();
        final source = ByteData.sublistView(original);
        final a = source.getInt16(44 + left * 2, Endian.little);
        final b = source.getInt16(44 + (left + 1) * 2, Endian.little);
        expect(
          pcm.getInt16(44 + index * 2, Endian.little),
          (a + (b - a) * (position - left)).round(),
        );
      }
    }
  });

  test('pitch preparation rejects unexpected audio formats', () {
    expect(
      () => pitchShiftFightWav(Uint8List(20), 1.04),
      throwsFormatException,
    );
  });
  const physical = [
    FightCue.hitLight,
    FightCue.hitHeavy,
    FightCue.blocked,
    FightCue.whooshLight,
    FightCue.whooshHeavy,
    FightCue.stepTap,
  ];

  for (final cue in physical) {
    test('$cue varies each play inside pitch/gain budgets', () {
      final random = Random(1997);
      final rates = <double>{};
      final volumes = <double>{};
      for (var i = 0; i < 200; i++) {
        final play = FightSoundVariation.sample(cue, random);
        expect(play.rate, inInclusiveRange(.96, 1.04));
        expect(play.volume / .8, inInclusiveRange(.9, 1.1));
        expect(play.volume, lessThanOrEqualTo(1));
        rates.add(play.rate);
        volumes.add(play.volume);
      }
      expect(rates.length, 200);
      expect(volumes.length, 200);
      expect(rates.any((rate) => rate < 1), isTrue);
      expect(rates.any((rate) => rate > 1), isTrue);
      expect(volumes.any((volume) => volume < .8), isTrue);
      expect(volumes.any((volume) => volume > .8), isTrue);
    });
  }

  test('musical/clock cues keep their tuning, clock stays softer', () {
    final random = Random(0);
    for (final cue in FightCue.values.where((cue) => !physical.contains(cue))) {
      for (var i = 0; i < 20; i++) {
        final play = FightSoundVariation.sample(cue, random);
        expect(play.rate, 1);
        expect(play.volume, switch (cue) {
          FightCue.lowHealthPulse => .35,
          FightCue.clockTick || FightCue.comboUnravel => .5,
          _ => .8,
        });
      }
    }
  });

  test(
    'clock tick is short mono PCM with a quieter peak than impacts',
    () async {
      final data = await rootBundle.load('assets/audio/clock_tick.wav');
      final wav = ByteData.sublistView(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      expect(wav.getUint16(22, Endian.little), 1);
      expect(wav.getUint32(24, Endian.little), 22050);
      expect(wav.getUint16(34, Endian.little), 16);
      expect(data.lengthInBytes, lessThan(60000));
      expect((data.lengthInBytes - 44) / 2 / 22050, closeTo(.065, .001));
      var peak = 0;
      for (var i = 44; i < data.lengthInBytes; i += 2) {
        peak = max(peak, wav.getInt16(i, Endian.little).abs());
      }
      expect(peak / 32767, inInclusiveRange(.28, .33));
    },
  );

  test(
    'unravel stays soft, fixed-pitch and uses a short mono PCM asset',
    () async {
      final data = await rootBundle.load('assets/audio/combo_unravel.wav');
      final wav = ByteData.sublistView(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      expect(wav.getUint16(22, Endian.little), 1);
      expect(wav.getUint32(24, Endian.little), 22050);
      expect(wav.getUint16(34, Endian.little), 16);
      expect(data.lengthInBytes, lessThan(60000));
      expect((data.lengthInBytes - 44) / 44100, closeTo(.24, .001));
      final play = FightSoundVariation.sample(
        FightCue.comboUnravel,
        Random(4),
        combo: 100,
      );
      expect(play.rate, 1);
      expect(play.volume, .5);
      expect(FightSoundVariation.varies(FightCue.comboUnravel), isFalse);
    },
  );

  test('player combo pitch rises in four 5% steps, then caps', () {
    for (final cue in [FightCue.hitLight, FightCue.hitHeavy]) {
      final base = FightSoundVariation.sample(cue, Random(42), combo: 1);
      for (var combo = 1; combo <= 10; combo++) {
        final play = FightSoundVariation.sample(cue, Random(42), combo: combo);
        expect(
          play.rate - base.rate,
          closeTo(min(combo - 1, 4) * .05, .000001),
        );
        expect(play.rate, inInclusiveRange(.96, 1.24));
        expect(
          play.volume,
          base.volume,
          reason: 'escalation never boosts gain',
        );
      }
      final reset = FightSoundVariation.sample(cue, Random(42), combo: 0);
      expect(reset.rate, base.rate);
    }
  });

  test('combo context does not escalate whooshes, guards or musical cues', () {
    for (final cue in FightCue.values.where(
      (cue) => !FightSoundVariation.isHit(cue),
    )) {
      final base = FightSoundVariation.sample(cue, Random(42));
      final high = FightSoundVariation.sample(cue, Random(42), combo: 100);
      expect(high.rate, base.rate);
      expect(high.volume, base.volume);
    }
  });

  test(
    'warm hit banks cover escalation plus jitter with actual PCM shifts',
    () async {
      final asset = await rootBundle.load('assets/audio/hit_light.wav');
      final original = asset.buffer.asUint8List(
        asset.offsetInBytes,
        asset.lengthInBytes,
      );
      for (final cue in [FightCue.hitLight, FightCue.hitHeavy]) {
        final rates = FightSoundVariation.pitchRates(cue);
        expect(rates, hasLength(15));
        expect(rates.first, closeTo(.96, .000001));
        expect(rates.last, closeTo(1.24, .000001));
        for (final rate in rates) {
          final variant = pitchShiftFightWav(original, rate);
          expect(
            (variant.length - 44) ~/ 2,
            (((original.length - 44) ~/ 2) / rate).floor(),
          );
        }
        final random = Random(1997);
        for (var combo = 0; combo < 12; combo++) {
          for (var i = 0; i < 30; i++) {
            final target = FightSoundVariation.sample(
              cue,
              random,
              combo: combo,
            ).rate;
            final error = rates
                .map((rate) => (rate - target).abs())
                .reduce(min);
            expect(error, lessThanOrEqualTo(.010001));
          }
        }
      }
    },
  );

  test('seeded variation is reproducible without changing cue API', () {
    final first = Random(42);
    final second = Random(42);
    for (final cue in FightCue.values) {
      final a = FightSoundVariation.sample(cue, first);
      final b = FightSoundVariation.sample(cue, second);
      expect(a.rate, b.rate);
      expect(a.volume, b.volume);
    }
  });

  test('silent seam accepts every cue without loading a plugin', () async {
    const sounds = SilentFightSounds();
    await sounds.warmUp();
    for (final cue in FightCue.values) {
      expect(() => sounds.play(cue), returnsNormally);
    }
  });
}
