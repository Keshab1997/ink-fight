import 'match_rules.dart';

/// The four one-shot actions a touch control can send. Movement is continuous
/// and travels as an axis instead (see `MatchController.setMoveAxis`).
enum InputAction { lightPunch, heavyKick, jump, block }

/// One player intent, in the shape the online mode will send it
/// (docs/technical/TECHNICAL_ARCHITECTURE.md): who, what, a sequence number and
/// a client timestamp.
///
/// It carries intent only — never a claimed result. The controller decides
/// whether the intent was legal and what it did; a stale sequence number is
/// dropped rather than replayed.
class InputCommand {
  const InputCommand({
    required this.fighter,
    required this.action,
    required this.sequence,
    this.timestampMs = 0,
  });

  final FighterId fighter;
  final InputAction action;
  final int sequence;
  final int timestampMs;
}
