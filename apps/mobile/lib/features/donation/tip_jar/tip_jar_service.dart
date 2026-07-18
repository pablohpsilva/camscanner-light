import 'tip_event.dart';
import 'tip_product.dart';

/// Loads tip products and drives consumable purchases. Injectable so the UI is
/// host-testable with a fake while the real StoreKit path stays isolated.
abstract class TipJarService {
  /// Returns the available tip products (ascending price), or an empty list if
  /// the store is unavailable or no products resolve.
  Future<List<TipProduct>> loadProducts();

  /// Starts a consumable purchase for [product]. Results arrive on [events].
  Future<void> buy(TipProduct product);

  /// Purchase-flow updates (pending / success / canceled / error).
  Stream<TipEvent> get events;

  /// Cancels the store subscription and closes the event stream.
  void dispose();
}
