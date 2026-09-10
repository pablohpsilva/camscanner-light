import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/view_state.dart';

void main() {
  // Exhaustive switch: the compiler enforces all four cases, and each maps to a
  // distinct outcome — the whole point of replacing the loose booleans.
  String describe(ViewState<int> s) => switch (s) {
    Loading() => 'loading',
    ErrorState(:final message) => 'error:$message',
    Empty() => 'empty',
    Loaded(:final data) => 'loaded:$data',
  };

  test('each case maps distinctly through an exhaustive switch', () {
    expect(describe(const Loading()), 'loading');
    expect(describe(const ErrorState('boom')), 'error:boom');
    expect(describe(const Empty()), 'empty');
    expect(describe(const Loaded(7)), 'loaded:7');
  });

  test('value equality', () {
    expect(const Loading<int>(), const Loading<int>());
    expect(const Empty<int>(), const Empty<int>());
    expect(const ErrorState<int>('a'), const ErrorState<int>('a'));
    expect(const ErrorState<int>('a'), isNot(const ErrorState<int>('b')));
    expect(const Loaded<int>(1), const Loaded<int>(1));
    expect(const Loaded<int>(1), isNot(const Loaded<int>(2)));
    expect(const Loading<int>(), isNot(const Empty<int>()));
  });

  // `expect(a, b)` only exercises operator==, so hashCode went untested. It is
  // a real contract, not a formality: these states are compared and stored by
  // ListenableBuilder-driven UI, and a hashCode that disagrees with == breaks
  // any Set/Map of them while == keeps looking correct.
  test('equal states share a hashCode', () {
    expect(const Loading<int>().hashCode, const Loading<int>().hashCode);
    expect(const Empty<int>().hashCode, const Empty<int>().hashCode);
    expect(
      const ErrorState<int>('a').hashCode,
      const ErrorState<int>('a').hashCode,
    );
    expect(const Loaded<int>(1).hashCode, const Loaded<int>(1).hashCode);
  });

  test('distinct states do not collide, and Set treats them as distinct', () {
    expect(
      const ErrorState<int>('a').hashCode,
      isNot(const ErrorState<int>('b').hashCode),
    );
    expect(const Loaded<int>(1).hashCode, isNot(const Loaded<int>(2).hashCode));
    expect(const Loading<int>().hashCode, isNot(const Empty<int>().hashCode));

    // The behaviour a wrong hashCode actually breaks. Built from a list rather
    // than a set literal so the duplicates are not a static lint (the point IS
    // that Set collapses them at runtime, via hashCode + ==).
    const states = <ViewState<int>>[
      Loading(),
      Loading(),
      Empty(),
      Loaded(1),
      Loaded(1),
      Loaded(2),
      ErrorState('a'),
    ];
    expect(states.toSet(), hasLength(5));
  });
}
