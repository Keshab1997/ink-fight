import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'bot/bot_strategy.dart';
import 'rules/fighter_state.dart';
import 'rules/input_command.dart';
import 'rules/match_controller.dart';
import 'rules/match_rules.dart';

// ---------------------------------------------------------------------------
// The feel numbers, all from docs/technical/GAME_FEEL.md — the view holds no
// combat constants of its own; anything the rules can answer, the rules answer.
// ---------------------------------------------------------------------------

/// §1 light punch, per delivered frame: 45 + 45 + 70 + 95 + 95 = 350 ms =
/// `lightAttack.totalMs`. Frame 002 (the contact pose) holds exactly the
/// 90–160 ms active window.
const List<int> _kLightPunchStepsMs = <int>[45, 45, 70, 95, 95];

/// §1 heavy kick: 80 + 80 + 80 + 90 + 170 + 170 = 670 ms =
/// `heavyAttack.totalMs`. Frame 003 (contact) holds the 240–330 ms window.
const List<int> _kHeavyKickStepsMs = <int>[80, 80, 80, 90, 170, 170];

/// §1 hurt: 000 at 0 ms, 001 at 70 ms, 002 at 150 ms, and the last frame is
/// held until hitstun ends — 220 ms light, 420 ms heavy — which the ticker's
/// non-looping "fixed in the last sprite" behaviour does for free. The final
/// step completes the cycle at exactly the heavy hitstun length.
const List<int> _kHurtStepsMs = <int>[70, 80, 270];

/// §1 jump: takeoff 100, rise 150, apex 150, fall 160, landing 140 = 700 ms =
/// `rules.jumpMs`, so the landing frame meets the ground.
const List<int> _kJumpStepsMs = <int>[100, 150, 150, 160, 140];

/// §1 block: raise for 90 ms, hold frames 001–002 looping at 140 ms while the
/// guard is up, release for the final 120 ms of `rules.blockHoldMs`.
const List<int> _kBlockRaiseStepsMs = <int>[90];
const List<int> _kBlockHoldStepsMs = <int>[140, 140];
const List<int> _kBlockReleaseStepsMs = <int>[120];

/// §5 knockdown: the fall itself, 90 + 100 + 120 + 140 + 150 = 600 ms, then
/// the defeat cycle takes over on the ground.
const List<int> _kKnockdownStepsMs = <int>[90, 100, 120, 140, 150];
const double _kKnockdownTotalMs = 600;

/// §2 hit-stop: confirmed hits freeze fighters and the match clock — never
/// the ink (§3) — for a weightier blow the heavier the attack.
const double _kHitStopLightMs = 70;
const double _kHitStopHeavyMs = 110;
const double _kHitStopBlockedMs = 50;

/// §5 the KO blow: slow motion at a quarter speed, then a frozen beat, then
/// the round-end card stamps in.
const double _kKoSlowMoMs = 350;
const double _kKoSlowMoFactor = .25;
const double _kKoFreezeMs = 250;

/// §3 line shake: a decaying sine along x. One wobble lasts about this long,
/// which reads as a hard jolt rather than a wobble.
const double _kShakePeriodMs = 28;
const double _kShakeLightAmpPx = 3;
const double _kShakeLightMs = 140;
const double _kShakeHeavyAmpPx = 7;
const double _kShakeHeavyMs = 240;

/// §3 camera response: a brief scale around the contact point that displaces
/// the screen edge by 1 px (light) / 4 px (heavy) and eases back out.
const double _kPullLightPx = 1;
const double _kPullLightMs = 120;
const double _kPullHeavyPx = 4;
const double _kPullHeavyMs = 180;

/// §3 impact ink: burst geometry per hit weight, and the restrained
/// black-and-white mark a blocked hit leaves instead of a burst.
const double _kBurstLightSpeedPxS = 120;
const double _kBurstLightMs = 180;
const double _kBurstHeavySpeedPxS = 200;
const double _kBurstHeavyMs = 260;
const double _kImpactMarkMs = 90;
const double _kImpactMarkSizeShare = .13;

/// §6 landing: a 90 ms squash to 94% height and a small ink puff at the feet.
const double _kLandingSquashMs = 90;
const double _kLandingSquashScaleY = .94;
const double _kPuffMs = 150;

/// The crimson of the rival's ink — the two flecks a heavy burst carries
/// (§3). The theme stays black-and-white on purpose; this is the one accent
/// the feel spec names by hex.
const ui.Color _kCrimsonFleck = ui.Color(0xFFC51F3A);

