import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/async/with_isolate_timeout.dart';

void main() {
  group('withIsolateTimeout', () {
    test('normal path: returns the value produced by run', () async {
      final result = await withIsolateTimeout<int>(
        () => 42,
        timeout: const Duration(milliseconds: 200),
      );

      expect(result, 42);
    });

    test(
      'timeout path: throws TimeoutException when run never completes',
      () async {
        final neverCompletes = Completer<int>();

        expect(
          () => withIsolateTimeout<int>(
            () => neverCompletes.future,
            timeout: const Duration(milliseconds: 50),
          ),
          throwsA(isA<TimeoutException>()),
        );
      },
    );

    test(
      'onTimeout fallback: returns the fallback value instead of throwing',
      () async {
        final neverCompletes = Completer<int>();

        final result = await withIsolateTimeout<int>(
          () => neverCompletes.future,
          timeout: const Duration(milliseconds: 50),
          onTimeout: () => -1,
        );

        expect(result, -1);
      },
    );

    test(
      'error passthrough: an error thrown inside run propagates unchanged',
      () async {
        final boom = StateError('boom');

        await expectLater(
          withIsolateTimeout<int>(
            () => throw boom,
            timeout: const Duration(milliseconds: 200),
          ),
          throwsA(same(boom)),
        );
      },
    );
  });
}
