import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/async/with_isolate_timeout.dart';

/// Top-level so it can cross the [compute] isolate boundary in the
/// [computeWithTimeout] smoke test (closures cannot be sent to an isolate).
int _addOne(int value) => value + 1;

void main() {
  group('withIsolateTimeout', () {
    test('normal path: returns the value produced by run', () async {
      final result = await withIsolateTimeout<int>(
        () => 42,
        timeout: const Duration(milliseconds: 200),
      );

      expect(result, 42);
    });

    test('timeout path: throws TimeoutException when run never completes', () {
      // fakeAsync drives the timeout timer to fire deterministically —
      // no real 50ms wall-clock wait, no flakiness under load.
      fakeAsync((async) {
        final neverCompletes = Completer<int>();
        Object? caught;

        withIsolateTimeout<int>(
          () => neverCompletes.future,
          timeout: const Duration(milliseconds: 50),
        ).catchError((Object error) {
          caught = error;
          return 0; // catchError must return the future's value type.
        });

        async.elapse(const Duration(milliseconds: 50));

        expect(caught, isA<TimeoutException>());
      });
    });

    test(
      'onTimeout fallback: returns the fallback value instead of throwing',
      () {
        fakeAsync((async) {
          final neverCompletes = Completer<int>();
          int? result;

          withIsolateTimeout<int>(
            () => neverCompletes.future,
            timeout: const Duration(milliseconds: 50),
            onTimeout: () => -1,
          ).then((value) => result = value);

          async.elapse(const Duration(milliseconds: 50));

          expect(result, -1);
        });
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

  group('computeWithTimeout', () {
    test('smoke: returns the value produced by the compute isolate', () async {
      final result = await computeWithTimeout<int, int>(
        _addOne,
        41,
        timeout: const Duration(seconds: 5),
      );

      expect(result, 42);
    });
  });
}
