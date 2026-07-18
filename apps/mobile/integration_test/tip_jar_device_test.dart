import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/donation/tip_jar/storekit_tip_jar_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS: StoreKit resolves the three tip products', (tester) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return; // Android has no tip jar; this test is iOS-only.
    }
    final service = StoreKitTipJarService();
    final products = await service.loadProducts();
    service.dispose();

    expect(products.map((p) => p.id).toList(), [
      'tip_small',
      'tip_medium',
      'tip_large',
    ]);
    for (final p in products) {
      expect(p.price, isNotEmpty); // StoreKit-localized price string
    }
  });
}
