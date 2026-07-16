/// A four-case load state (P06 task 2), replacing the loose
/// `_loading`/`_error`/`_empty` booleans whose combinations could represent
/// illegal states (e.g. loading AND error). Being `sealed`, a `switch` over it
/// is exhaustive and illegal combinations are unrepresentable.
sealed class ViewState<T> {
  const ViewState();
}

/// The data is being (re)loaded.
class Loading<T> extends ViewState<T> {
  const Loading();
  @override
  bool operator ==(Object other) => other is Loading<T>;
  @override
  int get hashCode => (Loading<T>).hashCode;
}

/// The load failed with a user-facing [message].
class ErrorState<T> extends ViewState<T> {
  final String message;
  const ErrorState(this.message);
  @override
  bool operator ==(Object other) =>
      other is ErrorState<T> && other.message == message;
  @override
  int get hashCode => Object.hash(ErrorState<T>, message);
}

/// Loaded successfully, but there is nothing to show.
class Empty<T> extends ViewState<T> {
  const Empty();
  @override
  bool operator ==(Object other) => other is Empty<T>;
  @override
  int get hashCode => (Empty<T>).hashCode;
}

/// Loaded successfully with [data].
class Loaded<T> extends ViewState<T> {
  final T data;
  const Loaded(this.data);
  @override
  bool operator ==(Object other) => other is Loaded<T> && other.data == data;
  @override
  int get hashCode => Object.hash(Loaded<T>, data);
}
