import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/logging/app_logger.dart';
import 'package:mobile/features/library/async_action_controller.dart';

/// Unit tests for the guarded async-action primitive (P06 task 1) — no widget
/// is pumped; the controller is a plain [ChangeNotifier] like SaveController.
void main() {
  test('drives idle → busy → idle around a successful action', () async {
    final c = AsyncActionController();
    final busyLog = <bool>[];
    c.addListener(() => busyLog.add(c.busy));

    expect(c.busy, isFalse);
    final result = await c.run(() async => 42);

    expect(result, 42);
    expect(c.busy, isFalse);
    expect(c.lastActionFailed, isFalse);
    expect(busyLog, [true, false]); // busy toggled on then off
  });

  test(
    'on failure: returns null, clears busy, logs, sets lastActionFailed',
    () async {
      final logger = SilentAppLogger();
      final c = AsyncActionController(logger: logger);

      final result = await c.run(
        () async => throw StateError('boom'),
        context: 'exportPdf',
      );

      expect(result, isNull);
      expect(c.busy, isFalse); // cleared in finally
      expect(c.lastActionFailed, isTrue);
      expect(logger.records, hasLength(1));
      expect(logger.records.single.context, 'exportPdf');
    },
  );

  test('is single-flight: a second run while busy is a no-op', () async {
    final c = AsyncActionController();
    var secondRan = false;

    final first = c.run(() async {
      // While the first action is in flight, a second run must be refused.
      final skipped = await c.run(() async {
        secondRan = true;
        return 1;
      });
      expect(skipped, isNull);
      return 0;
    });

    expect(await first, 0);
    expect(secondRan, isFalse);
  });

  test('resets lastActionFailed on the next successful run', () async {
    final c = AsyncActionController();
    await c.run(() async => throw StateError('x'));
    expect(c.lastActionFailed, isTrue);
    await c.run(() async => 1);
    expect(c.lastActionFailed, isFalse);
  });

  test('suppresses notifications after dispose', () async {
    final c = AsyncActionController();
    var notified = false;
    c.addListener(() => notified = true);
    c.dispose();
    final result = await c.run(() async => 1);
    expect(result, isNull); // disposed → skipped
    expect(notified, isFalse);
  });
}
