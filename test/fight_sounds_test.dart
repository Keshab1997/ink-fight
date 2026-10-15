import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:inkfight/game/audio/fight_sounds.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
        expect(play.volume, cue == FightCue.clockTick ? .5 : .8);
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
