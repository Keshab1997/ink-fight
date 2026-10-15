import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:inkfight/game/audio/fight_sounds.dart';

void main() {
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

  test('gong, counting and sting keep their tuning and gain', () {
    final random = Random(0);
    for (final cue in FightCue.values.where((cue) => !physical.contains(cue))) {
      for (var i = 0; i < 20; i++) {
        final play = FightSoundVariation.sample(cue, random);
        expect(play.rate, 1);
        expect(play.volume, .8);
      }
    }
  });

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
