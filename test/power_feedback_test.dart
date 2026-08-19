import 'package:flutter_test/flutter_test.dart';
import 'package:prothesis_mobile_controller/models/action_command.dart';
import 'package:prothesis_mobile_controller/models/power_feedback.dart';

void main() {
  group('PowerFeedback.tryParse', () {
    test('parses a successful power_on feedback', () {
      final feedback = PowerFeedback.tryParse(
        '{"timestamp": "2026-08-17T12:00:00.421870+00:00", "command": "power_on", '
        '"status": "success", "state": "on", '
        '"message": "started RoboticLegControl (sudo pid 4312)"}',
      );

      expect(feedback, isNotNull);
      expect(feedback!.command, PowerCommand.powerOn);
      expect(feedback.status, PowerFeedbackStatus.success);
      expect(feedback.state, ProsthesisState.on);
      expect(feedback.isSuccess, isTrue);
      expect(feedback.message, 'started RoboticLegControl (sudo pid 4312)');
      expect(
        feedback.timestamp,
        DateTime.utc(2026, 8, 17, 12, 0, 0, 421, 870),
      );
    });

    test('parses a failed power_off feedback, keeping the reported state', () {
      final feedback = PowerFeedback.tryParse(
        '{"timestamp": "2026-08-17T12:06:02.774390+00:00", "command": "power_off", '
        '"status": "failure", "state": "on", '
        '"message": "RoboticLegControl is still running after kill (pids 4312)"}',
      );

      expect(feedback, isNotNull);
      expect(feedback!.command, PowerCommand.powerOff);
      expect(feedback.isSuccess, isFalse);
      expect(feedback.state, ProsthesisState.on);
    });

    test('ignores unknown fields', () {
      final feedback = PowerFeedback.tryParse(
        '{"timestamp": "2026-08-17T12:00:00.421870+00:00", "command": "power_on", '
        '"status": "success", "state": "on", "message": "ok", "extra": 42}',
      );

      expect(feedback, isNotNull);
      expect(feedback!.state, ProsthesisState.on);
    });

    test('returns null for malformed payloads', () {
      const missingField =
          '{"timestamp": "2026-08-17T12:00:00.421870+00:00", "command": "power_on", '
          '"status": "success", "state": "on"}';
      const unknownEnum =
          '{"timestamp": "2026-08-17T12:00:00.421870+00:00", "command": "reboot", '
          '"status": "success", "state": "on", "message": "ok"}';
      const badTimestamp =
          '{"timestamp": "not a date", "command": "power_on", '
          '"status": "success", "state": "on", "message": "ok"}';

      expect(PowerFeedback.tryParse(missingField), isNull);
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
  });
}
