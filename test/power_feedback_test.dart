import 'package:flutter_test/flutter_test.dart';
import 'package:prosthesis_mobile_controller/models/action_command.dart';
import 'package:prosthesis_mobile_controller/models/power_feedback.dart';

void main() {
  group('PowerFeedback.tryParse', () {
    test('parses a successful power_on feedback', () {
      final feedback = PowerFeedback.tryParse(
        '{"timestamp": "2026-08-17T12:00:00.421870+00:00", "command": "power_on", '
        '"status": "success", "state": "on", "gait": 3, '
        '"message": "started RoboticLegControl (sudo pid 4312)"}',
      );

      expect(feedback, isNotNull);
      expect(feedback!.command, PowerCommand.powerOn);
      expect(feedback.status, PowerFeedbackStatus.success);
      expect(feedback.state, ProsthesisState.on);
      expect(feedback.gait, 3);
      expect(feedback.gaitMode, GaitMode.standing);
      expect(feedback.isSuccess, isTrue);
      expect(feedback.message, 'started RoboticLegControl (sudo pid 4312)');
      expect(feedback.timestamp, DateTime.utc(2026, 8, 17, 12, 0, 0, 421, 870));
    });

    test('parses a failed power_off feedback, keeping the reported state', () {
      final feedback = PowerFeedback.tryParse(
        '{"timestamp": "2026-08-17T12:06:02.774390+00:00", "command": "power_off", '
        '"status": "failure", "state": "on", "gait": 1, '
        '"message": "RoboticLegControl is still running after kill (pids 4312)"}',
      );

      expect(feedback, isNotNull);
      expect(feedback!.command, PowerCommand.powerOff);
      expect(feedback.isSuccess, isFalse);
      expect(feedback.state, ProsthesisState.on);
      expect(feedback.gaitMode, GaitMode.walking);
    });

    test('parses a set_gait feedback', () {
      final feedback = PowerFeedback.tryParse(
        '{"timestamp": "2026-08-17T12:03:00.100000+00:00", "command": "set_gait", '
        '"status": "success", "state": "on", "gait": 4, '
        '"message": "stopped RoboticLegControl; started with gait 4"}',
      );

      expect(feedback, isNotNull);
      expect(feedback!.command, PowerCommand.setGait);
      expect(feedback.isSuccess, isTrue);
      expect(feedback.state, ProsthesisState.on);
      expect(feedback.gaitMode, GaitMode.stairDescent);
    });

    test('parses a failed set_gait feedback', () {
      final feedback = PowerFeedback.tryParse(
        '{"timestamp": "2026-08-17T12:03:00.100000+00:00", "command": "set_gait", '
        '"status": "failure", "state": "off", "gait": 4, '
        '"message": "failed to start RoboticLegControl"}',
      );

      expect(feedback, isNotNull);
      expect(feedback!.command, PowerCommand.setGait);
      expect(feedback.isSuccess, isFalse);
      expect(feedback.state, ProsthesisState.off);
      expect(feedback.gaitMode, GaitMode.stairDescent);
    });

    test('keeps a gait value it cannot map to a known mode', () {
      final feedback = PowerFeedback.tryParse(
        '{"timestamp": "2026-08-17T12:06:02.774390+00:00", "command": "power_off", '
        '"status": "success", "state": "off", "gait": 0, '
        '"message": "stopped RoboticLegControl"}',
      );

      expect(feedback, isNotNull);
      expect(feedback!.gait, 0);
      expect(feedback.gaitMode, isNull);
    });

    test('ignores unknown fields', () {
      final feedback = PowerFeedback.tryParse(
        '{"timestamp": "2026-08-17T12:00:00.421870+00:00", "command": "power_on", '
        '"status": "success", "state": "on", "gait": 1, "message": "ok", '
        '"extra": 42}',
      );

      expect(feedback, isNotNull);
      expect(feedback!.state, ProsthesisState.on);
    });

    test('returns null for malformed payloads', () {
      const missingField =
          '{"timestamp": "2026-08-17T12:00:00.421870+00:00", "command": "power_on", '
          '"status": "success", "state": "on", "gait": 1}';
      const missingGait =
          '{"timestamp": "2026-08-17T12:00:00.421870+00:00", "command": "power_on", '
          '"status": "success", "state": "on", "message": "ok"}';
      const badGait =
          '{"timestamp": "2026-08-17T12:00:00.421870+00:00", "command": "power_on", '
          '"status": "success", "state": "on", "gait": "1", "message": "ok"}';
      const unknownEnum =
          '{"timestamp": "2026-08-17T12:00:00.421870+00:00", "command": "reboot", '
          '"status": "success", "state": "on", "gait": 1, "message": "ok"}';
      const badTimestamp =
          '{"timestamp": "not a date", "command": "power_on", '
          '"status": "success", "state": "on", "gait": 1, "message": "ok"}';

      expect(PowerFeedback.tryParse(missingField), isNull);
      expect(PowerFeedback.tryParse(missingGait), isNull);
      expect(PowerFeedback.tryParse(badGait), isNull);
      expect(PowerFeedback.tryParse(unknownEnum), isNull);
      expect(PowerFeedback.tryParse(badTimestamp), isNull);
      expect(PowerFeedback.tryParse('not json'), isNull);
      expect(PowerFeedback.tryParse('[]'), isNull);
    });
  });

  test('PowerCommand maps to and from the power command values', () {
    expect(PowerCommand.forState(PowerState.on), PowerCommand.powerOn);
    expect(PowerCommand.forState(PowerState.off), PowerCommand.powerOff);
    expect(PowerCommand.powerOn.requestedState, PowerState.on);
    expect(PowerCommand.powerOff.requestedState, PowerState.off);
    expect(PowerCommand.setGait.requestedState, isNull);
  });

  test('GaitMode.fromValue maps wire values to modes', () {
    for (final mode in GaitMode.values) {
      expect(GaitMode.fromValue(mode.value), mode);
    }
    expect(GaitMode.fromValue(0), isNull);
    expect(GaitMode.fromValue(99), isNull);
    expect(GaitMode.fromValue('1'), isNull);
  });
}
