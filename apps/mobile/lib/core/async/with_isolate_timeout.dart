import 'dart:async';

import 'package:flutter/foundation.dart' show ComputeCallback, compute;

/// Runs [run] and enforces [timeout] on the result.
///
/// A wedged native isolate (e.g. a `compute()` call stuck inside native
/// OpenCV/ML Kit code) CANNOT be killed from Dart — [Future.timeout] only
/// detaches the awaiting [Future]; the underlying isolate may keep running
/// in the background. This helper exists to make that detachment explicit
/// and reusable, not to actually cancel work.
///
/// If [run] throws (synchronously or asynchronously), the error propagates
/// unchanged. If [run] does not complete within [timeout], this throws a
/// [TimeoutException] unless [onTimeout] is supplied, in which case its
/// value/future is used instead.
Future<T> withIsolateTimeout<T>(
  FutureOr<T> Function() run, {
  required Duration timeout,
  FutureOr<T> Function()? onTimeout,
}) {
  return Future(() => run()).timeout(timeout, onTimeout: onTimeout);
}

/// Thin convenience wrapper around [compute] that applies [withIsolateTimeout]
/// semantics to a `compute()` isolate call. Mirrors the guarded pattern used
/// by `NativePageProcessor` (a `compute()` wrapped in `.timeout(...)`) so new
/// call sites do not have to repeat it inline.
///
/// See [withIsolateTimeout] for the timeout/cancellation caveats — they
/// apply here identically, since [compute] itself spawns an isolate that
/// cannot be killed from Dart if it wedges.
Future<R> computeWithTimeout<Q, R>(
  ComputeCallback<Q, R> fn,
  Q message, {
  required Duration timeout,
}) {
  return compute(fn, message).timeout(timeout);
}