/// §6 measured strides: the widest sole-to-sole spread the delivered walk
/// frames draw, in 1024 px canvas pixels (player walk_005: 529 px, rival
/// walk_003: 497 px, measured at the ground line).
const double _kPlayerWalkStridePx = 529;
const double _kRivalWalkStridePx = 497;

/// The arena view: a thin Flame layer over the deterministic [MatchController].
///
/// Nothing here decides what a hit does - the controller does (see
/// `rules/match_controller.dart`). This file only turns fighter states into
/// sprites and the hits it reports into feel: positions along the arena line,
/// mirrored facings, the animation whose per-frame holds obey the frame data
/// (GAME_FEEL §1), hit-stop, ink and shake drawn in [render] so a freeze can
/// stop the fighters without stopping the impact (§2–§3), and the knockout
/// cinematic (§5). Frames are discovered from the asset manifest, so a new
/// batch from the art pipeline is picked up without touching this file.
class InkFightBattleGame extends FlameGame {
  /// Normal is the default opponent: GDD §8, and the flat-feeling `easy`
  /// default was part of the problem (GAME_FEEL §7).
  InkFightBattleGame({BotProfile botProfile = BotProfile.normal})
    : _bot = BotController(profile: botProfile, fighter: FighterId.rival);

  /// The match this arena displays; read-only for HUD and tests.
  MatchController get match => _match;

  /// The profile the practice bot plays on; the screen hands it in from the
  /// menu's difficulty choice.
  BotProfile get botProfile => _bot.profile;

  /// True once the round-end card may stamp in: immediately when the clock
  /// decides the match, after the slow-motion and the frozen beat when a
  /// knockout does (GAME_FEEL §5).
  bool get roundEndCardVisible => _match.isFinished && _roundEndRevealed;

  /// Bumped whenever a value the HUD shows actually changes, so the screen
  /// can listen instead of rebuilding every frame.
  final ValueNotifier<int> hudVersion = ValueNotifier(0);

  final MatchController _match = MatchController();
  final BotController _bot;
  int _playerSequence = 0;
  int _lastHudSnapshot = 0;

  SpriteAnimationComponent? _player;
  SpriteAnimationComponent? _rival;
  _FighterAnims? _playerAnims;
  _FighterAnims? _rivalAnims;
  double _baselineY = 0;
  bool _loaded = false;

  /// Share of the viewport width a fighter sprite spans in landscape, where
  /// the width term of [_layout] always wins. Used to turn canvas pixels into
  /// arena units for the walk stride (§6).
  static const double _fighterWidthShare = .31;

  // -- feel state (all view-side; the simulation never sees any of it) -----

  /// §2 remaining hit-stop. While positive, fighters, bot and the match clock
  /// stand still and only the ink keeps moving.
  double _hitStopMs = 0;

  double _koSlowMoMs = 0;
  double _koFreezeMs = 0;

  /// Animation-time elapsed inside the KO cinematic; drives knockdown→defeat.
  double _koAnimMs = 0;
  bool _koCinematicStarted = false;
  bool _roundEndRevealed = false;

  final List<_Burst> _bursts = <_Burst>[];
  final List<_ImpactMark> _marks = <_ImpactMark>[];
  _Shake? _shake;
  _CameraPull? _pull;

  /// Seeded so the same fight splatters the same way run to run.
  final math.Random _fxRandom = math.Random(23);

  final Map<FighterId, FighterAction> _prevAction =
      <FighterId, FighterAction>{};
  final Map<FighterId, double> _landingSquashMs = <FighterId, double>{
    FighterId.player: 0,
    FighterId.rival: 0,
  };

  final Map<String, TextPainter> _countdownPainters = <String, TextPainter>{};

  /// Remaining hit-stop, for tests that assert the freeze directly.
  @visibleForTesting
  double get hitStopRemainingMs => _hitStopMs;

  /// Live ink bursts plus impact marks, for tests: the effects must keep
  /// running while the fighters are frozen (§2).
  @visibleForTesting
  int get liveEffectCount => _bursts.length + _marks.length;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    images.prefix = '';

    final frames = await _runtimeFrames();
    _playerAnims = await _buildAnims(
      frames,
      'player_ink_fighter',
      walkStridePx: _kPlayerWalkStridePx,
    );
    _rivalAnims = await _buildAnims(
      frames,
      'bot_crimson_rival',
      walkStridePx: _kRivalWalkStridePx,
    );

    _player = SpriteAnimationComponent(
      animation: _playerAnims!.idle,
      // Flame requires an explicit size when autoResize is off; _layout()
      // below replaces this placeholder with the real arena dimensions.
      size: Vector2.all(1),
      autoResize: false,
      anchor: Anchor.bottomCenter,
    );
    _rival = SpriteAnimationComponent(
      animation: _rivalAnims!.idle,
      size: Vector2.all(1),
      autoResize: false,
      anchor: Anchor.bottomCenter,
    );

