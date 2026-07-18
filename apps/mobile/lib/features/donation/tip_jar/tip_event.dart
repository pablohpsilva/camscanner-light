/// A purchase-flow update from the store, mapped to a plugin-free type.
sealed class TipEvent {
  const TipEvent();
}

/// The purchase is awaiting external action (e.g. Ask-to-Buy approval).
class TipEventPending extends TipEvent {
  const TipEventPending();
}

/// The purchase completed and was acknowledged to the store.
class TipEventSuccess extends TipEvent {
  const TipEventSuccess();
}

/// The user dismissed/cancelled the store sheet. Not an error.
class TipEventCanceled extends TipEvent {
  const TipEventCanceled();
}

/// The purchase failed.
class TipEventError extends TipEvent {
  const TipEventError();
}
