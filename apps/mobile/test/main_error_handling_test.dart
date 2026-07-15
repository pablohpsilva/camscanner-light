// Unit test for installGlobalErrorHandling: verifies uncaught FlutterError
// details are forwarded to the injected AppLogger while still tagging the
// context, without depending on the framework's default presentation.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/logging/app_logger.dart';
import 'package:mobile/main.dart';

void main() {
  test(
    'installGlobalErrorHandling forwards FlutterError details to the logger',
    () {
      // Saved/restored here in the test body (NOT tearDown/addTearDown): an
      // invariant fires first on tearDown and would leak the override.
      final previousOnError = FlutterError.onError;
      try {
        final silent = SilentAppLogger();
        installGlobalErrorHandling(silent);

        final error = StateError('boom');
        final stack = StackTrace.current;
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack),
        );

        expect(silent.records, hasLength(1));
        final record = silent.records.single;
        expect(record.error, same(error));
        expect(record.stackTrace, same(stack));
        expect(record.context, 'FlutterError');
      } finally {
        FlutterError.onError = previousOnError;
      }
    },
  );
}