    add(_rival!);
    add(_player!);
    _loaded = true;
    _layout(size);
  }

  /// Every runtime frame, grouped by `character/action` and sorted, so the
  /// animation recipes below always see the whole delivered cycle.
  Future<Map<String, List<String>>> _runtimeFrames() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final byDir = <String, List<String>>{};
    for (final key in manifest.listAssets()) {
      if (!key.startsWith('assets/characters/runtime/')) {
        continue;
      }
      byDir
          .putIfAbsent(key.substring(0, key.lastIndexOf('/')), () => [])
          .add(key);
    }
    for (final cycle in byDir.values) {
      cycle.sort();
    }
    return byDir;
  }

  Future<_FighterAnims> _buildAnims(
    Map<String, List<String>> frames,
    String character, {
    required double walkStridePx,
  }) async {
    Future<List<Sprite>> loadCycle(String action) async {
      final paths = frames['assets/characters/runtime/$character/$action'];
      if (paths == null || paths.isEmpty) {
        throw StateError('no runtime frames for $character/$action');
      }
      final sprites = <Sprite>[];
      for (final path in paths) {
        sprites.add(Sprite(await images.load(path)));
      }
      return sprites;
    }

    /// A cycle whose frames all hold the same time.
    Future<SpriteAnimation> cycle(
      String action, {
      required double stepTime,
      bool loop = false,
    }) async {
      return SpriteAnimation.spriteList(
        await loadCycle(action),
        stepTime: stepTime,
        loop: loop,
      );
    }

    /// A per-frame recipe (GAME_FEEL §1): `stepsMs[i]` is how long the frame
    /// at `from + i` holds. The recipe must fit the delivered frames exactly —
    /// a mismatch is a broken contract between the art pipeline and the feel
    /// spec, so it fails loudly instead of silently skating.
    Future<SpriteAnimation> recipe(
      String action,
      List<int> stepsMs, {
      int from = 0,
      bool loop = false,
    }) async {
      final sprites = await loadCycle(action);
      if (from + stepsMs.length > sprites.length) {
        throw StateError(
          '$character/$action delivers ${sprites.length} frames; the feel '
          'recipe wants ${stepsMs.length} from index $from',
        );
      }
      return SpriteAnimation.variableSpriteList(
        sprites.sublist(from, from + stepsMs.length),
        stepTimes: <double>[for (final ms in stepsMs) ms / 1000],
        loop: loop,
      );
    }

    // §6: the walk must not skate. The cycle may last exactly as long as the
    // controller needs to move the stride the art draws:
    // cycleMs = (strideUnits / walkSpeed) * 1000, stepTime = cycleMs / 6.
    final rules = _match.rules;
    final strideUnits =
        walkStridePx * _fighterWidthShare * rules.arenaWidth / 1024;
    final walkStepTime = strideUnits / rules.walkSpeed / 6;

    return _FighterAnims(
      idle: await cycle('idle', stepTime: .14, loop: true),
      walk: await cycle('walk', stepTime: walkStepTime, loop: true),
      jump: await recipe('jump', _kJumpStepsMs),
      lightPunch: await recipe('light_punch', _kLightPunchStepsMs),
      heavyKick: await recipe('heavy_kick', _kHeavyKickStepsMs),
      blockRaise: await recipe('block', _kBlockRaiseStepsMs),
      blockHold: await recipe('block', _kBlockHoldStepsMs, from: 1, loop: true),
      blockRelease: await recipe('block', _kBlockReleaseStepsMs, from: 3),
      hurt: await recipe('hurt', _kHurtStepsMs),
      knockdown: await recipe('knockdown', _kKnockdownStepsMs),
      victory: await cycle('victory', stepTime: .12, loop: true),
      defeat: await cycle('defeat', stepTime: .12),
    );
  }

  /// Winner poses, loser falls. A knockout plays the knockdown into the
  /// defeat cycle on the ground (§5); a match the clock decided goes straight
  /// to the end poses.
  SpriteAnimation _endPose(_FighterAnims anims, FighterState state) {
    final outcome = _match.outcome;
    if (outcome == MatchOutcome.draw) {
      // A double knockout falls too; a drawn clock just stands.
      return _koCinematicStarted ? _koFallenPose(anims) : anims.idle;
    }
    final playerWon = outcome == MatchOutcome.playerWin;
    final won = (state.id == FighterId.player) == playerWon;
    if (won) {
      return anims.victory;
    }
    return _koCinematicStarted ? _koFallenPose(anims) : anims.defeat;
  }

  /// The loser's knockout fall: 600 ms of knockdown in animation time — which
  /// the slow-motion stretches on screen — then the defeat cycle, held on the
  /// ground by its non-looping ticker.
  SpriteAnimation _koFallenPose(_FighterAnims anims) =>
      _koAnimMs < _kKnockdownTotalMs ? anims.knockdown : anims.defeat;

  /// §1 block in three phases: the raise, the looping guard while the hold
  /// lasts, and the release over the final 120 ms of the window.
  SpriteAnimation _blockAnimation(_FighterAnims anims, FighterState state) {
    final elapsedMs = _match.rules.blockHoldMs - state.blockRemainingMs;
    if (elapsedMs < _kBlockRaiseStepsMs.first) {
      return anims.blockRaise;
    }
    if (state.blockRemainingMs > _kBlockReleaseStepsMs.first) {
      return anims.blockHold;
    }
    return anims.blockRelease;
  }

  /// Touch intents, in the shape the online mode will send them later.
  void sendPlayerAction(InputAction action) {
    if (_match.isFinished) {
      return;
    }
    _match.submit(
      InputCommand(
        fighter: FighterId.player,
        action: action,
        sequence: ++_playerSequence,
      ),
    );
  }

  /// Continuous MOVE control: -1 walks away from the rival, +1 walks towards
  /// them, anything between scales the stride. The rules apply
  /// walkSpeed * |axis| and keep the facing locked onto the rival, so a
  /// negative axis is a retreat, not a turn.
  void setPlayerMoveAxis(double axis) {
    if (_match.isFinished) {
      return;
    }
    _match.setMoveAxis(FighterId.player, axis);
  }

  /// Held MOVE control: walk towards the rival while pressed. Delegates to
  /// [setPlayerMoveAxis]; kept speaking in booleans for the tests and any
  /// caller that only has a button.
  void setPlayerMoving(bool moving) => setPlayerMoveAxis(moving ? 1 : 0);

  /// Back to the countdown with full health; the arena keeps its layout and
  /// drops every scrap of feel state from the finished match.
  void restartMatch() {
    _match.reset();
    _bot.reset();
    _playerSequence = 0;
    _hitStopMs = 0;
    _koSlowMoMs = 0;
    _koFreezeMs = 0;
    _koAnimMs = 0;
    _koCinematicStarted = false;
    _roundEndRevealed = false;
    _bursts.clear();
    _marks.clear();
    _shake = null;
    _pull = null;
    _prevAction.clear();
    for (final id in FighterId.values) {
      _landingSquashMs[id] = 0;
    }
    _syncFromMatch();
  }

  @override
  void update(double dt) {
    if (!_loaded) {
      super.update(dt);
      return;
    }
    final realMs = dt * 1000;

    // Two clocks: `simDt` drives the fighters, the bot, the match and their
    // sprite animations; `fxDt` drives the ink. Hit-stop zeroes the first and
    // keeps the second (§2: freeze the fighters, never the impact); the KO
    // cinematic slows or freezes both (§5).
    var simDt = dt;
    var fxDt = dt;
    if (_koFreezeMs > 0) {
      _koFreezeMs -= realMs;
      simDt = 0;
      fxDt = 0;
      if (_koFreezeMs <= 0) {
        _revealRoundEnd();
      }
    } else if (_koSlowMoMs > 0) {
      _koSlowMoMs -= realMs;
      simDt = dt * _kKoSlowMoFactor;
      fxDt = simDt;
      if (_koSlowMoMs <= 0) {
        _koFreezeMs = _kKoFreezeMs;
      }
    } else if (_hitStopMs > 0) {
      _hitStopMs -= realMs;
      simDt = 0;
    }

    if (simDt > 0) {
      final simMs = simDt * 1000;
      if (_koCinematicStarted) {
        // The fall runs on animation time: quarter-speed during the slow-mo,
        // frozen during the beat, real time once the card is up.
        _koAnimMs += simMs;
      }
      for (final id in FighterId.values) {
        final squash = _landingSquashMs[id]!;
        if (squash > 0) {
          _landingSquashMs[id] = math.max(0.0, squash - simMs);
        }
      }
      _bot.update(simDt, _match);
      _match.tick(simDt);
      _consumeHitEvents();
      _syncFromMatch();
      // The simulation runs before the sprite tickers so a swing's animation
      // starts on the same frame its action does — that is what puts the
      // contact frame on screen inside the active window (§1).
      super.update(simDt);
    }
    if (_match.isFinished && !_koCinematicStarted && !_roundEndRevealed) {
      // The clock decided it (or a double KO already ran its cinematic):
      // no slow motion, the card may stamp in at once.
      _revealRoundEnd();
    }
    _updateEffects(fxDt);
  }

  void _revealRoundEnd() {
    if (_roundEndRevealed) {
      return;
    }
    _roundEndRevealed = true;
    hudVersion.value++;
  }

  /// Turns every swing the controller resolved since the last frame into
  /// feel: the stop, the ink, the shake — and the KO cinematic when the blow
  /// ended the match.
  void _consumeHitEvents() {
    for (final event in _match.drainHitEvents()) {
      switch (event.kind) {
        case HitKind.whiff:
          break; // A swing on air gets no stop and no ink (§2).
        case HitKind.blocked:
          _hitStopMs = math.max(_hitStopMs, _kHitStopBlockedMs);
          // The restrained mark, no burst (§3).
          _marks.add(
            _ImpactMark(
              center: _contactPoint(event),
              size: _fighterHeight() * _kImpactMarkSizeShare,
            ),
          );
        case HitKind.hit:
          _hitStopMs = math.max(
            _hitStopMs,
            event.heavy ? _kHitStopHeavyMs : _kHitStopLightMs,
          );
          _spawnBurst(event);
          _shake = _Shake(
            ampPx: event.heavy ? _kShakeHeavyAmpPx : _kShakeLightAmpPx,
            lifeMs: event.heavy ? _kShakeHeavyMs : _kShakeLightMs,
          );
          _pull = _CameraPull(
            ampPx: event.heavy ? _kPullHeavyPx : _kPullLightPx,
            lifeMs: event.heavy ? _kPullHeavyMs : _kPullLightMs,
            center: _contactPoint(event),
          );
      }
      if (event.ko && _match.isFinished && !_koCinematicStarted) {
        _startKoCinematic();
      }
    }
  }

  void _startKoCinematic() {
    _koCinematicStarted = true;
    _koAnimMs = 0;
    _koFreezeMs = 0;
    _koSlowMoMs = _kKoSlowMoMs;
    // The KO blow goes straight into the slow motion; its own hit-stop would
    // only delay it (§5 orders slow-mo first, then the frozen beat).
    _hitStopMs = 0;
  }

  /// Where a swing's ink belongs, in viewport pixels: the event's arena-line
  /// position, at chest height of the fighters.
  ui.Offset _contactPoint(HitEvent event) => ui.Offset(
    event.x / _match.rules.arenaWidth * size.x,
    // Soles rest 12.1% of the sprite above the anchor; the contact reads at
    // ~43% of the body above that.
    _baselineY - _fighterHeight() * (.121 + .43),
  );

  double _fighterHeight() => _player?.size.y ?? 0;

  /// §3 ink burst: light 7 blobs r 6–18 px, heavy 12 blobs r 10–30 px with
  /// the last two in the rival's crimson.
  void _spawnBurst(HitEvent event) {
    final origin = _contactPoint(event);
    final heavy = event.heavy;
    final count = heavy ? 12 : 7;
    final minR = heavy ? 10.0 : 6.0;
    final maxR = heavy ? 30.0 : 18.0;
    final speed = heavy ? _kBurstHeavySpeedPxS : _kBurstLightSpeedPxS;
    final blobs = <_Blob>[];
    for (var i = 0; i < count; i++) {
      final angle = _fxRandom.nextDouble() * 2 * math.pi;
      final v = speed * (.55 + .45 * _fxRandom.nextDouble());
      blobs.add(
        _Blob(
          x: origin.dx,
          y: origin.dy,
          vx: math.cos(angle) * v,
          vy: math.sin(angle) * v,
          r: minR + _fxRandom.nextDouble() * (maxR - minR),
          crimson: heavy && i >= count - 2,
        ),
      );
    }
    _bursts.add(
      _Burst(blobs: blobs, lifeMs: heavy ? _kBurstHeavyMs : _kBurstLightMs),
    );
  }

  /// §6 landing puff: a handful of small blobs kicked sideways at the feet.
  void _spawnLandingPuff(FighterState state) {
    final feet = ui.Offset(
      state.x / _match.rules.arenaWidth * size.x,
      _baselineY - _fighterHeight() * .121,
    );
    final blobs = <_Blob>[];
    for (var i = 0; i < 4; i++) {
      final outward = i.isEven ? -1.0 : 1.0;
      blobs.add(
        _Blob(
          x: feet.dx,
          y: feet.dy,
          vx: outward * (30 + 40 * _fxRandom.nextDouble()),
          vy: -(10 + 25 * _fxRandom.nextDouble()),
          r: 3 + 4 * _fxRandom.nextDouble(),
        ),
      );
    }
    _bursts.add(_Burst(blobs: blobs, lifeMs: _kPuffMs));
  }

  void _updateEffects(double dt) {
    if (dt <= 0) {
      return;
    }
    final ms = dt * 1000;
    for (final burst in _bursts) {
      burst.ageMs += ms;
      for (final blob in burst.blobs) {
        blob.x += blob.vx * dt;
        blob.y += blob.vy * dt;
      }
    }
    _bursts.removeWhere((burst) => burst.ageMs >= burst.lifeMs);
    for (final mark in _marks) {
      mark.ageMs += ms;
    }
    _marks.removeWhere((mark) => mark.ageMs >= _kImpactMarkMs);
    final shake = _shake;
    if (shake != null) {
      shake.ageMs += ms;
      if (shake.ageMs >= shake.lifeMs) {
        _shake = null;
      }
    }
    final pull = _pull;
    if (pull != null) {
      pull.ageMs += ms;
      if (pull.ageMs >= pull.lifeMs) {
        _pull = null;
      }
    }
  }

  void _syncFromMatch() {
    if (!_loaded || _player == null || _rival == null) {
      return;
    }
    final player = _match.stateOf(FighterId.player);
    final rival = _match.stateOf(FighterId.rival);
    _apply(_player!, _playerAnims!, player);
    _apply(_rival!, _rivalAnims!, rival);

    final snapshot = Object.hash(
      player.health,
      rival.health,
      _match.timeRemainingMs ~/ 1000,
      _match.phase,
      _match.outcome,
    );
    if (snapshot != _lastHudSnapshot) {
      _lastHudSnapshot = snapshot;
      hudVersion.value++;
    }
  }

  void _apply(
    SpriteAnimationComponent component,
    _FighterAnims anims,
    FighterState state,
  ) {
    final prevAction = _prevAction[state.id];
    _prevAction[state.id] = state.action;

    component.position.x = state.x / _match.rules.arenaWidth * size.x;
    // Frames are drawn facing right; `facing` mirrors whoever stands right.
    component.scale.x = state.facing;

    if (_match.isFinished) {
      _setAnimation(
        component,
        _endPose(anims, state),
        state.action,
        prevAction,
      );
      component.position.y = _baselineY;
      return;
    }

    // §6 landing: the jump cycle ended on its own feet — squash for 90 ms and
    // kick up a small puff. A jump interrupted by a hit does not land; it
    // stings.
    if (prevAction == FighterAction.jump &&
        state.action == FighterAction.idle) {
      _landingSquashMs[state.id] = _kLandingSquashMs;
      _spawnLandingPuff(state);
    }
    final squashMs = _landingSquashMs[state.id] ?? 0;
    // The anchor is the bottom centre, so squashing scale.y keeps the soles
    // on the floor line.
    component.scale.y = squashMs > 0 ? _kLandingSquashScaleY : 1;

    final animation = state.action == FighterAction.block
        ? _blockAnimation(anims, state)
        : anims.forAction(state.action);
    _setAnimation(component, animation, state.action, prevAction);

    var y = _baselineY;
    if (state.isAirborne) {
      final progress = 1 - state.jumpRemainingMs / _match.rules.jumpMs;
      y -= math.sin(math.pi * progress.clamp(0, 1)) * component.size.y * .16;
    }
    component.position.y = y;
  }

  /// Points the component at [animation], restarting it when the fighter
  /// re-enters an action it just left (hurt → idle → hurt must flinch again,
  /// a second jab must swing again). Assigning a different instance already
  /// creates a fresh ticker; assigning the *same* one is a no-op in Flame, so
  /// the reset has to be explicit.
  void _setAnimation(
    SpriteAnimationComponent component,
    SpriteAnimation animation,
    FighterAction action,
    FighterAction? prevAction,
  ) {
    if (component.animation != animation) {
      component.animation = animation;
    } else if (action != prevAction) {
      component.animationTicker?.reset();
    }
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _layout(size);
  }

  void _layout(Vector2 viewportSize) {
    if (!_loaded || viewportSize.x <= 0 || viewportSize.y <= 0) {
      return;
    }

    final fighterSize = math.min(
      viewportSize.y * .74,
      viewportSize.x * _fighterWidthShare,
    );
    final sizeVector = Vector2.all(fighterSize);
    _player!.size = sizeVector;
    _rival!.size = sizeVector;
    // The runtime frames carry ~12% transparent padding under the feet, so
    // sink the anchor by that share to put the soles on the arena floor.
    _baselineY = viewportSize.y * .80 + fighterSize * .121;
    for (final painter in _countdownPainters.values) {
      painter.dispose();
    }
    _countdownPainters.clear();
    _syncFromMatch();
  }

  @override
  void render(ui.Canvas canvas) {
    // The paper stays put: the world shakes over it, never off it.
    final paper = ui.Paint()..color = InkColors.paper;
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, size.x, size.y), paper);

    canvas.save();
    _applyCameraResponse(canvas);

    final grid = ui.Paint()
      ..color = InkColors.line.withValues(alpha: .24)
      ..strokeWidth = 1;
    for (double x = 0; x < size.x; x += 48) {
      canvas.drawLine(ui.Offset(x, 0), ui.Offset(x, size.y), grid);
    }
    for (double y = 0; y < size.y; y += 48) {
      canvas.drawLine(ui.Offset(0, y), ui.Offset(size.x, y), grid);
    }

    final floor = size.y * .80;
    final arenaLine = ui.Paint()
      ..color = InkColors.ink.withValues(alpha: .16)
      ..strokeWidth = 1.4
      ..style = ui.PaintingStyle.stroke;
    canvas.drawLine(ui.Offset(0, floor), ui.Offset(size.x, floor), arenaLine);
    canvas.drawOval(
      ui.Rect.fromCenter(
        center: ui.Offset(size.x / 2, floor),
        width: size.x * .56,
        height: size.y * .18,
      ),
      arenaLine,
    );

    super.render(canvas);
    // The ink draws over the fighters — the impact is the loudest thing on
    // screen for its few frames, but every effect lives and dies within the
    // ±15% height budget around the contact point and far below the HUD
    // (GDD §7: nothing hides the fighters or the health state).
    _renderInk(canvas);
    canvas.restore();

    _renderCountdown(canvas);
  }

  /// §3 shake and camera response, applied to the world only. The HUD is a
  /// Flutter widget stacked above the game, so it stays still for free.
  void _applyCameraResponse(ui.Canvas canvas) {
    final pull = _pull;
    if (pull != null) {
      final t = (pull.ageMs / pull.lifeMs).clamp(0.0, 1.0);
      // Peak displacement of `ampPx` half a screen away from the contact
      // point, easing out — a 4 px pull reads as the camera leaning in.
      final scale = 1 + pull.ampPx / (size.x * .5) * (1 - t);
      canvas.translate(pull.center.dx, pull.center.dy);
      canvas.scale(scale, scale);
      canvas.translate(-pull.center.dx, -pull.center.dy);
    }
    final shake = _shake;
    if (shake != null) {
      final t = (shake.ageMs / shake.lifeMs).clamp(0.0, 1.0);
      final wave = math.sin(shake.ageMs / _kShakePeriodMs * 2 * math.pi);
      canvas.translate(shake.ampPx * wave * (1 - t), 0);
    }
  }

  void _renderInk(ui.Canvas canvas) {
    for (final burst in _bursts) {
      final fade = (1 - burst.ageMs / burst.lifeMs).clamp(0.0, 1.0);
      for (final blob in burst.blobs) {
        final paint = ui.Paint()
          ..color = (blob.crimson ? _kCrimsonFleck : InkColors.ink).withValues(
            alpha: fade * .85,
          );
        canvas.drawCircle(
          ui.Offset(blob.x, blob.y),
          blob.r * (.65 + .35 * fade),
          paint,
        );
      }
    }
    for (final mark in _marks) {
      final t = (mark.ageMs / _kImpactMarkMs).clamp(0.0, 1.0);
      final fade = 1 - t;
      final r = mark.size * .5 * (1 + .25 * t);
      final center = mark.center;
      final core = ui.Paint()..color = InkColors.white.withValues(alpha: fade);
      canvas.drawCircle(center, r * .55, core);
      final ring = ui.Paint()
        ..color = InkColors.ink.withValues(alpha: fade)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, mark.size * .07)
        ..strokeCap = ui.StrokeCap.round;
      canvas.drawCircle(center, r, ring);
      for (var i = 0; i < 4; i++) {
        final angle = math.pi / 4 + i * math.pi / 2;
        canvas.drawLine(
          ui.Offset(
            center.dx + math.cos(angle) * r * 1.3,
            center.dy + math.sin(angle) * r * 1.3,
          ),
          ui.Offset(
            center.dx + math.cos(angle) * r * 1.9,
            center.dy + math.sin(angle) * r * 1.9,
          ),
          ring,
        );
      }
    }
  }

  /// §5 countdown: four 500 ms beats — 3 · 2 · 1 · FIGHT! — popping at each
  /// beat, in the doodle language: a soft ink bleed under the solid stroke.
  void _renderCountdown(ui.Canvas canvas) {
    if (_match.phase != MatchPhase.countdown) {
      return;
    }
    final remaining = _match.countdownRemainingMs;
    if (remaining <= 0) {
      return;
    }
    final label = remaining > 1500
        ? '3'
        : remaining > 1000
        ? '2'
        : remaining > 500
        ? '1'
        : 'FIGHT!';
    final beatMs = _match.rules.countdownMs / 4;
    final elapsed = _match.rules.countdownMs - remaining;
    final progress = (elapsed % beatMs) / beatMs;

    final bleed = _countdownPainter(label, bleed: true);
    final solid = _countdownPainter(label, bleed: false);
    canvas.save();
    canvas.translate(size.x / 2, size.y * .36);
    // Each beat stamps in slightly oversize and settles.
    final scale = 1 + .12 * (1 - progress);
    canvas.scale(scale, scale);
    bleed.paint(canvas, ui.Offset(-bleed.width / 2 + 3, -bleed.height / 2 + 3));
    solid.paint(canvas, ui.Offset(-solid.width / 2, -solid.height / 2));
    canvas.restore();
  }

  TextPainter _countdownPainter(String label, {required bool bleed}) {
    final fontSize = size.y * .16;
    return _countdownPainters.putIfAbsent('$label|$bleed|$fontSize', () {
      return TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: label.length > 2 ? 3 : 0,
            color: bleed ? InkColors.ink.withValues(alpha: .16) : InkColors.ink,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
    });
  }
}

