import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/logging/app_logger.dart';

void main() {
  group('SilentAppLogger', () {
    test('records error, stackTrace, and context passed to error()', () {
      final logger = SilentAppLogger();
      final stackTrace = StackTrace.current;
      final error = Exception('boom');

      logger.error(error, stackTrace: stackTrace, context: 'unit-test');

      expect(logger.records, hasLength(1));
      final record = logger.records.single;
      expect(record.error, same(error));
      expect(record.stackTrace, same(stackTrace));
      expect(record.context, 'unit-test');
    });

    test('records multiple calls in order with nullable fields', () {
      final logger = SilentAppLogger();
      final first = Exception('first');
      final second = Exception('second');

      logger.error(first);
      logger.error(second, context: 'second-call');

      expect(logger.records, hasLength(2));
      expect(logger.records[0].error, same(first));
      expect(logger.records[0].stackTrace, isNull);
      expect(logger.records[0].context, isNull);
      expect(logger.records[1].error, same(second));
      expect(logger.records[1].context, 'second-call');
    });
  });

  group('PrintAppLogger', () {
    test('is const-constructible', () {
      const logger = PrintAppLogger();
      expect(logger, isA<AppLogger>());
    });

    test('error() does not throw with stackTrace and context', () {
      const logger = PrintAppLogger();
      expect(
        () => logger.error(
          Exception('boom'),
          stackTrace: StackTrace.current,
          context: 'unit-test',
        ),
        returnsNormally,
      );
    });

    test('error() does not throw without stackTrace or context', () {
      const logger = PrintAppLogger();
      expect(() => logger.error(Exception('boom')), returnsNormally);
    });
  });
}
