import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/tip_jar/tip_event.dart';
import 'package:mobile/features/donation/tip_jar/tip_product.dart';

import 'fake_tip_jar_service.dart';

void main() {
  test(
    'buy emits the scripted event sequence and records the product',
    () async {
      final fake = FakeTipJarService();
      fake.scriptNextBuy(const [TipEventPending(), TipEventSuccess()]);
      final events = <TipEvent>[];
      fake.events.listen(events.add);

      const product = TipProduct(id: 'tip_small', price: r'$1.99');
      await fake.buy(product);
      await Future<void>.delayed(Duration.zero);

      expect(fake.buyCount, 1);
      expect(fake.lastBought, product);
      expect(events, [isA<TipEventPending>(), isA<TipEventSuccess>()]);
      fake.dispose();
    },
  );

  test('loadProducts returns scripted list', () async {
    final fake = FakeTipJarService()..scriptProducts(const []);
    expect(await fake.loadProducts(), isEmpty);
    fake.dispose();
  });
}
