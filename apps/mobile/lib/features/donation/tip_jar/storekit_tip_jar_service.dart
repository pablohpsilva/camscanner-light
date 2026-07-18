import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

import 'tip_event.dart';
import 'tip_jar_service.dart';
import 'tip_product.dart';
import 'tip_product_ids.dart';

/// Pure mapping from a StoreKit/Play [PurchaseStatus] to our plugin-free
/// [TipEvent]. Host-testable — no platform channel is touched.
TipEvent tipEventFromStatus(PurchaseStatus status) {
  switch (status) {
    case PurchaseStatus.pending:
      return const TipEventPending();
    case PurchaseStatus.purchased:
    case PurchaseStatus.restored:
      return const TipEventSuccess();
    case PurchaseStatus.canceled:
      return const TipEventCanceled();
    case PurchaseStatus.error:
      return const TipEventError();
  }
}

/// Real [TipJarService] backed by `in_app_purchase`. Consumable purchases are
/// finished with `completePurchase` so the same tip can be given again (an
/// unfinished iOS transaction is redelivered forever).
class StoreKitTipJarService implements TipJarService {
  StoreKitTipJarService({InAppPurchase? iap})
    : _iap = iap ?? InAppPurchase.instance;

  final InAppPurchase _iap;
  final _events = StreamController<TipEvent>.broadcast();
  final Map<String, ProductDetails> _detailsById = {};
  StreamSubscription<List<PurchaseDetails>>? _sub;

  @override
  Stream<TipEvent> get events => _events.stream;

  @override
  Future<List<TipProduct>> loadProducts() async {
    _sub ??= _iap.purchaseStream.listen(
      _onPurchases,
      onError: (_) => _emit(const TipEventError()),
    );
    if (!await _iap.isAvailable()) return const [];
    final response = await _iap.queryProductDetails(kTipProductIds.toSet());
    _detailsById
      ..clear()
      ..addEntries(response.productDetails.map((p) => MapEntry(p.id, p)));
    final products =
        response.productDetails
            .map((p) => TipProduct(id: p.id, price: p.price))
            .toList()
          ..sort(
            (a, b) =>
                kTipProductIds.indexOf(a.id) - kTipProductIds.indexOf(b.id),
          );
    return products;
  }

  @override
  Future<void> buy(TipProduct product) async {
    final details = _detailsById[product.id];
    if (details == null) {
      _emit(const TipEventError());
      return;
    }
    await _iap.buyConsumable(
      purchaseParam: PurchaseParam(productDetails: details),
    );
  }

  void _onPurchases(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      _emit(tipEventFromStatus(purchase.status));
      if (purchase.pendingCompletePurchase) {
        // Consumable: finish so it can be purchased again (and to avoid
        // Android auto-refunds / iOS redelivery).
        _iap.completePurchase(purchase);
      }
    }
  }

  void _emit(TipEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _events.close();
  }
}
