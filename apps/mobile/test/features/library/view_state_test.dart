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
}