/// The animation cycles one fighter view needs, built to the recipes in
/// docs/technical/GAME_FEEL.md §1.
class _FighterAnims {
  _FighterAnims({
    required this.idle,
    required this.walk,
    required this.jump,
    required this.lightPunch,
    required this.heavyKick,
    required this.blockRaise,
    required this.blockHold,
    required this.blockRelease,
    required this.hurt,
    required this.knockdown,
    required this.victory,
    required this.defeat,
  });

  final SpriteAnimation idle;
  final SpriteAnimation walk;
  final SpriteAnimation jump;
  final SpriteAnimation lightPunch;
  final SpriteAnimation heavyKick;

  /// Guard raise / held guard / guard drop (§1 block).
  final SpriteAnimation blockRaise;
  final SpriteAnimation blockHold;
  final SpriteAnimation blockRelease;

  final SpriteAnimation hurt;

  /// The knockout fall, before [defeat] on the ground (§5). Both characters
  /// ship both cycles — the 96-frame set is complete.
  final SpriteAnimation knockdown;

  final SpriteAnimation victory;
  final SpriteAnimation defeat;

  SpriteAnimation forAction(FighterAction action) => switch (action) {
    FighterAction.idle => idle,
    FighterAction.walk => walk,
    FighterAction.jump => jump,
    FighterAction.lightPunch => lightPunch,
    FighterAction.heavyKick => heavyKick,
    // Refined per phase by _blockAnimation(); the loop is the sane default.
    FighterAction.block => blockHold,
    FighterAction.hitstun || FighterAction.blockstun => hurt,
  };
}

