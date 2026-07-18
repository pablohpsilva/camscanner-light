import 'dart:async';

import 'package:mobile/features/donation/tip_jar/tip_event.dart';
import 'package:mobile/features/donation/tip_jar/tip_jar_service.dart';
import 'package:mobile/features/donation/tip_jar/tip_product.dart';

/// Deterministic [TipJarService] for host tests. Script the products
/// [loadProducts] returns and the sequence of [TipEvent]s the next [buy] emits.
class FakeTipJarService implements TipJarService {
  FakeTipJarService({this._products = _defaultProducts});

  static const _defaultProducts = <TipProduct>[
    TipProduct(id: 'tip_small', price: r'$1.99'),
    TipProduct(id: 'tip_medium', price: r'$4.99'),
    TipProduct(id: 'tip_large', price: r'$9.99'),
  ];

  List<TipProduct> _products;
  List<TipEvent> _nextBuy = const [TipEventSuccess()];
  bool _throwOnLoad = false;
  final _controller = StreamController<TipEvent>.broadcast();

  int buyCount = 0;
  TipProduct? lastBought;

  void scriptProducts(List<TipProduct> products) => _products = products;
  void scriptNextBuy(List<TipEvent> events) => _nextBuy = events;
  void scriptLoadThrows() => _throwOnLoad = true;

  @override
  Future<List<TipProduct>> loadProducts() async {
    if (_throwOnLoad) throw StateError('store down');
    return _products;
  }

  @override
  Future<void> buy(TipProduct product) async {
    buyCount++;
    lastBought = product;
    for (final e in _nextBuy) {
      _controller.add(e);
    }
  }

  @override
  Stream<TipEvent> get events => _controller.stream;

  @override
  void dispose() => _controller.close();
}