/// One ink blob flying out of a contact point (GAME_FEEL §3).
class _Blob {
  _Blob({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.r,
    this.crimson = false,
  });

  double x;
  double y;

  /// Velocity in viewport pixels per second.
  final double vx;
  final double vy;

  /// Radius in viewport pixels.
  final double r;

  /// The two crimson flecks a heavy burst carries.
  final bool crimson;
}

/// A burst of blobs with one shared lifetime.
class _Burst {
  _Burst({required this.blobs, required this.lifeMs});

  final List<_Blob> blobs;
  final double lifeMs;
  double ageMs = 0;
}

/// The restrained black-and-white mark a blocked hit leaves for 90 ms
/// (GAME_FEEL §3, art bible §4).
class _ImpactMark {
  _ImpactMark({required this.center, required this.size});

  final ui.Offset center;
  final double size;
  double ageMs = 0;
}

/// A decaying sine shake along x (GAME_FEEL §3).
class _Shake {
  _Shake({required this.ampPx, required this.lifeMs});

  final double ampPx;
  final double lifeMs;
  double ageMs = 0;
}

/// The brief camera lean around a contact point (GAME_FEEL §3).
class _CameraPull {
  _CameraPull({
    required this.ampPx,
    required this.lifeMs,
    required this.center,
  });

  final double ampPx;
  final double lifeMs;
  final ui.Offset center;
  double ageMs = 0;
}
